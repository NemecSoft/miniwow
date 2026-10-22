class_name Projectile
extends Area3D

## M5 技能弹道（法师火球/冰箭）：服务器权威移动与命中判定，客户端只播表现。
## 生成时由服务器 RPC 广播同一切始状态；命中时服务器广播 despawn，伤害走既有 apply_combat_damage 链路。
## 注意：本场景材质在 setup() 里动态新建，避免多枚弹道共用一份 sub_resource 互相抢色。
## M40：增加拖尾粒子（按技能配色）+ 施法前摇音效 + 命中爆发特效。

const TARGET_LAYERS := 5 # bit1 玩家层 + bit3 怪物层（与玩家准星射线一致）
const HIT_RADIUS := 0.4

var _direction := Vector3.FORWARD
var _speed := 18.0
var _traveled := 0.0
var _max_range := 12.0
var _skill_id := ""
var _attacker: Node = null ## 服务器上的攻击者节点（命中回调用；客户端为 null）
var _trail: GPUParticles3D

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _light: OmniLight3D = $Light


func _ready() -> void:
	_build_trail()


## M40：动态创建拖尾粒子（不依赖 tscn 节点，避免改场景文件）
func _build_trail() -> void:
	_trail = GPUParticles3D.new()
	_trail.name = "Trail"
	var ppm := ParticleProcessMaterial.new()
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ppm.emission_sphere_radius = 0.12
	ppm.direction = Vector3(0, 1, 0)
	ppm.spread = 35.0
	ppm.initial_velocity_min = 0.2
	ppm.initial_velocity_max = 0.7
	ppm.gravity = Vector3(0, -1.5, 0)
	ppm.scale_min = 0.12
	ppm.scale_max = 0.35
	ppm.lifetime_randomness = 0.5
	_trail.process_material = ppm
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1, 1)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var tq := QuadMesh.new()
	tq.size = Vector2(0.2, 0.2)
	_trail.draw_pass_1 = tq  # 无 draw_pass 粒子不渲染（M40 修）
	_trail.material_override = mat
	_trail.amount = 18
	_trail.lifetime = 0.45
	_trail.one_shot = false
	_trail.emitting = false
	add_child(_trail)


func setup(direction: Vector3, speed: float, max_range: float, skill_id: String, color: Color) -> void:
	_direction = direction.normalized()
	_speed = speed
	_max_range = max_range
	_skill_id = skill_id
	# 动态材质：每个实例一份，颜色互不干扰
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.6
	_mesh.set_surface_override_material(0, material)
	if _light:
		_light.light_color = color
	_apply_trail_theme()


## M40：按技能 id 给拖尾套色 + 播施法前摇音效（各端独立触发，纯表现）
func _apply_trail_theme() -> void:
	if _trail == null:
		return
	var tint := Color(1, 1, 1, 1)
	var cast_key := &"cast_fire"
	if _skill_id.begins_with("m_fireball"):
		tint = Color(1.0, 0.45, 0.12)
		cast_key = &"cast_fire"
	elif _skill_id.begins_with("m_frostbolt"):
		tint = Color(0.5, 0.85, 1.0)
		cast_key = &"cast_frost"
	elif _skill_id.begins_with("m_arcane"):
		tint = Color(0.7, 0.4, 1.0)
		cast_key = &"cast_arcane"
	# GPUParticles3D 无 modulate 属性（那是 2D），改用材质 emission 染色
	var mat := _trail.material_override as StandardMaterial3D
	if mat != null:
		mat.emission = tint
		mat.albedo_color = tint
	_trail.emitting = true
	# M43 空间化：原先 play() 是全局 2D——别人（含地图另一头的 bot）放技能，
	# 弹道音也会以全音量入耳。play_world 按离相机远近自动选 2D/3D。
	# near_distance 给 8 米：第三人称相机在身后约 5 米，自己出手仍走 2D 保清晰。
	SfxManager.play_world(cast_key, global_position, 8.0)


func set_attacker(attacker: Node) -> void:
	_attacker = attacker


func _physics_process(delta: float) -> void:
	var step := _speed * delta
	global_position += _direction * step
	_traveled += step
	if _traveled >= _max_range:
		queue_free() # 飞过最大射程自然消散
		return
	if not multiplayer.is_server():
		return
	_check_hit()


## 服务器：球形扫描命中（比 body_entered 信号更抗高速穿透）
func _check_hit() -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = HIT_RADIUS
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = TARGET_LAYERS
	query.collide_with_areas = false
	var hits := get_world_3d().direct_space_state.intersect_shape(query, 8)
	for hit in hits:
		var collider := hit.get("collider") as Object
		if not (collider is Node3D) or collider == _attacker:
			continue
		if collider.has_method("apply_combat_damage"):
			if _attacker and _attacker.has_method("_on_projectile_hit"):
				_attacker._on_projectile_hit(collider, _skill_id, name)
			_spawn_burst()
			queue_free()
			return


## M40：命中处生成对应元素的爆发特效（火/冰/奥术）
func _spawn_burst() -> void:
	var burst := ""
	if _skill_id.begins_with("m_fireball"):
		burst = "res://scenes/vfx/spell_fire_burst.tscn"
	elif _skill_id.begins_with("m_frostbolt"):
		burst = "res://scenes/vfx/spell_frost_burst.tscn"
	elif _skill_id.begins_with("m_arcane"):
		burst = "res://scenes/vfx/spell_arcane_burst.tscn"
	if burst != "":
		SfxManager.spawn_effect(burst, global_position)
