extends Node3D

## 星球地形（M45 立方球 / M46 多星球）
##
## 用立方球（cube-sphere）生成 6 块大陆/区域：每面 SEG×SEG 个四边形投射到球面，
## 高度取自 Planet.height_at()，配色/雪线/熔岩色由 PlanetProfile 灌进 shader。
##
## 【为什么不再用 Terrain3D】
##   Terrain3D 是高度场（Y 向上的平面网格），做不了球面。
##   球面地形用「解析吸附」做贴地（见 player.gd 的 _planet_frame_step），
##   不需要三角网碰撞体——几十万面的 trimesh 物理查询会把帧率吃掉。
##
## 【兼容】保留 `terrain` 字段（恒为 null）。旧脚本的 `starter.terrain != null`
##   判断会自动降级跳过，不会崩。

const SEG := 180                    # 每面 180 段（181×181 顶点，6 面共 19.6 万顶点）
const TERRAIN_SHADER := "res://shaders/world_terrain.gdshader"
const MASK_SIZE := 512              # 平面遮罩（只对面 0 有效：道路/草原/红土/熔岩）

## 兼容字段：球面世界没有 Terrain3D 实例
var terrain: Terrain3D = null
var mask_texture: ImageTexture
var planet_mesh: MeshInstance3D
var ocean_mesh: MeshInstance3D
## 无海洋星球（外域）的虚空球壳
var void_mesh: MeshInstance3D


func _ready() -> void:
	# 【M47】环境容器必须无变换 —— 球面世界里"世界 Y 向上"这件事根本不存在。
	# level.tscn 里的 Environment 曾经带 y=+2.2542782（平面时代"把地面抬高
	# 2.25 米"的遗留）。在球面上这等于把**整棵环境子树**（地形网格/Sky3D/
	# 竞技场/森林）沿世界 Y 平移 2.254 米：各点法线与世界 Y 的夹角不同，
	# 于是半径误差到处不一样（实测玩家出生点处网格低了 0.366m，正好是
	# 2.254 × 0.162），角色就悬在半空。场景里已删除，这里再做一道运行时兜底。
	var env_parent := get_parent()
	if env_parent is Node3D:
		var ep := env_parent as Node3D
		if ep.position.length_squared() > 1e-9:
			printerr("[Planet] Environment 容器带位移 %s，强制归零（球面世界不允许）" % str(ep.position))
			ep.position = Vector3.ZERO
	VillageData.ensure_loaded()
	var prof := Planet.profile()
	if prof.uses_zone_mask:
		mask_texture = _load_or_bake_mask()
	_build_planet()
	if prof.has_ocean:
		_build_ocean()
	else:
		_build_void_shell()
	if DisplayServer.get_name() == "headless":
		set_physics_process(false)


## 兼容接口：旧代码用 starter.terrain.data.get_height(pos)，统一改成 starter.height_at_pos(pos)
func height_at_pos(pos: Vector3) -> float:
	return Planet.height_at(pos)


func surface_height(pos: Vector3) -> float:
	return Planet.RADIUS + Planet.height_at(pos)


# ===== 遮罩（平面世界的道路/区域，只用于面 0）=====

func _mask_cache_path() -> String:
	return ProjectSettings.globalize_path("user://world_mask_v2_%d.png" % MASK_SIZE)


func _load_or_bake_mask() -> ImageTexture:
	var p := _mask_cache_path()
	var img: Image = null
	if FileAccess.file_exists(p):
		img = Image.load_from_file(p)
		if img != null and (img.get_width() != MASK_SIZE or img.get_height() != MASK_SIZE):
			img = null
	if img == null:
		var t0 := Time.get_ticks_msec()
		img = WorldShape.build_mask_image(MASK_SIZE)
		img.save_png(p)
		printerr("[Planet] 遮罩烘焙 %dms" % (Time.get_ticks_msec() - t0))
	return ImageTexture.create_from_image(img)


# ===== 球面网格 =====

func _build_planet() -> void:
	var t0 := Time.get_ticks_msec()
	var total_verts := 0
	var root := Node3D.new()
	root.name = "PlanetSurface"
	add_child(root)

	var mat := ShaderMaterial.new()
	mat.shader = load(TERRAIN_SHADER) as Shader
	# 遮罩：无海洋/无遮罩星球给一张全黑 1x1，避免 sampler 未绑定警告
	if mask_texture != null:
		mat.set_shader_parameter("mask_tex", mask_texture)
	else:
		var blank := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		blank.fill(Color(0, 0, 0, 0))
		mat.set_shader_parameter("mask_tex", ImageTexture.create_from_image(blank))
	# 星球调色板（M46：数组 uniform）
	var params := Planet.profile().shader_params()
	for k in params:
		mat.set_shader_parameter(k, params[k])

	for face in Planet.FACE_COUNT:
		var mesh := _build_face(face)
		if mesh == null:
			continue
		total_verts += (SEG + 1) * (SEG + 1)
		var mi := MeshInstance3D.new()
		mi.name = "Face%d" % face
		mi.mesh = mesh
		mi.material_override = mat
		# 球面是凸的，背面永远看不到；关掉背面剔除省一半光栅
		root.add_child(mi)
		# 【M47 架构】碰撞体**直接由渲染网格生成**——模型与碰撞天生逐三角形一致。
		#
		# 之前地形没有任何碰撞体，所以"人站在哪"只能靠 height_at() 解析式去猜，
		# 再把猜的值和渲染网格对不上（实测差 0.3~5.4m），于是不停地加 offset 补偿。
		# 按 Godot 官方建议（Collision shapes 3D）："concave shapes are the best
		# approach for a level's collision" —— 静态关卡就该用网格自身的 trimesh。
		# 从此贴地不再需要任何"算高度"，交给 move_and_slide()。
		var body := StaticBody3D.new()
		body.name = "Face%dBody" % face
		body.collision_layer = 2          # 静态世界层，与广场地台一致
		body.collision_mask = 0
		var cshape := CollisionShape3D.new()
		cshape.shape = mesh.create_trimesh_shape()
		body.add_child(cshape)
		mi.add_child(body)
		planet_mesh = mi
	printerr("[Planet] 6 面网格完成 顶点 %d 耗时 %dms" % [total_verts, Time.get_ticks_msec() - t0])


