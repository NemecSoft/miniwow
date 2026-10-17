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
	&"Death": true
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
	"sword_big": "SwordBig",
	"axe": "Axe",
	# M3 新武器复用模板模型：铁剑/精铁剑=单手剑、亡灵利刃=大剑、战斧=斧
	"sword_iron": "Sword",
	"sword_green": "Sword",
	"sword_blue": "SwordBig",
	"axe_iron": "Axe",
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
var mounted_seat: int = 0

## M19：上下车由载具调用；上车重置攻击/连招状态，下车恢复自由移动
func set_mounted(vehicle: Node3D, seat_index: int = 0) -> void:
	mounted_vehicle = vehicle
	mounted_seat = seat_index
	velocity = Vector3.ZERO
	is_attacking = false
	is_collecting = false
	_last_requested_animation = &""
	# M19：载具相机模式——SpringArm 本地 yaw 锁 0，断开"玩家旋转→相机→沙发→玩家"正反馈循环
	if _spring_arm_offset != null:
		_spring_arm_offset.set_yaw_locked(vehicle != null)
	_request_animation(&"Idle", true)

## M19：召唤专属沙发到身边并自动乘坐（WoW 坐骑键式）
func _summon_mount() -> void:
	var scene := get_tree().current_scene
	var vehicles := scene.get_node_or_null("Environment/Vehicles")
	if vehicles == null:
		return
	var couch := vehicles.get_node_or_null("couch_%d" % multiplayer.get_unique_id())
	if couch == null:
		return
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	couch.global_position = global_position + fwd * 2.5
	if couch.has_method("request_mount"):
		couch.request_mount.rpc_id(1)

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

# 金币（M2 怪物掉落奖励，M3 商人消费）
var gold := 0
signal gold_changed(total: int)

## M4：经验与等级（服务器权威，客户端经 sync_experience 同步）
var level := 1
var experience := 0 # 当前等级内已积累的经验（满级后封顶）
signal level_changed(new_level: int)
signal experience_changed(current: int, needed: int)

