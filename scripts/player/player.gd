class_name Character
extends CharacterBody3D

enum SkinColor { BLUE, YELLOW, GREEN, RED }

const NORMAL_SPEED = 6.0
const SPRINT_SPEED = 10.0
const JUMP_VELOCITY = 7.5
const FALL_GRAVITY_MULTIPLIER = 1.6
const BASE_NICKNAME_HEIGHT := 2.0
const SERVER_ANIMATION_REQUESTS_PER_SECOND := 10.0
const SERVER_ANIMATION_REQUEST_BURST := 6.0
const PICKUP_ANIMATION_DELAY_MSEC := 200
const PICKUP_ANIMATION_WINDOW_MSEC := 1200
const PICKUP_REQUEST_COOLDOWN_MSEC := 1000
## M24：bot 虚拟 peer id 基数（与 BotController.BOT_ID_BASE 同值，避免循环引用）
const BOT_AUTH_BASE := 9001

## M11：技能 → 音效映射（key 见 SfxManager._LIBRARY）。
## basic_attack 不在表内——普攻音效由 _play_attack_animation 按动画播。
const SKILL_SFX := {
	"p_renew": &"heal",
	"p_flash_heal": &"heal",
	"p_holy_nova": &"holy_missile",
	"p_smite": &"holy_missile",
	"m_fireball": &"fireball",
	"m_frostbolt": &"frostbolt",
	"m_arcane_blast": &"arcane",
	"m_arcane_power": &"arcane",
	"w_execute": &"heavy_punch",
	"w_whirlwind": &"swing",
	"w_shield_wall": &"shield_block",
}

## M13：脚步声参数——步频按 0.3s/步（约 3.3 步/秒，匹配跑速 5m/s），
## 水平速度低于该阈值（站立/缓步）不播
const FOOTSTEP_INTERVAL := 0.3
const FOOTSTEP_MIN_SPEED := 2.0
const FOOTSTEP_VOLUME_DB := -8.0
const REMOTE_FOOTSTEP_UNIT_SIZE := 6.0

var _footstep_accum := 0.0
## M15：空中标志——落地粒子只在"真的跳过/坠落后落地"触发，避免平地行走误触发
var _was_airborne := false
var _remote_moving := false # 远程端由动画广播（Run/Sprint）驱动，velocity 不可靠
## M14：开局默认职业（用户选定战士）——未选职业时 2/3/4 技能槽全部静默失效
const DEFAULT_CLASS_ID := "warrior"
## M16：空手打击改播重定向 Strike 动画（原 M9 的 Pickup 2.5x 方案废弃）
## M14：普攻动画统一提速倍率（打击感保底）
const ATTACK_ANIM_SPEED := 1.5

# ===== M18b-2：步兵动作战斗层（roguelite 机制移植，详见 design.md 5.17）=====
## 三连斩：普攻三段循环（挥剑→盾撞→转圈重斩），服务器权威计段决定伤害倍率。
## 客户端/服务器用同一推进规则（窗口内 +1 循环，超窗重置），普攻冷却两端同校验，
## 输入序列一致 → 段数一致。转圈圈（Attack1）回归为第三段招牌收尾。
const INFANTRY_CLASS_ID := "infantry"
const INFANTRY_COMBO_ANIMS: Array[StringName] = [&"SwordSlash", &"Kick", &"Attack1"]
const INFANTRY_COMBO_MULT: Array[float] = [1.0, 1.2, 1.6]
const COMBO_WINDOW_MSEC := 3000

## 冲刺（Shift 短按）：0.18s 高速位移，冷却 5s，打断当前攻击/拾取（dash_cancel）
const DASH_SPEED := 22.0
const DASH_DURATION_MSEC := 180
const DASH_COOLDOWN_MSEC := 5000

## 盾墙格挡（按住右键）：伤害 -70%，移速减半。无格挡动画，用姿态数值表达。
const BLOCK_DAMAGE_FACTOR := 0.3
const BLOCK_SPEED_FACTOR := 0.5

## 震屏：第三段转圈重斩出手 / 自身被击时触发（roguelite shake_camera 机制）
const SHAKE_ATTACK_MAGNITUDE := 0.12
const SHAKE_HURT_MAGNITUDE := 0.08

const ALLOWED_ANIMATION_STATES := {
	&"Idle": true,
	&"Run": true,
	&"Sprint": true,
	&"Jump": true,
	&"Jump2": true,
	&"Fall": true,
	&"Attack1": true,
	&"Kick": true,
	&"Pickup": true,
	&"Emote2": true,
	&"Strike": true,
	&"SwordSlash": true,
	# M18b-3：KayKit 备用视觉新增状态（机器人侧无此动画自动跳过）
	&"Dodge": true,
	&"Block": true,
	&"Death": true,
	# M29：骑乘坐姿（悬浮沙发）——GodotRobot 侧为 Universal 库烘焙动画
	&"Sit": true
}
const HAT_NODES_BY_ITEM := {
	"fedora": "Fedora",
	"headphones": "Headphones",
	"pirate_hat": "PirateHat",
	"sheriff_hat": "SheriffHat",
	"sombrero": "Sombrero",
	"wizard_hat": "WizardHat",
	# M3 新帽子复用模板模型：皮帽=礼帽、战盔=警长帽、秘术环带=巫师帽
	"cap": "Fedora",
	"helm": "SheriffHat",
	"circlet": "WizardHat",
}
const WEAPON_NODES_BY_ITEM := {
	"sword": "Sword",
	"sword_short": "SwordShort", # M40：CC0Tree 短剑模型
	"sword_big": "SwordBig",
	"axe": "Axe",
	# M3 新武器复用模板模型：铁剑/精铁剑=单手剑、亡灵利刃=大剑、战斧=斧
	"sword_iron": "Sword",
	"sword_green": "Sword",
	"sword_blue": "SwordBig",
	"axe_iron": "Axe",
	# M36：气球夺剑战利品复用大剑模型
	"balloon_sword": "SwordBig",
}
const BACKPACK_NODES_BY_ITEM := {"backpack": "Backpack"}
const HEAD_EQUIPMENT_PATH := "GodotRobot3D/RobotArmature/Skeleton3D/HeadAttach/"
const HAND_EQUIPMENT_PATH := "GodotRobot3D/RobotArmature/Skeleton3D/LeftHandAttach/"
const BACK_EQUIPMENT_PATH := "GodotRobot3D/RobotArmature/Skeleton3D/BackAttach/"
const FIRST_PERSON_HIDDEN_BONES: Array[StringName] = [&"Head", &"HeadTop"]

@export var skin_color: SkinColor = SkinColor.BLUE

@export_category("Nickname")
@export_range(0.0, 1.0, 0.01) var nickname_clearance: float = 0.2

@export_category("Objects")
@export var _body: Node3D = null

## M19：乘坐载具状态（非空 = 正在乘坐 hover_couch，本体位置由自己按座位跟随）
var mounted_vehicle: Node3D = null
## M27 条款 V6：骑乘中载具速度估计源（座位跟随的位置差）——驱动远程端 Sprint/Idle
var _mounted_last_vehicle_pos: Vector3 = Vector3.ZERO
var _terrain_probe: Node = null
var mounted_seat: int = 0

## M19：上下车由载具调用；上车重置攻击/连招状态，下车恢复自由移动
func set_mounted(vehicle: Node3D, seat_index: int = 0) -> void:
	mounted_vehicle = vehicle
	mounted_seat = seat_index
	velocity = Vector3.ZERO
	is_attacking = false
	is_blocking = false # M29b：格挡中上座会永久拦截 Sit 请求（_request_animation 的 Block 保护），必须清
	is_collecting = false
	_last_requested_animation = &""
	# M42：**上座绝不改朝向**——用户硬要求"角色本来朝哪，骑上坐骑仍保持原朝向"。
	# 旧实现 `rotation.y = vehicle.rotation.y` 把玩家根节点（相机弹簧臂的父节点）
	# 硬拽成载具朝向：探针实测上座瞬间相机世界朝向跳 -159.6°、根节点跳 -94.3°，
	# 这就是"莫名其妙转向"的唯一真凶（画面整体被拧，用户看到的就是角色转了）。
	# 载具自身朝向在召唤瞬间已对齐玩家身体朝向（见 _body_anchor_yaw），
	# 因此这里不需要任何对齐动作，上下座全程零跳变。
	if vehicle != null:
		# M27：上车瞬间对齐速度估计基准，避免首帧把"就位瞬移"当成高速 Sprint
		# M28b 修复：这两行原本缩进错位到块外，下座 vehicle=null 必崩
		# （SCRIPT ERROR global_position on Nil），并连带跳过下车动画恢复
		_mounted_last_vehicle_pos = vehicle.global_position
		# M29：骑乘改坐姿（原 Idle）
		_request_animation(&"Sit", true)
	else:
		# M29：下车恢复站立待机
		_request_animation(&"Idle", true)


## 【M47】骑乘有效性校验：车必须在座位表里真的有本地 peer。
## 只在骑乘分支用，所以容忍载具节点没有 seats（非载具挂载物一律放行）。
func _mounted_still_valid() -> bool:
	if not is_instance_valid(mounted_vehicle):
		return false
	var seats = mounted_vehicle.get("seats")
	if not (seats is Dictionary):
		return true
	return (seats as Dictionary).has(multiplayer.get_unique_id())


## M19：右键拖动转身——步行转角色节点；骑乘时右键只转相机（WoW 驭空术：
## 飞行方向永远从当前相机读取，沙发朝向由移动方向驱动，杜绝相机↔节点双轨漂移）
func _on_camera_turn(dx: float) -> void:
	if mounted_vehicle != null:
		return
	# M45：绕当地法线转（球面上世界 Y 不是"上"）
	_fwd = _fwd.rotated(_up, dx)


## M19：滚轮缩放镜头距离
func _on_camera_zoom(delta_length: float) -> void:
	if _spring_arm_offset != null:
		_spring_arm_offset.third_person_distance = clampf(
			_spring_arm_offset.third_person_distance + delta_length, 1.5, 14.0)
		_spring_arm_offset._apply_perspective()

## M19：X 召唤 = 把专属沙发放置到面前。
## M25：召唤即骑（用户决策）——放好后立即自动上座；再按 X 下座并收回。
## M27（docs/conventions-multiplayer-visual-sync.md 条款 V1/V2）：
## 载具只能由服务器创建（Vehicles 下 MultiplayerSpawner 广播，含 late-join 重放），
## 客户端严禁本地 instantiate——本地沙发只存在于一端，以其为发送方的
## request_mount.rpc_id(1) 会在服务器 "Node not found" 静默失败（M27 事故 A/B：
## 客户端 X/E 全废、主机坐骑客户端不可见）。
## 因此本函数拆成两半：服务器权威路径（本地造车+就位+上座）与客户端请求路径
## （rpc 请服务器代劳）。target_id 必须显式传递——服务器上
## multiplayer.get_unique_id() 恒为 1，直接复用会把车造给主机而不是请求者。
## M28：req_pos/req_yaw = 请求端按键瞬间的实时位置/朝向锚点。服务器视角的
## 玩家位置/朝向是网络延迟旧值，移动/转视角中召唤会把玩家钉回过去的状态
## （实测：位置有时跳、方向被拧）。客户端请求必须携带锚点；本机/bot 直调
## 不传（INF 哨兵），锚点即自身实时状态。
## M30：vehicle_kind = "couch"（悬浮沙发）| "car"（街机飞车）——场景与节点名随 kind 切换，
## 召唤/上座/同步链路两种载具完全共用（服务器权威 + M28 锚点机制）。
func _summon_mount(
	auto_mount: bool = true, target_id: int = -1,
	req_pos: Vector3 = Vector3(), req_yaw: float = INF,
	vehicle_kind: String = "couch"
) -> void:
	var vehicles := get_node_or_null("../../Environment/Vehicles")
	if vehicles == null:
		return
	if not multiplayer.is_server():
		# M27 条款 V1：客户端不本地造车，请求服务器在权威侧代召唤；
		# M28：携带按 X 瞬间的实时位置/朝向锚点（服务器视角是延迟旧值；
		# 朝向取身体世界朝向——步行身体朝移动方向，与根 rotation.y 解耦）。
		if vehicle_kind == "car":
			request_summon_car.rpc_id(1, global_position, _body_anchor_yaw())
		else:
			request_summon_mount.rpc_id(1, global_position, _body_anchor_yaw())
		return
	if target_id < 0:
		target_id = get_multiplayer_authority()
	# M28：召唤锚点——请求端实时状态优先，服务器视角值兜底。
	# 合理性校验：请求位置与服务器视角差 > 50m 视为异常（防伪造/防串号）。
	# 朝向：本机直调用身体世界朝向（同客户端锚点语义），req_yaw 优先。
	var anchor_pos := global_position
	var anchor_yaw := _body_anchor_yaw()
	if req_yaw != INF:
		anchor_yaw = req_yaw
	if req_yaw != INF:
		var anchor_dist := global_position.distance_to(req_pos)
		if anchor_dist <= 50.0:
			anchor_pos = req_pos
	var scene_path := "res://scenes/vehicles/hover_couch.tscn"
	if vehicle_kind == "car":
		scene_path = "res://scenes/vehicles/sports_car.tscn"
	var couch := vehicles.get_node_or_null(vehicle_kind + "_%d" % target_id)
	if couch == null:
		var scene := load(scene_path) as PackedScene
		if scene == null:
			return
		couch = scene.instantiate()
		couch.name = vehicle_kind + "_%d" % target_id
		# M28：完全原地召唤——沙发定位 = 锚点位置 - 座位0偏移，玩家贴座后
		# global_position 逐位等于按 X 瞬间的位置（零位移；旧"面前 2.5m"方案
		# 有固有前移，用户明确要求原地）。先定位后入树（V14：add_child(true)
		# 瞬间序列化 spawn 快照，入树后设置的位置来不及送达）。y 只做最低
		# 防埋（站地召唤时沙发不得入地；悬空召唤完全保持玩家高度）。
		# 朝向 = 身体世界朝向（入树前定，spawn 快照直接携带）。
		var seat0: Vector3 = Vector3.ZERO
		if couch.has_method("get_seat_offset"):
			seat0 = couch.get_seat_offset(0)
		# 座位偏移是局部的，先按车的目标朝向变换到世界再减
		var b_anchor := _mount_basis(Planet.up_at(anchor_pos), anchor_yaw)
		var couch_pos := anchor_pos - b_anchor * seat0
		# 【M47】防埋不能用世界 Y 射线：球面上没有碰撞体（地形是自建 ArrayMesh），
		# 射线直接打空；就算打中，世界 Y 在 -X 面也是水平的。
		# 直接用网格高度算出"当地地表半径"，把车沿**当地法线**抬到地面之上。
		var up0 := Planet.up_at(couch_pos)
		var ground_r: float = Planet.RADIUS + Planet.mesh_height(up0)
		if couch_pos.length() < ground_r + 0.6:
			couch_pos = up0 * (ground_r + 0.6)
		# 朝向上必须对齐当地法线：只设 rotation.y 会让车 basis.y 保持世界 +Y，
		# 在球面上等于把车立起来插进地里（实测与法线夹角 98°）。
		couch.transform = Transform3D(_mount_basis(up0, anchor_yaw),
			vehicles.to_local(couch_pos))
		vehicles.add_child(couch, true)
	else:
		# 复用路径：同样完全原地（下座后玩家可能已移动/转身，按当前锚点重定位）。
		var seat0: Vector3 = Vector3.ZERO
		if couch.has_method("get_seat_offset"):
			seat0 = couch.get_seat_offset(0)
		var b_anchor1 := _mount_basis(Planet.up_at(anchor_pos), anchor_yaw)
		var vpos := anchor_pos - b_anchor1 * seat0
		var up1 := Planet.up_at(vpos)
		var ground_r1: float = Planet.RADIUS + Planet.mesh_height(up1)
		if vpos.length() < ground_r1 + 0.6:
			vpos = up1 * (ground_r1 + 0.6)
		couch.global_transform = Transform3D(_mount_basis(up1, anchor_yaw), vpos)
	# M25：召唤即骑——沙发就位后立即上座（距离 2.5m 在 MOUNT_RANGE*2 内）
	# M27 条款 V2：代召唤场景走 server_mount_peer 本地直调。不可沿用
	# request_mount.rpc_id(1)——其 sender==0→1 归一会把请求者误判成主机(peer 1)，
	# 客户端按 X 结果给主机上了座（M27 高危陷阱）。
	# M28：锚点模式下请求者真实位置可能在锚点附近而非服务器旧值处——
	# 距离校验放宽到锚点距离（MOUNT_RANGE*2 + 5m 余量），拒绝时仅告警不静默。
	if auto_mount and couch.has_method("server_mount_peer"):
		couch.server_mount_peer(target_id, anchor_pos)


## M28：身体世界朝向对应的沙发 yaw。
## **M55 修正**：朝向角必须相对**当地切平面**表达，不能用 `atan2(x, z)`。
## 球面上世界 XZ 平面不是水平面：up 接近 ±X 时，atan2 会把 90° 的朝向读成 0°
## （实测沙发前方与身体正面差 85.5°，就是"飞行器歪着"的真因）。
## 现在编码/解码共用 Planet.yaw_of / basis_from_yaw（同一参考轴，严格互逆）。
func _mount_basis(up: Vector3, yaw: float) -> Basis:
	return Planet.basis_from_yaw(up, yaw)


## 身体正面 → 绕当地法线的角度。与 _mount_basis 同一套编码。
## 跨端安全：只传一个 float，接收端用 anchor_pos 的 up 解码即还原同一方向。
func _body_anchor_yaw() -> float:
	var up := Planet.up_at(global_position)
	if _body == null:
		var fallback := Planet.yaw_of(up, -global_transform.basis.z)
		return 0.0 if is_nan(fallback) else fallback
	# 3d_godot_robot：模型正面 = 局部 +Z
	var face: Vector3 = _body.global_transform.basis.z
	var y := Planet.yaw_of(up, face)
	return 0.0 if is_nan(y) else y


## M27 条款 V2：客户端 X 召唤请求——服务器在权威节点上代执行 _summon_mount。
## sender 必须是该玩家节点的 multiplayer authority（防伪造/防串号）。
## M28：req_pos/req_yaw = 请求端按 X 瞬间的实时位置/朝向（召唤锚点）。
@rpc("any_peer", "call_local", "reliable")
func request_summon_mount(req_pos: Vector3 = Vector3(), req_yaw: float = INF) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = get_multiplayer_authority()
	if sender != get_multiplayer_authority():
		return
	if mounted_vehicle != null:
		return
	_summon_mount(true, sender, req_pos, req_yaw)


## M30：客户端 V 召唤飞车请求——与沙发召唤同构（服务器权威代召唤 + 锚点）
@rpc("any_peer", "call_local", "reliable")
func request_summon_car(req_pos: Vector3 = Vector3(), req_yaw: float = INF) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = get_multiplayer_authority()
	if sender != get_multiplayer_authority():
		return
	if mounted_vehicle != null:
		return
	_summon_mount(true, sender, req_pos, req_yaw, "car")


