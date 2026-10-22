class_name HomeStarter
extends Node3D

## WoW 风玩家家园（M37）：村东南林间空地一座木屋 + 花园，
## 玩家从村庄广场的传送门进门即到家（见 home_portal.gd）。
##
## 布局（局部坐标，y = 离 HOME_CENTER 地面高度）：
## - 房屋 12(x) x 10(z)，中心 (0,-6)，南墙开门，东/西/北三面大窗看花园
## - 房前木平台甲板 + 黄色花圃 + 石头步道 + 大树 + 串灯 + 躺椅望远镜
## - 室内：东北厨房（L 型橱柜/灶台/油烟机/冰箱/中岛水果）、
##   西北卧室（床/书架）、西南客厅（沙发/茶几/地毯/壁炉）
##
## 网络架构：level.tscn 静态实例，两端各自程序化构建（确定性结构一一对应），
## 无权威状态（纯场景），传送逻辑在 home_portal.gd。

const HOME_CENTER := Vector3(170.0, 0.0, -300.0) ## 世界坐标：村东南约 170m 林间空地
const HOUSE_W := 12.0 ## 房屋东西向宽
const HOUSE_D := 10.0 ## 房屋南北向深（中心 z=-6）
const WALL_H := 3.2
const FLOOR_TOP := 0.15 ## 地板顶面离地高度（垫高防埋）
const BUILD_DELAY := 3.0 ## M34 铁律：等地形数据就绪再采样贴地

var _ground_y: float = 0.0 ## HOME_CENTER 处地面高度
var _terrain: Terrain3D = null

# 材质缓存（构建时统一创建）
var _mats: Dictionary = {}


func _ready() -> void:
	# M34 铁律：Terrain3D data_directory 异步加载，_ready 时地形未就绪，
	# get_height 会读到 NaN。延时到数据就绪再建家园（balloon_arena 同款 3s）。
	get_tree().create_timer(BUILD_DELAY).timeout.connect(_build_home)


func _build_home() -> void:
	_terrain = _find_terrain()
	_ground_y = _probe_ground_y()
	global_position = HOME_CENTER + Vector3(0.0, _ground_y, 0.0)
	_init_mats()
	_build_foundation()
	_build_garden()
	_build_house()
	_build_kitchen()
	_build_living_room()
	printerr("[Home] 家园已构建 center=", HOME_CENTER, " ground_y=", _ground_y)
	# 一次性取证参数 --home_shot：延时 4s 等两个传送门都就位后，
	# 把本地玩家传送过门拍照（顺带实测传送链路）。正式玩法不触发。
	if OS.get_cmdline_user_args().has("--home_shot"):
		get_tree().create_timer(4.0).timeout.connect(_home_shot_teleport)


## 取证：把本地玩家放到房正北 10m（相机在玩家 -Z 侧，镜头正对房子与门廊）
func _home_shot_teleport() -> void:
	if not multiplayer.is_server():
		return
	var level_scene := get_tree().current_scene
	if level_scene == null or not level_scene.has_method("_get_local_player"):
		return
	var player := level_scene._get_local_player() as Node3D
	if player == null:
		return
	if player.get("mounted_vehicle") != null and player.has_method("set_mounted"):
		player.set_mounted(null)
	player.global_position = HOME_CENTER + Vector3(0.0, 0.3, 15.0) ## 家南 15m 花园中，镜头北向看房全景
	player.global_rotation.y = 0.0
	printerr("[Home] 取证传送完成 world=", player.global_position)
	get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(player):
			printerr("[Home] 5s 后玩家位置=", player.global_position, " rot=", player.global_rotation.y))


# ===== 地形辅助 =====
func _find_terrain() -> Terrain3D:
	var tn := get_node_or_null("../TerrainStarter")
	if tn != null and tn.get("terrain") != null:
		return tn.get("terrain") as Terrain3D
	return null


func _probe_ground_y() -> float:
	var query := PhysicsRayQueryParameters3D.new()
	query.from = HOME_CENTER + Vector3(0.0, 60.0, 0.0)
	query.to = HOME_CENTER + Vector3(0.0, -10.0, 0.0)
	query.collision_mask = 2
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and is_finite(hit.position.y):
		return hit.position.y
	return 0.0


## 世界坐标 -> 离 HOME_CENTER 地面的局部 y。
## 家园区域已由 _build_foundation 铺平为地台（顶面 y=0），
## 所有花园/建筑装饰贴地台平面，不再逐点探测丘陵地形（±7m 起伏会悬空/埋地）。
func _local_y(_world_x: float, _world_z: float) -> float:
	return 0.0


## 地基平台：40x40m 木石地台（顶面 y=0）+ 碰撞体（layer 2 与村庄平台同层，玩家 mask=7 覆盖）。
## M37：丘陵地形 ±7m 起伏直接建房会悬空/埋地（实测 10m 外落差 3.9m），
## 整块垫平是最稳解，也契合 WoW 家园"宅基地"观感。
func _build_foundation() -> void:
	var body := StaticBody3D.new()
	body.name = "FoundationBody"
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.6, 40.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.3, 0.0)
	body.add_child(shape)
	add_child(body)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.3, 0.22)
	mat.roughness = 0.95
	var slab := MeshInstance3D.new()
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(40.0, 0.6, 40.0)
	slab.mesh = slab_mesh
	slab.position = Vector3(0.0, -0.3, 0.0)
	slab.material_override = mat
	add_child(slab)


