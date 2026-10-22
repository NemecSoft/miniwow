extends Node3D

## M19 悬浮沙发飞行器（最终版）。
## 控制（WoW 习惯，上下坐骑一致）：
##   WASD = 相机相对移动（骑乘时 W 沿镜头视线，可俯冲落地）
##   空格 = 上升，C = 下降（按到底贴地着陆）
##   Shift = 加速 2.5 倍；右键拖动 = 转身；左键拖动 = 环绕观察
## 网络：X 召唤/E 上下车走服务器验证；位置由玩家 mounted 跟随同步（玩家自带 Synchronizer）
## 防穿：纯代码位移 + Terrain3D 高度采样（垂直钳制 + 水平撞山阻挡），无物理引擎

## 飞行速度（米/秒）的**默认值**。数值按"绕星球一周要多久"来定，方便判断快慢：
##   一周 = 2π × 2200 ≈ 13823 m
##   巡航 60   → 约 230 秒一周
##   Shift 260 → 约 53 秒一周
##   Ctrl 1400 → 约 10 秒一周（专门用来快速验证"地形是圆的"）
##
## 这三个是默认值，不是最终值：运行时优先读 user://settings.cfg 的 [vehicle] 段
## （flight_speed / boost_speed / hyper_speed / vertical_speed），
## 改配置即可调，不需要改代码 —— 见 VehicleSettings.number()。
const DEFAULT_FLIGHT_SPEED := 60.0
const DEFAULT_BOOST_SPEED := 260.0
const DEFAULT_HYPER_SPEED := 1400.0
## 升降速度。飞到 1800m 高空看整个球约需 36 秒（原 14 要 2 分钟，太慢）。
const DEFAULT_VERTICAL_SPEED := 50.0
## 运行时生效值（_ready 从设置读一次，避免每帧开文件）
var flight_speed := DEFAULT_FLIGHT_SPEED
var boost_speed := DEFAULT_BOOST_SPEED
var hyper_speed := DEFAULT_HYPER_SPEED
var vertical_speed := DEFAULT_VERTICAL_SPEED
## 沙发底面离地面的悬浮高度（米）。这是**悬浮设计参数**，不是补丁偏移：
## 沙发本来就是悬空载具，贴地会视觉穿模。
const HOVER_CLEARANCE := 0.3
const MIN_HEIGHT_ABOVE_GROUND := 0.8
const MOUNT_RANGE := 3.5
const SEAT_OFFSETS := [
	Vector3(0, 1.1, 0.35),      # 0 主驾
	Vector3(-0.55, 1.1, 0.35),  # 1 左乘客
	Vector3(0.55, 1.1, 0.35),   # 2 右乘客
]

## project.godot: layer_1 = "world_decor"、layer_2 = "world"、layer_3 = "actor"。
## 地面射线覆盖前两层，只排除 actor（否则会把别的玩家/bot 当地面）。
const ACTOR_LAYER := 1 << 2

@export var terrain_starter_path: NodePath = ^"../../TerrainStarter"

## peer_id -> seat_index；空车 = {}
var seats := {}
## M25f 条款 M6：bot 专属沙发（自动驾驶载具）——拒绝任何玩家上座。
## bot_summon_and_mount 生成后打标记；玩家误登会被自动驾驶劫走（事故二）。
var bot_only := false
var _terrain_data: Terrain3DData = null
## M25c 条款 M3：空车滞留计时——约定"无人骑乘的坐骑不允许存在"。
## 正常流程下客/收回即时销毁；此计时只兜底召唤后骑乘失败等孤儿时序（3 秒）。
const EMPTY_RECALL_DELAY := 3.0
var _empty_time := 0.0
# M31：原 @onready var _model = $CouchModel 已删——全文件无一处使用（死代码），
# 且 sports_car.gd 继承本脚本后，car 场景没有 CouchModel 节点，每次生成 car_N 刷一条 ERR。


func _ready() -> void:
	add_to_group("vehicles")
	_load_speed_settings()
	# M25：headless 也跑物理——bot 自动驾驶（autopilot）需要 _physics_process；
	# headless 下无玩家沙发，bot 沙发靠自动驾驶移动（此前直接禁用会卡死骑行）
	# M21b：地形是异步创建的（terrain_starter.gd: terrain = await create_terrain()），
	# 沙发 _ready 时 terrain/data 可能尚未就绪——取不到就走 _physics_process 懒加载重试，
	# 不再一次性定生死（此前取空后防穿永久失效，骑乘俯冲/下降直接穿地，实测事故）。
	_try_grab_terrain()
	# M39：坐骑光环可见性跟随设置（默认开；暂停菜单可切换，存 user://settings.cfg）
	_apply_halo_visibility()
	# M26：删除原"动态挂位置同步器"逻辑。两个根因：
	# ① Godot 4 的 has_multiplayer_peer() 恒为 true（默认 OfflineMultiplayerPeer），
	#    "单机不挂"的注释从未生效，Host 单实例也一直挂着；
	# ② 当时客户端从不实例化沙发节点（沙发各端本地生成），同步器向没有
	#    couch_xxx 节点的对等端广播 position/rotation，双端实测每辆车刷
	#    "Node not found: .../couch_xxx/MultiplayerSynchronizer" + null 参数错误。
	# M27（docs/conventions-multiplayer-visual-sync.md 条款 V1）：沙发本体改由
	# level.tscn 的 VehicleMultiplayerSpawner 广播（服务器 add_child(true) 即同步，
	# 含 late-join 重放；客户端严禁本地 instantiate）。沙发场景自带
	# MultiplayerSynchronizer 同步 bot_only（变化广播）+ position/rotation
	# （广播模式，从 authority 端发出）——驾驶端的座位 0 骑手/服务器 bot 自驾
	# 移动沙发时各端同步可见。座位表仍走 sync_seats.rpc_id 真实骑手通道。


