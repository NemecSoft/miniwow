extends Node3D

## M19 贫瘠之地地形（按用户规格）：魔兽世界 Barrens 风格稀树草原。
## 【尺寸】2048x2048 米（region_size 512 → 4x4=16 regions），高度 0-100m
## 【高度】平原 55-65m / 丘陵 65-80m / 干涸河床 35-48m / 绿洲洼地 30-38m
## 【材质】程序生成通道打包纹理四套（红土/枯黄草/岩石/绿洲植被），
##         control map 逐像素绘制 base/overlay/blend（set_control_* API）
## 【色彩】温暖土黄 + 赤褐，无饱和绿；绿洲点缀枯绿
## 旧 GridMap 区域（主城 + 三张 KayKit 图）压到 0m 盆地中继续可用；
## 角色出生点迁移到新地图南部平原（level.gd RESPAWN_POINT）。
## 碰撞不开（玩法物理仍走 GridMap/保护区），雕刻可在编辑器继续。

const BAKED_DIR := "res://assets/terrain3d_world"
const WORLD_SIZE := 2048
const HALF := WORLD_SIZE / 2.0

# GridMap 保护区（保留区）：压到 0m 盆地
const PROTECTED_ZONES := [
	[Vector2(0, 0), 55.0],
	[Vector2(0, 70), 45.0],
	[Vector2(60, 70), 45.0],
	[Vector2(-60, 70), 45.0],
]
const BASIN_HEIGHT := -0.5
# 绿洲（十字路口 = 地图中部偏北）：[中心, 半径]
const OASIS_ZONES := [
	[Vector2(60, -280), 26.0],
	[Vector2(-70, -320), 24.0],
	[Vector2(-10, -240), 22.0],
]
const OASIS_FLOOR := 31.0
const WATER_LEVEL := 34.5
# 纹理槽位
const TEX_ROCK := 0
const TEX_REDSOIL := 1
const TEX_SAVANNA := 2
const TEX_OASIS := 3
# 植被
const TREE_COUNT := 260
const ROCK_COUNT := 90

var terrain: Terrain3D
var _camera_bound := false


func _process(_delta: float) -> void:
	if _camera_bound or terrain == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		terrain.set_camera(cam)
		terrain.set_physics_process(true)
		_camera_bound = true


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_physics_process(false)
		return
	terrain = await create_terrain()


func create_terrain() -> Terrain3D:
	printerr("[Terrain] create_terrain 开始")
	terrain = Terrain3D.new()
	terrain.name = "Terrain3D"
	var baked_globally := ProjectSettings.globalize_path(BAKED_DIR)
	var has_baked := DirAccess.dir_exists_absolute(BAKED_DIR) \
			and DirAccess.get_files_at(baked_globally).size() > 0

	add_child(terrain, true)
	if has_baked:
		# 官方属性顺序：data_directory → material → assets
		terrain.region_size = 512
		printerr("[Terrain] 开始加载烘焙数据...")
		terrain.data_directory = BAKED_DIR
		printerr("[Terrain] 已加载烘焙贫瘠之地 assets/terrain3d_world/")
		_setup_material(terrain)
		_setup_textures(terrain)
	else:
		terrain.region_size = 512
		_setup_material(terrain)
		_setup_textures(terrain)
		# 1) 高度图（16 位灰度规格的浮点等价：像素值 = 高度米 / 100）
		var img: Image = await build_heightmap()
		terrain.region_size = 512
		terrain.data.import_images([img, null, null], Vector3(-HALF, 0, -HALF), 0.0, 100.0)
		printerr("[Terrain] 高度图完成")
		# 2) control map 材质绘制（红土/枯草/岩石/绿洲）
		await paint_control_maps()
		printerr("[Terrain] 材质绘制完成")
		# 3) 保存 region（此后走 data_directory 快速加载，编辑器可继续雕）
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BAKED_DIR))
		terrain.data.save_directory(BAKED_DIR)
		printerr("[Terrain] 已保存到 assets/terrain3d_world/")

	var t0 := Time.get_ticks_msec()
	populate_trees()
	printerr("[Terrain] trees_ms=", Time.get_ticks_msec() - t0)
	var t1 := Time.get_ticks_msec()
	build_oasis_water()
	printerr("[Terrain] water_ms=", Time.get_ticks_msec() - t1)
	return terrain


func _setup_material(t: Terrain3D) -> void:
	t.material.world_background = Terrain3DMaterial.NONE


