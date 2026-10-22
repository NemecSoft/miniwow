class_name VillageLayout
extends Node3D

## 把 VillageData（随机生成的村庄布局 JSON）实例化成实体几何：
## 房屋 / 帐篷 / 谷仓 / 铁匠铺 / 箭塔、田地、桶箱车、火盆、图腾柱、旗帜。
##
## 【为什么程序化建模而不是直接用 KayKit 模型】
##   · 参考图是莫高雷草原部落 + 地狱火荒原，KayKit 是中世纪欧式小屋，风格不符
##   · 布局是随机数据（每栋尺寸/朝向都不同），程序化几何能逐栋贴合数据
##   · 单栋 3~5 个 mesh，61 栋 ≈ 250 个 draw call，帧率无压力
##
## 【确定性】同一份 JSON → 同样结果（所有随机都用固定 seed），
##   联机时各端本地生成不会出现建筑位置不一致。

const MAX_BUILDINGS := 400

var _mat_cache: Dictionary = {}


func build() -> void:
	# M45：自身归零 —— 子节点直接用 Planet.plane_transform() 算出的球面世界变换
	global_transform = Transform3D.IDENTITY
	VillageData.ensure_loaded()
	if VillageData.buildings.is_empty():
		printerr("[Village] 无布局数据，跳过")
		return
	var t0 := Time.get_ticks_msec()
	var root := Node3D.new()
	root.name = "Buildings"
	add_child(root)
	var created := 0
	for b in VillageData.buildings:
		if created >= MAX_BUILDINGS:
			break
		var node := _make_building(b)
		if node != null:
			root.add_child(node)
			created += 1
	_make_fields()
	_make_props()
	printerr("[Village] 建筑 %d 栋 / 田地 %d / 道具 %d，耗时 %dms" % [
		created, VillageData.fields.size(), VillageData.props.size(),
		Time.get_ticks_msec() - t0])


# ===== 材质 =====

func _mat(key: String, color: Color, rough: float = 0.9, metal: float = 0.0) -> StandardMaterial3D:
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	_mat_cache[key] = m
	return m


# ===== 建筑 =====

func _make_building(b: Dictionary) -> Node3D:
	var x := float(b.get("x", 0.0))
	var z := float(b.get("z", 0.0))
	var w := float(b.get("w", 9.0))
	var d := float(b.get("d", 9.0))
	var rot := float(b.get("rot", 0.0))
	var style := str(b.get("style", "hut"))
	var floors := int(b.get("floors", 1))
	var root := Node3D.new()
	root.name = "B_%s_%d" % [style, randi() % 10000]
	# M45：整栋建筑作为一个刚体旋到球面（局部仍是平面，尺度 10m 曲率无感）
	root.transform = Planet.plane_transform(x, z, rot)

	match style:
		"hut":
			_add_round_hut(root, w, d, floors)
		"tent":
			_add_tent(root, w * 0.9, d * 0.9)
		"barn":
			_add_barn(root, w, d, floors)
		"forge":
			_add_forge(root, w, d)
		"tower":
			_add_tower(root, w * 0.55, d * 0.55, 2 + floors)
		"wellhouse":
			_add_wellhouse(root, w * 0.7, d * 0.7)
		_:
			_add_house(root, w, d, floors)

	_add_collision(root, maxf(w * 0.72, 3.0), maxf(d * 0.72, 3.0), 4.5)
	return root


## M47：村庄小件同样要在远处消失（4600m 太空视角下屋顶/木桶都是黑点）
const DETAIL_RANGE := 900.0