## 速度默认值来自常量（有物理/体验依据，注释里有推导），但允许 user://settings.cfg
## 的 [vehicle] 段覆盖 —— 玩家/策划改配置即可调速，不用改代码重编。
func _load_speed_settings() -> void:
	flight_speed = VehicleSettings.number("flight_speed", DEFAULT_FLIGHT_SPEED)
	boost_speed = VehicleSettings.number("boost_speed", DEFAULT_BOOST_SPEED)
	hyper_speed = VehicleSettings.number("hyper_speed", DEFAULT_HYPER_SPEED)
	vertical_speed = VehicleSettings.number("vertical_speed", DEFAULT_VERTICAL_SPEED)


## M39：坐骑光环可见性——跟随 VehicleSettings（设置菜单可开关，默认开）。
## 纯本地视觉设置，不走网络同步：各端读同一份 settings.cfg。
##
## 注意：autoload 是 /root 下的节点，不是 Engine 单例（Engine.has_singleton
## 对 autoload 恒为 false，M38 教训的同类坑）——必须用 get_node_or_null 取。
func _apply_halo_visibility() -> void:
	var ring := get_node_or_null("HoverRing")
	if ring == null:
		return
	var vs := get_node_or_null("/root/VehicleSettings")
	if vs != null and vs.has_method("is_hover_halo_enabled"):
		ring.visible = bool(vs.call("is_hover_halo_enabled"))
		# 设置里改动时立刻生效（不用等下次召唤坐骑）
		if vs.has_signal("hover_halo_changed") \
				and not vs.is_connected("hover_halo_changed", _on_halo_setting_changed):
			vs.connect("hover_halo_changed", _on_halo_setting_changed)
	else:
		ring.visible = true


## M39：设置变更回调（开关光环）
func _on_halo_setting_changed(enabled: bool) -> void:
	var ring := get_node_or_null("HoverRing")
	if ring != null:
		ring.visible = enabled


## M39：坐骑光环可见性（供外部查询，例如 UI 同步按钮状态）
func is_hover_ring_visible() -> bool:
	var ring := get_node_or_null("HoverRing")
	return ring != null and ring.visible


## 主驾 peer id（座位 0 持有者）；空车返回 0
func get_driver_id() -> int:
	for peer_id in seats:
		if seats[peer_id] == 0:
			return int(peer_id)
	return 0


## M30：座位表虚函数——子类 sports_car.gd 覆盖为飞车自己的座位布局
## （const 在 GDScript 里被子类遮蔽后父类方法仍引用父类值，座位数/偏移
## 的差异化必须走函数覆盖）。
func _get_seat_offsets() -> Array:
	return SEAT_OFFSETS


func has_free_seat() -> bool:
	return seats.size() < _get_seat_offsets().size()


## M25f 条款 M6：标记为 bot 专属沙发（bot_summon_and_mount 调用）
func mark_bot_vehicle() -> void:
	bot_only = true


## M25f 条款 M7：一骑一席——发起者已骑在别的载具上则拒绝上座
func _rider_busy_elsewhere(peer_id: int) -> bool:
	var player := get_node_or_null("../../../PlayersContainer/" + str(peer_id))
	if player == null:
		return false
	var current = player.get("mounted_vehicle")
	return current != null and current != self


func get_seat_offset(seat_index: int) -> Vector3:
	var offsets: Array = _get_seat_offsets()
	return offsets[clampi(seat_index, 0, offsets.size() - 1)]


## 地形数据懒加载：terrain/data 异步就绪后自动补上（每帧判空重试，开销可忽略）
func _try_grab_terrain() -> void:
	var starter := get_node_or_null(terrain_starter_path)
	if starter and starter.terrain != null and starter.terrain.data != null:
		_terrain_data = starter.terrain.data


