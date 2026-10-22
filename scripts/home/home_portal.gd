class_name HomePortal
extends Node3D

## WoW 风家园传送门（M37）：木柱门框 + 发光门帘 + 上升光点 + 蓝紫点光源。
## 玩家走进门内即被送往对端传送门（家园 <-> 村庄广场）。
##
## 网络架构（遵守 M26/M28 铁律）：
## - 场景本体是 level.tscn 静态实例，两端各自程序化构建（确定性结构一一对应）
## - 传送是**服务器本地逻辑**：服务器遍历 PlayersContainer 里的真人玩家
##   （名字 = str(peer_id)，M28 铁律用 PeerQuery.is_bot_peer 排除 bot，
##   不用 >= 9001 判断——ENet 真人 id 是 9 亿级大随机数）
## - 服务器直接写玩家 global_position / global_rotation.y，
##   由玩家自带 MultiplayerSynchronizer 广播到各端（沙发骑乘同款路径）
## - 骑乘中的玩家（mounted_vehicle != null）跳过——不能把沙发拖进家园
## - destination 为 NodePath，level.tscn 里两个 Portal 实例互相引用

const PORTAL_RADIUS := 1.4 ## 触发半径（门中心 2.2m 宽，玩家走到门前即触发）
const PORTAL_COOLDOWN := 3.0 ## 全局冷却，防刚落马又弹回
const DEST_SPAWN_DIST := 3.0 ## 落点在对端门前 3m
const PORTAL_HEIGHT := 3.4
const PORTAL_HALF_WIDTH := 1.1
const BUILD_DELAY := 3.0 ## M34 铁律：等地形数据就绪再射线探测贴地

@export var world_position: Vector3 ## 世界坐标落点（level.tscn 配置；Environment 容器带 y≈2.25 变换，必须世界坐标定位）
@export var world_rotation_y: float = 0.0 ## 世界坐标朝向（0 = 面朝北 -Z）
@export var destination: NodePath ## 对端传送门（两个 Portal 实例在 level.tscn 互相引用）

var _curtain_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _light: OmniLight3D
var _particles: GPUParticles3D
var _cooldown: float = 0.0
var _built := false
var _ground_y: float = 0.0 ## 门前地面高度（射线探测）


func _ready() -> void:
	# M34 铁律：Terrain3D data_directory 异步加载，_ready 时地形未就绪，
	# 探测射线会打空。延时到数据就绪再贴地建门（balloon_arena 同款 3s）。
	get_tree().create_timer(BUILD_DELAY).timeout.connect(_place_portal)


func _place_portal() -> void:
	if _built:
		return
	_built = true
	_ground_y = _probe_ground_y()
	global_position = world_position + Vector3(0.0, _ground_y, 0.0)
	global_rotation.y = world_rotation_y
	_build_portal()
	printerr("[HomePortal] 传送门已构建 pos=", world_position, " ground_y=", _ground_y,
		" dest=", destination)


func _probe_ground_y() -> float:
	var query := PhysicsRayQueryParameters3D.new()
	query.from = world_position + Vector3(0.0, 60.0, 0.0)
	query.to = world_position + Vector3(0.0, -10.0, 0.0)
	query.collision_mask = 2
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and is_finite(hit.position.y):
		return hit.position.y
	return 0.0 # 平地 region 兜底


func _physics_process(delta: float) -> void:
	# 表现：门帘呼吸 + 环脉动 + 灯光闪烁（两端各自跑，同一套 sin 函数）
	var t := Time.get_ticks_msec() / 1000.0
	var breath: float = 0.92 + 0.08 * sin(t * 2.2)
	if _curtain_mat != null:
		_curtain_mat.emission_energy_multiplier = 1.1 * breath
	if _ring_mat != null:
		_ring_mat.emission_energy_multiplier = 0.5 * breath
	if _light != null:
		_light.light_energy = 2.0 + 0.6 * sin(t * 2.2 + 0.6)
	if not multiplayer.is_server():
		return
	# 服务器：进入检测 + 传送
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var container := get_node_or_null("/root/Level/PlayersContainer")
	if container == null:
		return
	for child in container.get_children():
		if child == null or not (child is Node3D):
			continue
		var name_str := str(child.name)
		if not name_str.is_valid_int():
			continue # 非玩家节点（bot 在别的容器）
		var peer_id := int(name_str)
		if peer_id <= 1 or PeerQuery.is_bot_peer(peer_id):
			continue
		var player := child as Node3D
		if player.get("mounted_vehicle") != null:
			continue # 骑乘中不传送
		var pos: Vector3 = player.global_position
		if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
			continue
		if pos.distance_to(global_position) <= PORTAL_RADIUS:
			_teleport(player)
			_cooldown = PORTAL_COOLDOWN
			return