## M25：收回专属沙发（下座后调用；服务器空车才真正回收）。
## M25f 条款 M8：只收自己名下的车——骑乘物不是 couch_<peer_id>/car_<peer_id> 时
## （误登 bot 沙发等）仅下座不收回，车是 bot 的，收回会坑死自动驾驶。
## M30：car_<id>（街机飞车）同名下车同样可收。
func _recall_mount() -> void:
	if mounted_vehicle == null or not is_instance_valid(mounted_vehicle):
		return
	var my_id := multiplayer.get_unique_id()
	if str(mounted_vehicle.name) != "couch_%d" % my_id \
			and str(mounted_vehicle.name) != "car_%d" % my_id:
		return
	if mounted_vehicle.has_method("server_recall"):
		mounted_vehicle.request_recall.rpc_id(1)


## M25：bot 专用——召唤沙发并自动上座（bot 逻辑只在服务器跑，本地直调不走 rpc；
## request_mount 的 rpc sender 会把直调误判成玩家 1，所以走 server_mount_peer）
func bot_summon_and_mount() -> void:
	if not multiplayer.is_server() or mounted_vehicle != null:
		return
	var vehicles := get_node_or_null("../../Environment/Vehicles")
	if vehicles == null:
		return
	var my_id := get_multiplayer_authority()
	# 【M47 事故修复】必须先确认自己真的是 bot。
	# 事故链：get_multiplayer_authority() 一旦返回 1（bot 节点 authority 被服务器
	# 兜底成 1，或 bot 判定走了别的分支），my_id 就变成玩家：
	#   → get_node_or_null("couch_1") 命中**玩家自己的沙发**
	#   → 下面的复用路径把它 global_transform 拉到 bot 脚下
	#   → server_mount_peer(1)
	# 玩家此刻正坐在 couch_1 上，座位跟随每帧写 global_position = 座位世界坐标，
	# 于是被一辆飞到 160m 外的车"锁着"一路平移 —— 用户原话
	# "角色直接像被风吹着走"；探针实测 velocity=0，位置每帧却位移 0.85m（≈51 m/s）。
	if not PeerQuery.is_bot_peer(my_id):
		return
	var couch := vehicles.get_node_or_null("couch_%d" % my_id)
	if couch == null:
		var scene := load("res://scenes/vehicles/hover_couch.tscn") as PackedScene
		if scene == null:
			return
		couch = scene.instantiate()
		couch.name = "couch_%d" % my_id
		# M28：先定位后入树（spawn 快照必须带正确位置，否则客户端看到的
		# bot 沙发 spawn 在原点）。
		# M47：位置必须沿**当地法线**抬高，朝向必须用对齐法线的 basis——
		# 原来 `global_position + Vector3(0,0.6,0)` + `rotation.y` 在球面上
		# 等于把 bot 的沙发立起来插进地里（实测夹角 98°，还离 bot 164m）。
		var bup := Planet.up_at(global_position)
		var bpos: Vector3 = global_position + bup * 0.6
		couch.transform = Transform3D(_mount_basis(bup, _body_anchor_yaw()),
			vehicles.to_local(bpos))
		vehicles.add_child(couch, true)
	# 复用路径也要重新对齐（bot 可能已经走了很远）
	var bup2 := Planet.up_at(global_position)
	couch.global_transform = Transform3D(_mount_basis(bup2, _body_anchor_yaw()),
		global_position + bup2 * 0.6)
	# M25f 条款 M6：bot 沙发打专属标记——拒绝玩家上座（自动驾驶劫持事故）
	if couch.has_method("mark_bot_vehicle"):
		couch.mark_bot_vehicle()
	couch.server_mount_peer(my_id)

## M18b-6：roguelite 头顶血条（玩家挂载点，青色）
@onready var _head_health_bar: RogueHealthBar = $HealthBar
@export var _spring_arm_offset: SpringArmCharacter = null

@export_category("Skin Colors")
@export var blue_texture: CompressedTexture2D
@export var yellow_texture: CompressedTexture2D
@export var green_texture: CompressedTexture2D
@export var red_texture: CompressedTexture2D

var player_inventory: PlayerInventory
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var can_double_jump = true
var has_double_jumped = false
var is_attacking := false
var is_collecting := false

# ===== MiniWoW 战斗系统（M1）=====
# 战斗目标只通过准星射线 / Q 键选择；伤害全部由服务器结算，客户端只播表现。
const COMBAT_TARGET_LAYERS := 5 # bit1 玩家层 + bit3 怪物层
const AUTO_TARGET_MAX_RANGE := 30.0 # 目标超出该距离自动脱目标

var current_target_path := ""
var _next_attack_msec := {} # 客户端冷却预测（HUD 遮罩用）
var _server_next_attack_msec := {} # 服务器权威冷却
var _applying_authority_sync := false # M5：正在应用服务器权威值时屏蔽属性回播（防 RPC 递归）

# ===== M18b-2：连招/冲刺/格挡状态 =====
var _combo_index := 0 # 客户端连招段（0/1/2），选动画用
var _combo_last_msec := 0
var _server_combo_index := 0 # 服务器权威连招段，算倍率用
var _server_combo_last_msec := 0
var _dash_until_msec := 0
var _next_dash_msec := 0
var _dash_direction := Vector3.ZERO
var is_blocking := false # 格挡姿态（客户端本地表现 + 服务器权威副本，见 set_blocking）
var _last_sent_blocking := false # 上报去重
var _shake_camera: Node = null # 本地玩家相机震屏（_ready 动态挂载）

## M36：气球夺剑——手持石块状态（客户端表现副本 has_stone 由服务器回执驱动，
## 服务器权威副本 _server_has_stone 防伪造；投掷冷却双端各一份）
const STONE_THROW_SPEED := 17.0
const STONE_THROW_COOLDOWN_MSEC := 600
var has_stone := false
var _server_has_stone := false
var _stone_throw_cooldown_msec := 0
var _stone_throw_local_cd_msec := 0

# 金币（M2 怪物掉落奖励，M3 商人消费）
var gold := 0
signal gold_changed(total: int)

## M4：经验与等级（服务器权威，客户端经 sync_experience 同步）
var level := 1
var experience := 0 # 当前等级内已积累的经验（满级后封顶）
signal level_changed(new_level: int)
signal experience_changed(current: int, needed: int)

## M5：职业（服务器权威，客户端经 sync_class 同步；空字符串 = 尚未选择）
## M27 条款 V3：player_class setter 驱动身体视觉切换——同步器（BotSyncConfig 的
## 900x:player_class）/ _add_player 初始化 / sync_class.rpc 都只写这个属性，
## 模型切换逻辑必须挂在这里，否则客户端 bot 永远是 GodotRobot
## （事故 C：双端模型双裂——服务器电视头、客户端机器人）。
## is_node_ready() 守卫：_ready 前（_body 未就绪）赋值时跳过，_ready 里显式补调。
var player_class := "":
	set(value):
		if player_class == value:
			return
		player_class = value
		if is_node_ready():
			_update_body_visual()
signal class_changed(class_id: String)

@onready var attribute_set: AttributeSet = $AttributeSet

## M5：技能弹道场景（法师火球/冰箭）
const PROJECTILE_SCENE := preload("res://scenes/combat/projectile.tscn")

var _current_speed: float
var _spawn_point = Vector3(0, 5, 0)
var _animation_sequence := 0
var _last_applied_animation_sequence := 0
var _last_requested_animation: StringName = &""
var _appearance_sync_requesters: Dictionary = {}
var _server_animation_request_tokens := SERVER_ANIMATION_REQUEST_BURST
var _last_server_animation_token_update_msec := 0
var _server_pickup_animation_started_msec := -1
var _last_server_pickup_request_msec := -PICKUP_REQUEST_COOLDOWN_MSEC
var _pickup_area_camera_yaw_offset := 0.0
var _equipped_hat_visual_id := ""
var _equipped_weapon_visual_id := "" # M11：装备音效的去重判断

@onready var nickname: Label3D = $PlayerNick/Nickname

@onready var _bottom_mesh: MeshInstance3D = get_node("GodotRobot3D/RobotArmature/Skeleton3D/Bottom")
@onready var _chest_mesh: MeshInstance3D = get_node("GodotRobot3D/RobotArmature/Skeleton3D/Chest")
@onready var _face_mesh: MeshInstance3D = get_node("GodotRobot3D/RobotArmature/Skeleton3D/Face")
@onready var _limbs_head_mesh: MeshInstance3D = get_node("GodotRobot3D/RobotArmature/Skeleton3D/LimbsAndHead")
@onready var _skeleton: Skeleton3D = get_node("GodotRobot3D/RobotArmature/Skeleton3D")
@onready var _pickup_area: Area3D = $GodotRobot3D/InfrontArea3D
@onready var _first_person_hud: CanvasLayer = $FirstPersonHUD


func _enter_tree():
	set_multiplayer_authority(str(name).to_int())
	$SpringArmOffset/SpringArm3D/Camera3D.current = is_multiplayer_authority()


func _ready():
	if multiplayer.is_server():
		player_inventory = PlayerInventory.new()
		_add_starting_items()
		_recalculate_equipment_bonus()
		call_deferred("_sync_equipment_appearance")
		if not is_multiplayer_authority():
			call_deferred("_sync_inventory_to_owner")

	set_player_skin(skin_color)
	# M40：CC0Tree 短剑无内嵌材质（FBX 贴出来纯白），运行时补一份金属材质
	var _m40_sword := get_node_or_null("GodotRobot3D/RobotArmature/Skeleton3D/LeftHandAttach/SwordShort")
	if _m40_sword != null:
		for mi in _m40_sword.find_children("*", "MeshInstance3D", true, false):
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.75, 0.78, 0.85)
			sm.metallic = 0.9
			sm.roughness = 0.25
			(mi as MeshInstance3D).set_surface_override_material(0, sm)
	# M18b-3：动画完成信号统一走 Body 路由（GodotRobot / KayKit 步兵两套视觉都转发到此）
	_body.body_animation_finished.connect(_on_animation_finished)
	_body.play_animation_state(&"Idle")
	nickname.visible = true
	_set_nickname_height(BASE_NICKNAME_HEIGHT)
	call_deferred("_update_nickname_height")
	if not multiplayer.is_server():
		call_deferred("_request_equipment_appearance")
	if is_multiplayer_authority() and _spring_arm_offset:
		_pickup_area_camera_yaw_offset = wrapf(
			_pickup_area.global_rotation.y - _spring_arm_offset.global_rotation.y, -PI, PI
		)
		_spring_arm_offset.perspective_changed.connect(_on_camera_perspective_changed)
		_on_camera_perspective_changed(_spring_arm_offset.is_first_person)
		# M18b-2：本地玩家相机挂震屏（噪声偏移 h/v_offset，quick_shake 触发）
		if _shake_camera == null:
			_shake_camera = ShakeCamera3D.new()
			_shake_camera.camera = _spring_arm_offset.get_node_or_null("SpringArm3D/Camera3D") as Camera3D
			if _shake_camera.camera != null:
				add_child(_shake_camera)

	_update_body_visual() # M18b-3：按职业挂身体视觉（默认战士=机器人）
	_enter_combat_ready()
	# M19 修订（用户 2026-10-18 要求）：开局即发放漂浮伙伴，不再锁任务。
	# 任务完成钩子（sync_quest_state 尾部）保留作双保险；各端自发生成自己的。
	if is_multiplayer_authority():
		call_deferred("_ensure_companion")


## M18b-3：身体视觉切换——步兵用 KayKit 人形，其余职业用 GodotRobot。
## 本地与远程玩家都走 sync_class，全端一致。
func _update_body_visual() -> void:
	_body.set("use_alt_body", player_class == INFANTRY_CLASS_ID)


func _on_camera_perspective_changed(first_person: bool) -> void:
	if not is_multiplayer_authority():
		return
	_body.visible = true
	_bottom_mesh.visible = not first_person
	_chest_mesh.visible = not first_person
	_face_mesh.visible = not first_person
	_limbs_head_mesh.visible = true
	nickname.visible = not first_person
	_first_person_hud.visible = first_person
	for bone_name in FIRST_PERSON_HIDDEN_BONES:
		var bone_index := _skeleton.find_bone(bone_name)
		if bone_index >= 0:
			_skeleton.set_bone_pose_scale(bone_index, Vector3.ZERO if first_person else Vector3.ONE)
	if first_person:
		_align_pickup_area_with_camera()
	else:
		_pickup_area.rotation = Vector3.ZERO
		call_deferred("_refresh_nickname_height_after_perspective_change")


func _refresh_nickname_height_after_perspective_change() -> void:
	if not is_multiplayer_authority() or _is_local_first_person():
		return
	var height := _calculate_nickname_height(_equipped_hat_visual_id)
	_set_nickname_height(height)
	nickname.visible = true
	if multiplayer.is_server():
		_broadcast_nickname_height(height)


func _align_pickup_area_with_camera() -> void:
	var pickup_rotation := _pickup_area.global_rotation
	pickup_rotation.y = wrapf(_spring_arm_offset.global_rotation.y + _pickup_area_camera_yaw_offset, -PI, PI)
	_pickup_area.global_rotation = pickup_rotation