func _physics_process(delta: float) -> void:
	# M33 诊断：位置已 NaN 时打印现场（沙发名/座位/自动驾驶目标），定位第一因
	if not (is_finite(global_position.x) and is_finite(global_position.y) and is_finite(global_position.z)):
		printerr("COUCH-NAN-POS: %s bot_only=%s seats=%s autopilot=%s pos=%s" % [
			name, bot_only, seats, autopilot_target, global_position])
	# ===== M25c 条款 M3 兜底：空车滞留超时自动销毁 =====
	# M27：仅服务器回收。客户端沙发由 MultiplayerSpawner 创建，seats 表收不到
	# （sync_seats.rpc_id 只发真实骑手本人，对端永远是空表）——客户端若也跑回收，
	# 会把服务器正在骑乘/自动驾驶中的沙发本地销毁，视觉上坐骑时隐时现
	# （实测 bot 沙发在客户端存活不超过 3 秒）。真正的回收以服务器
	# queue_free → spawner despawn 广播为准。
	if multiplayer.is_server() and seats.is_empty():
		_empty_time += delta
		if _empty_time >= EMPTY_RECALL_DELAY:
			queue_free()
			return
	else:
		_empty_time = 0.0
	_update_mount_prompt()
	if _terrain_data == null:
		_try_grab_terrain()
	# ===== M25：bot 自动驾驶（服务器权威；bot 无输入设备，直驱位置）=====
	_autopilot_tick(delta)
	# ===== M25f：bot 骑手座位钉位（仅服务器）=====
	# bot 权限 9001+ 使其在服务器上 is_multiplayer_authority()=false，
	# player.gd _physics_process 首行即 return——bot 的座位跟随从不执行，
	# 沙发被自动驾驶拖走时 bot 原地站桩，BT 的"到达"判定永远不成立（150s 超时空转）。
	# 沙发自身的 _physics_process 在服务器照跑，由此每帧把 bot 钉到座位
	# （服务器权威直调位置，不走 rpc；真人骑手由各客户端自己的座位跟随负责）。
	if multiplayer.is_server():
		var riders := get_node_or_null("../../../PlayersContainer")
		if riders != null:
			for peer_id in seats:
				if not PeerQuery.is_bot_peer(int(peer_id)):
					continue
				var rider := riders.get_node_or_null(str(peer_id))
				if rider is Node3D:
					# 【M47】座位偏移是车体**局部**坐标，必须过车的基。
					# 旧写法直接加 global_position：球面上车的 basis 不是单位阵，
					# bot 会被摆到离座位几十厘米到几米的错位置（和玩家座位
					# 偏移修的是同一个坑）。
					(rider as Node3D).global_position = global_transform \
							* get_seat_offset(int(seats[peer_id]))
	# ===== 驾驶（M30：抽成 _drive_tick 虚函数，sports_car.gd 覆盖实现街机驾驶）=====
	_drive_tick(delta)


## 驾驶输入处理（仅座位 0 的本地客户端执行；相机是唯一方向源，杜绝正反馈）。
## M30：从 _physics_process 原地抽出为虚函数——子类 sports_car.gd 覆盖为
## 特斯拉式街机驾驶（tsl 原始数值）。默认实现 = 悬浮沙发飞行驾驶。
func _drive_tick(delta: float) -> void:
	if seats.get(_local_peer_id()) != 0:
		return
	# M34：位置/相机任一为 NaN 时本帧直接返回。M33 的写入闸挡不住查询入口——
	# global_position 或 cam transform 为 NaN 时，下面的 cast_motion/intersect_ray
	# 收到 NaN 参数，引擎内部 normalize 刷屏（bot 骑沙发实测复发根因）。
	if not (is_finite(global_position.x) and is_finite(global_position.y) and is_finite(global_position.z)):
		printerr("COUCH-NAN: %s 位置NaN跳过驱动(drive)" % name)
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cam_pos := cam.global_position
	if not (is_finite(cam_pos.x) and is_finite(cam_pos.y) and is_finite(cam_pos.z)):
		printerr("COUCH-NAN: %s 相机NaN跳过驱动(drive)" % name)
		return
	var cam_basis := cam.global_transform.basis

	# WoW 驭空术：W/S 沿相机视线（含俯仰，可俯冲）；A/D 相机平面侧移
	var thrust := Input.get_axis("move_backward", "move_forward") # +1 前进
	# ===== M39：自动飞行（AutoRun 状态机）=====
	# 开启自动飞行 = 持续 W 前进（沿相机视线）+ 轻微爬升，避免贴地擦行。
	# 任意移动键按下会由 player.gd 调 AutoRun.stop() 取消（WoW Auto-Run 语义）。
	var auto_flying := false
	var ar := get_node_or_null("/root/AutoRun")
	if ar != null and ar.has_method("is_active"):
		auto_flying = bool(ar.call("is_active"))
	if auto_flying:
		thrust = 1.0
	var strafe := Input.get_axis("move_left", "move_right")        # +1 右移
	# 三档速度：Ctrl = 极速（验证球形用），Shift = 加速，默认巡航
	var speed := flight_speed
	if Input.is_physical_key_pressed(KEY_CTRL):
		speed = hyper_speed
	elif Input.is_action_pressed("shift"):
		speed = boost_speed
	var vel := (-cam_basis.z * thrust + cam_basis.x * strafe) * speed

	# 【M47 球面】升降必须沿**当地法线**，不能沿世界 +Y。
	# 球面上当地法线与世界 Y 的夹角可以到 96°（出生点实测 (0.994,-0.108,0.003)），
	# 用 Vector3.UP 当"上升"实际算出来的是"斜向下钻地"——这就是用户报的"飞行钻地"。
	var up_vec := Planet.up_at(global_position)
	var lift := 0.0
	if Input.is_action_pressed("jump"):
		lift += vertical_speed
	if Input.is_action_pressed("crouch"):
		lift -= vertical_speed
	# M39：自动飞行时轻微爬升（沿视线前进但保持离地，避免擦着地形飞）。
	# 爬升速度取 vertical_speed 的 35%——够脱离地面，又不会一路顶到天上。
	if auto_flying and lift <= 0.0:
		lift = vertical_speed * 0.35

	# M30c：水平方向过形状扫掠滑墙（撞楼/撞树/撞山不再穿透）
	var move := _resolve_horizontal_move(global_position, (vel + up_vec * lift) * delta, 1.2)
	var new_pos := global_position + move
	# 【M47 球面】地面钳制改成**径向**：球面上"地面高度"不是一个 y 值，而是半径。
	# 旧写法 `new_pos.y = maxf(new_pos.y, ground_y + 0.3)` 把世界 Y 当地面高度用，
	# 方向都不一样，必然把沙发压进地里。
	# 现在只守一条不变量：**沙发离球心的距离不得小于"该方向地表 + 悬浮高度"**。
	if new_pos.length_squared() > 0.0001:
		var g_r := _ground_radius_at(new_pos)
		var min_r := g_r + HOVER_CLEARANCE
		if new_pos.length() < min_r:
			new_pos = new_pos.normalized() * min_r
	# M33：同 autopilot——写位置前 NaN 闸，防 normalize 全线刷屏
	if is_finite(new_pos.x) and is_finite(new_pos.y) and is_finite(new_pos.z):
		global_position = new_pos
	else:
		printerr("COUCH-NAN: %s 放弃NaN位移(drive) pos=%s new_pos=%s" % [
			name, global_position, new_pos])

	# 沙发朝向 = 移动方向（纯视觉；玩家本体朝向由 player.gd 骑乘分支硬对齐到载具）
	if vel.length_squared() > 0.5:
		_turn_toward_dir(vel, 8.0 * delta)


