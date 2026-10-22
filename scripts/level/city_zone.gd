extends Node3D

## TSL 浮空城 1:1 复刻（docs/tsl-replica-design.md，全部数值源码反解原值）：
## - 世界边界 984×736（H1 冻结对象原值），路网 18 纵 + 12 横（m5/g5 原坐标）
## - 路宽规则、街区算法（ft 反解）、核心区 19 座地标（pt 表原值）、配色原值
## - 行道树/路灯 MultiMesh 批渲染；道路 BoxMesh + 程序车道线纹理
## - 挂在现有地图上空（用户钦定浮空），建筑可破坏（撞楼碎块沿用）
## 浮空平台世界位置：CITY_ORIGIN（level.tscn 里本节点 transform 决定，本脚本只管局部）

const CITY_SEED := 20261020
# ---- H1 世界边界（源码原值）----
const WORLD_MIN_X := -492.0
const WORLD_MAX_X := 492.0
const WORLD_MIN_Z := -452.0
const WORLD_MAX_Z := 284.0
# ---- m5/g5 路网坐标（源码原值）----
const ROAD_X := [-469.0, -405.0, -341.0, -277.0, -213.0, -157.0, -113.0, -69.0, -23.0, 23.0, 69.0, 113.0, 157.0, 213.0, 277.0, 341.0, 405.0, 469.0]
const ROAD_Z := [-431.0, -359.0, -287.0, -215.0, -143.0, -84.0, -29.0, 42.0, 61.0, 117.0, 189.0, 261.0]
# ---- pt 核心区地标表（源码原值：[x, z, 宽, 深, 层数]）----
const LANDMARKS := [
	[0.0, 0.0, 28.0, 24.0, 8.0], [-46.0, 0.0, 28.0, 30.0, 12.0], [46.0, 0.0, 28.0, 30.0, 10.0],
	[-91.0, -4.0, 27.0, 34.0, 9.0], [92.0, -2.0, 28.0, 32.0, 11.0], [0.0, -53.0, 28.0, 27.0, 6.0],
	[-46.0, -57.0, 28.0, 27.0, 7.0], [46.0, -57.0, 27.0, 29.0, 13.0], [-91.0, -58.0, 26.0, 30.0, 8.0],
	[92.0, -59.0, 29.0, 30.0, 7.0], [0.0, -112.0, 28.0, 29.0, 11.0], [-46.0, -113.0, 28.0, 28.0, 9.0],
	[46.0, -112.0, 28.0, 31.0, 8.0], [-91.0, -113.0, 28.0, 29.0, 12.0], [92.0, -113.0, 28.0, 29.0, 9.0],
	[-134.0, -54.0, 28.0, 29.0, 10.0], [134.0, -51.0, 27.0, 30.0, 11.0], [-136.0, 3.0, 27.0, 28.0, 7.0],
	[135.0, 1.0, 28.0, 28.0, 8.0],
]
const FLOOR_HEIGHT := 7.0            # 层高（源码 X0: h=K*7，每层 7 米——12 层地标 84 米）
const CORE_X := 157.0               # 核心区半宽（x ∈ [-157,157]）
const CORE_Z_MIN := -143.0
const CORE_Z_MAX := 61.0
# ---- 配色（源码 hex 原值）----
# M31b 配色全部改用 tsl 游戏逻辑区真值（main.js 3094000+ 城市构建段，
# 此前 #e8e7d9/#bc8963 系从库代码区误反解，已废弃）：
const COLOR_SIDEWALK := Color("c68e61")      # 人行道砖底
const COLOR_SIDEWALK2 := Color("cf976c")     # 人行道砖亮面
const BUILDING_PALETTE := [Color("d1d5cb"), Color("e6cbb0"), Color("c2b5a6"), Color("b4c8cf"), Color("d2c0ad")]
const COLOR_ROOF := Color("66694f")          # 楼顶
const COLOR_TRIM := Color("796b5e")          # 楼缘
const ASPHALT := Color("e9e7db")             # 路面浅米白（tsl 真值）
const COLOR_LANE := Color("fff2de")          # 车道暖白线
const COLOR_RACELINE := Color("ff3d57")      # 赛道红线
const RUBBLE_LIFETIME := 6.0
## 浮空平台顶面（局部 y）
const TOP_Y := 0.0
## M41：远景遮蔽距离。浮空城在 1.6km 外时，浅米白建筑 + 淡雾色叠成一块刺眼的
## "白板"贴在蓝天里（实测 d=1583~2038m，建筑与 Platform 都在画面中）。改成
## 超过该距离整城不渲染——此距离上雾已吃掉约 95%，切换完全看不出跳变，
## 飞近时城市从雾中逐渐浮现。
const VIEW_CULL_DISTANCE := 1200.0

