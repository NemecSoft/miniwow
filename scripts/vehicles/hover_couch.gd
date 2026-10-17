extends Node3D

## M19 悬浮沙发飞行器（最终版）。
## 控制（WoW 习惯，上下坐骑一致）：
##   WASD = 相机相对移动（骑乘时 W 沿镜头视线，可俯冲落地）
##   空格 = 上升，C = 下降（按到底贴地着陆）
##   Shift = 加速 2.5 倍；右键拖动 = 转身；左键拖动 = 环绕观察
## 网络：X 召唤/E 上下车走服务器验证；位置由玩家 mounted 跟随同步（玩家自带 Synchronizer）
## 防穿：纯代码位移 + Terrain3D 高度采样（垂直钳制 + 水平撞山阻挡），无物理引擎

const FLIGHT_SPEED := 30.0        # 奔跑 6.0 × 5
const BOOST_SPEED := 75.0         # Shift 加速
const VERTICAL_SPEED := 14.0
const MIN_HEIGHT_ABOVE_GROUND := 0.8
const MOUNT_RANGE := 3.5
const SEAT_OFFSETS := [
	Vector3(0, 1.1, 0.35),      # 0 主驾
	Vector3(-0.55, 1.1, 0.35),  # 1 左乘客
	Vector3(0.55, 1.1, 0.35),   # 2 右乘客
]

@export var terrain_starter_path: NodePath = ^"../../TerrainStarter"

## peer_id -> seat_index；空车 = {}
var seats := {}
var _terrain_data: Terrain3DData = null

@onready var _model: Node3D = $CouchModel


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_physics_process(false)
		return
	var starter := get_node_or_null(terrain_starter_path)
	if starter and starter.terrain != null:
		_terrain_data = starter.terrain.data
	# M19：多人连接时动态挂位置同步器（单机不挂——预置同步器的缓存回写曾钉死位置）
	if multiplayer.has_multiplayer_peer():
		var sync := MultiplayerSynchronizer.new()
		sync.name = "MultiplayerSynchronizer"
		var cfg := SceneReplicationConfig.new()
		cfg.add_property(^".:position")
		cfg.property_set_replication_mode(^".:position", 1)
		cfg.add_property(^".:rotation")
		cfg.property_set_replication_mode(^".:rotation", 1)
		sync.replication_config = cfg
		add_child(sync)


## 主驾 peer id（座位 0 持有者）；空车返回 0
func get_driver_id() -> int:
	for peer_id in seats:
		if seats[peer_id] == 0:
			return int(peer_id)
	return 0


func has_free_seat() -> bool:
	return seats.size() < SEAT_OFFSETS.size()


func get_seat_offset(seat_index: int) -> Vector3:
	return SEAT_OFFSETS[clampi(seat_index, 0, SEAT_OFFSETS.size() - 1)]


func _physics_process(delta: float) -> void:
	var local_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	var driver := get_driver_id()

	# ===== 驾驶（仅主驾客户端）=====
	if driver == local_id and driver != 0:
		var cam := get_viewport().get_camera_3d()
		var cam_fwd := -global_transform.basis.z
		if cam != null:
			cam_fwd = -cam.global_transform.basis.z   # 沿镜头视线（含俯仰，可俯冲）

		var move := Input.get_axis("move_backward", "move_forward")
		var speed := FLIGHT_SPEED
		if Input.is_action_pressed("shift"):
			speed = BOOST_SPEED
		var vel := cam_fwd * speed * move if move > 0.0 else \
				Vector3(-cam_fwd.x, 0, -cam_fwd.z).normalized() * speed * 0.4 * minf(move, 0.0)

		var up := 0.0
		if Input.is_action_pressed("jump"):
			up += VERTICAL_SPEED
		if Input.is_action_pressed("crouch"):
			up -= VERTICAL_SPEED

		# 纯代码位移 + 地形采样防穿（垂直钳制 + 水平撞山阻挡）
		var new_pos := global_position + (vel + Vector3.UP * up) * delta
		if _terrain_data != null:
			var tgt_ground: float = _terrain_data.get_height(new_pos)
			new_pos.y = maxf(new_pos.y, tgt_ground + 0.3)
			if tgt_ground > global_position.y + 2.0 and up <= 0.0:
				new_pos = Vector3(global_position.x, maxf(global_position.y, tgt_ground + 0.3), global_position.z)
		global_position = new_pos

		# 沙发朝向 = 移动方向；差量同步玩家节点（角色与沙发恒一致）
		if vel.length_squared() > 0.5:
			var new_yaw := lerp_angle(rotation.y, atan2(-vel.x, -vel.z), 8.0 * delta)
			var dy := new_yaw - rotation.y
			rotation.y = new_yaw
			var drv_player := _find_local_player()
			if drv_player != null:
				drv_player.rotation.y += dy


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	var local_player := _find_local_player()
	if local_player == null:
		return
	var local_id := multiplayer.get_unique_id()
	if seats.has(local_id):
		request_dismount.rpc_id(1)
	elif seats.is_empty() or has_free_seat():
		if global_position.distance_to(local_player.global_position) < MOUNT_RANGE:
			request_mount.rpc_id(1)


func _find_local_player() -> Node:
	if not multiplayer.has_multiplayer_peer():
		return null
	var container := get_node_or_null("../../PlayersContainer")
	if container == null:
		return null
	return container.get_node_or_null(str(multiplayer.get_unique_id()))


@rpc("any_peer", "call_local", "reliable")
func request_mount() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if not has_free_seat() or seats.has(sender):
		return
	var player := get_node_or_null("../../PlayersContainer/" + str(sender))
	if player == null or global_position.distance_to(player.global_position) > MOUNT_RANGE * 2.0:
		return
	var used: Array = seats.values()
	for seat_index in SEAT_OFFSETS.size():
		if not used.has(seat_index):
			seats[sender] = seat_index
			break
	_broadcast_seats()


@rpc("any_peer", "call_local", "reliable")
func request_dismount() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if not seats.has(sender):
		return
	seats.erase(sender)
	_broadcast_seats()


func _broadcast_seats() -> void:
	sync_seats.rpc(seats)


@rpc("any_peer", "call_local", "reliable")
func sync_seats(new_seats: Dictionary) -> void:
	var rpc_sender := multiplayer.get_remote_sender_id()
	if rpc_sender != 0 and rpc_sender != 1:
		return
	var previous_driver := get_driver_id()
	seats = {}
	for peer_id in new_seats:
		seats[int(peer_id)] = int(new_seats[peer_id])
	var new_driver := get_driver_id()
	set_multiplayer_authority(new_driver if new_driver != 0 else 1)
	var local_id := multiplayer.get_unique_id()
	var player := _find_local_player()
	if player != null:
		if seats.has(local_id):
			player.set_mounted(self, seats[local_id])
		elif previous_driver == local_id or player.mounted_vehicle == self:
			player.set_mounted(null)
			var drop := global_position
			if _terrain_data != null:
				drop.y = _terrain_data.get_height(global_position) + 0.5
			player.global_position = drop