func _physics_process(delta):
	# M45：球面化——每帧先把角色钉在星球表面、把根节点 basis 对齐当地法线。
	# 必须在 move_and_slide 之前：移动方向由 transform.basis 的局部 XZ 决定，
	# basis 已对齐切平面时，既有"本地 XZ 移动"代码自动变成"沿球面行走"。
	_planet_frame_step(delta)
	if not multiplayer.has_multiplayer_peer() or not is_multiplayer_authority():
		return
	# 【M48】把自己身体的朝向喂给别的端——见 _net_tick_body_yaw 的注释
	_net_tick_body_yaw()

	# M19：乘坐载具时本体位置由自己按座位跟随（沙发位置由 Synchronizer 同步），
	# 禁用自身移动/重力/攻击，保持 Idle 姿态
	# M19 安全网：意外沉入地形（GridMap 交界/碰撞缺口）时拉回地表
	if _terrain_probe == null:
		_terrain_probe = get_node_or_null("../../Environment/TerrainStarter")
	if _terrain_probe != null and _terrain_probe.terrain != null \
			and _terrain_probe.terrain.data != null and not is_multiplayer_authority() == false:
		var ground_check: float = _terrain_probe.terrain.data.get_height(global_position)
		if global_position.y < ground_check - 3.0:
			global_position.y = ground_check + 0.5
			_planet_zero_vertical()

	# 【M47 事故】骑乘不变量看门狗 —— 这一条挡住"人没上车却被当成在车上"的所有路径。
	#
	# 用户症状："角色直接像被风吹着走"。探针实测：velocity=0.00，位置却每帧
	# 位移 0.7~1.0m（≈51 m/s）匀速平移 —— 因为骑乘分支把 global_position
	# 直接写死成"座位世界坐标"，而车在飞。
	#
	# 所以骑乘状态必须每帧校验不变量：**这辆车的座位表里真有本地 peer**。
	# 只要不成立（车被 bot 抢走 / 座位被摘 / sync_seats 错播），立刻下座，
	# 让角色回到正常的地面移动逻辑，而不是继续被拖着飞。
	if mounted_vehicle != null and not _mounted_still_valid():
		printerr("MOUNT-WATCHDOG: %s 座位表已无本地 peer %d，强制下座（防被载具拖走）" % [
			name, multiplayer.get_unique_id()])
		set_mounted(null)

	if mounted_vehicle != null:
		velocity = Vector3.ZERO
		# M33：NaN 闸——载具位置非有限时不跟随（否则玩家位置被污染，
		# 相机/朝向/normalized 全线刷屏且不可自愈）
		# 【M47】座位偏移是车体局部坐标，必须过车的基。
		# 旧写法直接加到 global_position 上：球面上车的 basis 不是单位阵，
		# 偏移会算错方向 —— 玩家被塞进车体内部（画面里"角色不见了"）。
		var _seat_pos: Vector3 = mounted_vehicle.global_transform \
				* mounted_vehicle.get_seat_offset(mounted_seat)
		if is_finite(_seat_pos.x) and is_finite(_seat_pos.y) and is_finite(_seat_pos.z):
			global_position = _seat_pos
		# 【M55 硬不变量 I-MOUNT】骑乘期间：**角色朝向 ≡ 载具朝向**。
		# 用户明确要求"角色和飞行器的朝向要保持一致"，这不是"最好一致"而是必须一致。
		# 实现方式：每帧把身体正面硬对齐到载具前方（-载具.basis.z），不用 lerp。
		#   · 上座瞬间不会跳：载具就是按 _body_anchor_yaw()（= 身体正面）造出来的，
		#     两者本来就 0°，snap 是幂等操作（M42 的"上座被拧"根因是载具朝向算错，
		#     已在本轮 M55 修掉，不再是"snap 有问题"）。
		#   · 转向由载具驱动：载具按移动方向转，身体即时跟上，视觉上"车带着人转"。
		#   · 禁止反向驱动（身体带动载具）：那会让相机方向通过身体形成旋转正反馈。
		if _body != null:
			var _vfwd: Vector3 = -mounted_vehicle.global_transform.basis.z
			if is_finite(_vfwd.x) and is_finite(_vfwd.y) and is_finite(_vfwd.z):
				_body.snap_rotation_to(_vfwd)
		_mounted_last_vehicle_pos = mounted_vehicle.global_position
		# M29：骑乘恒坐姿（Sit，循环）；原按载具速度播 Idle/Sprint。
		# M29b：Sit 被打断（受击等）后自动恢复——去重会吞掉无 restart 的请求，
		# 只要当前动画不是 Sit 就强制重播，否则角色会停在受击/攻击末帧
		# （实测"有时在坐骑上跑动/怪姿势"）。
		var _sit_broken: bool = _body == null or _body.current_state() != &"Sit"
		_request_animation(&"Sit", _sit_broken)
		return

	# 死亡后冻结一切输入（表现层播 Fall 动画），直到释放灵魂回村复活
	if not attribute_set.is_alive():
		_planet_zero_horizontal()
		_apply_gravity(delta)
		move_and_slide()
		return

	var current_scene = get_tree().get_current_scene()
	var should_freeze = false
	if current_scene:
		if current_scene.has_method("is_gameplay_input_blocked") and current_scene.is_gameplay_input_blocked():
			should_freeze = true
		elif current_scene.has_method("is_chat_visible") and current_scene.is_chat_visible():
			should_freeze = true
		elif current_scene.has_method("is_inventory_visible") and current_scene.is_inventory_visible():
			should_freeze = true

	# M39：UI 打开（背包/商店/任务/地图/聊天）→ 停止自动前进。
	# 否则玩家在菜单里角色还在跑（WoW 里开界面也会停）。
	if should_freeze:
		AutoRun.stop()

	# ===== M18b-2：步兵冲刺（dash_cancel——打断攻击/拾取，0.18s 高速位移）=====
	var now_msec := Time.get_ticks_msec()
	if Input.is_action_just_pressed("dash") and player_class == INFANTRY_CLASS_ID \
			and _grounded and now_msec >= _next_dash_msec \
			and not should_freeze and attribute_set.is_alive():
		_next_dash_msec = now_msec + DASH_COOLDOWN_MSEC
		_dash_until_msec = now_msec + DASH_DURATION_MSEC
		# 冲刺方向 = 当前移动输入方向；无输入时沿面朝方向突进
		var dash_input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		var dash_dir := transform.basis * Vector3(dash_input.x, 0, dash_input.y)
		dash_dir = dash_dir.rotated(_up, _spring_arm_offset.rotation.y)
		# M37：NaN 闸先于 length() 比较（NaN 比较恒 false 会漏网）
		if not (is_finite(dash_dir.x) and is_finite(dash_dir.y) and is_finite(dash_dir.z)):
			dash_dir = -_body.global_transform.basis.z
		_dash_direction = dash_dir.normalized() if dash_dir.length() > 0.1 \
				else -_body.global_transform.basis.z
		is_attacking = false # dash_cancel：挥砍被闪避打断
		is_collecting = false
		_last_requested_animation = &""
		_request_animation(&"Dodge", true) # M18b-3：KayKit 侧播 Dodge_Forward
		SfxManager.play(&"dash") # M18b-5：冲刺破空声（roguelite dash.ogg）
		SfxManager.spawn_effect("res://scenes/vfx/swing_dust.tscn", global_position)

	# ===== M18b-2：盾墙格挡（按住右键；变化才上报，服务器记权威副本）=====
	# M39：鼠标左右键同时按住 = 鼠标前进（WoW 语义）时，右键不能算格挡——
	# 否则移速被 BLOCK_SPEED_FACTOR 砍半 + 播 Block 动画，与"前进"语义冲突。
	var want_block := Input.is_action_pressed("block") and player_class == INFANTRY_CLASS_ID \
			and _grounded and not is_attacking and not should_freeze and attribute_set.is_alive() \
			and not _both_mouse_held()
	if want_block != _last_sent_blocking:
		_last_sent_blocking = want_block
		is_blocking = want_block # 本地立即生效（移速表现零延迟）
		set_blocking.rpc_id(1, want_block)
		# M18b-3：切格挡姿态动画；解除时清去重缓存让下帧自然回 Idle/Run
		if want_block:
			_request_animation(&"Block", true)
		else:
			_last_requested_animation = &""

	# 冲刺期间无视攻击/拾取冻结（攻击已被打断），由下方速度覆盖接管
	var dashing := now_msec < _dash_until_msec

	if is_attacking or is_collecting:
		_planet_zero_horizontal()
		_apply_gravity(delta)
		move_and_slide()
		return

	if should_freeze:
		_freeze()
		_apply_gravity(delta)
		move_and_slide()
		_request_animation(_body.get_movement_animation(velocity))
		return

	if Input.is_action_just_pressed("pickup") and _grounded and _has_collectible_item_in_front():
		is_collecting = true
		_request_animation(&"Pickup", true)
		# M14 修复：E 键必须真正发起拾取请求。M8→M9 重构中 pickup() 调用丢失，
		# 导致只播动画不入包。延迟 200ms（服务器校验窗口起点 PICKUP_ANIMATION_DELAY_MSEC）
		# 后发起，动画时间戳已在 request_animation_state 服务器分支设置。
		get_tree().create_timer(PICKUP_ANIMATION_DELAY_MSEC / 1000.0).timeout.connect(func():
			if is_instance_valid(self) and is_collecting:
				pickup()
		)
		return

	# M36：E 键捡石块——附近 3m 有已长出的石堆且手上没石头（与掉落物拾取互斥，顺序无冲突）
	if Input.is_action_just_pressed("pickup") and _grounded and not has_stone:
		var pile_idx := _near_stone_pile_index()
		if pile_idx >= 0:
			is_collecting = true
			_request_animation(&"Pickup", true)
			pick_stone(pile_idx)
			return

	# 有目标时由 _unhandled_input 的战斗逻辑接管攻击；无目标时空挥一刀（纯动画）
	# M36：手持石块时左键改为投掷石块打气球（有目标/无目标两条路径都走投掷）
	# M39：鼠标双键按住（鼠标前进）时左键不空挥。
	if Input.is_action_just_pressed("attack") and _grounded and current_target_path.is_empty() \
			and not _both_mouse_held():
		if has_stone:
			throw_stone()
			return
		_start_attack()
		return

	if _grounded:
		# M15：落地粒子——从空中回到地面的一瞬（was_airborne 标志由空中分支设置）
		if _was_airborne:
			_was_airborne = false
			SfxManager.spawn_effect("res://scenes/vfx/land_particles.tscn", global_position)
		can_double_jump = true
		has_double_jumped = false

		if Input.is_action_just_pressed("jump"):
			try_jump()
	else:
		_was_airborne = true
		_apply_gravity(delta)

		if can_double_jump and not has_double_jumped and Input.is_action_just_pressed("jump"):
			try_double_jump()

	_move()
	# M18b-2：冲刺速度覆盖（优先级高于普通/疾跑移速）
	# 【M47】必须按当地切平面写，不能写世界 x/z —— 球面上速度的世界 X 分量
	# 是"径向"，写它等于把角色往地里/天上推。
	if dashing:
		var vr_d: float = velocity.dot(_up)
		velocity = _dash_direction * DASH_SPEED + _up * vr_d
	var collided = move_and_slide()
	if collided:
		_push_collided_items()

	_request_animation(_body.get_movement_animation(velocity))
	_update_combat(delta)
	_update_footsteps(delta)


## M48：把本地角色的**身体朝向**同步给其他端（15Hz，不可靠通道）。
##
## 【事故】_physics_process 对非 authority 在开头直接 return，远端玩家的
## _body.rotation.y 从来没有被任何代码写过 —— 而位置（Synchronizer）和
## Run/Sprint 动画（sync_animation_state）都是同步的。结果：在别人屏幕上，
## 一个"跑着跑步动画、朝向却永远定在出生角度"的角色贴在真正的自己旁边
## —— 用户原话"人走路是重影的，方向也不对"。
##
## 只同步 body 的**局部标量 yaw**：
##   · 不是根 rotation.y —— 根是相机朝向，只有本地玩家有意义，且每帧被相机覆盖
##   · 不是世界四元数 —— body 的父节点 basis 已经是当地坐标系（Planet.align_basis），
##     局部 yaw 在球面上天然正确，还省两个 float 和万向锁风险
const BODY_YAW_NET_INTERVAL := 3 # 30Hz 物理 / 3 ≈ 10Hz，足够看清走路朝向

var _yaw_net_tick: int = 0


func _net_tick_body_yaw() -> void:
	if _body == null:
		return
	_yaw_net_tick += 1
	if _yaw_net_tick % BODY_YAW_NET_INTERVAL != 0:
		return
	if multiplayer.get_peers().is_empty():
		return # 单机：没有远端要喂
	var yaw := _body.rotation.y
	if not is_finite(yaw):
		return
	_net_body_yaw.rpc(yaw)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _net_body_yaw(yaw: float) -> void:
	# 只收"该角色的权威方"发来的朝向：真人 = 他自己，bot = 服务器（id 1）
	var sender := multiplayer.get_remote_sender_id()
	if not (sender == get_multiplayer_authority() or sender == 1):
		return
	if is_multiplayer_authority():
		return # 自己的朝向自己算，绝不收网络值
	if not is_finite(yaw):
		return
	if _body != null:
		_body.rotation.y = yaw


## M24：通用跳跃接口——玩家输入与 bot AI 共用（AI 接管玩家的能力基座之一）。
## 在地面时起跳：物理速度 + 跳跃动画（经 _server_publish_animation 广播各端）
## + 音效/粒子。空中时返回 false。
func try_jump() -> bool:
	if not _grounded:
		return false
	_planet_jump(JUMP_VELOCITY)
	can_double_jump = true
	_was_airborne = true
	_request_animation(&"Jump", true)
	SfxManager.play(&"jump")
	SfxManager.spawn_effect("res://scenes/vfx/jump_particles.tscn", global_position)
	return true


## M24：通用二段跳接口（bot AI 与玩家输入共用）。空中且未用过二段跳时触发。
func try_double_jump() -> bool:
	if _grounded or not can_double_jump or has_double_jumped:
		return false
	_planet_jump(JUMP_VELOCITY)
	has_double_jumped = true
	can_double_jump = false
	_was_airborne = true
	_request_animation(&"Jump2", true)
	SfxManager.play(&"jump")
	SfxManager.spawn_effect("res://scenes/vfx/jump_particles.tscn", global_position)
	return true


## M13：脚步声——本地玩家按真实速度判定（2D 音），远程玩家由动画广播
## （Run/Sprint）驱动（velocity 不同步，不可靠，3D 空间音）
func _update_footsteps(delta: float) -> void:
	# M18b-5：步兵人形（KayKit）的脚步声由动画自带的 footstep 轨道驱动
	# （双足挂点 AudioStreamPlayer3D，随脚步节奏触发），代码脚步停用避免双声源
	if _body is Body and _body.use_alt_body:
		_footstep_accum = 0.0
		return
	var moving := false
	if is_multiplayer_authority():
		moving = _grounded \
			and Vector2(velocity.x, velocity.z).length() > FOOTSTEP_MIN_SPEED
	else:
		moving = _remote_moving
	if not moving:
		_footstep_accum = 0.0
		return
	_footstep_accum += delta
	if _footstep_accum < FOOTSTEP_INTERVAL:
		return
	_footstep_accum = 0.0
	if is_multiplayer_authority():
		SfxManager.play_random(SfxManager.FOOTSTEP_KEYS, FOOTSTEP_VOLUME_DB)
	else:
		SfxManager.play_3d_random(SfxManager.FOOTSTEP_KEYS, global_position, REMOTE_FOOTSTEP_UNIT_SIZE)


# ===== M45：球面化（星球重力 + 局部切平面坐标系）=====
## 背景：地图从平面改成球体后，"上"不再等于世界 +Y。
## 这里用「解析吸附 + 每帧把根节点 basis 对齐当地法线」实现球面行走：
##   · basis 的 Y 轴 = 当地法线 → 既有的「局部 XZ 移动 / 局部 Y 跳跃」代码全部无需改动
##   · 重力沿 -法线 → 走到球的另一面也有"下"
##   · 没有物理地面碰撞体（球面高度场太大），贴地靠径向吸附，接地状态靠 _grounded

var _up := Vector3.UP
var _fwd := Vector3.FORWARD
var _grounded := false
var _planet_ready := false
## 当前星球有没有海洋（外域没有 → 掉进虚空要兜底传送）
var _planet_has_ocean := true
## 无输入时的刹车速率（倍于当前移速）。1.0 = 一帧内停住
const _FRICTION_RATE := 1.6

## 球面对齐的写入阈值（弧度）。小于它就不写 transform。
## 取 0.5°：肉眼不可分辨，但足够把"每帧写一次"压成"每几秒写一次"，
## 让物理体的 floor 状态不再被自己的写操作打乱。
const ALIGN_WRITE_MIN_ANGLE := 0.0087 # ≈ 0.5°
var _aligned := Basis() # 上一次真正写进 transform 的 basis（零值表示还没写过）

## project.godot: 3d_physics/layer_3 = "actor"（玩家/bot/怪物）。第 1 层 = decor，
## 第 2 层 = world。地面射线要覆盖 1+2，只排除 3。
const ACTOR_LAYER := 1 << 2

## 接地吸附带（米）：脚底与地面的径向间隙小于它就判定为"站着"。
## 由 floor_snap_length 推导，不写死 —— 引擎本来就会在 snap 带内把角色吸住，
## 带内的一半以内必然是真实贴地（实测站立时 gap 在 0.038~0.083m 之间波动）。
var _ground_gap_band := 0.2


func _planet_init_once() -> void:
	if _planet_ready:
		return
	_planet_ready = true
	_up = Planet.up_at(global_position)
	var b := global_transform.basis
	_fwd = b * Vector3.FORWARD
	_fwd = _fwd - _up * _fwd.dot(_up)
	if _fwd.length_squared() < 0.000001:
		_fwd = Vector3.FORWARD
	_fwd = _fwd.normalized()
	up_direction = _up
	# 接地带宽 = 引擎吸附带的一半（吸附带内引擎负责把角色拉住，一半以内必然贴地）
	_ground_gap_band = maxf(0.05, floor_snap_length * 0.5)
	# M46：缓存"这颗星球有没有海"。外域没有海，边缘断崖下面是虚空，
	# 掉下去没有水托着会无限下坠，必须兜回地表。
	_planet_has_ocean = Planet.has_ocean()


## 每帧球面校正：平行传输基向量 → 径向吸附 → 对齐 basis（move_and_slide 之前调用）
func _planet_frame_step(_delta: float) -> void:
	_planet_init_once()
	var p := global_position
	if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
		return
	var up := Planet.up_at(p)
	# 平行传输：把上一帧前方向投影到新切平面，沿球面行走时朝向连续不漂
	var f := _fwd - up * _fwd.dot(up)
	if f.length_squared() < 0.000001:
		var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		f = ref - up * ref.dot(up)
	_fwd = f.normalized()
	_up = up
	up_direction = up

	# 径向吸附（双向）。
	# 【M47】旧实现只"抬"不"压"：角色落到地表上方 0~0.28m 的带宽里就停下，
	# 重力又被 _grounded 关掉，于是永远悬空 0.3 米 —— 视觉上就是"脚没踩住、
	# 重力不对"。现在只要在地表上方 35cm 内且没有向上速度，就精确压到地面。
	#
	# 【M47 再修】地面高度改由 _ground_radius_at() 决定：它先问物理世界
	# "脚下到底踩着什么"，没有碰撞面才退回地形网格。旧代码只认地形网格，
	# 站在广场地台上时会被人为压到地形高度、再被地台碰撞推回来，两股力
	# 每帧打架，水平位移被吃光 —— 用户看到的就是"按 W 原地踏步"。
	var ground_r: float = _ground_radius_at(p, up)
	var r: float = p.length()
	var gap: float = r - ground_r

	# 【M47 架构】站立判定交还给物理引擎。
	#
	# 之前地形 Face 没有碰撞体，is_on_floor() 恒为 false，所以只能"猜"地面：
	# 用 height_at() 算一个高度、和渲染网格对不上、再手动压低位置 —— 这就是
	# 用户说的"测量 + 加一点减一点凑合"。现在 Face 挂了 trimesh 碰撞（碰撞体
	# 就是渲染网格本身），move_and_slide() 会给出真实的 floor 结果。
	#
	# 【M53】gap 判据从写死的 0.08 改成"引擎吸附带的一半"：
	# 角色被 floor_snap 吸在地面上时，脚底与地面天然留出 ≤ snap 长度的缝
	# （实测 0.038~0.083m），写死 0.08 就正好卡在抖动范围里，每 2 帧翻一次。
	# 现在这个带宽由 floor_snap_length 推导，换角色/换胶囊不会失效。
	_grounded = is_on_floor() or gap < _ground_gap_band

	# 穿模安全网：只在穿透超过 0.8m（物理碰撞本该拦住的事故）时强制抬回。
	if gap < -0.8:
		global_position = p + up * (-gap)
		var vr: float = velocity.dot(up)
		if vr < 0.0:
			velocity -= up * vr

	# M46：外域掉进虚空 → 拉回起始大陆地表（面 0 的出生点附近）
	if not _planet_has_ocean and r < Planet.RADIUS + Planet.SEA_LEVEL - 6.0:
		var home: Vector3 = Planet.plane_to_surface(0.0, -130.0)
		global_position = home + Planet.up_at(home) * 2.0
		velocity = Vector3.ZERO
		_planet_zero_vertical()
		return

	# 根节点 basis 对齐球面：只有 authority 改，避免与同步写入互相打架。
	#
	# 【M53 事故修复】这里原来**每帧无条件**写 global_transform。
	# 实测后果：走路时物理服务器把角色当成"瞬移"，is_on_floor() 在相邻物理帧
	# 之间 true/false 反复翻转（120 帧翻 58 次，静止 40 帧翻 0 次）。
	# 连锁反应：
	#   _grounded 抖 → _apply_gravity 间歇生效（人一顿一顿）
	#   _was_airborne 每帧被置位 → 每帧生成一个落地粒子 → 身后拖出橙色烟雾带
	#   User: "角色移动仍旧不对，有重影"。
	# 修法：朝向变化小于视觉可辨角度时合并写入，物理体不再被无意义地重设。
	if is_multiplayer_authority():
		var target := Planet.align_basis(up, _fwd)
		if _aligned.x.length_squared() < 0.5 \
				or _aligned.y.angle_to(target.y) > ALIGN_WRITE_MIN_ANGLE \
				or _aligned.z.angle_to(target.z) > ALIGN_WRITE_MIN_ANGLE:
			var t2 := global_transform
			t2.basis = target
			global_transform = t2
			_aligned = target


func _planet_jump(v: float) -> void:
	var vr: float = velocity.dot(_up)
	velocity += _up * (v - vr)


## 【M47 根治】自适应地面半径 —— 不再"猜"地面在哪，而是问物理世界。
##
## 用户批评：「你不应该测量，而是设定计算，自动适应」。旧的 `mesh_height()`
## 只知道**地形网格**，不知道广场地台 / 台阶 / 建筑地板 / 载具甲板。站在广场上
## 时人被告知"地面在地形高度"，于是每帧被往下吸、又被地台碰撞推回来 ——
## 水平位移被碰撞吃光，表现就是"按 W 原地踏步"。
##
## 现在只保留一条规则：**脚下有什么碰撞面，就以什么面为准**；一个都打不到，
## 才退回地形网格。从此新增任何可站立物都不需要再改这里的代码。
func _ground_radius_at(p: Vector3, up: Vector3) -> float:
	var base: float = Planet.RADIUS + Planet.mesh_height(up)
	var space := get_world_3d().direct_space_state
	if space == null:
		return base
	# 起点取玩家头顶上方 1m、终点脚下 3m：
	#   · 站在地台上 → 打得到地台，用地台面
	#   · 站在野外   → 地形无碰撞，打空，用 mesh_height
	#   · 站在平台下方 → 起点仍在平台下方，不会误吸上去
	var from: Vector3 = p + up * 1.0
	var to: Vector3 = p - up * 3.0
	if not (is_finite(from.x) and is_finite(from.y) and is_finite(from.z)):
		return base
	if not (is_finite(to.x) and is_finite(to.y) and is_finite(to.z)):
		return base
	var q := PhysicsRayQueryParameters3D.create(from, to)
	# 【M53 事故修复】这里原来写死 collision_mask = 2（layer "world"）。
	# 但广场地板 KaykitArena/Floormap 是 GridMap，碰撞落在 layer 1（"world_decor"），
	# 于是射线**永远看不见脚下真正踩的那块板**，只能返回地形网格高度：
	#   gap 恒为 0.316m → gap < 0.08 恒不成立 → _grounded 100% 依赖 is_on_floor()，
	#   而 is_on_floor() 在 floor_snap 边缘来回翻（实测 120 帧翻 58 次）→
	#   每帧生成一个落地粒子 → 身后拖出橙色烟雾带（用户说的"重影"）。
	# 现在直接用角色自己的碰撞掩码（"我能站在什么上面"就是它），只摘掉 actor 层
	# 免得探到别的玩家/bot —— 判据唯一，不再有第二套层集合。
	q.collision_mask = collision_mask & ~ACTOR_LAYER
	q.collide_with_areas = false
	q.hit_from_inside = false
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return base
	var hp: Vector3 = hit["position"]
	if not (is_finite(hp.x) and is_finite(hp.y) and is_finite(hp.z)):
		return base
	return maxf(base, hp.length())


