class_name Body
extends Node3D

## 玩家身体视觉路由（M18b-3）：
## - 默认：GodotRobot 机器人骨架（animation_player 指向其 AnimationPlayer）
## - 步兵（use_alt_body=true）：切换到 KayKit Mannequin（alt_visual，见
##   infantry_mannequin.tscn——动画库键名与 MiniWoW 动画状态同名，零映射直播）。
## player.gd 只调 play_animation_state / get_movement_animation / apply_rotation，
## 与监听 body_animation_finished 信号；本脚本内部负责两套视觉的路由。

signal body_animation_finished(anim_name: StringName)

const LERP_VELOCITY: float = 0.15

@export_category("Objects")
@export var _character: CharacterBody3D = null
@export var animation_player: AnimationPlayer = null
## M18b-3：备用视觉（KayKit 步兵人形），默认隐藏
@export var alt_visual: Node3D = null

var _current_state: StringName = &""

## M18b-3：KayKit 循环动画（Animation .res 未烘焙循环标记，运行时设置）
const ALT_LOOP_ANIMS: Array[StringName] = [&"Idle", &"Run", &"Sprint", &"Fall"]

## M16：骨骼重定向动画（Universal 库 Punch_Jab 烘焙到本骨架，见 tools/bake_retarget.gd）。
## 运行时注入默认动画库——robot_body.tscn 的动画是内嵌 sub_resource，文本改库太脆弱。
const RETARGET_ANIMS := {
	&"Strike": preload("res://assets/animations/retarget/strike_jab.tres"),
	# M16b：替换 Attack1 旋风斩的挥剑动画（Sword_Attack 烘焙）
	&"SwordSlash": preload("res://assets/animations/retarget/sword_slash.tres"),
}

## M18b-3：KayKit 备用视觉的 AnimationPlayer（InfantryVisual/VisualRoot/Mannequin/AnimationPlayer）
var _alt_animation_player: AnimationPlayer = null

## M18b-3：步兵职业切换（player.gd sync_class 处调用）
var use_alt_body := false:
	set(value):
		if use_alt_body == value:
			return
		use_alt_body = value
		_apply_body_visibility()


func _ready() -> void:
	if animation_player == null:
		return
	var lib := animation_player.get_animation_library(&"")
	if lib:
		for anim_name in RETARGET_ANIMS:
			if not lib.has_animation(anim_name):
				lib.add_animation(anim_name, RETARGET_ANIMS[anim_name])
	# M18b-3：统一动画完成信号——player.gd 只连 body_animation_finished
	animation_player.animation_finished.connect(
		func(anim_name: StringName) -> void: body_animation_finished.emit(anim_name)
	)
	# 备用视觉初始化
	if alt_visual != null:
		_alt_animation_player = alt_visual.get_node_or_null(
			"Mannequin/AnimationPlayer"
		) as AnimationPlayer
		if _alt_animation_player != null:
			var alt_lib := _alt_animation_player.get_animation_library(&"")
			if alt_lib:
				for anim_name in ALT_LOOP_ANIMS:
					if alt_lib.has_animation(anim_name):
						alt_lib.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
			_alt_animation_player.animation_finished.connect(
				func(anim_name: StringName) -> void: body_animation_finished.emit(anim_name)
			)
		_apply_body_visibility()


func _apply_body_visibility() -> void:
	if alt_visual != null:
		alt_visual.visible = use_alt_body
	# GodotRobot 机器人骨架（含装备挂点）——步兵模式整体隐藏
	var armature := get_node_or_null("RobotArmature")
	if armature != null:
		armature.visible = not use_alt_body


func apply_rotation(_velocity: Vector3) -> void:
	# 模型正面为 +Z，但本节点的 rotation 是相对父节点的局部旋转：
	# 玩家根节点带 π 旋转（怪物根为 0），直接写世界公式必有一侧反。
	# 正确做法：先求速度的世界朝向角，再减去父节点全局 yaw 换算为局部目标角。
	# M18b-3：alt_visual 是本节点子节点，跟随旋转，无需分支。
	var world_yaw := atan2(_velocity.x, _velocity.z)
	var parent_basis: Basis = get_parent().global_transform.basis
	var parent_yaw: float = parent_basis.get_euler().y
	var local_target: float = world_yaw - parent_yaw
	var new_rotation_y = lerp_angle(rotation.y, local_target, LERP_VELOCITY)
	rotation.y = new_rotation_y


func get_movement_animation(_velocity: Vector3) -> StringName:
	if not _character.is_on_floor():
		if _velocity.y < 0:
			return &"Fall"
		if _current_state == &"Jump2":
			return &"Jump2"
		return &"Jump"

	if _velocity:
		if _character._is_running() and _character.is_on_floor():
			return &"Sprint"
		return &"Run"

	return &"Idle"


func play_animation_state(state: StringName, restart: bool = false, speed: float = 1.0) -> void:
	# M18b-3：步兵模式路由到 KayKit Mannequin（动画库键名 = MiniWoW 状态名）
	if use_alt_body and _alt_animation_player != null:
		if not _alt_animation_player.has_animation(state):
			return # Jump2 等备用视觉没有的动画静默跳过
		if not restart and _current_state == state and _alt_animation_player.is_playing():
			return
		_current_state = state
		_alt_animation_player.play(state, -1, speed)
		return
	if not animation_player:
		return
	if not animation_player.has_animation(state):
		return
	if not restart and _current_state == state and animation_player.is_playing():
		return
	_current_state = state
	# M9：speed 支持加速播放（打击型 Pickup 用 2.5x；普通动画恒 1.0）
	animation_player.play(state, -1, speed)