## 【M55 球面修复】绕**当地法线**转向，不能绕世界 Y，也不能用世界 atan2。
##
## 两处旧错（都是"球面上用平面角度"）：
##   ① 目标方向由 `atan2(-vel.x, -vel.z)` 算世界 yaw，再 `Basis(UP, yaw)*FORWARD`
##      转回来 —— 球面上当地水平面不是世界 XZ 平面，误差可达 90°。
##   ② 用来插值的"当前前方"取了 `basis.z`（+Z = 沙发后方），而 align_basis 的
##      forward 参数决定的是 -Z。两者符号相反，稳态收敛到"沙发背对前进方向"。
## 现在：直接吃世界方向向量，当前前方 = -basis.z，全程只在切平面里做旋转。
func _turn_toward_dir(dir: Vector3, weight: float) -> void:
	if not (is_finite(dir.x) and is_finite(dir.y) and is_finite(dir.z)):
		return
	var up := Planet.up_at(global_position)
	var want: Vector3 = dir - up * dir.dot(up)
	if want.length_squared() < 0.000001:
		return
	want = want.normalized()
	var cur: Vector3 = -global_transform.basis.z
	cur = cur - up * cur.dot(up)
	if cur.length_squared() < 0.000001:
		cur = want
	cur = cur.normalized()
	var ang := cur.signed_angle_to(want, up)
	var step := ang * clampf(weight, 0.0, 1.0)
	var t := global_transform
	t.basis = Planet.align_basis(up, cur.rotated(up, step))
	global_transform = t


## 【M47 球面】"地面在哪"改成**径向**回答：返回该方向地表离球心的距离。
##
## 旧 `_physics_ground_height()` 沿世界 Y 打射线、返回 y 值 —— 只在地图是平面时成立。
## 球面上"地面高度"必须用半径表达，否则同一个 y 在不同经度对应完全不同的高度。
## 规则与 player.gd 完全一致（单一真值源）：
##   · 脚下有碰撞面（建筑地板/广场/台阶）→ 以碰撞面为准
##   · 一个都打不到 → 用地形渲染网格的高度（Planet.mesh_height，与视觉同源）
func _ground_radius_at(pos: Vector3) -> float:
	var up := Planet.up_at(pos)
	var base: float = Planet.RADIUS + Planet.mesh_height(up)
	var space := get_world_3d().direct_space_state
	if space == null:
		return base
	var from: Vector3 = pos + up * 6.0
	var to: Vector3 = pos - up * 12.0
	if not (is_finite(from.x) and is_finite(from.y) and is_finite(to.x) and is_finite(to.y)):
		return base
	var q := PhysicsRayQueryParameters3D.create(from, to)
	# 【M53】原来没设掩码（默认 layer 1 = "world_decor"），打不到 layer 2 的
	# 地形 trimesh —— 野外飞行时地面高度全靠解析式猜，和渲染网格对不上。
	# 与 player.gd 用同一条规则：世界层（1+2）全查，只摘掉 actor 层。
	q.collision_mask = (1 | 2) & ~ACTOR_LAYER
	q.collide_with_areas = false
	q.hit_from_inside = false
	q.exclude = _ground_exclude_rids()
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return base
	var hp: Vector3 = hit["position"]
	if not (is_finite(hp.x) and is_finite(hp.y) and is_finite(hp.z)):
		return base
	return maxf(base, hp.length())


