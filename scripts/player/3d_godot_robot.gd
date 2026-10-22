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
	# M29：骑乘坐姿（Sitting_Idle 烘焙）——循环播放
	&"Sit": preload("res://assets/animations/retarget/sit_idle.tres"),
}

## M18b-3：KayKit 备用视觉的 AnimationPlayer（InfantryVisual/VisualRoot/Mannequin/AnimationPlayer）
var _alt_animation_player: AnimationPlayer = null

## M29：KayKit 侧骨骼重定向动画（Sitting_Idle 烘焙到 GamedevTV 骨架，
## 轨道路径 Rig_Medium/Skeleton3D:*，与 infantry_mannequin.tscn 结构一致）
const ALT_RETARGET_ANIMS := {
	&"Sit": preload("res://assets/animations/retarget/sit_idle_kaykit.tres"),
}

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
		# M29：烘焙产出的 Animation 资源未带循环标记，坐姿需循环播放
		if lib.has_animation(&"Sit"):
			lib.get_animation(&"Sit").loop_mode = Animation.LOOP_LINEAR
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
				# M29：注入 KayKit 坐姿动画并设循环
				for anim_name in ALT_RETARGET_ANIMS:
					if not alt_lib.has_animation(anim_name):
						alt_lib.add_animation(anim_name, ALT_RETARGET_ANIMS[anim_name])
						alt_lib.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
			_alt_animation_player.animation_finished.connect(
				func(anim_name: StringName) -> void: body_animation_finished.emit(anim_name)
			)
		_apply_body_visibility()


func _apply_body_visibility() -> void:
	if alt_visual != null:
		alt_visual.visible = use_alt_body
		# 【M47 朝向】两套模型的"正面"相反：
		#   GodotRobot3D 模型正面 = 局部 +Z（上层 apply_rotation 按这个写）
		#   KayKit Mannequin 正面 = 局部 -Z（Godot 标准）
		# 不统一的话，步兵形态下会**倒着走**（实测：人往远处跑，画面里却看到正脸）。
		# 在视觉根节点上转 180° 是最小改动：上层所有"用 basis.z 当脸"的逻辑
		# 一行都不用分支，两套模型从此语义一致。
		if use_alt_body:
			alt_visual.rotation.y = PI
	# GodotRobot 机器人骨架（含装备挂点）——步兵模式整体隐藏
	var armature := get_node_or_null("RobotArmature")
	if armature != null:
		armature.visible = not use_alt_body


## M48 正解：方向 → body 局部 rotation.y。
##
## 【事故】旧实现 = atan2(v.x, v.z) 求"世界水平 yaw"，再减父节点 basis.get_euler().y。
## 这套公式只在"父节点绕世界 Y 轴旋转"时成立：平面地图成立，**球面不成立**。
## 玩家站在赤道时当地法线 ≈ 世界 +X，他的"前后左右"落在世界 YZ 平面里，
## atan2(v.x, v.z) 算出来的根本不是他眼里的朝向。
## 实测偏差达 142°（tools/m48_body_probe.gd 的 ORI 行：
##   ORI[9002|W0]: |vh|=3.295 v_yaw=+99.7° bodyYaw=-118.0° 差=+142.3°）
## —— 用户"方向也不对"就是它。
##
## 【零推导做法】body 的局部 +Z 就是模型正面，而父节点 basis 已经是当地坐标系
## （Y = 当地法线，由 Planet.align_basis 建立）。把方向投影到父节点的切平面后，
## 在父节点自己的 x / z 轴上分解即可：
##     rotation.y = atan2(t·px, t·pz)
## 平面地图下父 basis 退化为单位基 → 公式等价于旧的 atan2(v.x, v.z)，零回归。
## 玩家根带 π 旋转、怪物根为 0 这类差异也自动消化（用的是完整 basis 而非 yaw）。
func _local_yaw_for(direction: Vector3) -> float:
	# M37：NaN 闸——非有限方向会把 NaN 写进 rotation.y
	if not (is_finite(direction.x) and is_finite(direction.y) and is_finite(direction.z)):
		return NAN
	var parent := get_parent() as Node3D
	if parent == null:
		return NAN
	var pb := parent.global_transform.basis.orthonormalized()
	# 去掉沿当地法线的分量：速度的径向分量（爬坡、落地冲量）不该改朝向
	var t := direction - pb.y * direction.dot(pb.y)
	if t.length_squared() < 1e-8:
		return NAN
	t = t.normalized()
	var yaw := atan2(t.dot(pb.x), t.dot(pb.z))
	return yaw if is_finite(yaw) else NAN


func apply_rotation(velocity: Vector3) -> void:
	var target := _local_yaw_for(velocity)
	if is_nan(target):
		return
	# M18b-3：alt_visual 是本节点子节点，跟随旋转，无需分支。
	rotation.y = lerp_angle(rotation.y, target, LERP_VELOCITY)


## M29b：骑乘中身体朝向硬对齐（无 lerp 平滑）——apply_rotation 的渐进平滑在
## 上座瞬间表现为"角色慢慢拧过去"（用户实测：上坐骑还是会改方向），
## 骑乘朝向必须立即到位。direction 语义与 apply_rotation 一致（模型 +Z 面朝它）。
func snap_rotation_to(direction: Vector3) -> void:
	var target := _local_yaw_for(direction)
	if is_nan(target):
		return
	rotation.y = target


## M29b：当前动画状态名（player.gd 骑乘分支判断 Sit 是否被其他动画打断用）
func current_state() -> StringName:
	return _current_state


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