var _destroyed_ids := {}
var _rng := RandomNumberGenerator.new()
var _ground_shape_ready := false


func _ready() -> void:
	add_to_group("city_zone")
	_rng.seed = CITY_SEED
	_build_platform()
	_build_roads()
	_build_city_blocks()
	_build_street_props_multi()
	_build_city_light()


## M41：远景遮蔽——相机离城超过 VIEW_CULL_DISTANCE 时整城不渲染，
## 消除远处"白板"。只切视觉，碰撞体与逻辑照常（玩家飞近自动恢复）。
func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var far: bool = cam.global_position.distance_to(global_position) > VIEW_CULL_DISTANCE
	if visible == far:
		visible = not far


## M31b tsl 场景氛围（main.js 3093xxx）：平行光 #fff0d7 强度 2.25 位置 (-50,100,70)——
## 只照城区，不动主世界全局环境
func _build_city_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff0d7")
	sun.light_energy = 2.25
	sun.position = Vector3(-50, 100, 70)
	add_child(sun)
	# 从该位置指向城区中心，保持 tsl 光照方向（须先进树再 look_at）
	sun.look_at(Vector3(0, TOP_Y, (WORLD_MIN_Z + WORLD_MAX_Z) / 2.0))


## ===== 平台（浮空底板）=====
func _build_platform() -> void:
	var platform := StaticBody3D.new()
	platform.name = "Platform"
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(WORLD_MAX_X - WORLD_MIN_X + 24.0, 6.0, WORLD_MAX_Z - WORLD_MIN_Z + 24.0)
	mesh.mesh = box
	mesh.position = Vector3((WORLD_MIN_X + WORLD_MAX_X) / 2.0, TOP_Y - 3.0, (WORLD_MIN_Z + WORLD_MAX_Z) / 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.40, 0.29)
	mesh.material_override = mat
	platform.add_child(mesh)
	var shape := CollisionShape3D.new()
	var cshape := BoxShape3D.new()
	cshape.size = box.size
	shape.shape = cshape
	shape.position = mesh.position
	platform.add_child(shape)
	add_child(platform)


## ===== 路网（X6 反解：路宽规则原值）=====
func _road_width_z_axis(x: float) -> float:
	# 纵向路（沿 z 轴、位于 x）：源码 e===-113?18 : e===113?12 : |e|===23?11 : |e|>157?12 : 8
	if x == -113.0:
		return 18.0
	if x == 113.0:
		return 12.0
	if absf(x) == 23.0:
		return 11.0
	if absf(x) > 157.0:
		return 12.0
	return 8.0


func _road_width_x_axis(z: float) -> float:
	# 横向路（沿 x 轴、位于 z）：源码 e===42||e>61||e<-143 ? 12 : 8
	if z == 42.0 or z > 61.0 or z < -143.0:
		return 12.0
	return 8.0