## 程序生成通道打包纹理四套（规范：Albedo RGB 颜色 + A 高度细节；
## Normal RGB 法线 + A 粗糙度），存 PNG 到 assets/terrain3d_barrens/
func _setup_textures(t: Terrain3D) -> void:
	var out_dir := ProjectSettings.globalize_path("res://assets/terrain3d_barrens")
	var sets := [
		{ # 岩石/岩盘：灰褐，锐利岩面，高粗糙
			"name": "rock", "c0": Color(0.412, 0.412, 0.412), "c1": Color(0.522, 0.482, 0.443),
			"rough": 0.95, "detail": "ridge", "uv": 0.35,
		},
		{ # 红土/荒地：赤褐，干裂纹路，高粗糙
			"name": "redsoil", "c0": Color(0.545, 0.271, 0.075), "c1": Color(0.627, 0.322, 0.176),
			"rough": 0.85, "detail": "crack", "uv": 0.25,
		},
		{ # 枯黄稀树草原：枯黄，草簇微起伏，中低粗糙
			"name": "savanna", "c0": Color(0.769, 0.639, 0.353), "c1": Color(0.851, 0.741, 0.478),
			"rough": 0.55, "detail": "grass", "uv": 0.18,
		},
		{ # 绿洲湿润植被：暗绿，平滑湿润，低粗糙
			"name": "oasis", "c0": Color(0.290, 0.365, 0.137), "c1": Color(0.361, 0.427, 0.192),
			"rough": 0.35, "detail": "grass", "uv": 0.2,
		},
	]
	var assets: Array[Terrain3DTextureAsset] = []
	for i in sets.size():
		var s: Dictionary = sets[i]
		var alb_path := "res://assets/terrain3d_barrens/%s_alb_ht.png" % s.name
		var nrm_path := "res://assets/terrain3d_barrens/%s_nrm_rgh.png" % s.name
		if not ResourceLoader.exists(alb_path):
			var pair := _make_texture_set(s.c0, s.c1, s.rough, s.detail)
			DirAccess.make_dir_recursive_absolute(out_dir)
			pair[0].save_png(out_dir + "/%s_alb_ht.png" % s.name)
			pair[1].save_png(out_dir + "/%s_nrm_rgh.png" % s.name)
		var ta := Terrain3DTextureAsset.new()
		ta.name = s.name.capitalize()
		ta.albedo_texture = load(alb_path)
		ta.normal_texture = load(nrm_path)
		ta.uv_scale = s.uv
		ta.normal_depth = 1.0
		ta.ao_strength = 1.5
		assets.append(ta)

	t.assets = Terrain3DAssets.new()
	for i in assets.size():
		t.assets.set_texture(i, assets[i])


## 生成一套通道打包纹理：返回 [albedo(RGB色+A高度), normal(RGB法线+A粗糙)]
func _make_texture_set(c0: Color, c1: Color, rough: float, detail: String) -> Array:
	var sz := 512
	var fbm := FastNoiseLite.new()
	fbm.fractal_octaves = 4
	fbm.frequency = 0.02
	var detail_n := FastNoiseLite.new()
	detail_n.seed = hash(detail)
	if detail == "crack":
		detail_n.noise_type = FastNoiseLite.TYPE_CELLULAR
		detail_n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
		detail_n.frequency = 0.035
	elif detail == "ridge":
		detail_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		detail_n.fractal_octaves = 5
		detail_n.frequency = 0.03
		detail_n.domain_warp_enabled = true
	else: # grass 细碎草簇
		detail_n.frequency = 0.09

	var alb := Image.create_empty(sz, sz, false, Image.FORMAT_RGBA8)
	var nrm := Image.create_empty(sz, sz, false, Image.FORMAT_RGBA8)
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(sz * sz)
	for y in sz:
		for x in sz:
			var macro: float = fbm.get_noise_2d(x, y) # 大色块（红土/深浅斑驳）
			var micro: float = detail_n.get_noise_2d(x, y) # 细节（裂纹/草簇/岩面）
			var m01: float = clampf(macro * 0.5 + 0.5, 0.0, 1.0)
			var col: Color = c0.lerp(c1, m01)
			# A 通道 = 高度细节
			var h01: float = clampf(micro * 0.5 + 0.5, 0.0, 1.0)
			alb.set_pixel(x, y, Color(col.r, col.g, col.b, h01))
			heights[y * sz + x] = h01
	# 法线从高度差分，A = 粗糙度
	for y in sz:
		for x in sz:
			var hl: float = heights[y * sz + (x - 1) % sz]
			var hr: float = heights[y * sz + (x + 1) % sz]
			var hu: float = heights[((y - 1) % sz) * sz + x]
			var hd: float = heights[((y + 1) % sz) * sz + x]
			var n := Vector3((hl - hr) * 2.0, (hd - hu) * 2.0, 1.0).normalized()
			var nx: float = n.x * 0.5 + 0.5
			var ny: float = n.y * 0.5 + 0.5 # OpenGL +Y
			var nz: float = n.z * 0.5 + 0.5
			nrm.set_pixel(x, y, Color(nx, ny, nz, rough))
	return [alb, nrm]