## M25f：物理射线测地面（村区 GridMap 地板也在内，terrain 数据之外的全靠它）。
## exclude：必须排除本车骑手——骑手坐在沙发正上方（座位 z 偏移 0.35 < 玩家
## 胶囊半径 0.358），射线从 +6m 下打必然擦中骑手头顶，骑手头顶会被当成"地面"，
## maxf 钳制每帧把沙发抬到骑手头顶 +0.3m → 骑手跟着上新沙发顶 → 正反馈，
## 实测 190m/s 垂直狂飙（用户报告"突然不受控制往上飞"的事故主因）。
func _physics_ground_height(pos: Vector3, exclude: Array[RID] = []) -> float:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 6.0, 0), pos + Vector3(0, -12.0, 0))
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	# M33：命中点/查询点可能含 NaN（射线端点 NaN 时 Godot 物理查询行为未定义，
	# 可能返回 NaN 命中点）。NaN 会让所有 `< -90.0` 比较为 false、兜底分支被跳过，
	# 一路污染 autopilot 的 cruise_y/up → global_position 被写成 NaN（实测刷屏根因）。
	var y := (hit.position.y as float) if not hit.is_empty() else -99.0
	return y if is_finite(y) else -99.0


## M25f：地面射线排除名单——**所有角色**（不只本车骑手）。
## M39 事故复盘：原实现只排除 `seats` 里的骑手 + 本地玩家。多车同行时
## （bot 集体返程，4 辆沙发位置几乎重合、y 差 0.1m），A 车的地面射线会
## 打中 **B 车的骑手**——射线只下探 18m，而 B 车骑手就贴在 A 车旁边几米内。
## 实测铁证：`couch_9001 y=71.2 pg=74.0`（pg 恒为 y+2.75 = 邻车骑手头顶），
## `up=-12`（本车想下降）却被 `maxf(new_pos.y, pg+0.4)` 每帧强抬 3.15m
## → 60fps 下 ≈189m/s 无界爬升，返程 bot 飞到 4579m 永远回不了村。
## 地面射线只该命中静态世界（地形/建筑/家具），一律排除全部角色碰撞体。
func _ground_exclude_rids() -> Array[RID]:
	var rids: Array[RID] = []
	var container := get_node_or_null("../../../PlayersContainer")
	if container == null:
		return rids
	for child in container.get_children():
		if child is CollisionObject3D:
			rids.append((child as CollisionObject3D).get_rid())
	return rids


## ===== M30c：水平障碍碰撞（形状扫掠 + 滑墙）=====
## 载具是纯运动学移动（直写位置），此前只有垂直防穿——撞楼/撞树/撞墙全穿透。
## 本函数对本帧位移做球形扫掠（cast_motion），被挡则截断并沿障碍面法线滑墙。
## 球心抬高 radius + LIFT（底面离当前地面 0.6m）：只挡真实障碍（楼/树干/陡墙），
## 不挡缓坡（贴地跟随负责爬坡），地面自身也不会误命中。
const SWEEP_LIFT := 0.6
var _sweep_shape := SphereShape3D.new() # 复用避免每帧分配

func _resolve_horizontal_move(from_pos: Vector3, move: Vector3, radius: float) -> Vector3:
	# 【M47 球面】"水平"= 当地切平面分量，不是世界 XZ；升降分量单独留出来。
	# 旧写法 `Vector3(move.x, 0, move.z)` 在球面上会把"沿径向的升降"当成水平，
	# 又把真正的"水平"丢掉一个分量 —— 方向全乱。
	var up := Planet.up_at(from_pos)
	var radial := move.dot(up)
	var planar := move - up * radial
	if planar.length_squared() < 0.000001:
		return move
	var space := get_world_3d().direct_space_state
	_sweep_shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _sweep_shape
	# 球心 = 当前位置沿当地法线抬高（底面离地 SWEEP_LIFT）
	params.transform = Transform3D(Basis.IDENTITY, from_pos + up * (radius + SWEEP_LIFT))
	params.motion = planar
	params.exclude = _ground_exclude_rids()
	params.collide_with_areas = false
	var result: Array = space.cast_motion(params)
	var safe: float = result[0]
	# M34：cast_motion 对异常输入可能返回 NaN（safe*planar=NaN 位移 → new_pos NaN）。
	# 非有限时放弃本帧水平位移，交垂直分量自行处理。
	if not is_finite(safe):
		return Vector3.ZERO
	if safe >= 1.0:
		return move  # 无障碍，原位移放行
	var corrected := planar * safe
	# 拿障碍面法线，去法线分量 = 沿墙滑行（保留切向速度，手感不硬停）。
	# M30f：本版本 PhysicsDirectSpaceState3D 无 rest_info——用 collide_shape
	# 拿接触点对，法线 = 球心(cast 末端) → 球面接触点。
	params.motion = planar * maxf(safe, 0.001)
	var contacts: PackedVector3Array = space.collide_shape(params, 2)
	if contacts.size() >= 2:
		var c0: Vector3 = contacts[0]
		if not (is_finite(c0.x) and is_finite(c0.y) and is_finite(c0.z)):
			return corrected + up * radial
		var sphere_center: Vector3 = from_pos + up * (radius + SWEEP_LIFT) + planar * safe
		var normal: Vector3 = (sphere_center - c0).normalized()
		normal -= up * normal.dot(up) # 只做切平面滑墙（升降交给径向钳制）
		if normal.length_squared() > 0.001:
			normal = normal.normalized()
			var tangent := planar - normal * planar.dot(normal)
			if tangent.length_squared() > 0.0001:
				params.motion = tangent
				var r2: Array = space.cast_motion(params)
				var safe2: float = r2[0]
				if is_finite(safe2):
					corrected += tangent * safe2
	corrected += up * radial # 升降分量不受滑墙影响（径向钳制单独负责）
	return corrected