func _mesh(parent: Node3D, m: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.visibility_range_end = DETAIL_RANGE
	mi.visibility_range_end_margin = 140.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(r_top: float, r_bot: float, h: float, seg: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


## 圆形土屋：夯土墙 + 圆锥茅草顶（莫高雷部落风）
func _add_round_hut(root: Node3D, w: float, d: float, floors: int) -> void:
	var r := (w + d) * 0.25
	var wall_h := 3.2 * floors
	_mesh(root, _cyl(r, r * 1.06, wall_h, 12), _mat("wall_earth", Color(0.52, 0.42, 0.30)), Vector3(0, wall_h * 0.5, 0))
	_mesh(root, _cyl(0.05, r * 1.18, 3.4 * floors, 12), _mat("roof_thatch", Color(0.60, 0.47, 0.24)), Vector3(0, wall_h + 1.7 * floors, 0))
	# 门洞（深色扁盒，贴在正面）
	_mesh(root, _box(Vector3(minf(r * 0.9, 2.0), 2.4, 0.18)), _mat("door", Color(0.20, 0.14, 0.09)),
		Vector3(0, 1.2, r * 0.97))
	# 二层加一圈木栏
	if floors > 1:
		_mesh(root, _cyl(r * 0.75, r * 0.75, 0.22, 12), _mat("wood_beam", Color(0.32, 0.23, 0.14)),
			Vector3(0, wall_h - 0.2, 0))
		_mesh(root, _cyl(r * 0.70, r * 0.70, 2.4, 12), _mat("wall_earth2", Color(0.56, 0.45, 0.33)),
			Vector3(0, wall_h + 1.2, 0))


## 兽皮帐篷
func _add_tent(root: Node3D, w: float, d: float) -> void:
	var r := (w + d) * 0.28
	_mesh(root, _cyl(0.06, r, 2.9, 8), _mat("tent_hide", Color(0.58, 0.44, 0.28), 0.95), Vector3(0, 1.45, 0))
	# 顶杆
	_mesh(root, _cyl(0.07, 0.05, 1.4, 5), _mat("wood_beam", Color(0.32, 0.23, 0.14)), Vector3(0, 3.4, 0))


## 长方形谷仓：木墙 + 双坡顶
func _add_barn(root: Node3D, w: float, d: float, floors: int) -> void:
	var h := 3.6 * floors
	_mesh(root, _box(Vector3(w, h, d)), _mat("wood_plank", Color(0.42, 0.30, 0.18)), Vector3(0, h * 0.5, 0))
	# 双坡顶：两块斜置薄板
	var roof_mat := _mat("roof_wood", Color(0.34, 0.24, 0.15))
	for s in [-1.0, 1.0]:
		var slab := _box(Vector3(w * 1.06, 0.22, d * 0.78))
		var mi := _mesh(root, slab, roof_mat, Vector3(0.0, h + 0.9, s * d * 0.24))
		mi.rotation.x = s * 0.52
	# 大门
	_mesh(root, _box(Vector3(w * 0.38, h * 0.72, 0.16)), _mat("door", Color(0.20, 0.14, 0.09)),
		Vector3(0, h * 0.36, d * 0.5 + 0.06))


## 普通木屋：石基 + 木墙 + 草顶
func _add_house(root: Node3D, w: float, d: float, floors: int) -> void:
	var base_h := 0.5
	var h := 3.2 * floors
	_mesh(root, _box(Vector3(w * 1.04, base_h, d * 1.04)), _mat("stone_base", Color(0.38, 0.36, 0.33)), Vector3(0, base_h * 0.5, 0))
	_mesh(root, _box(Vector3(w, h, d)), _mat("wood_plank", Color(0.44, 0.32, 0.20)), Vector3(0, base_h + h * 0.5, 0))
	var roof_mat := _mat("roof_thatch", Color(0.60, 0.47, 0.24))
	for s in [-1.0, 1.0]:
		var mi := _mesh(root, _box(Vector3(w * 1.10, 0.24, d * 0.74)), roof_mat,
			Vector3(0.0, base_h + h + 0.75, s * d * 0.23))
		mi.rotation.x = s * 0.55
	_mesh(root, _box(Vector3(minf(w * 0.34, 1.4), 2.2, 0.16)), _mat("door", Color(0.20, 0.14, 0.09)),
		Vector3(0, base_h + 1.1, d * 0.5 + 0.06))
	# 窗（发光暖色，夜里像有人住）
	var win := _mat("window_glow", Color(0.95, 0.78, 0.42), 0.4)
	win.emission_enabled = true
	win.emission = Color(1.0, 0.72, 0.32)
	win.emission_energy_multiplier = 0.55
	for s in [-1.0, 1.0]:
		_mesh(root, _box(Vector3(0.9, 0.9, 0.12)), win, Vector3(s * w * 0.3, base_h + h * 0.62, -d * 0.5 - 0.05))


## 铁匠铺：石屋 + 烟囱 + 炉口余烬光
func _add_forge(root: Node3D, w: float, d: float) -> void:
	var h := 3.4
	_mesh(root, _box(Vector3(w, h, d)), _mat("stone_wall", Color(0.34, 0.31, 0.28)), Vector3(0, h * 0.5, 0))
	_mesh(root, _box(Vector3(w * 1.08, 0.3, d * 1.08)), _mat("roof_dark", Color(0.24, 0.20, 0.17)), Vector3(0, h + 0.15, 0))
	_mesh(root, _cyl(0.5, 0.6, 3.2, 8), _mat("stone_wall", Color(0.30, 0.27, 0.25)),
		Vector3(w * 0.28, h + 1.5, -d * 0.22))
	var ember := _mat("ember", Color(1.0, 0.45, 0.12), 0.5)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.42, 0.08)
	ember.emission_energy_multiplier = 2.2
	_mesh(root, _box(Vector3(1.3, 1.1, 0.2)), ember, Vector3(0, 0.9, d * 0.5 + 0.08))


## 箭塔 / 瞭望塔
func _add_tower(root: Node3D, w: float, d: float, floors: int) -> void:
	var r := maxf(w, d) * 0.42
	var h := 3.0 * floors
	_mesh(root, _cyl(r * 1.08, r * 1.35, h, 8), _mat("wood_beam", Color(0.36, 0.26, 0.16)), Vector3(0, h * 0.5, 0))
	_mesh(root, _cyl(r * 1.7, r * 1.7, 0.26, 8), _mat("wood_plank", Color(0.44, 0.32, 0.20)), Vector3(0, h, 0))
	_mesh(root, _cyl(0.05, r * 1.5, 2.2, 8), _mat("roof_thatch", Color(0.60, 0.47, 0.24)), Vector3(0, h + 1.2, 0))
	_add_collision(root, r * 1.4, r * 1.4, h)


## 井屋 / 小棚
func _add_wellhouse(root: Node3D, w: float, d: float) -> void:
	_mesh(root, _cyl(w * 0.45, w * 0.45, 1.1, 10), _mat("stone_wall", Color(0.36, 0.34, 0.31)), Vector3(0, 0.55, 0))
	for i in 4:
		var a := float(i) / 4.0 * TAU
		_mesh(root, _cyl(0.10, 0.10, 2.6, 5), _mat("wood_beam", Color(0.32, 0.23, 0.14)),
			Vector3(cos(a) * w * 0.42, 1.3, sin(a) * d * 0.42))
	_mesh(root, _cyl(0.04, w * 0.75, 1.8, 8), _mat("roof_thatch", Color(0.58, 0.46, 0.25)), Vector3(0, 3.0, 0))


func _add_collision(root: Node3D, w: float, d: float, h: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, h, d)
	shape.shape = box
	shape.position = Vector3(0, h * 0.5, 0)
	body.add_child(shape)
	root.add_child(body)


# ===== 田地 =====

func _make_fields() -> void:
	var root := Node3D.new()
	root.name = "Fields"
	add_child(root)
	var soil := _mat("field_soil", Color(0.36, 0.26, 0.15), 0.98)
	var crop := _mat("crop", Color(0.52, 0.48, 0.20), 0.95)
	for f in VillageData.fields:
		var x := float(f.get("x", 0.0))
		var z := float(f.get("z", 0.0))
		var w := float(f.get("w", 30.0))
		var hh := float(f.get("h", 24.0))
		var rot := float(f.get("rot", 0.0))
		var node := Node3D.new()
		node.transform = Planet.plane_transform(x, z, rot)
		root.add_child(node)
		_mesh(node, _box(Vector3(w, 0.22, hh)), soil, Vector3(0, 0.05, 0))
		# 垄沟（成排低矮作物）
		var rows := int(hh / 2.6)
		for i in rows:
			var zz: float = -hh * 0.5 + (float(i) + 0.5) * (hh / float(rows))
			_mesh(node, _box(Vector3(w * 0.94, 0.42, 0.7)), crop, Vector3(0, 0.28, zz))


# ===== 道具 =====

func _make_props() -> void:
	var root := Node3D.new()
	root.name = "Props"
	add_child(root)
	for p in VillageData.props:
		var x := float(p.get("x", 0.0))
		var z := float(p.get("z", 0.0))
		var t := str(p.get("type", "crate"))
		var rot := float(p.get("rot", 0.0))
		var s := float(p.get("scale", 1.0))
		var node := _make_prop(t, s)
		if node == null:
			continue
		node.transform = Planet.plane_transform(x, z, rot)
		root.add_child(node)


func _make_prop(type: String, s: float) -> Node3D:
	var n := Node3D.new()
	match type:
		"barrel":
			_mesh(n, _cyl(0.42 * s, 0.42 * s, 1.0 * s, 8), _mat("barrel", Color(0.42, 0.28, 0.15)), Vector3(0, 0.5 * s, 0))
			_mesh(n, _cyl(0.45 * s, 0.45 * s, 0.08 * s, 8), _mat("iron_band", Color(0.28, 0.27, 0.25), 0.6, 0.5), Vector3(0, 0.78 * s, 0))
		"crate":
			_mesh(n, _box(Vector3(1.0, 1.0, 1.0) * s), _mat("crate", Color(0.50, 0.38, 0.22)), Vector3(0, 0.5 * s, 0))
		"cart":
			_mesh(n, _box(Vector3(1.9, 0.5, 1.1) * s), _mat("wood_plank", Color(0.44, 0.32, 0.20)), Vector3(0, 0.7 * s, 0))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var wheel := _cyl(0.42 * s, 0.42 * s, 0.12 * s, 10)
					var mi := _mesh(n, wheel, _mat("wood_beam", Color(0.32, 0.23, 0.14)),
						Vector3(sx * 0.7 * s, 0.44 * s, sz * 0.62 * s))
					mi.rotation.z = PI * 0.5
		"firepit":
			_mesh(n, _cyl(1.0 * s, 1.1 * s, 0.42 * s, 10), _mat("stone_wall", Color(0.34, 0.31, 0.28)), Vector3(0, 0.2 * s, 0))
			var fire := _mat("fire", Color(1.0, 0.52, 0.16), 0.4)
			fire.emission_enabled = true
			fire.emission = Color(1.0, 0.48, 0.12)
			fire.emission_energy_multiplier = 3.0
			_mesh(n, _cyl(0.02, 0.42 * s, 0.9 * s, 6), fire, Vector3(0, 0.7 * s, 0))
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.62, 0.28)
			light.light_energy = 1.6
			light.omni_range = 9.0
			light.position = Vector3(0, 1.1 * s, 0)
			n.add_child(light)
		"totem":
			_mesh(n, _cyl(0.26 * s, 0.32 * s, 3.4 * s, 6), _mat("totem_wood", Color(0.40, 0.28, 0.16)), Vector3(0, 1.7 * s, 0))
			for i in 3:
				_mesh(n, _box(Vector3(1.1, 0.18, 0.18) * s), _mat("totem_paint", Color(0.68, 0.30, 0.18)),
					Vector3(0, (0.9 + i * 0.9) * s, 0))
			_mesh(n, _cyl(0.02, 0.5 * s, 0.6 * s, 6), _mat("totem_paint", Color(0.68, 0.30, 0.18)), Vector3(0, 3.6 * s, 0))
		"haystack":
			_mesh(n, _cyl(0.9 * s, 1.0 * s, 1.3 * s, 9), _mat("roof_thatch", Color(0.62, 0.50, 0.26)), Vector3(0, 0.65 * s, 0))
			_mesh(n, _cyl(0.02, 1.15 * s, 1.0 * s, 9), _mat("roof_thatch", Color(0.66, 0.53, 0.28)), Vector3(0, 1.8 * s, 0))
		"anvil":
			_mesh(n, _box(Vector3(0.9, 0.5, 0.5) * s), _mat("iron", Color(0.26, 0.26, 0.27), 0.45, 0.8), Vector3(0, 0.7 * s, 0))
			_mesh(n, _cyl(0.3 * s, 0.42 * s, 0.5 * s, 8), _mat("wood_beam", Color(0.32, 0.23, 0.14)), Vector3(0, 0.25 * s, 0))
		"banner":
			_mesh(n, _cyl(0.06 * s, 0.06 * s, 3.2 * s, 5), _mat("wood_beam", Color(0.32, 0.23, 0.14)), Vector3(0, 1.6 * s, 0))
			_mesh(n, _box(Vector3(0.05, 1.4 * s, 0.9 * s)), _mat("banner_cloth", Color(0.62, 0.20, 0.14)), Vector3(0.06, 2.3 * s, 0))
		_:
			return null
	return n