## 清掉切平面内的水平速度，**保留**沿当地法线的垂直分量（死亡/攻击/冻结用：
## 人要停住，但该往下掉还得往下掉）。
func _planet_zero_horizontal() -> void:
	velocity = _up * velocity.dot(_up)


## 清掉沿当地法线的垂直分量，**保留**切平面内水平速度（沉地拉回后吃掉下落速度用）。
func _planet_zero_vertical() -> void:
	velocity -= _up * velocity.dot(_up)


func _apply_gravity(delta: float) -> void:
	# 【M53 事故修复】这里原来 `if _grounded: return` —— 站在地上就完全不施重力。
	# 但球面地面是**碰撞体**，接触状态由 move_and_slide 维护：
	# 不施重力 → 角色没有向下位移 → 引擎判定"没碰到地板" → is_on_floor() 变假
	# → 下一帧又施重力 → 又接触 …… 自激振荡（实测走 120 帧翻 58 次）。
	# 现在重力恒施加，落地的下压由 move_and_slide 与地面碰撞自然抵消，
	# 接触状态每帧都被真实维护，这就是 CharacterBody3D 的标准用法。
	# M45：重力沿当地法线反向（球背面的"下"指向球心）
	var vr: float = velocity.dot(_up)
	var gravity_multiplier: float = FALL_GRAVITY_MULTIPLIER if vr < 0.0 else 1.0
	velocity -= _up * gravity * gravity_multiplier * delta


## M9：空手判定——武器栏为空即空手。
## 仅 owner（含 host 玩家）会走到这里：动画请求由 owner 发起，
## 远程端只照播广播状态，无需背包数据。
func _is_unarmed() -> bool:
	if player_inventory == null:
		return false
	return player_inventory.equipped_weapon.item_id.is_empty()


## M9：普攻动画映射——空手时播 Strike（M16：Universal 库 Punch_Jab 骨骼重定向的
## 真拳击动作）；有武器保持 Attack1 挥剑；Kick 等其他攻击动画原样透传。
func _play_attack_animation(base_state: StringName) -> void:
	# M16d：动作分配——普攻（basic_attack）播 SwordSlash 挥剑，空手映射 Strike 直拳；
	# 技能显式指定的动画原样透传（w_whirlwind/w_execute 用 Attack1 转圈旋风斩、
	# heavy_strike 用 Kick 踢腿），保证多种攻击动作并存。
	# 挥击时在手部高度播一撮尘光。
	if base_state == &"SwordSlash" and _is_unarmed():
		_request_animation(&"Strike", true)
		_local_sfx(&"swing")
	elif base_state == &"Kick":
		_request_animation(base_state, true, ATTACK_ANIM_SPEED)
		_local_sfx(&"heavy_punch")
	else:
		_request_animation(base_state, true, ATTACK_ANIM_SPEED)
		# M18b-6：步兵人形的挥剑声由动画轨道触发 AttackAudio（fire-slash，原版唯一声源），
		# 代码不再叠加 swing，保持与 roguelite 原版一致
		if not (_body is Body and _body.use_alt_body):
			_local_sfx(&"swing")
	# 挥击尘光：模型正面（body 局部 +Z，见 4.2 朝向约定）前方约 1 米、胸口高度
	# （纯表现，各端独立触发）
	var forward: Vector3 = _body.global_transform.basis.z
	SfxManager.spawn_effect("res://scenes/vfx/swing_dust.tscn", global_position + forward * 1.0 + Vector3.UP * 1.0)


func _start_attack() -> void:
	if is_attacking or is_collecting or not _grounded:
		return
	is_attacking = true
	_planet_zero_horizontal()
	# M16d：无目标空挥与 basic_attack 对齐——播 SwordSlash（空手自动映射
	# Strike 直拳）。此前硬编码 Attack1（转圈旋风斩），导致没对准目标时
	# 左键全是转圈圈。转圈圈只属于 w_whirlwind/w_execute 技能。
	_play_attack_animation(&"SwordSlash")


func _on_animation_finished(animation_name: StringName) -> void:
	match animation_name:
		&"Attack1":
			is_attacking = false
		&"Kick":
			is_attacking = false
		&"Strike":
			# M16：重定向拳击动画播完复位攻击锁
			is_attacking = false
		&"SwordSlash":
			# M16b：重定向挥剑动画（替换 Attack1 旋风斩）播完复位攻击锁
			is_attacking = false
		&"Pickup":
			# M9：Pickup 身兼两职——拾取（1.0x）与空手打击（>1.0x）。
			# 两个标志本就互斥，统一复位无害且无需区分来源。
			is_collecting = false
			is_attacking = false
		&"Emote2":
			is_collecting = false
		_:
			return
	# M16c 修复：攻击期间移动动画请求被锁拦截（return 在去重更新之前），
	# _last_requested_animation 仍停留在攻击前的 Run/Idle——播完后走路请求
	# Run 会被 439 行去重 return 拦下，模型永远定格在攻击末帧（实测"一直低头"）。
	# 清空去重缓存，让下一帧的移动/待机请求必然通过。
	_last_requested_animation = &""


## 攻击类动画播放期间（is_attacking）禁止 Idle/Run/Sprint 覆盖，
## 否则下一帧的移动动画请求会把 1.2s 的攻击动作秒切走；
## Jump/Fall 系列允许打断攻击动画（WoW 手感：打人可以跳）
## M9：speed > 1.0 的 Pickup 是"空手打击"（拾取固定 1.0），同样享受攻击锁
func _request_animation(state: StringName, restart: bool = false, speed: float = 1.0) -> void:
	if not ALLOWED_ANIMATION_STATES.has(state):
		return
	var is_attack_anim := (
		state == &"Attack1"
		or state == &"Kick"
		or state == &"Strike"
		or state == &"SwordSlash"
		or (state == &"Pickup" and speed > 1.0)
	)
	if is_attacking and not is_attack_anim \
			and state != &"Jump" and state != &"Jump2" and state != &"Fall":
		return
	# M18b-3：格挡期间移动/待机请求不覆盖 Block 姿态（可跳跃/受击/冲刺打断）
	if is_blocking and not is_attack_anim \
			and state != &"Block" and state != &"Jump" and state != &"Jump2" \
			and state != &"Fall" and state != &"Dodge":
		return
	if not restart and _last_requested_animation == state:
		return
	_last_requested_animation = state
	is_attacking = is_attack_anim
	_body.play_animation_state(state, restart, speed)
	if multiplayer.is_server():
		request_animation_state(state, speed)
	else:
		request_animation_state.rpc_id(1, state, speed)


@rpc("any_peer", "call_local", "reliable")
func request_animation_state(state: StringName, speed: float = 1.0) -> void:
	if not multiplayer.is_server() or not _is_owner_request():
		return
	if not ALLOWED_ANIMATION_STATES.has(state):
		return
	if not _server_consume_animation_request_token():
		return
	# M14 修复：拾取动画 M9 起从 Emote2 改名 Pickup（拾取型恒 1.0x，打击型 2.5x），
	# 此处必须同步，否则时间戳永不设置、E 键拾取必然失败。打击型不算拾取。
	if state == &"Pickup" and speed <= 1.0:
		if not _is_grounded_on_server() or not _has_collectible_item_in_front():
			return
		_server_pickup_animation_started_msec = Time.get_ticks_msec()
	else:
		_server_pickup_animation_started_msec = -1
	_server_publish_animation(state, speed)


func _server_consume_animation_request_token() -> bool:
	var now := Time.get_ticks_msec()
	if _last_server_animation_token_update_msec == 0:
		_last_server_animation_token_update_msec = now
	else:
		var elapsed_seconds := (now - _last_server_animation_token_update_msec) / 1000.0
		_server_animation_request_tokens = minf(
			SERVER_ANIMATION_REQUEST_BURST,
			_server_animation_request_tokens + elapsed_seconds * SERVER_ANIMATION_REQUESTS_PER_SECOND
		)
		_last_server_animation_token_update_msec = now

	if _server_animation_request_tokens < 1.0:
		return false
	_server_animation_request_tokens -= 1.0
	return true


func _server_publish_animation(state: StringName, speed: float = 1.0) -> void:
	if not multiplayer.is_server():
		return
	_animation_sequence += 1
	sync_animation_state(state, _animation_sequence, speed)
	# M26：bot（9001+）已通过 BotMultiplayerSpawner 同步到客户端，动画照常广播；
	# rpc 寻的按发送方节点路径解析，客户端有对应节点即可播放。
	for pid in multiplayer.get_peers():
		sync_animation_state.rpc_id(pid, state, _animation_sequence, speed)


@rpc("any_peer", "call_local", "reliable")
func sync_animation_state(state: StringName, sequence: int, speed: float = 1.0) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	if sequence <= _last_applied_animation_sequence:
		return
	_last_applied_animation_sequence = sequence

	if not ALLOWED_ANIMATION_STATES.has(state):
		return

	# The owner already played the input-driven state immediately.
	if is_multiplayer_authority():
		return
	# 远程玩家的攻击动画同样需要锁，防止其本地移动动画请求秒切
	# M9：speed > 1.0 的 Pickup 是空手打击（拾取固定 1.0），同样上锁
	var is_strike := state == &"Attack1" or state == &"Kick" or state == &"Strike" or state == &"SwordSlash" or (state == &"Pickup" and speed > 1.0)
	if is_strike:
		is_attacking = true
		# M11：远程玩家挥击音（3D 空间音，各端独立触发）
		# M18b-6：步兵人形 SwordSlash 由动画轨道 fire-slash 发声，代码不再叠加
		if state == &"Kick":
			SfxManager.play_3d(&"heavy_punch", global_position)
		elif not (_body is Body and _body.use_alt_body and state == &"SwordSlash"):
			SfxManager.play_3d(&"swing", global_position)
	# M13：远程玩家移动状态驱动脚步声（Run/Sprint 算移动中）
	_remote_moving = state == &"Run" or state == &"Sprint"
	# M18b-5：远程玩家冲刺音（3D 空间音，各端独立触发）
	if state == &"Dodge":
		SfxManager.play_3d(&"dash", global_position)
	_body.play_animation_state(state, true, speed)


func _push_collided_items() -> void:
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		if c.get_collider() is RigidBody3D:
			apply_force_to_server_object.rpc_id(1, c.get_collider().name, -c.get_normal())


func _process(_delta):
	if not multiplayer.has_multiplayer_peer():
		return
	if not is_multiplayer_authority():
		return
	# ===== M39：鼠标左右键同时按住 = 自动前进（WoW 鼠标前进）=====
	# 按住式：两键同时按下 → 自动前进；任一键松开 → 立即停。
	# 在 _process 里轮询（而不是 _unhandled_input）——松开事件可能被
	# spring_arm_offset（右键转视角）先消费掉，用事件跟踪会漏掉松开。
	AutoRun.set_mouse_hold(_both_mouse_held())
	var first_person := _spring_arm_offset != null and _spring_arm_offset.is_first_person
	if first_person:
		_align_pickup_area_with_camera()
	var camera_input_blocked := false
	var current_scene := get_tree().get_current_scene()
	if current_scene and current_scene.has_method("is_camera_input_blocked"):
		camera_input_blocked = current_scene.is_camera_input_blocked()
	_first_person_hud.visible = (
		first_person and not camera_input_blocked and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	)
	_check_out_of_bounds()


func _freeze():
	_planet_zero_horizontal()
	_current_speed = 0
	_request_animation(&"Idle")


func _move() -> void:
	var input_direction: Vector2 = Vector2.ZERO
	if is_multiplayer_authority():
		input_direction = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		# ===== M39：自动行走（WoW Auto-Run）=====
		# 语义 = 持续按住 W（用户要求"和 W 键一样的作用"）。
		# Vector2(0, -1) 就是 get_vector("move_forward") 的值（y = backward - forward），
		# 与按住 W 完全同一条代码路径（含相机相对旋转与身体朝向跟随）。
		# 任意移动键按下会由 _unhandled_input 调 AutoRun.stop() 取消。
		if _auto_run_active():
			input_direction = Vector2(0.0, -1.0)

	var up := _up
	# 根节点 basis 已在 _planet_frame_step 里对齐当地切平面，所以 basis * (x,0,z)
	# 得到的就是切平面方向。
	var direction: Vector3 = transform.basis * Vector3(input_direction.x, 0, input_direction.y).normalized()

	_is_running()
	# M18b-2：盾墙格挡移速减半
	if is_blocking:
		_current_speed *= BLOCK_SPEED_FACTOR
	# 相机偏航绕**当地法线**（绕世界 Y 在球面上会把方向拧到地下去）
	direction = direction.rotated(up, _spring_arm_offset.rotation.y)
	direction -= up * direction.dot(up)

	# 【M47 事故修复 · 必读】速度必须按**当地切平面**拆，不能按世界 XZ。
	#
	# 旧代码只写 velocity.x / velocity.z（世界轴），而角色站的面 0 法线是 +X：
	# 他的"前后左右"落在世界 YZ 平面上，于是**水平速度里那个 Y 分量从头到尾
	# 没人写过、也没人清过**。一旦沾上一点（上坡打滑、被撞、落地冲击），
	# 它就永远留着 —— 用户原话"角色一直在像被风吹一样"就是它。
	# 而且 move_toward 把世界 x 拉向 0，对角色来说是"往上/往下"，
	# 刹车方向完全是错的。
	var vr: float = velocity.dot(up)          # 垂直当地地面
	var vh: Vector3 = velocity - up * vr       # 切平面内

	if direction.length_squared() > 0.0001:
		velocity = direction.normalized() * _current_speed + up * vr
		_body.apply_rotation(velocity)
		return

	# 无输入：在切平面内刹车（这才是球面世界里的"地面摩擦"）
	# 地形没有碰撞体 → is_on_floor() 恒 false → 物理引擎不给任何摩擦，
	# 必须自己收。系数 deliberately 很大：约 3 帧（0.05s）内归零，
	# 视觉上"松手就停"，但又不是硬切成 0（避免看起来像掉帧）。
	vh = vh.move_toward(Vector3.ZERO, _current_speed * 20.0 * get_physics_process_delta_time())
	velocity = vh + up * vr


func _is_running() -> bool:
	if Input.is_action_pressed("shift"):
		_current_speed = SPRINT_SPEED
		return true
	_current_speed = NORMAL_SPEED
	return false


## ===== M39：自动行走 / 自动飞行（WoW Auto-Run）=====
## 状态由 AutoRun 单例持有（autoload 名 AutoRun）：
##   · 小键盘 +（toggle_autorun 动作）→ 切换式开关
##   · 鼠标左右键同时按住          → 按住式（WoW 鼠标前进）
##   · 任意移动键按下              → AutoRun.stop() 全部取消
func _auto_run_active() -> bool:
	return AutoRun.is_active()


## 鼠标左右键是否同时按住（WoW 鼠标前进的判定）
func _both_mouse_held() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


## M39：是否是"移动类按键"按下（WASD / 空格 / C）——用于中断自动前进。
## 只看"按下"沿（pressed），长按不重复触发。
func _is_movement_key_pressed(event: InputEvent) -> bool:
	for action in ["move_forward", "move_backward", "move_left", "move_right", "jump", "crouch"]:
		if event.is_action_pressed(action):
			return true
	return false


func _check_out_of_bounds():
	# 【M47 事故修复 · 必读】不能用 y < -15 这种平面判据。
	# 球面上站在 -X / -Y / -Z 面的玩家，世界 y 天然是 -2000 级别，
	# 旧判据会把整个下半球都判定为"掉出地图"，每帧传送回 _spawn_point=(0,5,0)
	# ——也就是**球心**。用户 2026-10-22 看到"角色没站在地上、四周像恐怖游戏"
	# 就是这个：角色其实一直悬在星球中心，相机从球心往外看。
	# 正确的"掉出去"= 径向距离低于海底/虚空底（球面向内坠落）。
	if global_position.length() < Planet.RADIUS + Planet.SEA_LEVEL - 20.0:
		_reset_position_after_fall()


func _reset_position_after_fall():
	# 兜底位置也要按球面算，不能再用平面世界的 _spawn_point 常量
	var safe := Planet.plane_to_surface(0.0, -130.0)
	_spawn_point = safe + Planet.up_at(safe) * 2.0
	global_transform.origin = _spawn_point
	velocity = Vector3.ZERO


func _get_texture_from_name(color: SkinColor) -> CompressedTexture2D:
	match color:
		SkinColor.BLUE:
			return blue_texture
		SkinColor.GREEN:
			return green_texture
		SkinColor.RED:
			return red_texture
		SkinColor.YELLOW:
			return yellow_texture
		_:
			return blue_texture


## M27 条款 V4：皮肤必须覆盖全部身体视觉，一个都不能漏——
## 旧版只改 GodotRobot 的 4 个 mesh，步兵（KayKit Mannequin）换模型后
## 皮肤静默丢失（事故 C："模型对但没颜色"）。
func set_player_skin(skin_name: SkinColor) -> void:
	var texture = _get_texture_from_name(skin_name)

	_set_mesh_texture(_bottom_mesh, texture)
	_set_mesh_texture(_chest_mesh, texture)
	_set_mesh_texture(_face_mesh, texture)
	_set_mesh_texture(_limbs_head_mesh, texture)
	# M27：KayKit Mannequin（alt_visual）主 SkinnedMesh3D（身体）染色。
	# 武器挂件（LazerSword/Handle 等 MeshInstance3D）不染——
	# surface_override 优先级高于 material_override，无差别递归会把剑也换色。
	_apply_skin_to_alt_visual(texture)