## ===== M25：bot 自动驾驶（服务器权威）=====
## 目标非空时每帧驶向目标：巡航高度 = 地面 +10m，接近后降到地面 +1.2m。
## 到达（水平 <6m 且接近地面）由 bt_bot_move_to 负责下客收车。
var autopilot_target: Node3D = null
const AUTOPILOT_ARRIVE_XZ := 6.0

func set_autopilot(target: Node3D) -> void:
	autopilot_target = target

func _autopilot_tick(delta: float) -> void:
	if autopilot_target == null or not multiplayer.is_server():
		return
	if not is_instance_valid(autopilot_target):
		autopilot_target = null
		return
	# M34：位置或目标位置 NaN 时本帧直接返回——否则 _physics_ground_height 的
	# intersect_ray 和 flat.normalized() 收到 NaN 在引擎内部刷屏（查询在写入闸之前）。
	if not (is_finite(global_position.x) and is_finite(global_position.y) and is_finite(global_position.z)):
		printerr("COUCH-NAN: %s 位置NaN跳过驱动(autopilot)" % name)
		return
	var tgt_pos := autopilot_target.global_position
	if not (is_finite(tgt_pos.x) and is_finite(tgt_pos.y) and is_finite(tgt_pos.z)):
		printerr("COUCH-NAN: %s 目标位置NaN跳过驱动(autopilot) target=%s" % [name, autopilot_target.name])
		return
	var flat := Vector3(tgt_pos.x - global_position.x, 0.0, tgt_pos.z - global_position.z)
	var ground := _physics_ground_height(global_position, _ground_exclude_rids())
	# M39 修正 1：`th > 1.0` 误伤负高度地形。需求 2 把任务点拉到 1500m 外，
	# 新烘焙的远景丘陵是 -4~-5m（合法负高度），被判成"无数据"→ 走下面的
	# "维持当前高度"分支 → **无界爬升**（实测 bot 飞到 1424m 后一路爬到 569m
	# 高空，永远下不来，420s 超时）。改判据：非 NaN 且 |值| > 0.01 即信任。
	if (ground < -90.0 or not is_finite(ground)) and _terrain_data != null:
		var th: float = _terrain_data.get_height(global_position)
		if is_finite(th) and absf(th) > 0.01:
			ground = th
	# M33：NaN 兜底——射线探不到（-99）或探出 NaN 都走"维持当前高度"。
	# 原写法只判 < -90.0，NaN 比较恒 false → NaN 穿透到 cruise_y/up → 位置被写 NaN。
	if ground < -90.0 or not is_finite(ground):
		ground = global_position.y - 1.0  # 探不到地面：维持当前高度
	# M39 修正 2：探不到地面时**不能**用 `ground + 10` 当巡航高度——
	# ground = pos.y - 1.0 → cruise_y = pos.y + 9 → 每帧爬 9m，无界爬升。
	# 此时改为向**目标所在高度**收敛：目标在地面上时缓慢下降，
	# 高度差钳制在 ±10m 内，既不会爬升也不会自由落体。
	if ground > global_position.y - 2.0:
		ground = global_position.y - 2.0
	# M39 修正 5：ground 的**下界**同理要防污染。ground 若被误判成高空
	# （命中邻车骑手/远处建筑），cruise_y = ground + 10 会把巡航高度抬到天上，
	# 之后 want_y / up 全部跟着错。上界 6m 足够覆盖"从 6m 高空落到地面"的
	# 正常贴地过程；超过说明探到的是非地面物，弃用。
	if ground > global_position.y + 6.0:
		ground = global_position.y - 2.0
	# 巡航：远端高空、近端贴地
	var cruise_y := ground + (1.2 if flat.length() < 14.0 else 10.0)
	# M39 修正 3：爬升/下降速率对"离目标高度差"限幅，避免高度差被 vertical_speed
	# 放大成持续爬升。20m/s × 1s 内的高度差最多修正 20m。
	var want_y: float = clampf(tgt_pos.y + 12.0, cruise_y - 20.0, cruise_y + 20.0)
	var to := Vector3(tgt_pos.x, want_y, tgt_pos.z) - global_position
	var vel := Vector3.ZERO
	if flat.length() > 1.0:
		vel = flat.normalized() * flight_speed
	var up := clampf(to.y, -vertical_speed, vertical_speed)
	var new_pos := global_position + (vel + Vector3.UP * up) * delta
	var pg := _physics_ground_height(new_pos, _ground_exclude_rids())
	# M39 修正 4：抬升闸加**上限**。原写法 `new_pos.y = maxf(new_pos.y, pg+0.4)`
	# 在 pg 被误判成高空（命中邻车骑手/远处建筑）时会把沙发强行拽上去，
	# 且 `up` 明明是下降也拦不住 —— 这是返程爬升到 4579m 的最后一道放大器。
	# 地面永远在脚下：pg 只允许把本车抬到「当前高度 +2m」以内，
	# 真正的爬升交给 up/cruise_y 决定，误命中最多造成一次小抖动。
	if pg > -90.0 and pg <= global_position.y + 2.0:
		new_pos.y = maxf(new_pos.y, pg + 0.4)
	elif _terrain_data != null:
		# M39：同修正 1，负高度地形也要认（远景丘陵 -4~-5m）
		var tg: float = _terrain_data.get_height(new_pos)
		if is_finite(tg) and absf(tg) > 0.01 and tg <= global_position.y + 2.0:
			new_pos.y = maxf(new_pos.y, tg + 0.4)
	# M33：写位置前统一 NaN 闸——任何分量非有限就放弃本帧位移（保持原位）。
	# 位置一旦 NaN，钉位/同步/相机全线污染且不可自愈，必须在写入口统一拦。
	if is_finite(new_pos.x) and is_finite(new_pos.y) and is_finite(new_pos.z):
		global_position = new_pos
	else:
		printerr("COUCH-NAN: %s 放弃NaN位移 pos=%s new_pos=%s autopilot=%s" % [
			name, global_position, new_pos, autopilot_target])
	if vel.length_squared() > 0.5:
		_turn_toward_dir(vel, 8.0 * delta)