# ===== 构建辅助 =====
func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _add_sphere(parent: Node3D, radius: float, pos: Vector3, mat: StandardMaterial3D,
		scale: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 10
	s.rings = 6
	mi.mesh = s
	mi.position = pos
	mi.scale = scale
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _add_cylinder(parent: Node3D, radius: float, height: float, pos: Vector3,
		mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 10
	mi.mesh = c
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _add_collision_box(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	body.add_child(shape)
	parent.add_child(body)


func _init_mats() -> void:
	_mats["wood_dark"] = _mat(Color(0.32, 0.21, 0.12), 0.85)
	_mats["wood"] = _mat(Color(0.45, 0.31, 0.18), 0.8)
	_mats["wood_light"] = _mat(Color(0.58, 0.42, 0.26), 0.75)
	_mats["floor"] = _mat(Color(0.5, 0.36, 0.22), 0.7)
	_mats["stone"] = _mat(Color(0.55, 0.54, 0.52), 0.95)
	_mats["stone_dark"] = _mat(Color(0.38, 0.37, 0.35), 0.95)
	_mats["metal"] = _mat(Color(0.72, 0.74, 0.78), 0.35, 0.3)
	_mats["gold"] = _mat(Color(0.85, 0.68, 0.25), 0.4, 0.55)
	_mats["black"] = _mat(Color(0.1, 0.1, 0.11), 0.6)
	_mats["marble"] = _mat(Color(0.85, 0.83, 0.78), 0.3)
	_mats["fabric_orange"] = _mat(Color(0.85, 0.45, 0.18), 0.95)
	_mats["fabric_white"] = _mat(Color(0.9, 0.88, 0.82), 0.95)
	_mats["blanket_blue"] = _mat(Color(0.2, 0.35, 0.65), 0.95)
	_mats["soil"] = _mat(Color(0.28, 0.2, 0.13), 1.0)
	_mats["leaf"] = _mat(Color(0.18, 0.34, 0.15), 0.9)
	_mats["leaf_light"] = _mat(Color(0.3, 0.45, 0.2), 0.9)
	_mats["leaf_purple"] = _mat(Color(0.5, 0.14, 0.38), 0.85)
	_mats["flower_yellow"] = _mat(Color(0.95, 0.78, 0.15), 0.8)
	_mats["flower_white"] = _mat(Color(0.92, 0.92, 0.88), 0.8)
	_mats["grass"] = _mat(Color(0.24, 0.38, 0.18), 0.95)
	# 玻璃（大窗看花园）
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.82, 0.88, 0.22)
	glass.roughness = 0.08
	glass.metallic = 0.25
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats["glass"] = glass
	# 暖光自发光（灯带/灯泡/火光）
	var glow_warm := StandardMaterial3D.new()
	glow_warm.albedo_color = Color(1.0, 0.82, 0.5)
	glow_warm.emission_enabled = true
	glow_warm.emission = Color(1.0, 0.75, 0.38)
	glow_warm.emission_energy_multiplier = 1.6
	_mats["glow_warm"] = glow_warm
	var glow_fire := StandardMaterial3D.new()
	glow_fire.albedo_color = Color(1.0, 0.5, 0.15)
	glow_fire.emission_enabled = true
	glow_fire.emission = Color(1.0, 0.42, 0.1)
	glow_fire.emission_energy_multiplier = 2.2
	_mats["glow_fire"] = glow_fire


func _mat(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


# ===== 花园（先建，房屋压在其后）=====
func _build_garden() -> void:
	var g := Node3D.new()
	g.name = "Garden"
	add_child(g)
	var hw := HOUSE_W * 0.5
	_build_deck(g, hw)
	_build_flower_beds(g)
	_build_path_stones(g)
	_build_big_tree(g)
	_build_rocks(g)
	_build_fairy_lights(g)
	_build_deck_chair(g)
	_build_fence(g)
	_build_grass_tufts(g)


## 木平台甲板（房前 14 x 7.2m，木板条 + 支撑柱 + 围栏）
func _build_deck(parent: Node3D, hw: float) -> void:
	var deck := Node3D.new()
	deck.name = "Deck"
	parent.add_child(deck)
	# 木板条（沿 x 排，0.14m 宽）
	var z := -0.6
	while z < 6.6:
		var wx := HOME_CENTER.x
		var wz: float = HOME_CENTER.z + z
		var mi := _add_box(deck, Vector3(14.0, 0.12, 0.13),
			Vector3(0.0, _local_y(wx, wz) + 0.06, z), _mats["floor"])
		mi.name = "Plank"
		z += 0.16
	# 支撑柱（四角 + 中间）
	for px in [-6.6, 0.0, 6.6]:
		for pz in [-0.4, 6.2]:
			var wx: float = HOME_CENTER.x + px
			var wz: float = HOME_CENTER.z + pz
			_add_cylinder(deck, 0.09, 0.5, Vector3(px, _local_y(wx, wz) + 0.25, pz), _mats["wood_dark"])
	# 甲板围栏（南侧 + 两侧，留中缺口下花园）
	for px in [-6.8, 6.8]:
		_add_box(deck, Vector3(0.1, 0.95, 7.0), Vector3(px, 0.55, 3.0), _mats["wood"])
	_add_box(deck, Vector3(14.0, 0.1, 0.1), Vector3(0.0, 0.95, -0.65), _mats["wood"])
	# 台阶（甲板中缺口下花园；地台时代差极小，贴地台面）
	for i in 3:
		var sz: float = 6.7 + float(i) * 0.28
		_add_box(deck, Vector3(2.4, 0.1, 0.26),
			Vector3(0.0, 0.05, sz), _mats["floor"])


## 黄色花圃三池（参考图视觉核心：甲板前一排金黄）+ 紫红阔叶丛
func _build_flower_beds(parent: Node3D) -> void:
	var beds := Node3D.new()
	beds.name = "FlowerBeds"
	parent.add_child(beds)
	for bx in [-5.2, -0.4, 4.4]:
		var bed := Node3D.new()
		bed.position = Vector3(bx, 0.0, 9.6)
		beds.add_child(bed)
		# 土池
		var wx: float = HOME_CENTER.x + bx
		var wz: float = HOME_CENTER.z + 9.6
		var base_y: float = _local_y(wx, wz)
		_add_box(bed, Vector3(2.5, 0.25, 1.4), Vector3(0.0, base_y - 0.1, 0.0), _mats["soil"])
		# 木围边
		_add_box(bed, Vector3(2.6, 0.16, 0.1), Vector3(0.0, base_y + 0.02, 0.68), _mats["wood"])
		_add_box(bed, Vector3(2.6, 0.16, 0.1), Vector3(0.0, base_y + 0.02, -0.68), _mats["wood"])
		_add_box(bed, Vector3(0.1, 0.16, 1.5), Vector3(-1.28, base_y + 0.02, 0.0), _mats["wood"])
		_add_box(bed, Vector3(0.1, 0.16, 1.5), Vector3(1.28, base_y + 0.02, 0.0), _mats["wood"])
		# 金黄花朵 12 朵（确定性网格排布 + 茎）
		for i in 12:
			var fx: float = -1.0 + 0.32 * float(i % 5)
			var fz: float = -0.42 + 0.42 * float(i / 5)
			var hy: float = _local_y(HOME_CENTER.x + bx + fx, HOME_CENTER.z + 9.6 + fz) - base_y
			_add_cylinder(bed, 0.014, 0.34, Vector3(fx, hy + 0.17, fz), _mats["leaf"])
			_add_sphere(bed, 0.085, Vector3(fx, hy + 0.4, fz), _mats["flower_yellow"])
			_add_sphere(bed, 0.05, Vector3(fx, hy + 0.46, fz), _mats["flower_white"], Vector3(0.7, 0.5, 0.7))
	# 紫红阔叶植物丛（花圃东侧，参考图右侧大红叶）
	for pi in [Vector2(9.2, 11.5), Vector2(11.0, 14.0), Vector2(-12.5, 10.5)]:
		var plant := Node3D.new()
		var wx2: float = HOME_CENTER.x + pi.x
		var wz2: float = HOME_CENTER.z + pi.y
		var py: float = _local_y(wx2, wz2)
		plant.position = Vector3(pi.x, py, pi.y)
		parent.add_child(plant)
		for k in 5:
			var ang: float = TAU * float(k) / 5.0
			var lf := _add_sphere(plant, 0.34,
				Vector3(cos(ang) * 0.42, 0.5 + 0.12 * float(k % 3), sin(ang) * 0.42),
				_mats["leaf_purple"] if k % 2 == 0 else _mats["leaf"],
				Vector3(1.0, 0.62, 1.0), Vector3(0.3, ang, 0.2))
		_add_sphere(plant, 0.3, Vector3(0.0, 0.42, 0.0), _mats["leaf_light"], Vector3(1.0, 0.7, 1.0))


## 石头步道（甲板往南 5 块扁平石）
func _build_path_stones(parent: Node3D) -> void:
	var path := Node3D.new()
	path.name = "Path"
	parent.add_child(path)
	for i in 5:
		var pz: float = 12.8 + float(i) * 2.1
		var px: float = -0.6 + 1.2 * float(i % 2)
		var wx: float = HOME_CENTER.x + px
		var wz: float = HOME_CENTER.z + pz
		var sy: float = _local_y(wx, wz)
		var stone := _add_sphere(path, 0.42,
			Vector3(px, sy + 0.05, pz), _mats["stone"], Vector3(1.0, 0.16, 0.78))
		stone.rotation.y = float(i) * 0.7


## 大树（花园东南，参考图左侧大树剪影）
func _build_big_tree(parent: Node3D) -> void:
	var tree := Node3D.new()
	tree.name = "BigTree"
	var tx := 12.0
	var tz := 17.5
	var wx: float = HOME_CENTER.x + tx
	var wz: float = HOME_CENTER.z + tz
	tree.position = Vector3(tx, _local_y(wx, wz), tz)
	parent.add_child(tree)
	_add_cylinder(tree, 0.3, 5.4, Vector3(0.0, 2.7, 0.0), _mats["wood_dark"])
	# 两根枝
	_add_cylinder(tree, 0.12, 2.2, Vector3(1.1, 4.2, 0.3), _mats["wood_dark"]).rotation.z = -0.7
	_add_cylinder(tree, 0.12, 2.0, Vector3(-0.9, 4.5, -0.4), _mats["wood_dark"]).rotation.z = 0.6
	# 三层绿冠
	_add_sphere(tree, 2.6, Vector3(0.0, 6.2, 0.0), _mats["leaf"], Vector3(1.0, 0.82, 1.0))
	_add_sphere(tree, 1.9, Vector3(1.4, 5.4, 0.5), _mats["leaf_light"])
	_add_sphere(tree, 1.8, Vector3(-1.3, 5.6, -0.6), _mats["leaf"])


## 岩石（花园西南两丛）
func _build_rocks(parent: Node3D) -> void:
	var rocks := Node3D.new()
	rocks.name = "Rocks"
	parent.add_child(rocks)
	for r in [Vector3(-12.0, 13.0, 1.0), Vector3(-13.6, 15.2, 0.7), Vector3(-11.2, 15.8, 1.3)]:
		var wx: float = HOME_CENTER.x + r.x
		var wz: float = HOME_CENTER.z + r.y
		_add_sphere(rocks, r.z, Vector3(r.x, _local_y(wx, wz) + 0.1, r.y),
			_mats["stone"], Vector3(1.0, 0.66, 0.9), Vector3(0.2, r.x, 0.15))


## 串灯（大树 <-> 房檐 <-> 西侧，两绳 + 发光灯泡）
func _build_fairy_lights(parent: Node3D) -> void:
	var lights := Node3D.new()
	lights.name = "FairyLights"
	parent.add_child(lights)
	var bulb_mat: StandardMaterial3D = _mats["glow_warm"]
	var cord_mat := _mat(Color(0.2, 0.18, 0.15), 1.0)
	# 绳1：大树顶 (12,6.4,17.5) -> 房东南檐 (6.2,2.9,-0.4)
	_add_cord(lights, Vector3(12.0, 6.2, 17.5), Vector3(6.2, 2.9, -0.4), cord_mat, bulb_mat, 9)
	# 绳2：房西南檐 (-6.2,2.9,-0.4) -> 西侧岩石后立杆 (-13.5,3.4,10.0)
	_add_cord(lights, Vector3(-6.2, 2.9, -0.4), Vector3(-13.5, 3.4, 10.0), cord_mat, bulb_mat, 8)
	# 串灯共享暖光点光源（挂绳中点）
	var mid := (Vector3(12.0, 6.2, 17.5) + Vector3(6.2, 2.9, -0.4)) * 0.5
	var wxm: float = HOME_CENTER.x + mid.x
	var wzm: float = HOME_CENTER.z + mid.z
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 1.6
	light.omni_range = 9.0
	light.position = Vector3(mid.x, _local_y(wxm, wzm) + mid.y - 1.0, mid.z)
	lights.add_child(light)


## 一条灯绳：分段圆柱近似下垂 + 灯泡
func _add_cord(parent: Node3D, a: Vector3, b: Vector3, cord_mat: StandardMaterial3D,
		bulb_mat: StandardMaterial3D, bulb_count: int) -> void:
	var segs := 8
	var sag := 0.9
	for i in segs:
		var t0: float = float(i) / float(segs)
		var t1: float = float(i + 1) / float(segs)
		var p0: Vector3 = _cord_point(a, b, t0, sag)
		var p1: Vector3 = _cord_point(a, b, t1, sag)
		var diff: Vector3 = p1 - p0
		var len: float = diff.length()
		if len < 0.001:
			continue
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.012
		c.bottom_radius = 0.012
		c.height = len
		c.radial_segments = 4
		mi.mesh = c
		# Y 轴对齐绳方向
		var y_axis: Vector3 = diff / len
		var x_axis: Vector3 = y_axis.cross(Vector3.UP)
		if x_axis.length() < 0.001:
			x_axis = Vector3.RIGHT
		else:
			x_axis = x_axis.normalized()
		var z_axis: Vector3 = x_axis.cross(y_axis)
		mi.transform = Transform3D(Basis(x_axis, y_axis, z_axis), (p0 + p1) * 0.5)
		mi.material_override = cord_mat
		parent.add_child(mi)
	# 灯泡（挂在绳下垂最低点附近均匀分布）
	for i in bulb_count:
		var t: float = float(i + 1) / float(bulb_count + 1)
		var p: Vector3 = _cord_point(a, b, t, sag)
		_add_sphere(parent, 0.07, p + Vector3(0.0, -0.07, 0.0), bulb_mat)


func _cord_point(a: Vector3, b: Vector3, t: float, sag: float) -> Vector3:
	var p: Vector3 = a.lerp(b, t)
	p.y -= sag * sin(PI * t)
	return p


## 躺椅 + 望远镜（甲板西侧，参考图左侧）
func _build_deck_chair(parent: Node3D) -> void:
	var chair := Node3D.new()
	chair.name = "Lounger"
	var cx := -6.0
	var cz := 3.2
	var wx: float = HOME_CENTER.x + cx
	var wz: float = HOME_CENTER.z + cz
	var base_y: float = _local_y(wx, wz)
	chair.position = Vector3(cx, base_y + 0.12, cz)
	chair.rotation.y = PI * 0.5
	parent.add_child(chair)
	# 椅座 + 靠背（斜）
	_add_box(chair, Vector3(0.62, 0.1, 1.9), Vector3(0.0, 0.42, 0.0), _mats["wood"])
	_add_box(chair, Vector3(0.62, 0.08, 0.95), Vector3(0.0, 0.72, -1.0), _mats["fabric_orange"],
		Vector3(-0.5, 0.0, 0.0))
	# 布面（座/靠）
	_add_box(chair, Vector3(0.58, 0.06, 1.8), Vector3(0.0, 0.48, 0.0), _mats["fabric_orange"])
	_add_box(chair, Vector3(0.58, 0.05, 0.9), Vector3(0.0, 0.78, -1.02), _mats["fabric_orange"],
		Vector3(-0.5, 0.0, 0.0))
	# 两条腿
	for lz in [0.8, -0.8]:
		_add_box(chair, Vector3(0.56, 0.42, 0.08), Vector3(0.0, 0.21, lz), _mats["wood_dark"])
	# 望远镜三脚架 + 镜筒
	var scope := Node3D.new()
	scope.position = Vector3(0.9, 0.0, -0.3)
	scope.rotation.y = -0.6
	chair.add_child(scope)
	for ang in [0.0, 2.1, 4.2]:
		var leg := _add_cylinder(scope, 0.025, 1.1, Vector3(0.0, 0.55, 0.0), _mats["metal"])
		leg.rotation = Vector3(0.25 * cos(ang), ang, 0.25 * sin(ang))
	_add_cylinder(scope, 0.09, 0.75, Vector3(0.0, 1.2, 0.0), _mats["gold"]).rotation.z = PI * 0.5
	_add_sphere(scope, 0.11, Vector3(0.4, 1.2, 0.0), _mats["gold"])
	_add_sphere(scope, 0.09, Vector3(-0.4, 1.2, 0.0), _mats["gold"])


## 四周矮篱笆（花园边界）
func _build_fence(parent: Node3D) -> void:
	var fence := Node3D.new()
	fence.name = "Fence"
	parent.add_child(fence)
	# 两侧（x = ±17，z 1~29）+ 远端（z = 29）
	var posts: Array[Vector2] = []
	var zz := 1.0
	while zz < 29.5:
		posts.append(Vector2(-17.0, zz))
		posts.append(Vector2(17.0, zz))
		zz += 1.7
	var xx := -17.0
	while xx < 17.5:
		posts.append(Vector2(xx, 29.0))
		xx += 1.7
	for p in posts:
		var wx: float = HOME_CENTER.x + p.x
		var wz: float = HOME_CENTER.z + p.y
		var fy: float = _local_y(wx, wz)
		_add_box(fence, Vector3(0.09, 0.95, 0.09), Vector3(p.x, fy + 0.48, p.y), _mats["wood"])
	# 横杆逐段贴地（每 3.3m 一段，避免长盒穿越坡面）
	for fx in [-17.0, 17.0]:
		var zz2 := 1.0
		while zz2 < 29.0:
			var wx2: float = HOME_CENTER.x + fx
			var wz2: float = HOME_CENTER.z + zz2
			_add_box(fence, Vector3(0.05, 0.05, 3.3), Vector3(fx, _local_y(wx2, wz2) + 0.45, zz2 + 1.65), _mats["wood_light"])
			_add_box(fence, Vector3(0.05, 0.05, 3.3), Vector3(fx, _local_y(wx2, wz2) + 0.85, zz2 + 1.65), _mats["wood_light"])
			zz2 += 3.3
	var xx2 := -17.0
	while xx2 < 29.0 + 17.0:
		var wx3: float = HOME_CENTER.x + xx2
		var wz3: float = HOME_CENTER.z + 29.0
		_add_box(fence, Vector3(3.3, 0.05, 0.05), Vector3(xx2 + 1.65, _local_y(wx3, wz3) + 0.45, 29.0), _mats["wood_light"])
		_add_box(fence, Vector3(3.3, 0.05, 0.05), Vector3(xx2 + 1.65, _local_y(wx3, wz3) + 0.85, 29.0), _mats["wood_light"])
		xx2 += 3.3


## 草丛散布（确定性伪随机）
func _build_grass_tufts(parent: Node3D) -> void:
	var grass := Node3D.new()
	grass.name = "Grass"
	parent.add_child(grass)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261021
	for i in 40:
		var gx: float = rng.randf_range(-16.0, 16.0)
		var gz: float = rng.randf_range(1.5, 28.0)
		if absf(gx) < 8.0 and gz < 7.5:
			continue # 甲板区不种草
		if absf(gz - 9.6) < 1.2 and absf(gx) < 7.5:
			continue # 花圃区
		var wx: float = HOME_CENTER.x + gx
		var wz: float = HOME_CENTER.z + gz
		var gy: float = _local_y(wx, wz)
		var tuft := Node3D.new()
		tuft.position = Vector3(gx, gy, gz)
		grass.add_child(tuft)
		for k in 4:
			_add_sphere(tuft, 0.13 + 0.05 * float(k % 2),
				Vector3(0.1 * float(k % 3) - 0.1, 0.1 + 0.06 * float(k), 0.08 * float(k / 3) - 0.04),
				_mats["grass"], Vector3(1.0, 0.7, 1.0), Vector3(0.1, float(k), 0.1))


# ===== 房屋 =====
func _build_house() -> void:
	var house := Node3D.new()
	house.name = "House"
	add_child(house)
	var hw := HOUSE_W * 0.5
	var cz := -HOUSE_D * 0.5 # 中心 z=-5
	# 地板 + 天花
	_add_box(house, Vector3(HOUSE_W + 0.6, 0.3, HOUSE_D + 0.6),
		Vector3(0.0, FLOOR_TOP - 0.15, cz), _mats["floor"])
	# 地板碰撞（玩家进屋踩地板，不掉到地台面）
	_add_collision_box(house, Vector3(HOUSE_W + 0.6, 0.3, HOUSE_D + 0.6),
		Vector3(0.0, FLOOR_TOP - 0.15, cz))
	_add_box(house, Vector3(HOUSE_W + 0.7, 0.22, HOUSE_D + 0.7),
		Vector3(0.0, WALL_H + 0.32, cz), _mats["wood_dark"])
	# 北墙（z = cz-5）+ 两扇大窗
	_build_wall_with_windows(house, Vector3(0.0, 0.0, cz - HOUSE_D * 0.5), true,
		[-3.2, 3.2], Vector3(0.0, 0.0, -1.0))
	# 南墙（z = cz+5）：中门 + 两窗
	_build_south_wall(house, cz)
	# 东墙 + 西墙：整面大玻璃
	_build_wall_with_windows(house, Vector3(hw, 0.0, cz), false,
		[0.0], Vector3(1.0, 0.0, 0.0))
	_build_wall_with_windows(house, Vector3(-hw, 0.0, cz), false,
		[0.0], Vector3(-1.0, 0.0, 0.0))
	# 斜坡屋顶（两块斜板）+ 东西山墙（PrismMesh）
	var roof := Node3D.new()
	roof.name = "Roof"
	house.add_child(roof)
	var roof_mat := _mat(Color(0.42, 0.22, 0.14), 0.85)
	var slope_len := HOUSE_D * 0.62
	for sz in [-1.0, 1.0]:
		var panel := _add_box(roof, Vector3(HOUSE_W + 1.2, 0.14, slope_len),
			Vector3(0.0, WALL_H + 1.55, cz + sz * 1.55), roof_mat)
		panel.rotation.x = sz * 0.62
	# 山墙（三角棱柱）
	for sx in [-1.0, 1.0]:
		var gable := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(HOUSE_D + 0.55, 1.9, 0.2)
		gable.mesh = pm
		gable.position = Vector3(sx * (hw + 0.02), WALL_H + 1.5, cz)
		gable.rotation.y = PI * 0.5
		gable.material_override = _mats["wood"]
		roof.add_child(gable)
	# 门廊雨棚（南门外小坡顶）
	var awning := _add_box(house, Vector3(3.2, 0.1, 1.6),
		Vector3(0.0, 2.5, cz + HOUSE_D * 0.5 + 0.8), roof_mat)
	awning.rotation.x = 0.35
	# 门廊灯（暖光）
	var porch_light := OmniLight3D.new()
	porch_light.light_color = Color(1.0, 0.78, 0.45)
	porch_light.light_energy = 1.8
	porch_light.omni_range = 7.0
	porch_light.position = Vector3(0.0, 2.4, cz + HOUSE_D * 0.5 + 0.9)
	house.add_child(porch_light)
	var bulb := _add_sphere(house, 0.09, porch_light.position, _mats["glow_warm"])


## 带窗的墙（窗位置给局部偏移表）
func _build_wall_with_windows(parent: Node3D, center: Vector3, along_x: bool,
		window_offsets: Array, normal: Vector3) -> void:
	var wall := Node3D.new()
	wall.position = center
	wall.rotation.y = 0.0 if along_x else PI * 0.5
	parent.add_child(wall)
	var length: float = HOUSE_W if along_x else HOUSE_D
	var width: float = HOUSE_D if along_x else HOUSE_W
	# 墙体（沿墙局部 x = 长度方向，y = 高）
	_add_box(wall, Vector3(length, WALL_H, 0.24), Vector3(0.0, FLOOR_TOP + WALL_H * 0.5, 0.0), _mats["wood"])
	# 窗（玻璃 + 木框，参考图2 大玻璃）
	for off in window_offsets:
		var win_w: float = 4.6 if not along_x else 3.6
		var win_h: float = 2.1
		var wy: float = FLOOR_TOP + 1.55
		var glass_mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(win_w, win_h)
		glass_mi.mesh = quad
		glass_mi.position = Vector3(float(off), wy, 0.13)
		glass_mi.rotation.y = PI
		glass_mi.material_override = _mats["glass"]
		wall.add_child(glass_mi)
		# 木框（四边 + 中梃）
		var frame_mat: StandardMaterial3D = _mats["wood_dark"]
		_add_box(wall, Vector3(win_w + 0.16, 0.12, 0.1), Vector3(float(off), wy - win_h * 0.5 - 0.06, 0.14), frame_mat)
		_add_box(wall, Vector3(win_w + 0.16, 0.12, 0.1), Vector3(float(off), wy + win_h * 0.5 + 0.06, 0.14), frame_mat)
		_add_box(wall, Vector3(0.12, win_h + 0.24, 0.1), Vector3(float(off) - win_w * 0.5 - 0.06, wy, 0.14), frame_mat)
		_add_box(wall, Vector3(0.12, win_h + 0.24, 0.1), Vector3(float(off) + win_w * 0.5 + 0.06, wy, 0.14), frame_mat)
		_add_box(wall, Vector3(0.08, win_h, 0.1), Vector3(float(off), wy, 0.14), frame_mat)
		_add_box(wall, Vector3(win_w, 0.08, 0.1), Vector3(float(off), wy, 0.14), frame_mat)


## 南墙：中门 + 两窗
func _build_south_wall(parent: Node3D, cz: float) -> void:
	var wall := Node3D.new()
	wall.position = Vector3(0.0, 0.0, cz + HOUSE_D * 0.5)
	parent.add_child(wall)
	# 门洞两段墙
	_add_box(wall, Vector3(5.1, WALL_H, 0.24), Vector3(-3.45, FLOOR_TOP + WALL_H * 0.5, 0.0), _mats["wood"])
	_add_box(wall, Vector3(5.1, WALL_H, 0.24), Vector3(3.45, FLOOR_TOP + WALL_H * 0.5, 0.0), _mats["wood"])
	# 门楣
	_add_box(wall, Vector3(2.8, 0.9, 0.24), Vector3(0.0, FLOOR_TOP + 2.75, 0.0), _mats["wood"])
	# 门框
	_add_box(wall, Vector3(0.14, 2.3, 0.34), Vector3(-0.85, FLOOR_TOP + 1.15, 0.05), _mats["wood_dark"])
	_add_box(wall, Vector3(0.14, 2.3, 0.34), Vector3(0.85, FLOOR_TOP + 1.15, 0.05), _mats["wood_dark"])
	_add_box(wall, Vector3(1.9, 0.14, 0.34), Vector3(0.0, FLOOR_TOP + 2.3, 0.05), _mats["wood_dark"])
	# 双开木门（微开 20°）
	for sd in [-1.0, 1.0]:
		var door := Node3D.new()
		door.position = Vector3(sd * 0.44, FLOOR_TOP + 1.1, 0.06)
		door.rotation.y = sd * 0.35
		wall.add_child(door)
		_add_box(door, Vector3(0.84, 2.16, 0.06), Vector3(sd * 0.42, 0.0, 0.0), _mats["wood_light"])
		_add_sphere(door, 0.05, Vector3(sd * 0.32, 0.0, 0.05), _mats["gold"])
	# 门侧两窗（小）
	for off in [-3.45, 3.45]:
		var win_w := 2.6
		var win_h := 1.5
		var wy: float = FLOOR_TOP + 1.7
		var glass_mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(win_w, win_h)
		glass_mi.mesh = quad
		glass_mi.position = Vector3(off, wy, 0.13)
		glass_mi.rotation.y = PI
		glass_mi.material_override = _mats["glass"]
		wall.add_child(glass_mi)
		var frame_mat: StandardMaterial3D = _mats["wood_dark"]
		_add_box(wall, Vector3(win_w + 0.14, 0.1, 0.1), Vector3(off, wy - win_h * 0.5 - 0.05, 0.14), frame_mat)
		_add_box(wall, Vector3(win_w + 0.14, 0.1, 0.1), Vector3(off, wy + win_h * 0.5 + 0.05, 0.14), frame_mat)
		_add_box(wall, Vector3(0.1, win_h + 0.2, 0.1), Vector3(off - win_w * 0.5 - 0.05, wy, 0.14), frame_mat)
		_add_box(wall, Vector3(0.1, win_h + 0.2, 0.1), Vector3(off + win_w * 0.5 + 0.05, wy, 0.14), frame_mat)


# ===== 室内（局部坐标，相对 House 节点）=====

## 厨房（东北角 L 型橱柜 + 灶台油烟机 + 冰箱 + 中岛水果）
func _build_kitchen() -> void:
	var house := get_node_or_null("House")
	if house == null:
		return
	var k := Node3D.new()
	k.name = "Kitchen"
	house.add_child(k)
	var fy := FLOOR_TOP
	# ---- L 型地柜：北段（靠北墙）+ 东段（靠东墙）----
	# 北段 x 2.2~5.8
	_build_cabinet_run(k, Vector3(4.0, fy, -9.55), 3.6, true, false)
	# 东段 z -9.4~-6.4（靠东墙，柜背贴 x=5.9）
	_build_cabinet_run(k, Vector3(5.55, fy, -7.9), 3.0, false, true)
	# 吊柜（北墙上段）
	_build_cabinet_run(k, Vector3(4.0, fy + 1.62, -9.85), 3.6, true, true)
	# ---- 黑色灶台（东段柜台上，两口灶 + 锅）----
	var stove := Node3D.new()
	stove.position = Vector3(5.35, fy + 0.88, -8.9)
	k.add_child(stove)
	_add_box(stove, Vector3(0.62, 0.05, 1.5), Vector3(0.0, 0.03, 0.0), _mats["black"])
	for sz in [-0.5, 0.5]:
		_add_cylinder(stove, 0.17, 0.04, Vector3(0.0, 0.06, sz), _mats["black"])
	# 锅（球 + 双耳 + 盖）
	_add_sphere(stove, 0.19, Vector3(0.06, 0.2, -0.5), _mats["metal"], Vector3(1.0, 0.7, 1.0))
	_add_sphere(stove, 0.13, Vector3(0.06, 0.34, -0.5), _mats["metal"])
	# 抽油烟机（东墙上，下宽上窄梯形两盒）
	var hood := Node3D.new()
	hood.position = Vector3(5.72, fy + 1.15, -8.9)
	k.add_child(hood)
	_add_box(hood, Vector3(0.5, 0.55, 1.4), Vector3(0.0, -0.28, 0.0), _mats["metal"])
	_add_box(hood, Vector3(0.34, 0.5, 0.9), Vector3(0.0, 0.24, 0.0), _mats["metal"])
	_add_cylinder(hood, 0.13, 0.7, Vector3(0.0, 0.85, 0.0), _mats["metal"])
	# ---- 冰箱（东北角）----
	var fridge := Node3D.new()
	fridge.position = Vector3(5.35, fy, -1.1)
	k.add_child(fridge)
	_add_box(fridge, Vector3(1.0, 1.95, 0.95), Vector3(0.0, 0.98, 0.0), _mats["fabric_white"])
	_add_box(fridge, Vector3(1.02, 0.06, 0.97), Vector3(0.0, 1.5, 0.0), _mats["metal"])
	_add_box(fridge, Vector3(0.05, 0.5, 0.05), Vector3(-0.42, 1.2, 0.5), _mats["gold"])
	_add_box(fridge, Vector3(0.05, 0.7, 0.05), Vector3(-0.42, 0.75, 0.5), _mats["gold"])
	# ---- 中岛 + 水果盘 ----
	var island := Node3D.new()
	island.position = Vector3(0.0, fy, -6.0)
	k.add_child(island)
	_add_box(island, Vector3(2.6, 0.85, 1.1), Vector3(0.0, 0.42, 0.0), _mats["wood"])
	_add_box(island, Vector3(2.75, 0.07, 1.25), Vector3(0.0, 0.88, 0.0), _mats["marble"])
	_add_box(island, Vector3(2.3, 0.1, 0.1), Vector3(0.0, 0.15, 0.5), _mats["wood_dark"]) # 踢脚
	# 水果盘（木盘 + 黄香蕉 3 + 红番茄 2 + 橙 1）
	_add_cylinder(island, 0.3, 0.05, Vector3(-0.7, 0.93, 0.0), _mats["wood_light"])
	for i in 3:
		_add_sphere(island, 0.075, Vector3(-0.82 + 0.14 * float(i), 1.0, -0.06 + 0.05 * float(i % 2)),
			_mats["flower_yellow"], Vector3(1.0, 0.55, 1.0), Vector3(0.0, 0.0, 0.4))
	_add_sphere(island, 0.08, Vector3(-0.66, 1.0, 0.1), _mat(Color(0.85, 0.2, 0.15), 0.6))
	_add_sphere(island, 0.08, Vector3(-0.58, 1.0, -0.08), _mat(Color(0.85, 0.2, 0.15), 0.6))
	_add_sphere(island, 0.085, Vector3(0.7, 0.98, 0.05), _mat(Color(0.95, 0.55, 0.1), 0.6))
	# 吧台凳两张
	for sx in [-0.55, 0.55]:
		var stool := Node3D.new()
		stool.position = Vector3(sx, fy, -4.6)
		k.add_child(stool)
		_add_cylinder(stool, 0.2, 0.08, Vector3(0.0, 0.62, 0.0), _mats["fabric_orange"])
		_add_cylinder(stool, 0.045, 0.6, Vector3(0.0, 0.31, 0.0), _mats["wood_dark"])
		_add_cylinder(stool, 0.16, 0.03, Vector3(0.0, 0.02, 0.0), _mats["wood_dark"])
	# 厨房灯带（吊柜下发光条 + 点光源）
	_add_box(k, Vector3(3.4, 0.04, 0.1), Vector3(4.0, fy + 1.52, -9.4), _mats["glow_warm"])
	var kl := OmniLight3D.new()
	kl.light_color = Color(1.0, 0.8, 0.5)
	kl.light_energy = 2.2
	kl.omni_range = 7.0
	kl.position = Vector3(4.0, fy + 1.45, -7.6)
	k.add_child(kl)


## 一段橱柜：柜体 + 台面 + 柜门分隔 + 金把手（along_x: 沿 x 展开）
func _build_cabinet_run(parent: Node3D, center: Vector3, length: float, along_x: bool,
		upper: bool) -> void:
	var cab := Node3D.new()
	cab.position = center
	parent.add_child(cab)
	if upper:
		# 吊柜：高 0.8 深 0.35
		_add_box(cab, Vector3(length, 0.8, 0.35), Vector3(0.0, 0.4, 0.0), _mats["wood"])
		_add_box(cab, Vector3(length, 0.06, 0.38), Vector3(0.0, 0.82, 0.0), _mats["wood_dark"])
		var doors := int(length / 0.9)
		for i in doors:
			var off: float = -length * 0.5 + 0.45 + 0.9 * float(i)
			if along_x:
				_add_box(cab, Vector3(0.03, 0.72, 0.32), Vector3(off, 0.4, 0.19), _mats["wood_light"])
				_add_sphere(cab, 0.035, Vector3(off + 0.32, 0.72, 0.22), _mats["gold"])
			else:
				_add_box(cab, Vector3(0.32, 0.72, 0.03), Vector3(0.19, 0.4, off), _mats["wood_light"])
				_add_sphere(cab, 0.035, Vector3(0.22, 0.72, off + 0.32), _mats["gold"])
		return
	# 地柜：高 0.88 深 0.62 + 大理石台面
	var size_x: float = length if along_x else 0.62
	var size_z: float = 0.62 if along_x else length
	_add_box(cab, Vector3(size_x, 0.88, size_z), Vector3(0.0, 0.44, 0.0), _mats["wood"])
	_add_box(cab, Vector3(size_x + 0.05, 0.06, size_z + 0.05), Vector3(0.0, 0.91, 0.0), _mats["marble"])
	# 柜门 + 金把手
	var doors := int(length / 0.9)
	for i in doors:
		var off: float = -length * 0.5 + 0.45 + 0.9 * float(i)
		if along_x:
			_add_box(cab, Vector3(0.03, 0.8, 0.6), Vector3(off, 0.44, 0.32), _mats["wood_light"])
			_add_sphere(cab, 0.035, Vector3(off + 0.34, 0.75, 0.35), _mats["gold"])
		else:
			_add_box(cab, Vector3(0.6, 0.8, 0.03), Vector3(0.32, 0.44, off), _mats["wood_light"])
			_add_sphere(cab, 0.035, Vector3(0.35, 0.75, off + 0.34), _mats["gold"])


## 客厅（西南）：沙发/茶几/地毯 + 卧室（西北）：床/书架 + 北墙壁炉 + 吊灯
func _build_living_room() -> void:
	var house := get_node_or_null("House")
	if house == null:
		return
	var l := Node3D.new()
	l.name = "LivingRoom"
	house.add_child(l)
	var fy := FLOOR_TOP
	# ---- 沙发（面朝东北，靠背在西）----
	var sofa := Node3D.new()
	sofa.position = Vector3(-3.6, fy, -3.2)
	sofa.rotation.y = PI * 0.25
	l.add_child(sofa)
	_add_box(sofa, Vector3(2.4, 0.42, 0.9), Vector3(0.0, 0.21, 0.0), _mats["fabric_orange"])
	_add_box(sofa, Vector3(2.4, 0.55, 0.22), Vector3(0.0, 0.62, -0.36), _mats["fabric_orange"])
	_add_box(sofa, Vector3(0.2, 0.5, 0.9), Vector3(-1.22, 0.25, 0.0), _mats["fabric_orange"])
	_add_box(sofa, Vector3(0.2, 0.5, 0.9), Vector3(1.22, 0.25, 0.0), _mats["fabric_orange"])
	# 坐垫 + 靠枕
	_add_box(sofa, Vector3(1.1, 0.12, 0.8), Vector3(-0.6, 0.48, 0.02), _mats["fabric_orange"])
	_add_box(sofa, Vector3(1.1, 0.12, 0.8), Vector3(0.6, 0.48, 0.02), _mats["fabric_orange"])
	_add_box(sofa, Vector3(0.5, 0.45, 0.16), Vector3(-0.5, 0.68, -0.18), _mats["fabric_white"], Vector3(0.25, 0, 0))
	_add_box(sofa, Vector3(0.5, 0.45, 0.16), Vector3(0.55, 0.68, -0.18), _mats["blanket_blue"], Vector3(-0.2, 0, 0))
	# ---- 茶几 ----
	var table := Node3D.new()
	table.position = Vector3(-2.1, fy, -2.6)
	l.add_child(table)
	_add_box(table, Vector3(1.0, 0.08, 0.5), Vector3(0.0, 0.42, 0.0), _mats["wood_light"])
	_add_box(table, Vector3(0.9, 0.38, 0.42), Vector3(0.0, 0.21, 0.0), _mats["wood"])
	for cx in [-0.4, 0.4]:
		for cz in [-0.18, 0.18]:
			_add_box(table, Vector3(0.06, 0.4, 0.06), Vector3(cx, 0.2, cz), _mats["wood_dark"])
	# 茶杯两盏
	_add_cylinder(table, 0.045, 0.09, Vector3(-0.22, 0.5, 0.0), _mats["fabric_white"])
	_add_cylinder(table, 0.045, 0.09, Vector3(0.22, 0.5, 0.0), _mats["blanket_blue"])
	# ---- 地毯 ----
	var rug := Node3D.new()
	rug.position = Vector3(-3.0, fy + 0.01, -3.0)
	l.add_child(rug)
	_add_box(rug, Vector3(3.4, 0.03, 2.8), Vector3(0.0, 0.0, 0.0), _mat(Color(0.62, 0.2, 0.16), 0.95))
	_add_box(rug, Vector3(3.0, 0.035, 2.4), Vector3(0.0, 0.005, 0.0), _mat(Color(0.75, 0.32, 0.22), 0.95))
	# ---- 床（西北角）----
	var bed := Node3D.new()
	bed.position = Vector3(-4.4, fy, -8.6)
	l.add_child(bed)
	_add_box(bed, Vector3(1.3, 0.35, 2.2), Vector3(0.0, 0.18, 0.0), _mats["wood_dark"])
	_add_box(bed, Vector3(1.2, 0.22, 2.1), Vector3(0.0, 0.46, 0.0), _mats["fabric_white"])
	_add_box(bed, Vector3(1.24, 0.1, 1.35), Vector3(0.0, 0.6, 0.32), _mats["blanket_blue"])
	_add_box(bed, Vector3(0.9, 0.14, 0.45), Vector3(0.0, 0.62, -0.78), _mats["fabric_white"])
	# 床头板
	_add_box(bed, Vector3(1.3, 0.9, 0.1), Vector3(0.0, 0.45, -1.15), _mats["wood"])
	# ---- 书架（西墙，4 层彩书）----
	var shelf := Node3D.new()
	shelf.position = Vector3(-5.6, fy, -6.2)
	l.add_child(shelf)
	_add_box(shelf, Vector3(0.34, 2.1, 2.2), Vector3(0.0, 1.05, 0.0), _mats["wood_dark"])
	var book_colors := [Color(0.6, 0.15, 0.15), Color(0.15, 0.3, 0.6), Color(0.2, 0.45, 0.2), Color(0.7, 0.55, 0.1)]
	for row in 4:
		var ry: float = 0.35 + 0.45 * float(row)
		_add_box(shelf, Vector3(0.28, 0.04, 2.1), Vector3(0.16, ry + 0.24, 0.0), _mats["wood_light"])
		for b in 6:
			var bm := StandardMaterial3D.new()
			bm.albedo_color = book_colors[(row + b) % 4]
			bm.roughness = 0.85
			_add_box(shelf, Vector3(0.2, 0.3, 0.14), Vector3(0.17, ry + 0.1, -0.8 + 0.3 * float(b)), bm)
	# ---- 壁炉（北墙中间）----
	var fp := Node3D.new()
	fp.position = Vector3(0.6, fy, -9.65)
	l.add_child(fp)
	_add_box(fp, Vector3(2.2, 1.5, 0.5), Vector3(0.0, 0.75, 0.0), _mats["stone"])
	_add_box(fp, Vector3(1.3, 0.95, 0.42), Vector3(0.0, 0.62, 0.05), _mats["black"])
	_add_box(fp, Vector3(1.5, 0.14, 0.56), Vector3(0.0, 1.58, 0.0), _mats["wood_dark"])
	# 火焰（3 颗发光球）+ 木柴
	_add_box(fp, Vector3(0.7, 0.08, 0.12), Vector3(0.0, 0.2, 0.1), _mats["wood_dark"])
	_add_sphere(fp, 0.16, Vector3(-0.16, 0.32, 0.08), _mats["glow_fire"], Vector3(1.0, 1.3, 1.0))
	_add_sphere(fp, 0.12, Vector3(0.14, 0.3, 0.06), _mats["glow_fire"], Vector3(1.0, 1.2, 1.0))
	_add_sphere(fp, 0.09, Vector3(0.0, 0.44, 0.05), _mats["glow_fire"], Vector3(1.0, 1.4, 1.0))
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.55, 0.2)
	fl.light_energy = 2.4
	fl.omni_range = 7.5
	fl.position = Vector3(0.0, 0.7, 0.4)
	fp.add_child(fl)
	# ---- 中央吊灯（绳 + 木盏 + 点光源）----
	var lamp := Node3D.new()
	lamp.position = Vector3(0.0, 0.0, -6.0)
	l.add_child(lamp)
	_add_cylinder(lamp, 0.015, 1.1, Vector3(0.0, WALL_H - 0.55, 0.0), _mats["wood_dark"])
	_add_cylinder(lamp, 0.24, 0.16, Vector3(0.0, WALL_H - 1.2, 0.0), _mats["wood"])
	_add_cylinder(lamp, 0.26, 0.06, Vector3(0.0, WALL_H - 1.3, 0.0), _mats["glow_warm"])
	var ll := OmniLight3D.new()
	ll.light_color = Color(1.0, 0.82, 0.55)
	ll.light_energy = 2.6
	ll.omni_range = 9.0
	ll.position = Vector3(0.0, WALL_H - 1.5, 0.0)
	lamp.add_child(ll)
	# ---- 北墙挂画（木框 + 远山色块）----
	var art := Node3D.new()
	art.position = Vector3(-3.2, 0.0, -9.85)
	l.add_child(art)
	_add_box(art, Vector3(1.3, 0.95, 0.06), Vector3(0.0, 2.1, 0.0), _mats["wood_dark"])
	_add_box(art, Vector3(1.1, 0.75, 0.03), Vector3(0.0, 2.1, 0.04), _mat(Color(0.55, 0.68, 0.78), 0.8))
	_add_sphere(art, 0.16, Vector3(-0.25, 2.3, 0.06), _mats["glow_warm"])