## M27 条款 V4：在 alt_visual 子树找主 SkinnedMesh3D（身体）换 albedo 贴图。
## Mannequin 为 glb 实例，内部网格结构不写死——按类型+角色判定。
## 注意：alt_visual 是 Body 脚本的 export 引用，子节点真名是 InfantryVisual
## （player.tscn 写死），直接按名取最稳（export 引用在节点就绪前为 null）。
func _apply_skin_to_alt_visual(texture: CompressedTexture2D) -> void:
	if _body == null or texture == null:
		return
	var alt_visual := _body.get_node_or_null("InfantryVisual") as Node
	if alt_visual == null:
		return
	var stack: Array[Node] = [alt_visual]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		# 类名判定而非 `is SkinnedMesh3D`——部分构建对该全局类型名解析不稳定
		# （实测 Parse Error: Could not find type "SkinnedMesh3D"）。
		if node is GeometryInstance3D and str(node.get_class()) == "SkinnedMesh3D" \
				and not (node.name in WEAPON_VISUAL_NAMES):
			var skin_mesh := node as GeometryInstance3D
			for surface in skin_mesh.get_surface_count():
				var new_material := StandardMaterial3D.new()
				new_material.albedo_texture = texture
				skin_mesh.set_surface_override_material(surface, new_material)
			return # 主身体只有一个 SkinnedMesh3D，命中即收工
		for child in node.get_children():
			stack.append(child)


## M27：武器/挂件视觉名——皮肤染色需要跳过（不随职业皮肤变色）
const WEAPON_VISUAL_NAMES: Array[StringName] = [&"LazerSword", &"Handle", &"SlashVFX"]


func _set_mesh_texture(mesh_instance: MeshInstance3D, texture: CompressedTexture2D) -> void:
	if mesh_instance:
		var new_material := StandardMaterial3D.new()
		new_material.albedo_texture = texture
		mesh_instance.set_surface_override_material(0, new_material)


@rpc("any_peer", "call_local", "reliable")
func sync_inventory_to_owner(inventory_data: Dictionary):
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return

	if not is_multiplayer_authority():
		return

	if not player_inventory:
		player_inventory = PlayerInventory.new()
	player_inventory.from_dict(inventory_data)
	_recalculate_equipment_bonus()

	var level_scene = get_tree().get_current_scene()
	if (
		level_scene
		and get_multiplayer_authority() == multiplayer.get_unique_id()
		and level_scene.has_method("update_local_inventory_display")
	):
		level_scene.update_local_inventory_display()


@rpc("any_peer", "call_local", "reliable")
func request_move_item(from_slot: int, to_slot: int, quantity: int = -1):
	if not multiplayer.is_server():
		return

	var requesting_client = multiplayer.get_remote_sender_id()
	if not _is_owner_request():
		push_warning(
			(
				"Client "
				+ str(requesting_client)
				+ " tried to modify inventory for player "
				+ str(get_multiplayer_authority())
			)
		)
		return

	if not player_inventory:
		return

	if not player_inventory.is_slot_active(from_slot) or not player_inventory.is_slot_active(to_slot):
		push_warning("Invalid slot indices: from=" + str(from_slot) + " to=" + str(to_slot))
		return

	if quantity != -1 and quantity <= 0:
		push_warning("Invalid move quantity: " + str(quantity))
		return

	var success = false
	if quantity == -1:
		success = player_inventory.move_item(from_slot, to_slot)
		if not success:
			success = player_inventory.swap_items(from_slot, to_slot)
	else:
		success = player_inventory.move_item(from_slot, to_slot, quantity)

	if success:
		_sync_inventory_to_owner()


@rpc("any_peer", "call_local", "reliable")
func request_add_item(item_id: String, quantity: int = 1):
	if not multiplayer.is_server():
		return

	var requesting_client = multiplayer.get_remote_sender_id()
	var is_local_server_call = requesting_client == 0 and multiplayer.get_unique_id() == 1
	if requesting_client != 1 and not is_local_server_call:
		push_warning(
			"Client " + str(requesting_client) + " tried to add items to player " + str(get_multiplayer_authority())
		)
		return

	if not player_inventory:
		return

	if quantity <= 0:
		push_warning("Invalid quantity: " + str(quantity))
		return

	var item = ItemDatabase.get_item(item_id)
	if not item:
		push_warning("Item not found: " + item_id)
		return

	var remaining = player_inventory.add_item(item, quantity)
	var added = quantity - remaining

	if added > 0:
		_sync_inventory_to_owner()


func request_add_single_item(item_id: String) -> bool:
	if not multiplayer.is_server():
		return false

	if player_inventory == null:
		return false

	var item = ItemDatabase.get_item(item_id)
	if not item:
		push_warning("Item not found: " + item_id)
		return false

	var remaining = player_inventory.add_item(item, 1)

	if remaining == 0:
		_sync_inventory_to_owner()
		return true
	return false


@rpc("any_peer", "call_local", "reliable")
func request_remove_item(item_id: String, quantity: int = 1):
	if not multiplayer.is_server():
		return

	var requesting_client = multiplayer.get_remote_sender_id()
	if not _is_owner_request():
		push_warning(
			(
				"Client "
				+ str(requesting_client)
				+ " tried to remove items from player "
				+ str(get_multiplayer_authority())
			)
		)
		return

	if not player_inventory:
		return

	if quantity <= 0:
		push_warning("Invalid quantity: " + str(quantity))
		return

	var removed = player_inventory.remove_item(item_id, quantity)

	if removed > 0:
		_sync_inventory_to_owner()


@rpc("authority", "call_local", "reliable")
func add_world_item(scene_path: String, player_position: Vector3) -> void:
	var item_container = get_node_or_null("/root/Level/Environment/ItemContainer")
	if not item_container:
		push_warning("ItemContainer not found at /root/Level/Environment/ItemContainer")
		return
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_warning("Cannot add world item: invalid scene path '" + scene_path + "'")
		return
	var packed_scene = load(scene_path) as PackedScene
	if not packed_scene:
		push_warning("Cannot add world item: scene path is not a PackedScene '" + scene_path + "'")
		return
	var instance_item := packed_scene.instantiate() as Node3D
	if not instance_item:
		push_warning("Cannot add world item: scene root is not a Node3D '" + scene_path + "'")
		return
	item_container.add_child(instance_item, true)
	instance_item.global_position = player_position


func get_inventory() -> PlayerInventory:
	return player_inventory


func _sync_inventory_to_owner() -> void:
	if not multiplayer.is_server() or not player_inventory:
		return
	var owner_id = get_multiplayer_authority()
	if owner_id == 1:
		sync_inventory_to_owner(player_inventory.to_dict())
	elif multiplayer.get_peers().has(owner_id):
		sync_inventory_to_owner.rpc_id(owner_id, player_inventory.to_dict())
	# M20-Bot：虚拟 authority（bot，未连接 peer）背包由服务器本地管理，无需同步


@rpc("any_peer", "call_local", "reliable")
func request_equip_item(from_slot: int, item_type: Item.ItemType) -> void:
	if not multiplayer.is_server() or not _is_owner_request():
		return
	if not player_inventory or not player_inventory.is_slot_active(from_slot):
		return
	if item_type != Item.ItemType.WEAPON and item_type != Item.ItemType.HAT and item_type != Item.ItemType.BACKPACK:
		return
	if player_inventory.equip_from_slot(from_slot, item_type):
		_sync_inventory_to_owner()
		_sync_equipment_appearance()
		_recalculate_equipment_bonus()


@rpc("any_peer", "call_local", "reliable")
func request_unequip_item(item_type: Item.ItemType, destination_slot: int = -1) -> void:
	if not multiplayer.is_server() or not _is_owner_request():
		return
	if not player_inventory:
		return
	if item_type != Item.ItemType.WEAPON and item_type != Item.ItemType.HAT and item_type != Item.ItemType.BACKPACK:
		return
	if destination_slot < -1 or destination_slot >= PlayerInventory.MAX_INVENTORY_SIZE:
		return
	if destination_slot >= 0 and not player_inventory.is_slot_active(destination_slot):
		return
	if player_inventory.unequip_to_slot(item_type, destination_slot):
		_sync_inventory_to_owner()
		_sync_equipment_appearance()
		_recalculate_equipment_bonus()


func _is_owner_request() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	return sender == get_multiplayer_authority() or (sender == 0 and multiplayer.is_server())


func _sync_equipment_appearance() -> void:
	if not multiplayer.is_server() or not player_inventory:
		return
	var weapon_id := player_inventory.equipped_weapon.item_id
	var hat_id := player_inventory.equipped_hat.item_id
	var backpack_id := player_inventory.equipped_backpack.item_id
	var nickname_height := _calculate_nickname_height(hat_id)
	_broadcast_nickname_height(nickname_height)
	sync_equipment_appearance.rpc(weapon_id, hat_id, backpack_id)
	sync_equipment_appearance(weapon_id, hat_id, backpack_id)


func _request_equipment_appearance() -> void:
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		return
	request_equipment_appearance.rpc_id(1)


@rpc("any_peer", "reliable")
func request_equipment_appearance() -> void:
	if not multiplayer.is_server() or not player_inventory:
		return
	var requester_id := multiplayer.get_remote_sender_id()
	if requester_id <= 0:
		return
	if _appearance_sync_requesters.has(requester_id):
		return
	_appearance_sync_requesters[requester_id] = true
	_sync_equipment_appearance_to_peer(requester_id)


func _sync_equipment_appearance_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or not player_inventory or peer_id <= 0:
		return
	var weapon_id := player_inventory.equipped_weapon.item_id
	var hat_id := player_inventory.equipped_hat.item_id
	var backpack_id := player_inventory.equipped_backpack.item_id
	sync_equipment_appearance.rpc_id(peer_id, weapon_id, hat_id, backpack_id)


