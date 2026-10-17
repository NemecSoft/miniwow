extends Node3D

## M19 悬浮沙发飞行器（多人同乘版）。
## 速度 = 奔跑速度（6.0）× 5 = 30 m/s。座位 3 个：主驾 + 左右乘客。
## 网络架构（Godot 模板标准）：
## - 乘坐：E 上车 → request_mount.rpc_id(1) → 服务器分配最小空位 → sync_seats 广播
## - 驾驶权：主驾 = 座位 0 持有者（第一个上车的），set_multiplayer_authority(driver)
##   主驾客户端本地直接移动（客户端权威，与玩家移动同构），位置经 Synchronizer 同步
## - 跟随：所有乘员端自己每帧把玩家放到沙发座位偏移上（沙发位置由 Synchronizer 同步）
## - 禁穿地：飞行高度 >= 地形高度 + 0.8
## 每位玩家进世界自动获得一台专属沙发（level.gd 分发，名字 couch_<peer_id>）。

const HOVER_SPEED := 10.0         # WoW 悬停态：W/S 缓慢前后
const FLIGHT_SPEED := 30.0        # 奔跑 6.0 × 5（巡航）
const BOOST_SPEED := 75.0         # WoW 加速态（Shift）：俯冲/爬升飞行
const VERTICAL_SPEED := 14.0
const TURN_SPEED := 2.2           # A/D 转向（弧度/秒）
const MAX_PITCH_DEG := 45.0
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
var _pitch_deg := 0.0
var _last_safe_pos := Vector3.ZERO   # 最后一个无碰撞悬停点（防嵌入卡死回滚用）             # 加速态俯仰（+ 爬升 / - 俯冲）

@onready var _prompt: Label3D = $Prompt
@onready var _model: Node3D = $CouchModel


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_physics_process(false)
		return
	# 路径用场景根绝对定位（相对路径跨 Vehicles 容器曾解析出 Environment/Environment 双层错误）
	var starter := get_node_or_null("../../TerrainStarter")
	if starter and starter.terrain != null:
		_terrain_data = starter.terrain.data


## 主驾 peer id（座位 0 持有者）；空车返回 0
func get_driver_id() -> int:
	for peer_id in seats:
		if seats[peer_id] == 0:
			return int(peer_id)
	return 0


func get_seat_count() -> int:
	return seats.size()


func has_free_seat() -> bool:
	return seats.size() < SEAT_OFFSETS.size()


func get_seat_offset(seat_index: int) -> Vector3:
	return SEAT_OFFSETS[clampi(seat_index, 0, SEAT_OFFSETS.size() - 1)]


func _physics_process(delta: float) -> void:
	var local_player := _find_local_player()
	var local_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	_prompt.visible = not seats.is_empty() and seats.has(local_id) == false \
			and local_player != null and has_free_seat() \
			and global_position.distance_to(local_player.global_position) < MOUNT_RANGE

	# ===== 驾驶（仅主驾客户端）——还原到好版本：相机相对全向飞行 =====
	# W/S/A/D = 相机相对水平移动；空格升 / C 降；Shift 加速；move_and_slide 物理挡山
	var driver := get_driver_id()
	if driver == local_id and driver != 0:
		# WoW 驭空式：沙发朝向跟随镜头 yaw；W 沿镜头视线飞（含俯仰——
		# 右键压镜头 + W = 俯冲落地）。防穿由 _terrain_data 采样保证（已修复）
		var cam := get_viewport().get_camera_3d()
		var cam_fwd := -global_transform.basis.z
		var cam_yaw := rotation.y
		if cam != null:
			cam_fwd = -cam.global_transform.basis.z
			cam_yaw = atan2(-cam_fwd.x, -cam_fwd.z)
		rotation.y = lerp_angle(rotation.y, cam_yaw, 10.0 * delta)

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

		var ground_y := 0.15
		if _terrain_data != null:
			ground_y = _terrain_data.get_height(global_position)
		var floor_y := ground_y + (0.15 if Input.is_action_pressed("crouch") else MIN_HEIGHT_ABOVE_GROUND)

		# 纯代码移动（无物理引擎——一切行为可预测）
		var new_pos := global_position + (vel + Vector3.UP * up) * delta
		if _terrain_data != null:
			var cur_ground: float = _terrain_data.get_height(global_position)
			var tgt_ground: float = _terrain_data.get_height(new_pos)
			# 水平撞山：目标点地表比当前脚下高出 2m 以上 → 阻挡水平分量（可继续升降）
			if tgt_ground > global_position.y + 2.0 and up <= 0.0:
				new_pos = global_position + Vector3(0, up * delta, 0)
			# 垂直防穿：永不低于地表 + 0.3（贴地即着陆）
			new_pos.y = maxf(new_pos.y, tgt_ground + 0.3)
		global_position = new_pos

		# 沙发朝向 = 移动方向（角色朝向随沙发，不随 WASD 独立转）
		if vel.length_squared() > 0.5:
			rotation.y = lerp_angle(rotation.y, atan2(-vel.x, -vel.z), 8.0 * delta)


func _unhandled_input(event: InputEvent) -> void:
	# M19 WoW 载具相机：主驾按住右键拖动 = 转沙发（相机锁背面跟随）
	if event is InputEventMouseMotion and get_driver_id() == multiplayer.get_unique_id() \
			and get_driver_id() != 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		rotation.y -= event.relative.x * 0.005
		return
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
	var my_id := multiplayer.get_unique_id()
	var container := get_node_or_null("../../../PlayersContainer")
	if container == null:
		return null
	return container.get_node_or_null(str(my_id))


@rpc("any_peer", "call_local", "reliable")
func request_mount() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if not has_free_seat() or seats.has(sender):
		return
	var player := get_node_or_null("../../../PlayersContainer/" + str(sender))
	if player == null or global_position.distance_to(player.global_position) > MOUNT_RANGE * 2.0:
		return
	# 分配最小空位
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


## 服务器：广播座位表（由服务器 authority 发出）
func _broadcast_seats() -> void:
	sync_seats.rpc(seats)


@rpc("any_peer", "call_local", "reliable")
func sync_seats(new_seats: Dictionary) -> void:
	# 服务器广播：发送者必须是服务器(1)或本机 call_local(0)
	var rpc_sender := multiplayer.get_remote_sender_id()
	if rpc_sender != 0 and rpc_sender != 1:
		return
	var previous_driver := get_driver_id()
	seats = {}
	for peer_id in new_seats:
		seats[int(peer_id)] = int(new_seats[peer_id])
	var new_driver := get_driver_id()
	# 驾驶权随主驾变动
	set_multiplayer_authority(new_driver if new_driver != 0 else 1)
	# 本地玩家上下车状态
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