## M5：职业（服务器权威，客户端经 sync_class 同步；空字符串 = 尚未选择）
var player_class := ""
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
	if not multiplayer.has_multiplayer_peer() or not is_multiplayer_authority():
		return

	# M19：乘坐载具时本体位置由自己按座位跟随（沙发位置由 Synchronizer 同步），
	# 禁用自身移动/重力/攻击，保持 Idle 姿态
	if mounted_vehicle != null:
		velocity = Vector3.ZERO
		global_position = mounted_vehicle.global_position \
				+ mounted_vehicle.get_seat_offset(mounted_seat)
		# 角色朝向 = 飞行器朝向（用户要求：上车后不再随鼠标转角色）
		rotation.y = mounted_vehicle.rotation.y
		return

	# 死亡后冻结一切输入（表现层播 Fall 动画），直到释放灵魂回村复活
	if not attribute_set.is_alive():
		velocity.x = 0
		velocity.z = 0
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

	# ===== M18b-2：步兵冲刺（dash_cancel——打断攻击/拾取，0.18s 高速位移）=====
	var now_msec := Time.get_ticks_msec()
	if Input.is_action_just_pressed("dash") and player_class == INFANTRY_CLASS_ID \
			and is_on_floor() and now_msec >= _next_dash_msec \
			and not should_freeze and attribute_set.is_alive():
		_next_dash_msec = now_msec + DASH_COOLDOWN_MSEC
		_dash_until_msec = now_msec + DASH_DURATION_MSEC
		# 冲刺方向 = 当前移动输入方向；无输入时沿面朝方向突进
		var dash_input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		var dash_dir := transform.basis * Vector3(dash_input.x, 0, dash_input.y)
		dash_dir = dash_dir.rotated(Vector3.UP, _spring_arm_offset.rotation.y)
		_dash_direction = dash_dir.normalized() if dash_dir.length() > 0.1 \
				else -_body.global_transform.basis.z
		is_attacking = false # dash_cancel：挥砍被闪避打断
		is_collecting = false
		_last_requested_animation = &""
		_request_animation(&"Dodge", true) # M18b-3：KayKit 侧播 Dodge_Forward
		SfxManager.play(&"dash") # M18b-5：冲刺破空声（roguelite dash.ogg）
		SfxManager.spawn_effect("res://scenes/vfx/swing_dust.tscn", global_position)

	# ===== M18b-2：盾墙格挡（按住右键；变化才上报，服务器记权威副本）=====
	var want_block := Input.is_action_pressed("block") and player_class == INFANTRY_CLASS_ID \
			and is_on_floor() and not is_attacking and not should_freeze and attribute_set.is_alive()
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
		velocity.x = 0
		velocity.z = 0
		_apply_gravity(delta)
		move_and_slide()
		return

	if should_freeze:
		_freeze()
		_apply_gravity(delta)
		move_and_slide()
		_request_animation(_body.get_movement_animation(velocity))
		return

	if Input.is_action_just_pressed("pickup") and is_on_floor() and _has_collectible_item_in_front():
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

	# 有目标时由 _unhandled_input 的战斗逻辑接管攻击；无目标时空挥一刀（纯动画）
	if Input.is_action_just_pressed("attack") and is_on_floor() and current_target_path.is_empty():
		_start_attack()
		return

	if is_on_floor():
		# M15：落地粒子——从空中回到地面的一瞬（was_airborne 标志由空中分支设置）
		if _was_airborne:
			_was_airborne = false
			SfxManager.spawn_effect("res://scenes/vfx/land_particles.tscn", global_position)
		can_double_jump = true
		has_double_jumped = false

		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
			can_double_jump = true
			_was_airborne = true
			_request_animation(&"Jump", true)
			SfxManager.play(&"jump")
			SfxManager.spawn_effect("res://scenes/vfx/jump_particles.tscn", global_position)
	else:
		_was_airborne = true
		_apply_gravity(delta)

		if can_double_jump and not has_double_jumped and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
			has_double_jumped = true
			can_double_jump = false
			_was_airborne = true
			_request_animation(&"Jump2", true)
			SfxManager.play(&"jump")
			SfxManager.spawn_effect("res://scenes/vfx/jump_particles.tscn", global_position)

	_move()
	# M18b-2：冲刺速度覆盖（优先级高于普通/疾跑移速）
	if dashing:
		velocity.x = _dash_direction.x * DASH_SPEED
		velocity.z = _dash_direction.z * DASH_SPEED
	var collided = move_and_slide()
	if collided:
		_push_collided_items()

	_request_animation(_body.get_movement_animation(velocity))
	_update_combat(delta)
	_update_footsteps(delta)


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
		moving = is_on_floor() \
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


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var gravity_multiplier = FALL_GRAVITY_MULTIPLIER if velocity.y < 0 else 1.0
	velocity.y -= gravity * gravity_multiplier * delta


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
		SfxManager.play(&"swing")
	elif base_state == &"Kick":
		_request_animation(base_state, true, ATTACK_ANIM_SPEED)
		SfxManager.play(&"heavy_punch")
	else:
		_request_animation(base_state, true, ATTACK_ANIM_SPEED)
		# M18b-6：步兵人形的挥剑声由动画轨道触发 AttackAudio（fire-slash，原版唯一声源），
		# 代码不再叠加 swing，保持与 roguelite 原版一致
		if not (_body is Body and _body.use_alt_body):
			SfxManager.play(&"swing")
	# 挥击尘光：模型正面（body 局部 +Z，见 4.2 朝向约定）前方约 1 米、胸口高度
	# （纯表现，各端独立触发）
	var forward: Vector3 = _body.global_transform.basis.z
	SfxManager.spawn_effect("res://scenes/vfx/swing_dust.tscn", global_position + forward * 1.0 + Vector3.UP * 1.0)


func _start_attack() -> void:
	if is_attacking or is_collecting or not is_on_floor():
		return
	is_attacking = true
	velocity.x = 0
	velocity.z = 0
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
	sync_animation_state.rpc(state, _animation_sequence, speed)
	sync_animation_state(state, _animation_sequence, speed)


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
	velocity.x = 0
	velocity.z = 0
	_current_speed = 0
	_request_animation(&"Idle")


func _move() -> void:
	var input_direction: Vector2 = Vector2.ZERO
	if is_multiplayer_authority():
		input_direction = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	var direction: Vector3 = transform.basis * Vector3(input_direction.x, 0, input_direction.y).normalized()

	_is_running()
	# M18b-2：盾墙格挡移速减半
	if is_blocking:
		_current_speed *= BLOCK_SPEED_FACTOR
	direction = direction.rotated(Vector3.UP, _spring_arm_offset.rotation.y)

	if direction:
		velocity.x = direction.x * _current_speed
		velocity.z = direction.z * _current_speed
		_body.apply_rotation(velocity)
		return

	velocity.x = move_toward(velocity.x, 0, _current_speed)
	velocity.z = move_toward(velocity.z, 0, _current_speed)


func _is_running() -> bool:
	if Input.is_action_pressed("shift"):
		_current_speed = SPRINT_SPEED
		return true
	_current_speed = NORMAL_SPEED
	return false


func _check_out_of_bounds():
	if global_transform.origin.y < -15.0:
		_reset_position_after_fall()


func _reset_position_after_fall():
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