func _build_roads() -> void:
	var length_z := WORLD_MAX_Z - WORLD_MIN_Z - 12.0
	var length_x := WORLD_MAX_X - WORLD_MIN_X - 12.0
	var mid_z := (WORLD_MIN_Z + WORLD_MAX_Z) / 2.0
	var mid_x := (WORLD_MIN_X + WORLD_MAX_X) / 2.0
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_texture = _make_road_texture()
	for x: float in ROAD_X:
		_add_road_mesh(Vector3(x, TOP_Y + 0.03, mid_z), Vector3(_road_width_z_axis(x), 0.06, length_z), road_mat)
	for z: float in ROAD_Z:
		_add_road_mesh(Vector3(mid_x, TOP_Y + 0.031, z), Vector3(length_x, 0.06, _road_width_x_axis(z)), road_mat)


func _add_road_mesh(pos: Vector3, size: Vector3, mat: Material) -> void:
	var road := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	road.mesh = box
	road.position = pos
	road.material_override = mat
	add_child(road)


## 车道线纹理（M31b tsl 真值：浅米白路面 #e9e7db + 暖白虚线 #fff2de + 两侧赛道红线 #ff3d57）
func _make_road_texture() -> ImageTexture:
	var px_w := 128
	var px_h := 256
	var img := Image.create(px_w, px_h, false, Image.FORMAT_RGB8)
	img.fill(ASPHALT)
	# 两侧赛道红线（tsl #ff3d57）
	for x in range(2, 7):
		for y in px_h:
			img.set_pixel(x, y, COLOR_RACELINE)
			img.set_pixel(px_w - 1 - x, y, COLOR_RACELINE)
	# 中央暖白虚线（tsl #fff2de）
	var dash := 24
	var gap := 40
	var y := 0
	while y < px_h:
		for dy in range(mini(dash, px_h - y)):
			for x in range(px_w / 2 - 2, px_w / 2 + 2):
				img.set_pixel(x, y + dy, COLOR_LANE)
		y += dash + gap
	# uv 横向重复 4 次（路宽方向虚线间距合理化由 repeat 完成）
	return ImageTexture.create_from_image(img)


## ===== 街区（ft 反解）=====
func _is_core_block(x_min: float, x_max: float, z_min: float, z_max: float) -> bool:
	return x_min >= -CORE_X and x_max <= CORE_X and z_min >= CORE_Z_MIN and z_max <= CORE_Z_MAX