## 高度图（像素值 = 高度米/100，对应"16 位灰度归一化 + Height Scale 100"规格）
func build_heightmap() -> Image:
	var plain := FastNoiseLite.new()
	plain.frequency = 0.0015
	plain.fractal_octaves = 3
	var hills := FastNoiseLite.new()
	hills.frequency = 0.004
	hills.fractal_octaves = 4
	hills.seed = 11
	var gully := FastNoiseLite.new() # 侵蚀沟壑走向
	gully.frequency = 0.006
	gully.seed = 23

	var img: Image = Image.create_empty(WORLD_SIZE, WORLD_SIZE, false, Image.FORMAT_RF)
	for px in WORLD_SIZE:
		var wx: float = px - HALF
		for pz in WORLD_SIZE:
			var wz: float = pz - HALF
			var world := Vector2(wx, wz)

			# 基础平原 55-65m
			var h := 60.0 + plain.get_noise_2d(px, pz) * 5.0
			# 丘陵 65-80m：噪声门控的区域隆起
			var hill_mask: float = hills.get_noise_2d(px, pz)
			if hill_mask > 0.15:
				h += clampf((hill_mask - 0.15) * 2.2, 0.0, 1.0) * 20.0
			# 干涸河床/侵蚀沟壑 35-48m：蜿蜒谷
			var river_d: float = absf(wx - _dry_river_x(wz))
			if river_d < 70.0:
				var gully_extra: float = clampf(gully.get_noise_2d(px, pz) * 12.0, -6.0, 6.0)
				var t: float = clampf((70.0 - river_d) / 52.0, 0.0, 1.0)
				t = t * t * (3.0 - 2.0 * t)
				h = lerpf(h, 41.0 + gully_extra, t)
			# 绿洲洼地 30-38m：宽过渡平滑凹陷（避免陡峭漏斗）
			for oasis in OASIS_ZONES:
				var d: float = world.distance_to(oasis[0])
				var radius: float = oasis[1]
				if d < radius * 2.6:
					var t: float = clampf((radius * 2.6 - d) / (radius * 1.8), 0.0, 1.0)
					t = t * t * (3.0 - 2.0 * t)
					var floor_h: float = OASIS_FLOOR + clampf((d / radius) * 3.0, 0.0, 3.0)
					h = lerpf(h, floor_h, t)

			# GridMap 保留区压到盆地（最高优先级）
			var zone_d := _zone_distance(world)
			if zone_d <= 0.0:
				h = BASIN_HEIGHT
			else:
				var blend: float = clampf(zone_d / 100.0, 0.0, 1.0)
				blend = blend * blend * (3.0 - 2.0 * blend)
				h = lerpf(BASIN_HEIGHT, h, blend)

			img.set_pixel(px, pz, Color(clampf(h, 0.0, 100.0) / 100.0, 0.0, 0.0, 1.0))
	return img


func rng_oasis_floor(d: float, radius: float) -> float:
	# 洼底微起伏（0~2m），水面 34.5 之下保持池状
	return clampf((d / radius) * 2.0, 0.0, 2.0)


## 干涸河床中心线（南北向蜿蜒）
func _dry_river_x(z: float) -> float:
	return -240.0 + 130.0 * sin(z * 0.0014) + 55.0 * sin(z * 0.0006 + 2.1)


## control map 材质绘制：逐像素 base/overlay/blend（官方 set_control_* API）
func paint_control_maps() -> void:
	var blend_n := FastNoiseLite.new()
	blend_n.frequency = 0.008
	blend_n.seed = 99
	var painted := 0
	for px in WORLD_SIZE:
		var wx: float = px - HALF
		for pz in WORLD_SIZE:
			var wz: float = pz - HALF
			var world := Vector2(wx, wz)
			var pos := Vector3(wx, 0, wz)
			var zone_d := _zone_distance(world)
			if zone_d <= 2.0:
				continue # GridMap 保护区保持默认，无所谓
			var h: float = terrain.data.get_height(pos)
			# 坡度（2m 差分）
			var hx: float = terrain.data.get_height(pos + Vector3(2, 0, 0)) - h
			var hz: float = terrain.data.get_height(pos + Vector3(0, 0, 2)) - h
			var slope: float = sqrt(hx * hx + hz * hz) / 2.0

			var in_oasis := false
			var oasis_edge := 1.0
			for oasis in OASIS_ZONES:
				var d: float = world.distance_to(oasis[0])
				if d < oasis[1] * 1.5:
					in_oasis = true
					oasis_edge = clampf((oasis[1] * 1.5 - d) / (oasis[1] * 0.7), 0.0, 1.0)
					break

			if slope > 0.55:
				# 陡坡 → 岩石
				terrain.data.set_control_auto(pos, false)
				terrain.data.set_control_base_id(pos, TEX_ROCK)
			elif in_oasis and h < 39.0:
				# 绿洲洼地 → 湿润植被，边缘与红土过渡
				terrain.data.set_control_auto(pos, false)
				terrain.data.set_control_base_id(pos, TEX_OASIS if oasis_edge > 0.5 else TEX_REDSOIL)
				terrain.data.set_control_overlay_id(pos, TEX_OASIS)
				terrain.data.set_control_blend(pos, clampf(oasis_edge, 0.1, 0.9))
			else:
				# 主地面：红土底 + 枯黄草 overlay 噪声混合（约 50/35）
				var b: float = blend_n.get_noise_2d(px, pz) * 0.5 + 0.5
				terrain.data.set_control_auto(pos, false)
				terrain.data.set_control_base_id(pos, TEX_REDSOIL)
				terrain.data.set_control_overlay_id(pos, TEX_SAVANNA)
				terrain.data.set_control_blend(pos, clampf(b, 0.15, 0.85))
			painted += 1
	printerr("[Terrain] painted=", painted)


