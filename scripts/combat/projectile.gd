class_name Projectile
extends Area3D

## M5 技能弹道（法师火球/冰箭）：服务器权威移动与命中判定，客户端只播表现。
## 生成时由服务器 RPC 广播同一切始状态（直线弹道各端本地模拟，零逐帧同步成本）；
## 命中时服务器广播 despawn，伤害走既有 apply_combat_damage 链路（飘字/抖动全复用）。
## 注意：本场景材质在 setup() 里动态新建，避免多枚弹道共用一份 sub_resource 互相抢色。

const TARGET_LAYERS := 5 # bit1 玩家层 + bit3 怪物层（与玩家准星射线一致）
const HIT_RADIUS := 0.4

var _direction := Vector3.FORWARD
var _speed := 18.0
var _traveled := 0.0
var _max_range := 12.0
var _skill_id := ""
var _attacker: Node = null ## 服务器上的攻击者节点（命中回调用；客户端为 null）

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _light: OmniLight3D = $Light


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
			queue_free()
			return