## 服务器：把玩家送到对端传送门前 3m，面朝对端门
func _teleport(player: Node3D) -> void:
	var dest := get_node_or_null(destination) as Node3D
	if dest == null or not is_instance_valid(dest):
		printerr("[HomePortal] destination 无效: ", destination)
		return
	# 对端门的前方 = -Z（Godot 惯例），落点站门前 3m
	var forward: Vector3 = -dest.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var spawn_pos: Vector3 = dest.global_position + forward * DEST_SPAWN_DIST + Vector3(0.0, 0.25, 0.0)
	# M33 NaN 铁律：落点逐分量检查
	if not (is_finite(spawn_pos.x) and is_finite(spawn_pos.y) and is_finite(spawn_pos.z)):
		return
	player.global_position = spawn_pos
	player.global_rotation.y = dest.global_rotation.y + PI
	_cooldown = PORTAL_COOLDOWN
	var msg := "你穿过传送门，来到了%s。" % _destination_name(dest)
	var level_scene := get_tree().current_scene
	if level_scene != null and level_scene.has_method("show_chat_message"):
		level_scene.show_chat_message(tr("系统"), msg)
	printerr("[HomePortal] 传送玩家 ", player.name, " -> ", dest.name, " world=", spawn_pos,
		" player_rot_y=", player.global_rotation.y, " dest_rot_y=", dest.global_rotation.y)


func _destination_name(dest: Node3D) -> String:
	if dest.get("portal_label") != null:
		return str(dest.get("portal_label"))
	return "另一端"


# ===== 构建（两端各自跑，确定性结构）=====
func _build_portal() -> void:
	var wood_mat := _make_wood()
	_ring_mat = _make_glow(Color(0.45, 0.62, 1.0), 0.5)
	_curtain_mat = _make_curtain()
	# 两根木柱
	for sx in [-PORTAL_HALF_WIDTH, PORTAL_HALF_WIDTH]:
		var post := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.34, PORTAL_HEIGHT, 0.34)
		post.mesh = box
		post.position = Vector3(sx, PORTAL_HEIGHT * 0.5, 0.0)
		post.material_override = wood_mat
		add_child(post)
	# 顶横梁
	var beam := MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(PORTAL_HALF_WIDTH * 2.0 + 0.5, 0.36, 0.36)
	beam.mesh = beam_mesh
	beam.position = Vector3(0.0, PORTAL_HEIGHT, 0.0)
	beam.material_override = wood_mat
	add_child(beam)
	# 发光环（TorusMesh 立起来）
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.78
	ring.mesh = torus
	ring.position = Vector3(0.0, PORTAL_HEIGHT * 0.55, 0.0)
	ring.rotation.x = PI * 0.5
	ring.material_override = _ring_mat
	add_child(ring)
	# 门帘（自发光 Quad，additive 双面）
	var curtain := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(PORTAL_HALF_WIDTH * 2.0 - 0.15, PORTAL_HEIGHT - 0.9)
	curtain.mesh = quad
	curtain.position = Vector3(0.0, PORTAL_HEIGHT * 0.5, 0.0)
	curtain.material_override = _curtain_mat
	add_child(curtain)
	# 上升光点粒子
	_particles = GPUParticles3D.new()
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0.0, 1.0, 0.0)
	pmat.spread = 18.0
	pmat.initial_velocity_min = 0.5
	pmat.initial_velocity_max = 1.1
	pmat.gravity = Vector3(0.0, 0.1, 0.0)
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pmat.emission_sphere_radius = 0.9
	var pcol := Gradient.new()
	pcol.set_color(0, Color(0.75, 0.85, 1.0, 0.9))
	pcol.set_color(1, Color(0.4, 0.55, 1.0, 0.0))
	var ptex := GradientTexture2D.new()
	ptex.gradient = pcol
	pmat.color_ramp = ptex
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	sphere.radial_segments = 6
	sphere.rings = 3
	_particles.amount = 28
	_particles.lifetime = 2.2
	_particles.process_material = pmat
	_particles.draw_pass_1 = sphere
	_particles.position = Vector3(0.0, 0.2, 0.0)
	add_child(_particles)
	# 蓝紫点光源
	_light = OmniLight3D.new()
	_light.light_color = Color(0.45, 0.62, 1.0)
	_light.light_energy = 2.2
	_light.omni_range = 6.5
	_light.position = Vector3(0.0, PORTAL_HEIGHT * 0.5, 0.0)
	add_child(_light)


func _make_wood() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.24, 0.14)
	mat.roughness = 0.85
	return mat


func _make_glow(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.4
	return mat


func _make_curtain() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var color := Color(0.35, 0.55, 1.0)
	mat.albedo_color = Color(color.r, color.g, color.b, 0.45)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.1
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