func _build_city_blocks() -> void:
	var window_tex := _make_window_texture()
	for i in range(ROAD_Z.size() - 1):
		for a in range(ROAD_X.size() - 1):
			var s: float = ROAD_X[a]
			var o: float = ROAD_X[a + 1]
			var c: float = ROAD_Z[i]
			var l: float = ROAD_Z[i + 1]
			var wz_s := _road_width_z_axis(s)
			var wz_o := _road_width_z_axis(o)
			var wx_c := _road_width_x_axis(c)
			var wx_l := _road_width_x_axis(l)
			# 人行道边距：核心 2.5 / 外围 3.5（源码 f?2.5:3.5）
			var m := 2.5 if _is_core_block(s, o, c, l) else 3.5
			var v := s + wz_s / 2.0 + m
			var g := o - wz_o / 2.0 - m
			var x := c + wx_c / 2.0 + m
			var y := l - wx_l / 2.0 - m
			var block_w := g - v
			var block_d := y - x
			var idx := i * 19 + a
			if block_w < 12.0 or block_d < 14.0:
				continue # 太窄 → 公园（底板草绿已呈现）
			if idx % 11 == 3:
				continue # 公园街区（源码 S%11===3）
			var cx := (v + g) / 2.0
			var cz := (x + y) / 2.0
			var is_core := _is_core_block(s, o, c, l)
			# 中央广场街区（MCP 方尖碑坐镇）：铺底板+方尖碑，不生成楼
			if s == 23.0 and o == 69.0 and c == -29.0 and l == 42.0:
				_add_sidewalk_slab(v, g, x, y)
				_spawn_monument(Vector3((v + g) / 2.0, TOP_Y, (x + y) / 2.0))
				continue
			# M31b：街区铺人行道砖底板（tsl #c68e61 系）
			_add_sidewalk_slab(v, g, x, y)
			if is_core:
				# 核心区：pt 地标命中全放（tsl 是数组遍历，非取首个），位置 clamp 进地块
				var lm_found := false
				for lm: Array in LANDMARKS:
					var lx: float = lm[0]
					var lz: float = lm[1]
					if lx > s and lx < o and lz > c and lz < l:
						lm_found = true
						var lw: float = minf(lm[2], block_w)
						var ld: float = minf(lm[3], block_d)
						# 用户指令 2026-10-20：城市楼一律 10~30 层（覆盖 tsl 原值 6~13）
						var lh: float = clampf(lm[4], 10.0, 30.0) * FLOOR_HEIGHT
						# 源码：max(v+w/2, min(g-w/2, U))——中心 clamp 进楼占地范围
						var px := clampf(lx, v + lw / 2.0, g - lw / 2.0)
						var pz := clampf(lz, x + ld / 2.0, y - ld / 2.0)
						_spawn_building("building_%d_%d_%d_%d" % [i, a, int(lm[0]), int(lm[1])], Vector3(px, TOP_Y, pz), lw, ld, lh, window_tex, true)
				if lm_found:
					continue
				# 核心区无地标：整块大底盘楼（源码 args:[_,A,g-v,y-x,3+S%2]，宽=整个地块不收缩）
				# 用户指令：层数一律 10~30（覆盖 tsl 原值 3~4）
				var h_core := (10.0 + float(idx % 21)) * FLOOR_HEIGHT
				_spawn_building("building_%d_%d_%d" % [i, a, 0], Vector3(cx, TOP_Y, cz), block_w, block_d, h_core, window_tex, false, 1 + idx % 4)
				continue
			# 用户指令 2026-10-20：全部楼 10~30 层（覆盖 tsl 原值 5~11 / 2~6）
			var floors := 10.0 + float(idx % 21)
			var style := int(idx % 4)
			# 楼宽收缩（源码 (o-s)*(.74+S%3*.025)，两维同用 S%3）
			var shrink := 0.74 + float(idx % 3) * 0.025
			var bw := minf(block_w, (o - s) * shrink)
			var bd := minf(block_d, (l - c) * shrink)
			_spawn_building("building_%d_%d_%d" % [i, a, 1], Vector3(cx, TOP_Y, cz), bw, bd, floors * FLOOR_HEIGHT, window_tex, false, style)


func _spawn_building(id: String, base_pos: Vector3, w: float, d: float, h: float, window_tex: Texture2D, is_landmark: bool, style: int = 0) -> void:
	if h < 3.0:
		h = 3.0
	var building := StaticBody3D.new()
	building.name = id
	building.add_to_group("building")
	building.position = base_pos
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(w, h, d)
	mesh.mesh = box
	mesh.position.y = h / 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = window_tex
	# M31b tsl 原值：x0.repeat.set(1/3.5, 1/7)——宽 3.5m 一幅、高 7m 一层一幅（层数=h/7）
	mat.uv1_scale = Vector3(w / 3.5, h / 7.0, 1.0)
	mat.metallic = 0.1
	mat.roughness = 0.65
	# 风格配色（tsl：S0.clone() 后 color.set(变体色)——tint 乘纹理）
	var color: Color
	if is_landmark:
		color = BUILDING_PALETTE[0]
	else:
		color = BUILDING_PALETTE[(style + int(base_pos.x / 50.0)) % BUILDING_PALETTE.size()]
	mat.albedo_color = color
	mesh.material_override = mat
	building.add_child(mesh)
	# 楼顶檐口（M31b tsl 真值：楼顶 #66694f、楼缘 #796b5e）
	var cap := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(w + 0.6, 0.5, d + 0.6)
	cap.mesh = cbox
	cap.position.y = h + 0.25
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = COLOR_ROOF
	cap.material_override = cmat
	building.add_child(cap)
	var shape := CollisionShape3D.new()
	var cshape := BoxShape3D.new()
	cshape.size = Vector3(w, h + 0.5, d)
	shape.shape = cshape
	shape.position.y = (h + 0.5) / 2.0
	building.add_child(shape)
	add_child(building)


