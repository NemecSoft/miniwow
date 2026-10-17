extends State

## M19：骑乘悬浮沙发状态（Jeheno TPC 状态机扩展）。
## 进入：靠近沙发按 E（Interact）；退出：再按 E 或被服务器踢出座位。
## 骑乘期间角色吸附座位，移动输入交给沙发的驾驶逻辑（couch 读 Input）。

const SEAT_OFFSET := Vector3(0, 1.1, 0.35)
const MOUNT_RANGE := 3.5

var mount_target: Node3D = null
var char_ref: CharacterBody3D = null


func _find_nearest_couch() -> Node3D:
	var best: Node3D = null
	var best_d := MOUNT_RANGE
	for v in char_ref.get_tree().get_nodes_in_group("vehicles"):
		var d: float = char_ref.global_position.distance_to(v.global_position)
		if d < best_d:
			best_d = d
			best = v
	return best


func enter(char_reference: CharacterBody3D) -> void:
	char_ref = char_reference
	mount_target = _find_nearest_couch()
	if mount_target != null and mount_target.has_method("request_mount"):
		var my_id: int = multiplayer.get_unique_id()
		if not mount_target.seats.has(my_id):
			mount_target.request_mount.rpc_id(1)


func physics_update(_delta: float) -> void:
	# 退出条件：目标失效 / 未上座（服务器拒绝） / 再按 E
	if mount_target == null or not is_instance_valid(mount_target):
		transitioned.emit("IdleState")
		return
	var my_id: int = multiplayer.get_unique_id()
	if not mount_target.seats.has(my_id):
		transitioned.emit("IdleState")
		return
	# 吸附座位（纯视觉；沙发移动经 Node3D 位置同步）
	char_ref.global_position = mount_target.global_position + SEAT_OFFSET
	char_ref.velocity = Vector3.ZERO
	if Input.is_action_just_pressed("interact"):
		mount_target.request_dismount.rpc_id(1)
		return


func exit() -> void:
	mount_target = null
	char_ref = null