@rpc("any_peer", "reliable")
func sync_equipment_appearance(weapon_id: String, hat_id: String, backpack_id: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 1 and not (sender == 0 and multiplayer.is_server()):
		return
	_set_equipment_visibility(weapon_id, hat_id, backpack_id)


func _set_equipment_visibility(weapon_id: String, hat_id: String, backpack_id: String) -> void:
	_equipped_hat_visual_id = hat_id
	# M11：武器变化时播装备音（对比上次值，进服首次初始化不播）；
	# 本地玩家 2D 音，远程玩家 3D 空间音
	var weapon_changed: bool = weapon_id != _equipped_weapon_visual_id and _equipped_weapon_visual_id != ""
	_set_equipment_nodes_visibility(HEAD_EQUIPMENT_PATH, HAT_NODES_BY_ITEM, hat_id)
	_set_equipment_nodes_visibility(HAND_EQUIPMENT_PATH, WEAPON_NODES_BY_ITEM, weapon_id)
	_set_equipment_nodes_visibility(BACK_EQUIPMENT_PATH, BACKPACK_NODES_BY_ITEM, backpack_id)
	if weapon_changed:
		if is_multiplayer_authority():
			SfxManager.play(&"equip")
		else:
			SfxManager.play_3d(&"equip", global_position)
	_equipped_weapon_visual_id = weapon_id
	# M9：空手武器 fallback——武器栏为空时左手自动拿鸡腿（纯外观）；
	# 装备任何武器后隐藏。visible 经 MultiplayerSynchronizer 全服同步。
	var chicken_leg := get_node_or_null(HAND_EQUIPMENT_PATH + "ChickenLeg") as Node3D
	if chicken_leg:
		chicken_leg.visible = weapon_id.is_empty()


func _broadcast_nickname_height(height: float) -> void:
	if not multiplayer.is_server():
		return
	var level_scene := get_tree().get_current_scene()
	if level_scene and level_scene.has_method("register_player_nickname_height"):
		level_scene.register_player_nickname_height(get_multiplayer_authority(), height)


func _set_equipment_nodes_visibility(parent_path: String, nodes_by_item: Dictionary, equipped_item_id: String) -> void:
	for item_id in nodes_by_item:
		var equipment := get_node_or_null(parent_path + str(nodes_by_item[item_id])) as Node3D
		if equipment:
			equipment.visible = item_id == equipped_item_id


func _update_nickname_height(hat_id: String = "") -> void:
	if not nickname:
		return
	nickname.visible = not _is_local_first_person()
	_set_nickname_height(_calculate_nickname_height(hat_id))


func _calculate_nickname_height(hat_id: String) -> float:
	var target_height := BASE_NICKNAME_HEIGHT
	var equipped_hat := _get_hat_node(hat_id)
	if equipped_hat:
		var hat_top := _get_visual_top(equipped_hat)
		if hat_top > -INF and hat_top < INF:
			target_height = max(BASE_NICKNAME_HEIGHT, hat_top + nickname_clearance)
	return target_height


func _set_nickname_height(height: float) -> void:
	var nickname_position := nickname.position
	nickname_position.y = height
	nickname.position = nickname_position


func apply_synced_nickname_height(height: float) -> void:
	if not nickname:
		return
	nickname.visible = not _is_local_first_person()
	if height > -INF and height < INF:
		_set_nickname_height(maxf(BASE_NICKNAME_HEIGHT, height))
	else:
		_set_nickname_height(BASE_NICKNAME_HEIGHT)


func _is_local_first_person() -> bool:
	return is_multiplayer_authority() and _spring_arm_offset != null and _spring_arm_offset.is_first_person


func get_current_nickname_height() -> float:
	return nickname.position.y if nickname else BASE_NICKNAME_HEIGHT


func _get_hat_node(hat_id: String) -> Node3D:
	if HAT_NODES_BY_ITEM.has(hat_id):
		var requested_hat_path := HEAD_EQUIPMENT_PATH + str(HAT_NODES_BY_ITEM[hat_id])
		var requested_hat := get_node_or_null(requested_hat_path) as Node3D
		if requested_hat:
			return requested_hat
	return null


func _get_visual_top(root: Node3D) -> float:
	var visual_top := -INF
	if root is MeshInstance3D:
		visual_top = _get_mesh_top(root as MeshInstance3D)

	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance:
			visual_top = max(visual_top, _get_mesh_top(mesh_instance))
	return visual_top


func _get_mesh_top(mesh_instance: MeshInstance3D) -> float:
	var visual_top := -INF
	var mesh_bounds := mesh_instance.get_aabb()
	for endpoint_index in range(8):
		var endpoint_global := mesh_instance.to_global(mesh_bounds.get_endpoint(endpoint_index))
		visual_top = max(visual_top, to_local(endpoint_global).y)
	return visual_top


func _add_starting_items():
	if not player_inventory:
		return

	var backpack := ItemDatabase.get_item("backpack")
	if backpack:
		player_inventory.add_item(backpack, 1)

	var starting_item_ids: Array[String] = [
		"fedora",
		"headphones",
		"pirate_hat",
		"sheriff_hat",
		"sombrero",
		"wizard_hat",
		"sword",
		"sword_big",
		"axe",
		"chicken_leg",
		"bone",
		"chalice",
		# M3 新手装备与补给：铁剑+皮帽直接穿上，面包/清水各 3 个
		"sword_iron",
		"cap",
		"bread",
		"water",
	]

	for item_id in starting_item_ids:
		var item = ItemDatabase.get_item(item_id)
		if item:
			player_inventory.add_item(item, 1)
	# 新手装备自动穿上，开局就能感受到属性加成
	player_inventory.equip_from_slot(player_inventory.get_slot_index_of("sword_iron"), Item.ItemType.WEAPON)
	player_inventory.equip_from_slot(player_inventory.get_slot_index_of("cap"), Item.ItemType.HAT)
	player_inventory.add_item(ItemDatabase.get_item("bread"), 2)
	player_inventory.add_item(ItemDatabase.get_item("water"), 2)


func pickup() -> void:
	if multiplayer.is_server():
		request_pickup()
	else:
		request_pickup.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_pickup() -> void:
	if not multiplayer.is_server() or not _is_owner_request():
		return
	var now := Time.get_ticks_msec()
	if now - _last_server_pickup_request_msec < PICKUP_REQUEST_COOLDOWN_MSEC:
		return
	_last_server_pickup_request_msec = now

	var animation_elapsed := now - _server_pickup_animation_started_msec
	if (
		_server_pickup_animation_started_msec < 0
		or animation_elapsed < PICKUP_ANIMATION_DELAY_MSEC
		or animation_elapsed > PICKUP_ANIMATION_WINDOW_MSEC
	):
		return
	if not _is_grounded_on_server():
		return
	if not _has_collectible_item_in_front():
		return
	_server_pickup_animation_started_msec = -1
	_server_pickup()


func _server_pickup() -> void:
	var world_drops := get_node_or_null("/root/Level/Environment/ItemContainer") as WorldDrops
	var level_scene := get_tree().current_scene
	for item in _get_collectible_items_in_front():
		var quantity: int = maxi(1, item.quantity)
		var db_item := ItemDatabase.get_item(item.item_id)
		if db_item == null or player_inventory == null:
			continue
		# 入包（数量感知，服务器本地权威路径）；一个都塞不下 = 满包
		var remaining := player_inventory.add_item(db_item, quantity)
		var added := quantity - remaining
		if added <= 0:
			if level_scene and level_scene.has_method("show_chat_message"):
				level_scene.show_chat_message.rpc(tr("系统"), tr("背包已满，无法拾取 %s") % tr(db_item.name))
			SfxManager.play(&"inventory_full")
			continue
		_sync_inventory_to_owner()
		# 通知所有端移除掉落物（服务器权威）
		if world_drops:
			world_drops.remove_drop(item)
		elif item.is_inside_tree():
			item.queue_free()
		# 播报
		var label := "[%s]%s" % [tr(db_item.get_rarity_name()), tr(db_item.name)]
		if added > 1:
			label += " x%d" % added
		if level_scene and level_scene.has_method("show_chat_message"):
			level_scene.show_chat_message.rpc(tr("系统"), tr("拾取了 ") + label)
		SfxManager.play_3d(&"pickup", global_position)


func _has_collectible_item_in_front() -> bool:
	return not _get_collectible_items_in_front().is_empty()


## M8：球形距离检测（WoW 式脚边拾取）。
## 原先用 InfrontArea3D 圆柱检测，但矮掉落物（鸡腿碰撞盒仅 0.19 米高）
## 躺在地面上完全在检测区（y 0.9~2.1）下方，根本捡不起来——
## 改用玩家周围 2.5 米球形范围，与碰撞盒高度无关。
const PICKUP_RANGE := 2.5


func _get_collectible_items_in_front() -> Array[ItemRigidBody3D]:
	var collectible_items: Array[ItemRigidBody3D] = []
	var container := get_node_or_null("/root/Level/Environment/ItemContainer")
	if container == null:
		return collectible_items
	for child in container.get_children():
		var item := child as ItemRigidBody3D
		if item and not item.item_id.is_empty() and ItemDatabase.get_item(item.item_id):
			if global_position.distance_to(item.global_position) <= PICKUP_RANGE:
				collectible_items.append(item)
	return collectible_items


@rpc("any_peer", "call_local", "reliable")
func apply_force_to_server_object(object_name: String, normal: Vector3) -> void:
	# M43 安全闸：本 RPC 原先完全裸奔（任何客户端可对 ItemContainer 内任意刚体施 100 倍力）。
	# 三道闸：① 仅服务器处理且必须来自该玩家的 authority；② 法线必须是有限值；
	# ③ 只接受"近单位向量"（客户端踢物传的是碰撞法线），并 normalize 后使用，
	#    防止客户端传 (1e9,1e9,1e9) 把掉落物轰到天外。
	if not multiplayer.is_server() or not _is_owner_request():
		return
	if not (is_finite(normal.x) and is_finite(normal.y) and is_finite(normal.z)):
		return
	var len_sq := normal.length_squared()
	if len_sq < 0.0001 or len_sq > 4.0:
		return
	if object_name.is_empty() or object_name.length() > 64:
		return
	var object_node = get_node_or_null("/root/Level/Environment/ItemContainer")
	if object_node:
		for n in object_node.get_children():
			if n.name == object_name and n is RigidBody3D:
				n.apply_force(normal.normalized() * 100)


func _is_grounded_on_server() -> bool:
	if not multiplayer.is_server() or not is_inside_tree():
		return false
	var query := PhysicsRayQueryParameters3D.new()
	query.from = global_position + Vector3.UP * 0.15
	query.to = global_position + Vector3.DOWN * 0.3
	query.collision_mask = 2
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# ===== MiniWoW 战斗系统实现 =====

func _enter_combat_ready() -> void:
	attribute_set.died.connect(_on_combat_died)
	attribute_set.hp_changed.connect(_on_attribute_hp_changed)
	attribute_set.hp_changed.connect(_on_hp_alert_check) # M11：低血/满血提示音（纯表现）
	attribute_set.mp_changed.connect(_on_attribute_mp_changed)
	# M19：WoW 相机信号——右键转身（步行转角色 / 骑乘转沙发）、滚轮缩放
	if _spring_arm_offset != null:
		_spring_arm_offset.character_turn_requested.connect(_on_camera_turn)
		_spring_arm_offset.zoom_requested.connect(_on_camera_zoom)
	attribute_set.stats_changed.connect(_on_attribute_stats_changed) # M5：装备/增益导致攻防变化
	# M14：开局默认战士（用户选定）——否则 2/3/4 技能槽因未选职业全部静默失效；
	# 职业训练师处仍可换。走 request_choose_class 正常链路（配属性+广播+绑技能栏）。
	# M18b-1 修复：默认打上 meta 标记——level._add_player 依据它仍弹出职业选择界面
	# （否则弹窗条件 is_empty 永远为假，玩家一辈子见不到选职业界面）。手动选职业后清除。
	if multiplayer.is_server() and player_class.is_empty():
		request_choose_class(DEFAULT_CLASS_ID)
		set_meta("auto_defaulted_class", true)
	# M19：伙伴改为任务获得——角色初始没有伙伴，
	# 完成任一任务后自动获得漂浮伙伴（见 sync_quest_state 的发放钩子）
	# M11：进服欢迎音——本地玩家战斗系统就绪即视为已进入世界（远程玩家不播）
	if is_multiplayer_authority():
		SfxManager.play(&"welcome")


## M15：生成 Plush 伙伴"小跟班"（设计文档 5.10）
func _spawn_partner() -> void:
	if get_tree().root.get_node_or_null("Level/Partner") != null:
		return # 已生成（重连/重生场景不重复刷）
	var scene := load("res://scenes/npcs/partner.tscn") as PackedScene
	if scene == null:
		return
	# 用 /root/Level 引用（与项目其余硬编码路径一致）；测试环境下
	# current_scene 是测试场景而非 level 实例，不能依赖 current_scene
	var level := get_tree().root.get_node_or_null("Level")
	if level == null:
		return
	var partner := scene.instantiate() as Node3D
	partner.name = "Partner"
	level.add_child(partner)
	partner.global_position = global_position + Vector3(1.2, 0.3, 1.2)
	partner.set("owner_player", self)


## M11：血量阈值提示音——只在本地玩家身上判断（别人的血量变化不吵我）。
## hp_changed 各端都会发（服务器结算 / 客户端应用权威值），故各端都能触发。
func _on_hp_alert_check(current: int, maximum: int) -> void:
	if not is_multiplayer_authority() or maximum <= 0 or not attribute_set.is_alive():
		return
	if current < maximum / 4:
		SfxManager.play_hp_alert(&"low_hp")
	elif current >= maximum:
		SfxManager.play_hp_alert(&"full_heal")


func _get_hud() -> HUD:
	return get_node_or_null("/root/Level/HUD") as HUD


## M3：根据已穿装备重算攻击/防御加成。
## 服务器在穿脱/同步时调用；客户端在 sync_inventory_to_owner 后也会走到这里，
## 两端各自本地计算，保证伤害预测与 HUD 显示一致。
func _recalculate_equipment_bonus() -> void:
	if player_inventory == null or attribute_set == null:
		return
	var bonus_atk := 0
	var bonus_def := 0
	for equipped_slot in [
		player_inventory.equipped_weapon,
		player_inventory.equipped_hat,
		player_inventory.equipped_backpack,
	]:
		if equipped_slot == null or equipped_slot.is_empty():
			continue
		var item := ItemDatabase.get_item(equipped_slot.item_id)
		if item:
			bonus_atk += item.bonus_atk
			bonus_def += item.bonus_def
	attribute_set.apply_equipment_bonus(bonus_atk, bonus_def)
	if is_multiplayer_authority():
		var hud := _get_hud()
		if hud:
			hud.set_player_stats(attribute_set.atk, attribute_set.def)


func _on_attribute_hp_changed(_current: int, _maximum: int) -> void:
	# _applying_authority_sync：正在应用服务器广播的权威值时不再回播，
	# 否则 sync_player_hp 的 call_local 会经 set_hp_from_authority → hp_changed 无限递归
	if _applying_authority_sync or not multiplayer.is_server():
		return
	sync_player_hp.rpc(attribute_set.hp, attribute_set.max_hp, attribute_set.is_alive())


func _on_attribute_mp_changed(_current: int, _maximum: int) -> void:
	if _applying_authority_sync or not multiplayer.is_server():
		return
	sync_player_mp.rpc(attribute_set.mp, attribute_set.max_mp)


## M19：服务器权威状态 RPC 只接受服务器(1)或本机 call_local(0) 的来源
func _sender_is_server() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	return sender == 0 or sender == 1


@rpc("any_peer", "call_local", "reliable")
func sync_player_hp(hp: int, max_hp_value: int, alive: bool) -> void:
	if not _sender_is_server():
		return
	_applying_authority_sync = true
	attribute_set.max_hp = max_hp_value
	attribute_set.set_hp_from_authority(hp)
	_applying_authority_sync = false
	# M18b-6：roguelite 头顶血条（玩家挂载点 y=2.4，青色）
	if _head_health_bar:
		_head_health_bar.set_health(hp, max_hp_value)
		_head_health_bar.sprite_3d.transparency = 0.0 if alive else 1.0
	if alive:
		nickname.visible = not _is_local_first_person()
		# M18b-6：本地第一人称时自己的头顶血条贴脸，与昵称同步隐藏
		_head_health_bar.visible = not _is_local_first_person()
	else:
		nickname.visible = false
		if _head_health_bar:
			_head_health_bar.visible = false


@rpc("any_peer", "call_local", "reliable")
func sync_player_mp(mp: int, max_mp_value: int) -> void:
	if not _sender_is_server():
		return
	_applying_authority_sync = true
	attribute_set.max_mp = max_mp_value
	attribute_set.set_mp_from_authority(mp)
	_applying_authority_sync = false


## M5：攻防变化（装备/增益）→ 服务器广播，HUD 与各端伤害保持一致
func _on_attribute_stats_changed(atk: int, def_value: int) -> void:
	if not multiplayer.is_server():
		return
	sync_player_stats.rpc(atk, def_value)


@rpc("any_peer", "call_local", "reliable")
func sync_player_stats(atk: int, def_value: int) -> void:
	if not _sender_is_server():
		return
	var hud := _get_hud()
	if hud and is_multiplayer_authority():
		hud.set_player_stats(atk, def_value)


## M4：增加经验（仅服务器调用：怪物击杀 / 任务交付）。
## 升级时属性成长并回满血蓝（hp/mp 信号链自动同步），并向全服播报。
func add_experience(amount: int) -> void:
	if not multiplayer.is_server() or amount <= 0:
		return
	if level >= LevelData.MAX_LEVEL:
		experience = 0
		sync_experience.rpc(level, experience)
		experience_changed.emit(experience, LevelData.exp_to_next(level))
		return
	experience += amount
	var leveled_up := false
	while level < LevelData.MAX_LEVEL and experience >= LevelData.exp_to_next(level):
		experience -= LevelData.exp_to_next(level)
		level += 1
		leveled_up = true
	if leveled_up:
		attribute_set.apply_level_growth(level)
		var level_scene := get_tree().current_scene
		if level_scene and level_scene.has_method("show_chat_message"):
			level_scene.show_chat_message.rpc(
				tr("系统"), tr("%s 升到了 Lv.%d！") % [nickname.text, level]
			)
	if level >= LevelData.MAX_LEVEL:
		experience = 0
	sync_experience.rpc(level, experience)
	level_changed.emit(level)
	experience_changed.emit(experience, LevelData.exp_to_next(level))


@rpc("any_peer", "call_local", "reliable")
func sync_experience(new_level: int, current_exp: int) -> void:
	# M26：服务器下发型同步。曾用 authority 模式——单人 Host 被
	# OfflineMultiplayerPeer 本地调用掩盖，双端真连后服务器(1)向
	# authority=客户端/bot 的节点发 RPC 全被引擎拒绝（客户端刷屏）。
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	var previous_level := level
	level = new_level
	experience = current_exp
	if level != previous_level:
		attribute_set.apply_level_growth(level) # 客户端重算成长（满血由 sync_player_hp 覆盖）
		level_changed.emit(level)
	experience_changed.emit(experience, LevelData.exp_to_next(level))


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)
	if multiplayer.is_server():
		sync_player_gold.rpc(gold)


@rpc("any_peer", "call_local", "reliable")
func sync_player_gold(total: int) -> void:
	# M26：服务器下发型同步（防客户端伪造），根因同 sync_experience
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	gold = total
	gold_changed.emit(gold)


## M3：服务器扣金币（购买用），失败不退步
func spend_gold(amount: int) -> bool:
	if amount <= 0 or gold < amount or not multiplayer.is_server():
		return false
	gold -= amount
	gold_changed.emit(gold)
	sync_player_gold.rpc(gold)
	return true


# ===== M3 消耗品与交易（全部服务器权威校验）=====

## 双击消耗品：回血/回蓝并扣除 1 个
@rpc("any_peer", "call_local", "reliable")
func request_use_consumable(from_slot: int) -> void:
	if not multiplayer.is_server() or not _is_owner_request():
		return
	if not player_inventory or not player_inventory.is_slot_active(from_slot):
		return
	if not attribute_set.is_alive():
		return
	var slot := player_inventory.get_slot(from_slot)
	if slot == null or slot.is_empty():
		return
	var item := ItemDatabase.get_item(slot.item_id)
	if item == null or not item.is_consumable():
		return
	# 单一恢复类消耗品在对应属性已满时不允许浪费（M14：不再静默，给出提示）
	var level_scene := get_tree().current_scene
	if item.heal_amount > 0 and item.restore_mp <= 0 and attribute_set.hp >= attribute_set.max_hp:
		if level_scene and level_scene.has_method("show_chat_message"):
			level_scene.show_chat_message(tr("系统"), tr("生命值已满，先不用吃 %s") % tr(item.name))
		return
	if item.restore_mp > 0 and item.heal_amount <= 0 and attribute_set.mp >= attribute_set.max_mp:
		if level_scene and level_scene.has_method("show_chat_message"):
			level_scene.show_chat_message(tr("系统"), tr("法力值已满，先不用喝 %s") % tr(item.name))
		return
	if player_inventory.remove_item(item.id, 1) <= 0:
		return
	if item.heal_amount > 0:
		attribute_set.heal(item.heal_amount)
	if item.restore_mp > 0:
		attribute_set.restore_mp(item.restore_mp)
	_sync_inventory_to_owner()


## 商人处购买：先扣钱再入包，背包满则自动退钱
@rpc("any_peer", "call_local", "reliable")
func request_buy_item(item_id: String) -> void:
	if not multiplayer.is_server() or not _is_owner_request():
		return
	if not player_inventory or not attribute_set.is_alive():
		return
	# M43 安全闸：原先只校验 value>0，客户端可隔着半张地图买任意物品（含未上架的）。
	# 现在要求 ① 物品在商人货架白名单内 ② 玩家确实站在某个商人 3 米内。
	if not ItemDatabase.MERCHANT_STOCK.has(item_id):
		return
	if not _is_near_any_merchant():
		return
	var item := ItemDatabase.get_item(item_id)
	if item == null or item.value <= 0:
		return
	if not spend_gold(item.value):
		return
	var remaining := player_inventory.add_item(item, 1)
	if remaining > 0: # 背包满，退钱
		add_gold(item.value)
		return
	_sync_inventory_to_owner()


## 商人处出售：从背包移除 1 个并按价值换钱
@rpc("any_peer", "call_local", "reliable")
func request_sell_item(from_slot: int) -> void:
	if not multiplayer.is_server() or not _is_owner_request():
		return
	if not player_inventory or not attribute_set.is_alive():
		return
	# M43：出售同样要求站在商人旁（否则可在任意地点把背包变现）
	if not _is_near_any_merchant():
		return
	if not player_inventory.is_slot_active(from_slot):
		return
	var slot := player_inventory.get_slot(from_slot)
	if slot == null or slot.is_empty():
		return
	var item := ItemDatabase.get_item(slot.item_id)
	if item == null or item.value <= 0:
		return
	if player_inventory.remove_item(item.id, 1) <= 0:
		return
	add_gold(item.get_sell_price())
	_sync_inventory_to_owner()


## M43：服务端权威的交易距离校验。留 0.5m 余量吸收网络位置插值抖动，
## 避免"明明站在商人面前却买不了"的误判。
const MERCHANT_TRADE_RANGE := 3.5


func _is_near_any_merchant() -> bool:
	if not is_inside_tree():
		return false
	for m in get_tree().get_nodes_in_group("merchants"):
		if m is Node3D and global_position.distance_to((m as Node3D).global_position) <= MERCHANT_TRADE_RANGE:
			return true
	return false


func _on_combat_died() -> void:
	# M18b-3：死亡独立状态（KayKit 侧播 Death_A 倒地；机器人侧无此动画维持原状）
	_request_animation(&"Death", true)
	if is_multiplayer_authority():
		var hud := _get_hud()
		if hud:
			hud.show_death_panel()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		return
	# M5：界面打开时屏蔽战斗按键（背包/商店/任务/职业选择等）
	var current_scene := get_tree().current_scene
	if current_scene and current_scene.has_method("is_gameplay_input_blocked") and current_scene.is_gameplay_input_blocked():
		return
	if not attribute_set.is_alive():
		return
	# M31c：驾驶 tsl 飞车时 Q/E 是翻滚、↑↓ 是俯仰（tsl 原键位）——
	# 屏蔽骑乘中 Q(选目标)/E(交互) 的原功能，避免翻滚误选目标/误交互
	if mounted_vehicle != null and mounted_vehicle.is_in_group("tsl_car"):
		if event.is_action_pressed("target_nearest") or event.is_action_pressed("interact") \
				or event.is_action_pressed("pickup"):
			return
	# M19：G 调试发放漂浮伙伴（任务链接入前的演示途径）
	if event.is_action_pressed("debug_grant_companion") if InputMap.has_action("debug_grant_companion") else false:
		_ensure_companion()
		return
	# ===== M39：自动行走 / 自动飞行（WoW Auto-Run）=====
	# 小键盘 + （或主键盘 =）：切换式开关。骑乘时 = 自动飞行，落地时 = 自动行走。
	if event.is_action_pressed("toggle_autorun"):
		AutoRun.toggle()
		get_viewport().set_input_as_handled()
		return
	# 任意移动键按下 → 中断自动前进（WoW Auto-Run 原生行为）。
	# 注意：必须在 toggle_autorun 之后判断，否则 + 键本身会被当成移动键。
	if _is_movement_key_pressed(event):
		AutoRun.stop()
	# M19/M25/M25f：X = 召唤即骑；骑乘中再按 = 对当前骑乘物下座并收回（条款 M8：
	# 骑的不是自己名下车时只下座不收回——误登 bot 沙发时 X 是唯一自救键）
	if event.is_action_pressed("mount"):
		if mounted_vehicle != null:
			mounted_vehicle.request_dismount.rpc_id(1)
			_recall_mount()
		else:
			_summon_mount(true)
		return
	# M30：V = 召唤/收回街机飞车（与 X 沙发同构；骑乘中按 V 先下再收）
	if event.is_action_pressed("mount_car"):
		if mounted_vehicle != null:
			mounted_vehicle.request_dismount.rpc_id(1)
			_recall_mount()
		else:
			_summon_mount(true, -1, Vector3(), INF, "car")
		return
	if event.is_action_pressed("attack"):
		# M39：鼠标左右键同时按住 = 鼠标前进（WoW 语义）→ 左键不触发攻击/选目标。
		# 否则按住双键前进会一路上挥砍。
		if _both_mouse_held():
			return
		# M36：手持石块时左键 = 投掷石块（优先级高于选目标/普攻）
		if has_stone:
			throw_stone()
			get_viewport().set_input_as_handled()
			return
		var picked := _combat_pick_screen_center()
		if picked != null:
			_set_target(picked)
		if not current_target_path.is_empty():
			try_attack(current_target_path, "basic_attack")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("target_nearest"):
		_select_nearest_target()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("skill_1") or event.is_action_pressed("skill_2") \
		or event.is_action_pressed("skill_3") or event.is_action_pressed("skill_4"):
		var slot_index := _skill_action_slot_index(event)
		if slot_index >= 0:
			_try_use_class_skill(slot_index)
		get_viewport().set_input_as_handled()


## M5：把 skill_1~4 按键映射到职业技能槽位（0~3）
func _skill_action_slot_index(event: InputEvent) -> int:
	if event.is_action_pressed("skill_1"):
		return 0
	if event.is_action_pressed("skill_2"):
		return 1
	if event.is_action_pressed("skill_3"):
		return 2
	if event.is_action_pressed("skill_4"):
		return 3
	return -1


## M5：释放职业技能（槽位 0~3 对应职业的 4 个技能）
## M14：技能失败原因提示限流（同一技能 800ms 内只提示一次，防连按刷屏）
const SKILL_NOTIFY_COOLDOWN_MSEC := 800
var _skill_notify_last_msec := {}


## M14：本地聊天提示（不进 RPC 广播，只有自己看到）
func _notify_local(msg: String) -> void:
	var level_scene := get_tree().current_scene
	if level_scene and level_scene.has_method("show_chat_message"):
		level_scene.show_chat_message(tr("系统"), msg)