## ===== 中央广场方尖碑（Blender MCP 程序化建模产物 arcane_monument.glb，2026-10-20）=====
func _spawn_monument(pos: Vector3) -> void:
	var scene: PackedScene = load("res://assets/models/arcane_monument.glb")
	if scene == null:
		push_warning("arcane_monument.glb 未导入，中央广场空置")
		return
	var monument: Node3D = scene.instantiate()
	monument.position = pos
	add_child(monument)
	# 碰撞：底座盒 + 柱身圆柱（不进 building 组，不可被撞楼系统破坏）
	var body := StaticBody3D.new()
	body.name = "MonumentCollision"
	var base_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 1.6, 6.0)
	base_shape.shape = box
	base_shape.position.y = 0.8
	body.add_child(base_shape)
	var shaft_shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.2
	cyl.height = 12.0
	shaft_shape.shape = cyl
	shaft_shape.position.y = 6.8
	body.add_child(shaft_shape)
	monument.add_child(body)
	# 晶体发光：给名为 ObeliskCrystal 材质的 mesh 提亮（glb 材质自带 emission，兜底加 OmniLight）
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.2, 0.95, 0.9)
	glow.light_energy = 6.0
	glow.omni_range = 18.0
	glow.position.y = 13.7
	monument.add_child(glow)

	# M40：奥术流光（常驻上升粒子）+ 晶体光呼吸（建筑动态效果）
	var flow := GPUParticles3D.new()
	var fppm := ParticleProcessMaterial.new()
	fppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fppm.emission_sphere_radius = 1.0
	fppm.direction = Vector3(0, 1, 0)
	fppm.spread = 20.0
	fppm.initial_velocity_min = 1.5
	fppm.initial_velocity_max = 3.0
	fppm.gravity = Vector3(0, 0, 0)
	fppm.scale_min = 0.1
	fppm.scale_max = 0.35
	var fmat := StandardMaterial3D.new()
	fmat.emission_enabled = true
	fmat.emission = Color(0.4, 0.9, 1.0)
	fmat.emission_energy_multiplier = 2.5
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.no_depth_test = true
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var fq := QuadMesh.new()
	fq.size = Vector2(0.2, 0.2)
	flow.draw_pass_1 = fq  # 无 draw_pass 粒子不渲染（M40 修）
	flow.material_override = fmat
	flow.process_material = fppm
	flow.amount = 30
	flow.lifetime = 3.0
	flow.emitting = true
	flow.position.y = 2.0
	monument.add_child(flow)
	# 晶体光呼吸（4 ↔ 9 来回）
	var tw := create_tween()
	tw.set_loops(-1)
	tw.tween_property(glow, "light_energy", 9.0, 2.0)
	tw.tween_property(glow, "light_energy", 4.0, 2.0)