func _zone_distance(world_pos: Vector2) -> float:
	var worst := INF
	for zone in PROTECTED_ZONES:
		worst = minf(worst, world_pos.distance_to(zone[0]) - zone[1])
	return worst


func _outside_zones(world_pos: Vector2) -> bool:
	return _zone_distance(world_pos) > 0.0


## 稀树草原植被：稀疏枯树 + 绿洲旁密植（橄榄色树冠）
func populate_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261017
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.15
	trunk_mesh.bottom_radius = 0.28
	trunk_mesh.height = 3.0
	trunk_mesh.radial_segments = 6
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.42, 0.30, 0.18, 1)
	trunk_mat.roughness = 0.95
	trunk_mesh.material = trunk_mat

	var leaf_mesh := CylinderMesh.new()
	leaf_mesh.top_radius = 0.0
	leaf_mesh.bottom_radius = 1.8
	leaf_mesh.height = 2.2
	leaf_mesh.radial_segments = 8
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.36, 0.40, 0.20, 1) # 枯橄榄绿（非饱和）
	leaf_mat.roughness = 0.9
	leaf_mesh.material = leaf_mat

	var near_oasis: Array[Transform3D] = []
	var far_trees: Array[Transform3D] = []
	var attempts := 0
	var target := TREE_COUNT
	while near_oasis.size() + far_trees.size() < target and attempts < target * 40:
		attempts += 1
		var pos := Vector3(rng.randf_range(-HALF + 40, HALF - 40), 0, rng.randf_range(-HALF + 40, HALF - 40))
		if not _outside_zones(Vector2(pos.x, pos.z)):
			continue
		var h: float = terrain.data.get_height(pos)
		if h < 30.0 or h > 85.0:
			continue
		var hx: float = terrain.data.get_height(pos + Vector3(2, 0, 0)) - h
		var hz: float = terrain.data.get_height(pos + Vector3(0, 0, 2)) - h
		if sqrt(hx * hx + hz * hz) > 0.8:
			continue
		var oasis_near := false
		for oasis in OASIS_ZONES:
			if Vector2(pos.x, pos.z).distance_to(oasis[0]) < oasis[1] * 3.0:
				oasis_near = true
				break
		var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(
			Vector3.ONE * rng.randf_range(0.7, 1.5))
		var xf := Transform3D(basis, Vector3(pos.x, h - 0.1, pos.z))
		if oasis_near:
			near_oasis.append(xf) # 绿洲旁密植
			near_oasis.append(xf) # 双份密度
		elif rng.randf() < 0.35: # 稀树草原：远处仅 35% 保留
			far_trees.append(xf)

	_add_multimesh(trunk_mesh, near_oasis)
	_add_multimesh(leaf_mesh, near_oasis)
	_add_multimesh(trunk_mesh, far_trees)
	_add_multimesh(leaf_mesh, far_trees)


func _add_multimesh(mesh: Mesh, xforms: Array[Transform3D]) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)


## 绿洲水池：三个洼地中心放圆水面
func build_oasis_water() -> void:
	var water_mat := StandardMaterial3D.new()
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.albedo_color = Color(0.30, 0.52, 0.55, 0.8) # 微浊蓝绿
	water_mat.roughness = 0.06
	water_mat.metallic = 0.15
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(38, 38)
	water_mesh.material = water_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = water_mesh
	mm.instance_count = OASIS_ZONES.size()
	for i in OASIS_ZONES.size():
		var c: Vector2 = OASIS_ZONES[i][0]
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(c.x, WATER_LEVEL, c.y)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