## M14：带限流的技能失败提示
func _notify_skill(skill_id: String, msg: String) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_skill_notify_last_msec.get(skill_id, 0)) < SKILL_NOTIFY_COOLDOWN_MSEC:
		return
	_skill_notify_last_msec[skill_id] = now
	_notify_local(msg)


func _try_use_class_skill(slot_index: int) -> void:
	if player_class.is_empty():
		# M14：双保险——M14 起开局默认战士，正常不会再走到这里
		_notify_local(tr("尚未选择职业：请到村东的职业训练师处选择"))
		return
	var class_data := ClassDatabase.get_class_data(player_class)
	if class_data == null or slot_index >= class_data.skill_ids.size():
		return
	try_use_skill(class_data.skill_ids[slot_index])


func _update_combat(_delta: float) -> void:
	if current_target_path.is_empty():
		return
	var target := get_node_or_null(current_target_path)
	if target == null or not _is_target_alive(target):
		_clear_target()
		return
	var target_position := (target as Node3D).global_position
	if global_position.distance_to(target_position) > AUTO_TARGET_MAX_RANGE:
		_clear_target()
		return
	# 按住左键 = 自动攻击
	if Input.is_action_pressed("attack"):
		try_attack(current_target_path, "basic_attack")


func _is_target_alive(node: Node) -> bool:
	var attrs := CombatMath.get_attribute_set(node)
	return attrs != null and attrs.is_alive()


func _combat_pick_screen_center() -> Node:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var screen_center := get_viewport().get_visible_rect().size / 2.0
	var origin := camera.project_ray_origin(screen_center)
	var direction := camera.project_ray_normal(screen_center)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 100.0)
	query.collision_mask = COMBAT_TARGET_LAYERS
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider := hit.get("collider") as Object
	if collider is Node and collider != self and _is_attackable_target(collider):
		return collider
	return null


func _is_attackable_target(node: Node) -> bool:
	return node is TrainingDummy or node is Monster or node is Character


func _select_nearest_target() -> void:
	var best: Node = null
	var best_distance := 25.0
	for monster in get_tree().get_nodes_in_group("monsters"):
		if not _is_target_alive(monster):
			continue
		var distance := global_position.distance_to((monster as Node3D).global_position)
		if distance < best_distance:
			best = monster
			best_distance = distance
	if best != null:
		_set_target(best)


func _set_target(node: Node) -> void:
	if node == null or node == self:
		return
	# 取消旧目标的选中环
	if not current_target_path.is_empty():
		var old_target := get_node_or_null(current_target_path)
		if old_target and old_target.has_method("set_selected"):
			old_target.set_selected(false)
	current_target_path = _absolute_path(node)
	if node.has_method("set_selected"):
		node.set_selected(true)
	var hud := _get_hud()
	if hud:
		hud.set_target(node)


func _clear_target() -> void:
	if not current_target_path.is_empty():
		var old_target := get_node_or_null(current_target_path)
		if old_target and old_target.has_method("set_selected"):
			old_target.set_selected(false)
	current_target_path = ""
	var hud := _get_hud()
	if hud:
		hud.clear_target()


func try_attack(target_path: String, skill_id: String) -> void:
	if not is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		return
	if not attribute_set.is_alive() or target_path.is_empty():
		return
	var skill := SkillDatabase.get_skill(skill_id)
	if skill == null:
		return
	var now := Time.get_ticks_msec()
	if now < int(_next_attack_msec.get(skill_id, 0)):
		return
	# 客户端冷却预测（HUD 遮罩立即响应），服务器权威冷却见 request_attack
	_next_attack_msec[skill_id] = now + int(skill.cooldown * 1000.0)
	# M18b-2：步兵普攻三连斩——本地推进段数并播对应段动画（与服务器同一推进规则）；
	# 其他职业/技能照旧播技能资源声明的动画。第三段转圈重斩出手附带震屏。
	if player_class == INFANTRY_CLASS_ID and skill_id == "basic_attack":
		var adv := _advance_combo(_combo_index, _combo_last_msec, now)
		_combo_index = adv[0]
		_combo_last_msec = adv[1]
		_play_attack_animation(INFANTRY_COMBO_ANIMS[_combo_index])
		if _combo_index == 2:
			_trigger_shake(SHAKE_ATTACK_MAGNITUDE)
	else:
		_play_attack_animation(skill.animation)
	_play_skill_sfx(skill_id)
	request_attack.rpc_id(1, target_path, skill_id)


## M18b-2：连招推进（客户端与服务器共用规则）——窗口内 +1 循环三段，
## 超窗（COMBO_WINDOW_MSEC）重置回第一段。返回 [新段, 时间戳]。
func _advance_combo(current: int, last_msec: int, now: int) -> Array:
	if now - last_msec > COMBO_WINDOW_MSEC:
		return [0, now]
	return [(current + 1) % INFANTRY_COMBO_ANIMS.size(), now]


## M18b-2：本地玩家相机震屏（噪声偏移，见 shake_camera_3d.gd）
func _trigger_shake(magnitude: float) -> void:
	if _shake_camera != null:
		_shake_camera.quick_shake(magnitude)