## M31b 楼墙纹理：tsl canvas 256 算法 1:1（main.js x0）
## 底 #d1d5cb → 内框 #abb6ae → 玻璃渐变 #66858b/#375c69/#244756 → 窗棂竖横条 #d1d5cb → 斜高光 #d7eef3
func _make_window_texture() -> ImageTexture:
	var px := 256
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	var c_base := Color("d1d5cb")
	var c_frame := Color("abb6ae")
	var g_top := Color("66858b")
	var g_mid := Color("375c69")
	var g_bot := Color("244756")
	var c_line := Color("d1d5cb")
	var c_glint := Color(0.843, 0.933, 0.953, 0.22)  # #d7eef3 α~0.22
	img.fill(c_base)
	for y in range(12, 244):
		for x in range(13, 243):
			img.set_pixel(x, y, c_frame)
	# 玻璃渐变区（22,20 → 212×214）
	for y in range(20, 234):
		for x in range(22, 234):
			var t := clampf((float(y) - 18.0) / 224.0, 0.0, 1.0)
			var col: Color
			if t < 0.48:
				col = g_top.lerp(g_mid, t / 0.48)
			else:
				col = g_mid.lerp(g_bot, (t - 0.48) / 0.52)
			img.set_pixel(x, y, col)
	# 窗棂：竖条 x∈[122,127) + 横条 y∈[124,130)
	for y in range(20, 234):
		for x in range(122, 127):
			img.set_pixel(x, y, c_line)
	for y in range(124, 130):
		for x in range(22, 234):
			img.set_pixel(x, y, c_line)
	# 斜高光两道（62,25→33,111 与 175,142→146,221，宽约 3px）
	_draw_line_px(img, 62, 25, 33, 111, c_glint)
	_draw_line_px(img, 175, 142, 146, 221, c_glint)
	return ImageTexture.create_from_image(img)


func _draw_line_px(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	var steps := maxi(absi(x1 - x0), absi(y1 - y0))
	for i in steps + 1:
		var x := x0 + (x1 - x0) * i / steps
		var y := y0 + (y1 - y0) * i / steps
		for dx in range(3):
			var px := x + dx
			if px >= 0 and px < img.get_width() and y >= 0 and y < img.get_height():
				var dst := img.get_pixel(px, y)
				img.set_pixel(px, y, dst.lerp(Color(col.r, col.g, col.b), col.a))


## M31b：人行道砖底板（整街区一块，共享材质省 draw call）
var _sidewalk_mat: StandardMaterial3D = null

func _add_sidewalk_slab(v: float, g: float, z0: float, z1: float) -> void:
	if _sidewalk_mat == null:
		_sidewalk_mat = StandardMaterial3D.new()
		_sidewalk_mat.albedo_color = COLOR_SIDEWALK
		_sidewalk_mat.roughness = 0.9
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(g - v, 0.12, z1 - z0)
	slab.mesh = box
	slab.position = Vector3((v + g) / 2.0, TOP_Y + 0.06, (z0 + z1) / 2.0)
	slab.material_override = _sidewalk_mat
	add_child(slab)


## ===== 街道设施（MultiMesh 批渲染：树 + 灯，9m 间隔原值，|x|==23 路跳过）=====
func _build_street_props_multi() -> void:
	var tree_xforms: Array[Transform3D] = []
	var lamp_xforms: Array[Transform3D] = []
	# 纵向路两侧
	for x: float in ROAD_X:
		if absf(x) == 23.0:
			continue # 源码：|x|===23 跳过
		var w := _road_width_z_axis(x)
		for side: float in [-1.0, 1.0]:
			var px := x + side * (w / 2.0 + 1.2)
			var z := WORLD_MIN_Z + 8.0
			while z < WORLD_MAX_Z - 8.0:
				# 路口避让
				var skip := false
				for cz: float in ROAD_Z:
					if absf(z - cz) < _road_width_x_axis(cz) / 2.0 + 2.5:
						skip = true
						break
				if not skip:
					var t := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE), Vector3(px, TOP_Y, z))
					if int(z / 9.0) % 2 == 0:
						tree_xforms.append(t)
					else:
						lamp_xforms.append(t)
				z += 9.0
	# 横向路两侧
	for z: float in ROAD_Z:
		var d := _road_width_x_axis(z)
		for side: float in [-1.0, 1.0]:
			var pz := z + side * (d / 2.0 + 1.2)
			var x := WORLD_MIN_X + 8.0
			while x < WORLD_MAX_X - 8.0:
				var skip := false
				for cx: float in ROAD_X:
					if absf(x - cx) < _road_width_z_axis(cx) / 2.0 + 2.5:
						skip = true
						break
				if not skip:
					var t2 := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE), Vector3(x, TOP_Y, pz))
					if int(x / 9.0) % 2 == 0:
						tree_xforms.append(t2)
					else:
						lamp_xforms.append(t2)
				x += 9.0
	_add_multi_trees(tree_xforms)
	_add_multi_lamps(lamp_xforms)