## ===== M25：bot 上下车/收车（服务器本地直调；bot 的 peer 不真实存在，不走 rpc）=====
## M28：req_pos = 召唤锚点（请求端按键瞬间的实时位置）。距离校验以锚点为准
## ——服务器视角玩家位置是网络延迟旧值，移动中召唤会被 MOUNT_RANGE*2 误拒；
## 哨兵默认（x>=90000）走原服务器视角逻辑（bot 路径无延迟，不需要锚点）。
func server_mount_peer(peer_id: int, req_pos: Vector3 = Vector3(99999, 99999, 99999)) -> bool:
	if not multiplayer.is_server():
		return false
	if not has_free_seat() or seats.has(peer_id):
		return false
	# M25f 条款 M6：bot 专属沙发只接 bot；玩家沙发不接 bot（对称防御）。
	# M28：bot 判定改 PeerQuery.is_bot_peer——旧 `peer_id >= 9001` 无上界判定
	# 把 ENet 大随机 id 的真人客户端误判成 bot，客户端永远上不了座（M28 事故）。
	if bot_only and not PeerQuery.is_bot_peer(peer_id):
		return false
	if not bot_only and PeerQuery.is_bot_peer(peer_id):
		return false
	if _rider_busy_elsewhere(peer_id):
		return false
	var player := get_node_or_null("../../../PlayersContainer/" + str(peer_id))
	if player == null:
		return false
	var ref_pos: Vector3 = player.global_position
	if req_pos.x < 90000.0:
		ref_pos = req_pos
	if global_position.distance_to(ref_pos) > MOUNT_RANGE * 2.0:
		return false
	var used: Array = seats.values()
	for seat_index in _get_seat_offsets().size():
		if not used.has(seat_index):
			seats[peer_id] = seat_index
			break
	_broadcast_seats()
	if player.has_method("set_mounted"):
		player.set_mounted(self, seats[peer_id])
	return true


func server_dismount_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or not seats.has(peer_id):
		return
	seats.erase(peer_id)
	_broadcast_seats()
	var player := get_node_or_null("../../../PlayersContainer/" + str(peer_id))
	if player != null and player.has_method("set_mounted"):
		player.set_mounted(null)
		var drop := global_position
		var pg := _physics_ground_height(global_position, _ground_exclude_rids())
		if pg > -90.0:
			drop.y = pg + 0.5
		elif _terrain_data != null:
			var th: float = _terrain_data.get_height(global_position)
			if th > 1.0:
				drop.y = th + 0.5
		player.global_position = drop
	# M25c 条款 M3：下客即收车——空车立即销毁（bot 到达下车即消失）
	if seats.is_empty():
		queue_free()


## M25c 条款 M4：骑手掉线摘座——玩家节点已销毁，从座位表移除该 peer，空车即回收
func server_remove_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or not seats.has(peer_id):
		return
	seats.erase(peer_id)
	_broadcast_seats()
	if seats.is_empty():
		queue_free()


## 收车：空车才回收（骑手先下再收）
func server_recall() -> void:
	if multiplayer.is_server() and seats.is_empty():
		queue_free()


## 本地 peer id：单机与 Host 均为 1（Godot 无 peer 时默认 1，与玩家节点名一致）
func _local_peer_id() -> int:
	return multiplayer.get_unique_id()


## 本地玩家节点（按 peer id 找；座位判定与 Prompt 显隐用）
func _local_player() -> Node:
	var container := get_node_or_null("../../../PlayersContainer")
	if container == null:
		return null
	return container.get_node_or_null(str(multiplayer.get_unique_id()))