## M18b-2：格挡姿态上报（服务器权威副本，供怪物攻击结算 -70% 减伤）
@rpc("any_peer", "call_local", "reliable")
func set_blocking(blocking: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != get_multiplayer_authority():
		return
	is_blocking = blocking


# ===== M36：气球夺剑——捡石块 / 投掷石块（服务器权威，链路同 M5 弹道）=====

func _get_balloon_arena() -> BalloonArena:
	var level_scene := get_tree().current_scene
	if level_scene == null:
		return null
	return level_scene.get_node_or_null("Environment/BalloonArena") as BalloonArena


## 附近可取的石堆下标（3m 内且已长出），无则 -1（各端本地检测，纯表现引导）
func _near_stone_pile_index() -> int:
	var arena := _get_balloon_arena()
	if arena == null:
		return -1
	return arena.get_nearest_stone_pile(global_position)


## E 键捡石块（客户端入口：单机本地直调，联机 rpc_id(1) 请求）
func pick_stone(pile_idx: int) -> void:
	if multiplayer.is_server():
		request_pick_stone(pile_idx)
	else:
		request_pick_stone.rpc_id(1, pile_idx)


@rpc("any_peer", "call_local", "reliable")
func request_pick_stone(pile_idx: int) -> void:
	if not multiplayer.is_server():
		return
	# sender 0 = 服务器本地调用（单机），否则必须是节点 authority（owner）
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != get_multiplayer_authority():
		return
	if not attribute_set.is_alive() or not _grounded:
		return
	if _server_has_stone:
		return
	var arena := _get_balloon_arena()
	if arena == null:
		return
	# 服务器权威距离校验（防伪造 idx / 超远程程拾取）
	if arena.get_nearest_stone_pile(global_position) != pile_idx:
		return
	_server_has_stone = true
	arena.take_stone_pile(pile_idx)
	sync_stone_state.rpc_id(get_multiplayer_authority(), true)


## 左键投掷石块（客户端入口：本地冷却预测 + 立即清石表现，服务器校验后广播）
func throw_stone() -> void:
	if not has_stone or not attribute_set.is_alive() or not _grounded:
		return
	var now := Time.get_ticks_msec()
	if now < _stone_throw_local_cd_msec:
		return
	_stone_throw_local_cd_msec = now + STONE_THROW_COOLDOWN_MSEC
	var origin := global_position + Vector3.UP * 1.3
	var direction := _stone_throw_direction()
	has_stone = false
	is_collecting = false
	_play_attack_animation(&"SwordSlash")
	if multiplayer.is_server():
		request_throw_stone(origin, direction)
	else:
		request_throw_stone.rpc_id(1, origin, direction)


@rpc("any_peer", "call_local", "reliable")
func request_throw_stone(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != get_multiplayer_authority():
		return
	var now := Time.get_ticks_msec()
	if now < _stone_throw_cooldown_msec:
		return
	if not _server_has_stone or not attribute_set.is_alive():
		return
	_stone_throw_cooldown_msec = now + STONE_THROW_COOLDOWN_MSEC
	_server_has_stone = false
	var arena := _get_balloon_arena()
	if arena == null:
		return
	var stone_name := "Stone_%d_%d" % [get_multiplayer_authority(), randi()]
	arena.spawn_authority_stone(stone_name, origin, direction, STONE_THROW_SPEED)
	arena.spawn_stone_visual.rpc(stone_name, origin, direction, STONE_THROW_SPEED)
	sync_stone_state.rpc_id(get_multiplayer_authority(), false)


## 服务器→owner 回执：手持石块状态（权威副本的客户端镜像）
@rpc("any_peer", "call_local", "reliable")
func sync_stone_state(has: bool) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	has_stone = has
	if has:
		_notify_local("捡起了石块，按左键投掷击破气球！")


## 投掷方向：相机朝向 + 轻微上抛（气球悬在 6m 高，需要抛物线）；NaN 全闸兜底
func _stone_throw_direction() -> Vector3:
	var dir := Vector3.FORWARD
	if _spring_arm_offset != null:
		dir = -_spring_arm_offset.global_transform.basis.z
	if not (is_finite(dir.x) and is_finite(dir.y) and is_finite(dir.z)) or dir.length() < 0.001:
		dir = Vector3.FORWARD
	dir = dir + Vector3.UP * 0.35
	if dir.length() < 0.001:
		return Vector3.FORWARD
	return dir.normalized()


func get_skill_cooldown_ratio(skill_id: String) -> float:
	var skill := SkillDatabase.get_skill(skill_id)
	if skill == null or skill.cooldown <= 0.0:
		return 0.0
	var next_msec := int(_next_attack_msec.get(skill_id, 0))
	var now := Time.get_ticks_msec()
	if now >= next_msec:
		return 0.0
	return clampf(float(next_msec - now) / (skill.cooldown * 1000.0), 0.0, 1.0)


## M5：释放职业技能（按目标类型自动选目标：敌人/自己/友方/自身AoE）
func try_use_skill(skill_id: String) -> void:
	if not is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		return
	if not attribute_set.is_alive():
		return
	var skill := SkillDatabase.get_skill(skill_id)
	if skill == null:
		return
	var now := Time.get_ticks_msec()
	if now < int(_next_attack_msec.get(skill_id, 0)):
		_notify_skill(skill_id, tr("【%s】还在冷却中") % tr(skill.skill_name))
		return
	var target_path := _resolve_skill_target_path(skill)
	if target_path.is_empty():
		_notify_skill(skill_id, tr("【%s】需要一个目标——先点击或用 Tab 键选中敌人") % tr(skill.skill_name))
		return # 需要目标但当前没有合法目标
	# 客户端预校验：明显不合法的释放直接放弃（不进冷却、不发 RPC），
	# 避免服务器拒绝后客户端却显示了假冷却
	var target := get_node_or_null(target_path)
	if target == null:
		return
	if skill.range > 0.0 and target != self:
		var distance := global_position.distance_to((target as Node3D).global_position)
		if distance > skill.range:
			_notify_skill(skill_id, tr("距离太远，【%s】需要靠近到 %.1f 米内") % [tr(skill.skill_name), skill.range])
			return
	if attribute_set.mp < skill.mp_cost:
		_notify_skill(skill_id, tr("法力不足，【%s】需要 %d 点法力") % [tr(skill.skill_name), skill.mp_cost])
		return
	if skill.requires_target_hp_below > 0.0:
		var threshold_attrs := CombatMath.get_attribute_set(target)
		if threshold_attrs == null:
			return
		var hp_ratio := float(threshold_attrs.hp) / float(maxi(1, threshold_attrs.max_hp))
		if hp_ratio >= skill.requires_target_hp_below:
			_notify_skill(skill_id, tr("【%s】只能对生命低于 %d%% 的目标使用") % [tr(skill.skill_name), int(skill.requires_target_hp_below * 100)])
			return
	# 客户端冷却预测（HUD 遮罩立即响应），服务器权威冷却见 request_attack
	_next_attack_msec[skill_id] = now + int(skill.cooldown * 1000.0)
	_play_attack_animation(skill.animation)
	_play_skill_sfx(skill_id)
	request_attack.rpc_id(1, target_path, skill_id)


## M11：技能释放音效（客户端预测处播一次；普攻由动画函数播，不在映射内）
func _play_skill_sfx(skill_id: String) -> void:
	if SKILL_SFX.has(skill_id):
		_local_sfx(SKILL_SFX[skill_id])


## M43 空间化：动作音效按"是不是我自己的动作"分流。
## 自己的动作走 2D——第三人称相机在身后约 5 米，若也走 3D，自己的挥剑声会被
## 自己的弹簧臂距离衰减掉，听感反而变小。
## 别人的动作（含 bot：bot 攻击由服务器代播，此时 authority 是 900x 而非本地玩家）
## 必须走 3D，否则地图另一头的挥剑声会以全音量灌进耳朵——这正是用户的原始抱怨。
func _local_sfx(key: StringName) -> void:
	if is_multiplayer_authority():
		SfxManager.play(key)
	else:
		SfxManager.play_3d(key, global_position)


## M5：按技能目标类型解析实际目标路径（空字符串 = 放弃释放）
func _resolve_skill_target_path(skill: SkillData) -> String:
	match skill.target_type:
		SkillData.TargetType.SELF, SkillData.TargetType.AOE_SELF:
			return _absolute_path(self)
		SkillData.TargetType.ALLY:
			# 当前目标是玩家（且存活、在射程内）则治疗队友，否则治疗自己
			if not current_target_path.is_empty():
				var ally := get_node_or_null(current_target_path)
				if ally is Character and ally != self and _is_target_alive(ally):
					if global_position.distance_to((ally as Node3D).global_position) <= skill.range:
						return current_target_path
			return _absolute_path(self)
		_: # ENEMY：必须有当前目标
			if current_target_path.is_empty():
				return ""
			var target := get_node_or_null(current_target_path)
			if target == null or not _is_target_alive(target):
				return ""
			return current_target_path


## 节点的真绝对路径（/root/...）。注意：get_root().get_path_to() 只返回相对 root 的
## "Level/XXX"，在本节点上 get_node_or_null 解析不到，必须补 "/root/" 前缀。
func _absolute_path(node: Node) -> String:
	return str(get_tree().get_root().get_path()) + "/" + str(get_tree().get_root().get_path_to(node))


## 服务器权威：校验技能合法性并按效果组结算
@rpc("any_peer", "call_local", "reliable")
func request_attack(target_path: String, skill_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var is_local_host_call := sender_id == 0
	if not is_local_host_call and sender_id != get_multiplayer_authority():
		return
	printerr("ATK_DIAG: %d 攻击 %s skill=%s alive=%s" % [
		get_multiplayer_authority(), target_path, skill_id, attribute_set.is_alive()])  # 临时诊断
	if not attribute_set.is_alive():
		return
	var skill := SkillDatabase.get_skill(skill_id)
	if skill == null:
		return
	# M5：按目标类型解析实际目标（自身/AoE 技能忽略传入目标）
	var target_node := _resolve_attack_target(skill, target_path)
	if target_node == null:
		return
	if skill.range > 0.0 and target_node != self:
		if global_position.distance_to((target_node as Node3D).global_position) > skill.range:
			return
	# 斩杀条件：目标生命必须低于阈值
	if skill.requires_target_hp_below > 0.0:
		var threshold_attrs := CombatMath.get_attribute_set(target_node)
		if threshold_attrs == null:
			return
		var hp_ratio := float(threshold_attrs.hp) / float(maxi(1, threshold_attrs.max_hp))
		if hp_ratio >= skill.requires_target_hp_below:
			return
	var now := Time.get_ticks_msec()
	if now < int(_server_next_attack_msec.get(skill_id, 0)):
		return
	if not attribute_set.spend_mp(skill.mp_cost):
		return
	_server_next_attack_msec[skill_id] = now + int(skill.cooldown * 1000.0)
	# M18b-2：服务器权威连招计数——步兵普攻按同规则推进段数，
	# 伤害倍率 = 技能倍率 × 连段倍率（段 3 转圈重斩 1.6x）
	var used_anim: StringName
	if player_class == INFANTRY_CLASS_ID and skill_id == "basic_attack":
		var adv := _advance_combo(_server_combo_index, _server_combo_last_msec, now)
		_server_combo_index = adv[0]
		_server_combo_last_msec = adv[1]
		_resolve_skill_effects(skill, target_node, INFANTRY_COMBO_MULT[_server_combo_index])
		used_anim = INFANTRY_COMBO_ANIMS[_server_combo_index]
	else:
		_resolve_skill_effects(skill, target_node)
		used_anim = skill.animation
	# M24：bot（虚拟 peer 9001+）没有本地客户端——玩家攻击动画由"发起端"本地播，
	# bot 的发起端就是服务器，结算成功后由服务器代播（_request_animation 会经
	# _server_publish_animation 广播到所有客户端，各端可见）。
	if get_multiplayer_authority() >= BOT_AUTH_BASE:
		_play_attack_animation(used_anim)
		_play_skill_sfx(skill_id)


## M5：服务器侧目标解析（与客户端 _resolve_skill_target_path 对应的权威版）
func _resolve_attack_target(skill: SkillData, target_path: String) -> Node:
	match skill.target_type:
		SkillData.TargetType.SELF, SkillData.TargetType.AOE_SELF:
			return self
		SkillData.TargetType.ALLY:
			if not target_path.is_empty():
				var ally := get_node_or_null(target_path)
				if ally is Character and ally != self and ally.attribute_set.is_alive():
					return ally
			return self # 没有有效队友目标 → 对自己释放
		_: # ENEMY
			if target_path.is_empty():
				return null
			var target := get_node_or_null(target_path)
			if target == null or target == self:
				return null
			var target_attrs := CombatMath.get_attribute_set(target)
			if target_attrs == null or not target_attrs.is_alive():
				return null
			return target


## M5：技能效果分流：弹道 → 飞行命中结算；AoE → 范围结算；其余 → 单体结算
## M18b-2：extra_mult 附加倍率（步兵连招段倍率），默认 1.0
func _resolve_skill_effects(skill: SkillData, target_node: Node, extra_mult: float = 1.0) -> void:
	if skill.is_projectile:
		_spawn_skill_projectile(skill, target_node)
		return
	if skill.target_type == SkillData.TargetType.AOE_SELF:
		_apply_aoe_effects(skill, extra_mult)
		return
	_apply_effects_to_target(skill, target_node, extra_mult)


## M5：单体结算（伤害/治疗/HOT/减速/增益）
func _apply_effects_to_target(skill: SkillData, target_node: Node, extra_mult: float = 1.0) -> void:
	var target_attrs := CombatMath.get_attribute_set(target_node)
	if target_attrs == null or not target_attrs.is_alive():
		return
	# 增益：对自己生效（盾墙/奥术强化）
	if (skill.buff_atk > 0 or skill.buff_def > 0) and target_node == self:
		target_attrs.apply_buff(skill.buff_atk, skill.buff_def, skill.buff_duration)
	# 瞬时治疗
	var heal_amount := _instant_heal_amount(skill, target_attrs)
	if heal_amount > 0:
		var applied := target_attrs.heal(heal_amount)
		if applied > 0 and target_node is Character:
			(target_node as Character).sync_combat_heal.rpc(_absolute_path(target_node), applied)
	# 持续治疗（HOT）
	if skill.hot_ticks > 0:
		var per_tick := skill.hot_amount
		if skill.heal_percent > 0.0:
			per_tick = int(float(target_attrs.max_hp) * skill.heal_percent)
		target_attrs.add_hot(per_tick, skill.hot_ticks, skill.hot_interval)
	# 伤害与减速只对敌方生效
	if _is_enemy_target(target_node):
		if skill.damage_multiplier > 0.0:
			_deal_skill_damage(skill, target_node, target_attrs, extra_mult)
		if skill.slow_duration > 0.0:
			target_attrs.apply_slow(skill.slow_factor, skill.slow_duration)


## M5：AoE 结算（以自身为中心）：敌人受伤害，队友（含自己）受治疗
func _apply_aoe_effects(skill: SkillData, extra_mult: float = 1.0) -> void:
	var radius := skill.aoe_radius
	if radius <= 0.0:
		return
	for entity in _get_combat_entities():
		if global_position.distance_to((entity as Node3D).global_position) > radius:
			continue
		var entity_attrs := CombatMath.get_attribute_set(entity)
		if entity_attrs == null or not entity_attrs.is_alive():
			continue
		if entity is Character:
			# 友方玩家（含自己）：只治疗
			var heal_amount := _instant_heal_amount(skill, entity_attrs)
			if heal_amount > 0:
				var applied := entity_attrs.heal(heal_amount)
				if applied > 0:
					(entity as Character).sync_combat_heal.rpc(_absolute_path(entity), applied)
		elif entity != self:
			# 怪物/木桩：只伤害（不会炸到自己）
			if skill.damage_multiplier > 0.0:
				_deal_skill_damage(skill, entity, entity_attrs, extra_mult)


## 瞬时治疗量：HOT 技能不瞬治疗；heal_percent 优先于固定值
func _instant_heal_amount(skill: SkillData, target_attrs: AttributeSet) -> int:
	if skill.hot_ticks > 0:
		return 0
	if skill.heal_percent > 0.0:
		return int(float(target_attrs.max_hp) * skill.heal_percent)
	return skill.heal_amount


func _deal_skill_damage(skill: SkillData, target_node: Node, target_attrs: AttributeSet, extra_mult: float = 1.0) -> void:
	var is_crit := CombatMath.roll_crit()
	var damage := CombatMath.calculate_damage(attribute_set.atk, skill.damage_multiplier * extra_mult, target_attrs.def)
	if is_crit:
		damage = int(round(float(damage) * CombatMath.CRIT_MULTIPLIER))
	# 统一战斗接口：木桩 / 怪物 / 玩家都实现 apply_combat_damage
	if target_node.has_method("apply_combat_damage"):
		target_node.apply_combat_damage(damage, get_multiplayer_authority(), is_crit)
	# M18b-2：击退——沿攻击者→目标方向施加速度脉冲（怪物侧指数衰减 + 硬直）。
	# 仅服务器执行（本函数只在服务器跑），位置由 MultiplayerSynchronizer 广播。
	if skill.knockback_force > 0.0 and target_node is Monster:
		var push_dir: Vector3 = (target_node as Node3D).global_position - global_position
		push_dir.y = 0.0
		# M37：NaN 闸必须先于 length() 比较——NaN 与任何数比较恒 false，
		# 原来的 length()>0.1 闸对 NaN 无效，NaN 方向会被 normalize 后
		# 写进怪物击退速度，怪物位置随即 NaN，全场 normalize 刷屏。
		if not (is_finite(push_dir.x) and is_finite(push_dir.z)):
			return
		if push_dir.length() > 0.1:
			(target_node as Monster).add_knockback(push_dir.normalized() * skill.knockback_force)


## M5：敌方判定（怪物/木桩，或除自己以外的玩家——PVP 开放）
func _is_enemy_target(node: Node) -> bool:
	if node is Monster or node is TrainingDummy:
		return true
	if node is Character:
		return node != self
	return false


## M5：场上可参与战斗的实体（怪物组 + 全部玩家）
func _get_combat_entities() -> Array:
	var entities: Array = []
	for monster in get_tree().get_nodes_in_group("monsters"):
		entities.append(monster)
	var players_container := get_tree().get_root().get_node_or_null("Level/PlayersContainer")
	if players_container:
		for player in players_container.get_children():
			entities.append(player)
	return entities


## M5：服务器生成弹道并全服广播（各端本地模拟直线飞行，命中时广播消失）
func _spawn_skill_projectile(skill: SkillData, target_node: Node) -> void:
	var target_position := (target_node as Node3D).global_position + Vector3.UP * 1.0
	var origin := global_position + Vector3.UP * 1.2
	# M33：NaN 闸必须在 normalized() **之前**——原来先 normalize 再查，
	# 闸来得太晚，引擎内部已经刷了一堆警告。
	var raw_dir := target_position - origin
	var direction := raw_dir
	if not (is_finite(raw_dir.x) and is_finite(raw_dir.y) and is_finite(raw_dir.z)) or raw_dir.length() < 0.001:
		direction = -global_transform.basis.z
	if not (is_finite(direction.x) and is_finite(direction.y) and is_finite(direction.z)) or direction.length() < 0.001:
		direction = Vector3.FORWARD
	direction = direction.normalized()
	var projectile_name := "Proj_%d_%d" % [get_multiplayer_authority(), randi()]
	spawn_projectile.rpc(projectile_name, origin, direction, skill.projectile_speed, skill.range, skill.id)
	# 服务器本地实例记录攻击者，用于命中回调
	var local_projectile := _effects_root().get_node_or_null(projectile_name) as Projectile
	if local_projectile:
		local_projectile.set_attacker(self)


@rpc("any_peer", "call_local", "reliable")
func spawn_projectile(
	proj_name: String,
	origin: Vector3,
	direction: Vector3,
	speed: float,
	max_range: float,
	skill_id: String
) -> void:
	# M26：服务器下发型同步（防客户端伪造），根因同 sync_experience
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	var skill := SkillDatabase.get_skill(skill_id)
	var color := Color(1.0, 0.55, 0.15)
	if skill:
		color = skill.projectile_color
	var projectile := PROJECTILE_SCENE.instantiate() as Projectile
	projectile.name = proj_name
	# 先入树再配置：@onready 的 $Mesh/$Light 要等 _ready，且 Effects 容器带变换，
	# 起始点必须用 global_position（局部 position 会被容器变换平移导致打偏）
	_effects_root().add_child(projectile)
	projectile.global_position = origin
	projectile.setup(direction, speed, max_range, skill_id, color)


## M5：服务器命中后广播：全服移除弹道（伤害已由 apply_combat_damage 链路同步）
@rpc("any_peer", "call_local", "reliable")
func despawn_projectile(proj_name: String) -> void:
	# M26：服务器下发型同步（防客户端伪造），根因同 sync_experience
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	var projectile := _effects_root().get_node_or_null(proj_name)
	if projectile:
		projectile.queue_free()


## M5：服务器弹道命中回调（由 projectile.gd 触发）：结算伤害并广播弹道消失
func _on_projectile_hit(collider: Object, skill_id: String, proj_name: String) -> void:
	if not multiplayer.is_server():
		return
	var skill := SkillDatabase.get_skill(skill_id)
	if skill == null:
		return
	var target_attrs := CombatMath.get_attribute_set(collider as Node)
	if target_attrs == null or not target_attrs.is_alive():
		return
	_apply_effects_to_target(skill, collider as Node)
	despawn_projectile.rpc(proj_name)


@rpc("any_peer", "call_local", "reliable")
func sync_combat_heal(target_path: String, amount: int) -> void:
	# M26：服务器下发型同步（防客户端伪造），根因同 sync_experience
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	var target := get_node_or_null(target_path) as Node3D
	if target == null:
		return
	DamageNumber.spawn(_effects_root(), target.global_position + Vector3.UP * 1.7, amount, false, Color(0.35, 1.0, 0.45))


# ===== M5：职业系统（服务器权威，客户端经 sync_class 同步）=====

## 客户端 UI 调用：请求选择/更换职业
@rpc("any_peer", "call_local", "reliable")
func request_choose_class(class_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != get_multiplayer_authority():
		return
	var class_data := ClassDatabase.get_class_data(class_id)
	if class_data == null:
		return
	player_class = class_id
	remove_meta("auto_defaulted_class") # M18b-1：主动选择过，不再自动弹选择界面
	# M27 条款 V3：职业变更回写 Network.players 权威副本——否则迟加入客户端
	# 经 _sync_registered_player 创建该玩家节点时 class 为空，
	# 模型退回 GodotRobot（事故 C："客户机看到红色机器人"）。
	var authority_id := get_multiplayer_authority()
	if Network.players.has(authority_id):
		Network.players[authority_id]["class"] = class_id
	_apply_class_base_stats()
	sync_class.rpc(class_id)
	var level_scene := get_tree().current_scene
	if level_scene and level_scene.has_method("show_chat_message"):
		level_scene.show_chat_message.rpc(
			tr("系统"), tr("%s 选择了职业：%s！") % [nickname.text, tr(class_data.display_name)]
		)


@rpc("any_peer", "call_local", "reliable")
func sync_class(class_id: String) -> void:
	if not _sender_is_server():
		return
	player_class = class_id
	_apply_class_base_stats()
	_update_body_visual() # M18b-3：步兵切 KayKit 人形（全端一致）
	class_changed.emit(class_id)


## M5：按职业重配基础属性（服务器与客户端各自本地计算，再叠加装备加成与等级成长）
func _apply_class_base_stats() -> void:
	var class_data := ClassDatabase.get_class_data(player_class)
	if class_data == null:
		return
	attribute_set.set_class_base(
		class_data.base_max_hp,
		class_data.base_max_mp,
		class_data.base_atk,
		class_data.base_def
	)
	attribute_set.apply_level_growth(level)
	_recalculate_equipment_bonus()
	if is_multiplayer_authority():
		var hud := _get_hud()
		if hud:
			hud.bind_class_skills(class_data.skill_ids)


## 服务器调用：由攻击方在 request_attack 结算后触发
func apply_combat_damage(amount: int, _source_peer_id: int, is_crit: bool) -> void:
	if not multiplayer.is_server():
		return
	if not attribute_set.is_alive():
		return
	var applied := attribute_set.apply_damage(amount)
	if applied <= 0:
		return
	# 用真绝对路径传目标（get_path() 的相对路径在本节点上解析不到自己）
	# M18b-2：附带服务器侧格挡状态（步兵盾墙 -70% 已在伤害入口折算，此处供表现）
	sync_combat_damage.rpc(_absolute_path(self), applied, is_crit, is_blocking)


@rpc("any_peer", "call_local", "reliable")
func sync_combat_damage(target_path: String, amount: int, is_crit: bool, blocked: bool = false) -> void:
	# M26：服务器下发型同步（防客户端伪造），根因同 sync_experience
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	var target := get_node_or_null(target_path) as Node3D
	if target == null:
		return
	# M13：玩家受击闷响（纯表现；跟着伤害数字的接收端走，各端独立触发）
	# M18b-2：格挡命中播盾牌格挡音效 + 伤害数字变灰
	# M18b-5：步兵（KayKit 铠甲人形）被击播 roguelite 金属声，其余职业保持血肉声
	if blocked:
		SfxManager.play_3d(&"shield_block", target.global_position)
	elif target is Character and target.player_class == "infantry":
		SfxManager.play_3d(&"metal_hit", target.global_position)
	else:
		SfxManager.play_3d(&"player_hit", target.global_position)
	# M14：命中火花——橙红粒子一闪，打击视觉反馈的核心（纯表现，各端独立触发）
	SfxManager.spawn_effect("res://scenes/vfx/hit_spark.tscn", target.global_position + Vector3.UP * 1.0)
	var tint := Color(0.75, 0.75, 0.75) if blocked else Color(1.0, 0.9, 0.3)
	DamageNumber.spawn(_effects_root(), target.global_position + Vector3.UP * 1.7, amount, is_crit, tint)
	DamageNumber.shake(target)
	# M18b-2：自己被击震屏（格挡时减半——盾牌扛住了）
	if target == self and is_multiplayer_authority():
		_trigger_shake(SHAKE_HURT_MAGNITUDE * (0.5 if blocked else 1.0))


func _effects_root() -> Node:
	return get_node_or_null("/root/Level/Environment/Effects")


func request_respawn_action() -> void:
	if not is_multiplayer_authority():
		return
	request_respawn.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_respawn() -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != get_multiplayer_authority():
		return
	attribute_set.full_restore()
	var level_scene := get_tree().get_current_scene()
	if level_scene and level_scene.has_method("get_respawn_point"):
		global_position = level_scene.get_respawn_point()
	velocity = Vector3.ZERO
	sync_player_respawn.rpc(global_position)


@rpc("any_peer", "call_local")
func sync_player_respawn(new_position: Vector3) -> void:
	# M26：服务器下发型同步（防客户端伪造），根因同 sync_experience
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	global_position = new_position
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	attribute_set.full_restore()
	_request_animation(&"Idle", true)
	nickname.visible = not _is_local_first_person()
	var hud := _get_hud()
	if hud:
		hud.hide_death_panel()
		hud.clear_target()


# ===== M4 任务系统（服务器权威，进度全量同步）=====

var _quest_progress: Dictionary = {} # quest_id -> 当前进度（击杀数）
var _quests_done: Array[String] = [] # 已交付的任务 id

signal quest_state_changed # 任务状态变化（HUD 追踪/任务面板刷新）


## 怪物死亡时由 monster.gd 调用：推进所有以该怪物为目标的进行中任务。
## 只发给最后一下的玩家（与金币/经验同规则，组队各自结算）。
func add_quest_kill_progress(monster_id: String) -> void:
	if not multiplayer.is_server():
		return
	for quest_id in _quest_progress:
		var quest := QuestDatabase.get_quest(quest_id)
		if quest == null or quest.objective_type != QuestData.ObjectiveType.KILL_MONSTER:
			continue
		if quest.target_monster_id != monster_id:
			continue
		var count: int = _quest_progress[quest_id]
		if count >= quest.required_count:
			continue
		count += 1
		_quest_progress[quest_id] = count
		if count >= quest.required_count:
			var level_scene := get_tree().current_scene
			if level_scene and level_scene.has_method("show_chat_message"):
				level_scene.show_chat_message.rpc(
					tr("任务"),
					tr("【%s】目标完成：%s %d/%d —— 回城找卫兵队长·卡尔交付！")
						% [tr(quest.name), tr(quest.objective_text), count, quest.required_count]
				)
	_sync_quest_state()


## 任务状态（QuestUI / HUD / 测试用）：done/ready/active/available/locked/unknown
func get_quest_status(quest_id: String) -> String:
	if _quests_done.has(quest_id):
		return "done"
	if _quest_progress.has(quest_id):
		var quest := QuestDatabase.get_quest(quest_id)
		var count: int = _quest_progress[quest_id]
		if quest and count >= quest.required_count:
			return "ready"
		return "active"
	var quest := QuestDatabase.get_quest(quest_id)
	if quest == null:
		return "unknown"
	if level < quest.min_level:
		return "locked"
	if not quest.prerequisite_quest_id.is_empty() and not _quests_done.has(quest.prerequisite_quest_id):
		return "locked"
	return "available"


func get_quest_count(quest_id: String) -> int:
	return int(_quest_progress.get(quest_id, 0))


@rpc("any_peer", "call_local", "reliable")
func request_accept_quest(quest_id: String) -> void:
	if not multiplayer.is_server() or not _is_owner_request():
		return
	var quest := QuestDatabase.get_quest(quest_id)
	if quest == null or get_quest_status(quest_id) != "available":
		return
	_quest_progress[quest_id] = 0
	var level_scene := get_tree().current_scene
	if level_scene and level_scene.has_method("show_chat_message"):
			level_scene.show_chat_message.rpc(
				tr("任务"),
				tr("已接受任务【%s】：%s 0/%d")
					% [tr(quest.name), tr(quest.objective_text), quest.required_count]
			)
	_sync_quest_state()


@rpc("any_peer", "call_local", "reliable")
func request_turn_in_quest(quest_id: String) -> void:
	if not multiplayer.is_server() or not _is_owner_request():
		return
	var quest := QuestDatabase.get_quest(quest_id)
	if quest == null or get_quest_status(quest_id) != "ready" or not attribute_set.is_alive():
		return
	# 先发物品奖励；背包满则整体拒绝（避免经验和金币被部分发出）
	if not quest.reward_item_id.is_empty() and not request_add_single_item(quest.reward_item_id):
		return
	add_experience(quest.reward_exp)
	if quest.reward_gold > 0:
		add_gold(quest.reward_gold)
	_quest_progress.erase(quest_id)
	_quests_done.append(quest_id)
	# M24：好感度结算——协作过的 bot 按各自性格加好感
	RelationshipManager.on_quest_completed(self)
	var level_scene := get_tree().current_scene
	if level_scene and level_scene.has_method("show_chat_message"):
			level_scene.show_chat_message.rpc(
				tr("任务"), tr("完成任务【%s】！获得 %s") % [tr(quest.name), quest.get_reward_summary()], &"quest_success"
			)
	_sync_quest_state()


## 全量同步任务状态给所有客户端（接取/进度/交付后由服务器调用）
func _sync_quest_state() -> void:
	sync_quest_state.rpc(_quest_progress.duplicate(), _quests_done.duplicate())


@rpc("any_peer", "call_local", "reliable")
func sync_quest_state(progress: Dictionary, done: Array) -> void:
	# M26：服务器下发型同步（防客户端伪造），根因同 sync_experience
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	_quest_progress.clear()
	for key in progress:
		_quest_progress[str(key)] = int(progress[key])
	_quests_done.clear()
	for quest_id in done:
		_quests_done.append(str(quest_id))
	quest_state_changed.emit()
	# M19 伙伴发放钩子：完成第一个任务 → 获得漂浮伙伴（各端自发生成自己的，
	# 伙伴是纯表现单机实体不进多人同步）。任务链设计后续扩展，
	# 可按 _quests_done 内容解锁不同伙伴模型（set_model 接口）
	if is_multiplayer_authority() and _quests_done.size() > 0:
		_ensure_companion()


## M19：确保伙伴存在（无则生成漂浮伙伴）
func _ensure_companion() -> void:
	if get_tree().root.get_node_or_null("Level/Partner") != null:
		return
	_spawn_partner()