func _add_multi_trees(xforms: Array[Transform3D]) -> void:
	if xforms.is_empty():
		return
	# M31b tsl 真值（main.js l1）：方树池 1.5×0.24×1.5 #334852 +
	# 方干 0.45×2.6×0.45 #775d42（中心 y=1.15）+ 锥冠 Cone(2.25, h1×0.87) #46795c（中心 y=4.1）
	var pool_mm := MultiMesh.new()
	pool_mm.transform_format = MultiMesh.TRANSFORM_3D
	var pool_mesh := BoxMesh.new()
	pool_mesh.size = Vector3(1.5, 0.24, 1.5)
	pool_mm.mesh = pool_mesh
	pool_mm.instance_count = xforms.size()
	var trunk_mm := MultiMesh.new()
	trunk_mm.transform_format = MultiMesh.TRANSFORM_3D
	var trunk_mesh := BoxMesh.new()
	trunk_mesh.size = Vector3(0.45, 2.6, 0.45)
	trunk_mm.mesh = trunk_mesh
	trunk_mm.instance_count = xforms.size()
	var crown_mm := MultiMesh.new()
	crown_mm.transform_format = MultiMesh.TRANSFORM_3D
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.0
	crown_mesh.bottom_radius = 2.25
	crown_mesh.height = 0.87
	crown_mesh.radial_segments = 16
	crown_mm.mesh = crown_mesh
	crown_mm.instance_count = xforms.size()
	for i in xforms.size():
		var pt := xforms[i]
		pt.origin.y += 0.12
		pool_mm.set_instance_transform(i, pt)
		var tt := xforms[i]
		tt.origin.y += 1.15
		trunk_mm.set_instance_transform(i, tt)
		var ct := xforms[i]
		ct.origin.y += 4.1
		crown_mm.set_instance_transform(i, ct)
	var pool_node := MultiMeshInstance3D.new()
	pool_node.multimesh = pool_mm
	var pm2 := StandardMaterial3D.new()
	pm2.albedo_color = Color("334852")
	pool_node.material_override = pm2
	add_child(pool_node)
	var trunk_node := MultiMeshInstance3D.new()
	trunk_node.multimesh = trunk_mm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color("775d42")
	trunk_node.material_override = tmat
	add_child(trunk_node)
	var crown_node := MultiMeshInstance3D.new()
	crown_node.multimesh = crown_mm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color("46795c")
	crown_node.material_override = cmat
	add_child(crown_node)


func _add_multi_lamps(xforms: Array[Transform3D]) -> void:
	if xforms.is_empty():
		return
	var pole_mm := MultiMesh.new()
	pole_mm.transform_format = MultiMesh.TRANSFORM_3D
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.09
	pole_mesh.bottom_radius = 0.13
	pole_mesh.height = 6.0
	pole_mm.mesh = pole_mesh
	pole_mm.instance_count = xforms.size()
	var head_mm := MultiMesh.new()
	head_mm.transform_format = MultiMesh.TRANSFORM_3D
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.28
	head_mesh.height = 0.56
	head_mm.mesh = head_mesh
	head_mm.instance_count = xforms.size()
	for i in xforms.size():
		var tt := xforms[i]
		tt.origin.y += 3.0
		pole_mm.set_instance_transform(i, tt)
		var ht := xforms[i]
		ht.origin.y += 6.1
		head_mm.set_instance_transform(i, ht)
	var pole_node := MultiMeshInstance3D.new()
	pole_node.multimesh = pole_mm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.25, 0.27, 0.30)
	pole_node.material_override = pmat
	add_child(pole_node)
	var head_node := MultiMeshInstance3D.new()
	head_node.multimesh = head_mm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.95, 0.92, 0.75)
	hmat.emission_enabled = true
	hmat.emission = Color(1.0, 0.95, 0.75)
	hmat.emission_energy_multiplier = 1.5
	head_node.material_override = hmat
	add_child(head_node)