func set_player_skin(skin_name: SkinColor) -> void:
	var texture = _get_texture_from_name(skin_name)

	_set_mesh_texture(_bottom_mesh, texture)
	_set_mesh_texture(_chest_mesh, texture)
	_set_mesh_texture(_face_mesh, texture)
	_set_mesh_texture(_limbs_head_mesh, texture)


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
	else:
		sync_inventory_to_owner.rpc_id(owner_id, player_inventory.to_dict())


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
	var object_node = get_node_or_null("/root/Level/Environment/ItemContainer")
	if object_node:
		for n in object_node.get_children():
			if n.name == object_name and n is RigidBody3D:
				n.apply_force(normal * 100)


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
	attribute_set.stats_changed.connect(_on_attribute_stats_changed) # M5：装备/增益导致攻防变化
	# M14：开局默认战士（用户选定）——否则 2/3/4 技能槽因未选职业全部静默失效；
	# 职业训练师处仍可换。走 request_choose_class 正常链路（配属性+广播+绑技能栏）。
	# M18b-1 修复：默认打上 meta 标记——level._add_player 依据它仍弹出职业选择界面
	# （否则弹窗条件 is_empty 永远为假，玩家一辈子见不到选职业界面）。手动选职业后清除。
	if multiplayer.is_server() and player_class.is_empty():
		request_choose_class(DEFAULT_CLASS_ID)
		set_meta("auto_defaulted_class", true)
	# M15：本地玩家生成专属伙伴（单机表现实体，挂 level 场景不进多人同步）
	if is_multiplayer_authority():
		call_deferred("_spawn_partner")
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


@rpc("authority", "call_local", "reliable")
func sync_experience(new_level: int, current_exp: int) -> void:
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


@rpc("authority", "call_local", "reliable")
func sync_player_gold(total: int) -> void:
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
	# M19：X 召唤/收回专属沙发飞行器（WoW 坐骑键式）
	if event.is_action_pressed("mount"):
		if mounted_vehicle != null:
			mounted_vehicle.request_dismount.rpc_id(1)
		else:
			_summon_mount()
		return
	if event.is_action_pressed("attack"):
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
		SfxManager.play(SKILL_SFX[skill_id])


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
	if player_class == INFANTRY_CLASS_ID and skill_id == "basic_attack":
		var adv := _advance_combo(_server_combo_index, _server_combo_last_msec, now)
		_server_combo_index = adv[0]
		_server_combo_last_msec = adv[1]
		_resolve_skill_effects(skill, target_node, INFANTRY_COMBO_MULT[_server_combo_index])
	else:
		_resolve_skill_effects(skill, target_node)


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
	var direction := (target_position - origin).normalized()
	if direction == Vector3.ZERO:
		direction = -global_transform.basis.z
	var projectile_name := "Proj_%d_%d" % [get_multiplayer_authority(), randi()]
	spawn_projectile.rpc(projectile_name, origin, direction, skill.projectile_speed, skill.range, skill.id)
	# 服务器本地实例记录攻击者，用于命中回调
	var local_projectile := _effects_root().get_node_or_null(projectile_name) as Projectile
	if local_projectile:
		local_projectile.set_attacker(self)


@rpc("authority", "call_local", "reliable")
func spawn_projectile(
	proj_name: String,
	origin: Vector3,
	direction: Vector3,
	speed: float,
	max_range: float,
	skill_id: String
) -> void:
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
@rpc("authority", "call_local", "reliable")
func despawn_projectile(proj_name: String) -> void:
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


@rpc("authority", "call_local", "reliable")
func sync_combat_heal(target_path: String, amount: int) -> void:
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


@rpc("authority", "call_local", "reliable")
func sync_combat_damage(target_path: String, amount: int, is_crit: bool, blocked: bool = false) -> void:
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


@rpc("authority", "call_local")
func sync_player_respawn(new_position: Vector3) -> void:
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
	var level_scene := get_tree().current_scene
	if level_scene and level_scene.has_method("show_chat_message"):
			level_scene.show_chat_message.rpc(
				tr("任务"), tr("完成任务【%s】！获得 %s") % [tr(quest.name), quest.get_reward_summary()], &"quest_success"
			)
	_sync_quest_state()


## 全量同步任务状态给所有客户端（接取/进度/交付后由服务器调用）
func _sync_quest_state() -> void:
	sync_quest_state.rpc(_quest_progress.duplicate(), _quests_done.duplicate())


@rpc("authority", "call_local", "reliable")
func sync_quest_state(progress: Dictionary, done: Array) -> void:
	_quest_progress.clear()
	for key in progress:
		_quest_progress[str(key)] = int(progress[key])
	_quests_done.clear()
	for quest_id in done:
		_quests_done.append(str(quest_id))
	quest_state_changed.emit()