## 附近有空位时显示"E - 骑乘"提示（Label3D，3.5 米内）
func _update_mount_prompt() -> void:
	var prompt := get_node_or_null("Prompt") as Label3D
	if prompt == null:
		return
	# M25f 条款 M6：bot 专属沙发不显示骑乘提示
	if bot_only:
		prompt.visible = false
		return
	var local := _local_player()
	var show := false
	if local != null and has_free_seat() and not seats.has(_local_peer_id()):
		show = local.global_position.distance_to(global_position) <= MOUNT_RANGE
	prompt.visible = show


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	var local_player := _local_player()
	if local_player == null:
		return
	var local_id := multiplayer.get_unique_id()
	if seats.has(local_id):
		# 下座永远允许——被困 bot 沙发的乘客靠 E/X 自救（条款 M6/M8）
		request_dismount.rpc_id(1)
	elif not bot_only and (seats.is_empty() or has_free_seat()):
		# M25f 条款 M6/M7：bot 沙发不接玩家；一骑一席由 request_mount 服务器端兜底
		if global_position.distance_to(local_player.global_position) < MOUNT_RANGE:
			request_mount.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_mount() -> void:
	if not multiplayer.is_server():
		return
	# M25f 条款 M6：bot 自动驾驶沙发拒绝玩家上座（会被劫走，且非主驾无法驾驶）
	if bot_only:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if not has_free_seat() or seats.has(sender):
		return
	# M25f 条款 M7：一骑一席——已骑别的载具就拒绝
	if _rider_busy_elsewhere(sender):
		return
	var player := get_node_or_null("../../../PlayersContainer/" + str(sender))
	if player == null or global_position.distance_to(player.global_position) > MOUNT_RANGE * 2.0:
		return
	var used: Array = seats.values()
	for seat_index in _get_seat_offsets().size():
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
	# M25c 条款 M3：玩家按 E 下车 → 空车立即销毁（再按 X 的主动收回另走 request_recall）
	if seats.is_empty():
		queue_free()


## M25：玩家 X 收回专属沙发（只有车主能收；下座 rpc 先入队，收到时车已空）
## M30：sports_car 继承本 rpc——车名前缀按场景类型判断（couch_/car_）
@rpc("any_peer", "call_local", "reliable")
func request_recall() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	var prefix := "couch_"
	if name.begins_with("car_"):
		prefix = "car_"
	if str(sender) != name.trim_prefix(prefix):
		return
	if seats.is_empty():
		queue_free()


func _broadcast_seats() -> void:
	# M26：沙发不是全局同步节点（本地生成 + rpc 上座架构）——
	# 全播会让没有该沙发节点的对等端刷 "Node not found: Vehicles/couch_xxx"
	# （含服务器自己：客户端本地生成的 couch_2 在服务器不存在；
	# 沙发销毁后飞行中的 loopback 消息同样触发）。只发给真实骑手
	# （其本地一定有该节点，因为沙发就是骑手本地生成的）+ 本地播放。
	sync_seats(seats)
	for peer_id in seats:
		var pid := int(peer_id)
		if not PeerQuery.is_bot_peer(pid):
			sync_seats.rpc_id(pid, seats)


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
	# M25：bot（PeerQuery.is_bot_peer，虚拟 id 不真实在线）权威保持服务器(1)——
	# 否则 MultiplayerSynchronizer 认为一个不在线的 peer 拥有沙发，位置不再同步。
	# M28：判定改 PeerQuery（旧 <9001 把真人客户端 id 误判成 bot，authority 挂错）。
	if new_driver != 0 and not PeerQuery.is_bot_peer(new_driver):
		set_multiplayer_authority(new_driver)
	else:
		set_multiplayer_authority(1)
	var local_id := multiplayer.get_unique_id()
	var player := _local_player()
	if player != null:
		# 【M47 事故防御】bot 专属沙发绝不接真人。
		# 上游 bot_summon_and_mount 的 peer 判定一旦错把玩家当自己，这里就是
		# 最后一道闸：宁可不上座，也不能让玩家被自动驾驶的车拖着飞。
		if bot_only and seats.has(local_id):
			printerr("COUCH-GUARD: %s 是 bot 专属车，拒绝本地 peer %d 上座" % [name, local_id])
			seats.erase(local_id)
		if seats.has(local_id):
			player.set_mounted(self, seats[local_id])
			# 上座：位置由 player._physics_process 座位跟随驱动，不在此处瞬移
		elif previous_driver == local_id or player.mounted_vehicle == self:
			player.set_mounted(null)
			if _terrain_data == null:
				_try_grab_terrain()  # 下车落点也要地形数据（骑乘早期下车场景）
			# M25f：下车落点——物理射线优先。村区 Terrain3D 数据高度返回 0，
			# 直接采用会把玩家放到村地板（y2.25）之下穿模坠落；数据高度 >1 才信。
			# （此前此处无差别瞬移本地玩家到沙发位置：任何座位广播都会触发，
			#  且 terrain 0 导致 y=0.5 穿地板——用户被困 bot 沙发时按下车的
			#  落点就走的这条路径。）
			var drop := global_position
			var pg := _physics_ground_height(global_position, _ground_exclude_rids())
			if pg > -90.0:
				drop.y = pg + 0.5
			elif _terrain_data != null:
				var th: float = _terrain_data.get_height(global_position)
				if th > 1.0:
					drop.y = th + 0.5
			player.global_position = drop
	# M25c 条款 M3：座位广播为空 = 服务器已收车——各端同步销毁，杜绝客户端残留空车
	if seats.is_empty():
		queue_free()