func _build_face(face: int) -> ArrayMesh:
	var n := SEG + 1
	var verts := PackedVector3Array()
	verts.resize(n * n)
	var normals := PackedVector3Array()
	normals.resize(n * n)
	var uvs := PackedVector2Array()
	uvs.resize(n * n)
	var colors := PackedColorArray()
	colors.resize(n * n)
	# 【M47】把每个顶点的高度原样交给 Planet 缓存。
	# 贴地必须用"渲染网格真实顶点"的插值，不能用 height_at 重算一遍 ——
	# 实测两者差 0.30m（探针 mesh_ground_probe：玩家比渲染网格高 0.366m），
	# 角色就悬在半空。缓存后 mesh_height 与渲染网格逐字节一致。
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var face_col := Color(float(face) / 5.0, 0.0, 0.0, 1.0)

	var step := 2.0 / float(SEG)
	for iy in n:
		var v: float = -1.0 + step * float(iy)
		for ix in n:
			var u: float = -1.0 + step * float(ix)
			var d := Planet.dir_of(face, u, v)
			var h := Planet.height_at(d)
			var i: int = iy * n + ix
			verts[i] = d * (Planet.RADIUS + h)
			uvs[i] = Vector2(u, v)
			colors[i] = face_col
			heights[i] = h

	Planet.set_mesh_cache(face, heights)

	# 法线：用相邻顶点差分（球面切向叉积），比直接用 d 更能表现山体明暗
	for iy in n:
		for ix in n:
			var i: int = iy * n + ix
			var xl: int = iy * n + maxi(ix - 1, 0)
			var xr: int = iy * n + mini(ix + 1, n - 1)
			var yt: int = mini(iy + 1, n - 1) * n + ix
			var yb: int = maxi(iy - 1, 0) * n + ix
			var du := verts[xr] - verts[xl]
			var dv := verts[yt] - verts[yb]
			var nrm := du.cross(dv)
			if nrm.length_squared() < 1e-9:
				nrm = verts[i]
			nrm = nrm.normalized()
			# 保证朝外（球面法线同向）
			if nrm.dot(verts[i]) < 0.0:
				nrm = -nrm
			normals[i] = nrm

	var idx := PackedInt32Array()
	idx.resize(SEG * SEG * 6)
	var k := 0
	for iy in SEG:
		for ix in SEG:
			var i0: int = iy * n + ix
			var i1: int = i0 + 1
			var i2: int = i0 + n
			var i3: int = i2 + 1
			# 绕序：从球外看为顺时针（Godot 正面 = 顺时针）
			idx[k] = i0
			idx[k + 1] = i2
			idx[k + 2] = i1
			idx[k + 3] = i1
			idx[k + 4] = i2
			idx[k + 5] = i3
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ===== 海洋球壳（艾泽拉斯）=====

func _build_ocean() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/planet_ocean.gdshader") as Shader
	mat.set_shader_parameter("planet_radius", Planet.RADIUS)
	var sphere := SphereMesh.new()
	sphere.radius = Planet.RADIUS + Planet.SEA_LEVEL
	sphere.height = (Planet.RADIUS + Planet.SEA_LEVEL) * 2.0
	sphere.radial_segments = 160
	sphere.rings = 90
	sphere.material = mat
	ocean_mesh = MeshInstance3D.new()
	ocean_mesh.name = "Ocean"
	ocean_mesh.mesh = sphere
	ocean_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean_mesh)
	printerr("[Planet] 海洋球壳 R+%d" % int(Planet.SEA_LEVEL))


# ===== 虚空球壳（外域）=====

## 外域没有海洋，边缘是断崖直接坠入虚空。这里在 sea_floor 处铺一层暗紫球壳
## 当作"虚空的底"，让断崖看起来是插进虚空而不是插进空气。
## 必须不透明：半透明球壳会把整颗星球扣成一个玻璃罩（M45 海洋踩过这个坑）。
func _build_void_shell() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/planet_void.gdshader") as Shader
	mat.set_shader_parameter("planet_radius", Planet.RADIUS)
	var col := Planet.profile().void_color
	mat.set_shader_parameter("void_color", Vector3(col.r, col.g, col.b))
	var r: float = Planet.RADIUS + Planet.SEA_FLOOR
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 128
	sphere.rings = 72
	sphere.material = mat
	void_mesh = MeshInstance3D.new()
	void_mesh.name = "VoidShell"
	void_mesh.mesh = sphere
	void_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(void_mesh)
	printerr("[Planet] 虚空球壳 R%+d" % int(Planet.SEA_FLOOR))