## ===== 回环接口（浮空城不设回环，保留接口兼容）=====
func get_loop_entry(_world_pos: Vector3, _min_speed: float) -> Dictionary:
	return {}


## ===== 破坏系统（沿用）=====
@rpc("any_peer", "call_local", "reliable")
func request_destroy_building(building_id: String, impact_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var node := get_node_or_null(building_id)
	if node == null or _destroyed_ids.has(building_id):
		return
	_destroyed_ids[building_id] = true
	do_destroy_building.rpc(building_id, impact_pos)


@rpc("any_peer", "call_local", "reliable")
func do_destroy_building(building_id: String, impact_pos: Vector3) -> void:
	var rpc_sender := multiplayer.get_remote_sender_id()
	if rpc_sender != 0 and rpc_sender != 1:
		return
	var node := get_node_or_null(building_id)
	if node == null:
		return
	var origin: Vector3 = (node as Node3D).global_position
	var h: float = 10.0
	var color := Color(0.5, 0.5, 0.55)
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() > 0 and (meshes[0] as MeshInstance3D).mesh is BoxMesh:
		h = ((meshes[0] as MeshInstance3D).mesh as BoxMesh).size.y
	if meshes.size() > 0 and (meshes[0] as MeshInstance3D).material_override is StandardMaterial3D:
		color = ((meshes[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	node.queue_free()
	_destroyed_ids[building_id] = true
	_spawn_rubble(origin + Vector3(0, h / 2.0, 0), h, color, impact_pos)


func _spawn_rubble(center: Vector3, building_h: float, color: Color, impact_pos: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 8:
		var chunk := RigidBody3D.new()
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		var size := rng.randf_range(0.8, 2.0)
		box.size = Vector3(size, size, size)
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color.darkened(rng.randf_range(0.0, 0.25))
		mesh.material_override = mat
		chunk.add_child(mesh)
		var shape := CollisionShape3D.new()
		var cshape := BoxShape3D.new()
		cshape.size = box.size
		shape.shape = cshape
		chunk.add_child(shape)
		chunk.global_position = center + Vector3(
			rng.randf_range(-2.0, 2.0), rng.randf_range(-building_h / 2.0, building_h / 2.0), rng.randf_range(-2.0, 2.0))
		chunk.mass = size * 2.0
		add_child(chunk)
		var away := (chunk.global_position - impact_pos).normalized()
		if away.length_squared() < 0.01:
			away = Vector3.FORWARD
		chunk.apply_central_impulse((away * 0.6 + Vector3.UP * 0.8).normalized() * rng.randf_range(18.0, 40.0))
		get_tree().create_timer(RUBBLE_LIFETIME).timeout.connect(
			func() -> void:
				if is_instance_valid(chunk):
					chunk.queue_free()
		)


## late-join 补发（level.gd 玩家加入时调用）
func sync_destroyed_to(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	for building_id in _destroyed_ids:
		if not get_node_or_null(str(building_id)):
			continue
		sync_destroyed.rpc_id(peer_id, str(building_id))


@rpc("any_peer", "call_local", "reliable")
func sync_destroyed(building_id: String) -> void:
	var rpc_sender := multiplayer.get_remote_sender_id()
	if rpc_sender != 0 and rpc_sender != 1:
		return
	if _destroyed_ids.has(building_id):
		return
	_destroyed_ids[building_id] = true
	var node := get_node_or_null(building_id)
	if node != null:
		node.queue_free()
