extends Node3D

## M15：Plush 伙伴"小跟班"（设计文档 5.10）。
## 纯表现单机实体：不进多人同步（不在 PlayersContainer，各端玩家有自己的伙伴）、
## 不可被打、无碰撞（直接 lerp 位置，不走物理）。
## 跟随规则：距离 <2.5 米待机；2.5~6 米步行；6~12 米奔跑；>15 米瞬移兜底。

const PARTNER_SCENE := "res://scenes/npcs/partner.tscn"
## M16b 修正：glb 内部没有任何材质，COLOR_0 顶点色方案无效（贴出来仍是白的）——
## 原始配色其实靠 Jeheno 包里的贴图。改用官方 ShaderMaterial
## （albedo+normal 贴图，godot_plush.gdshader 带菲涅尔边缘光）覆盖全部 surface。
const PLUSH_MAT := preload("res://assets/characters/partner/plush_mat.tres")
## 跟随距离阈值（米）
const DIST_IDLE := 2.5
const DIST_WALK := 6.0
const DIST_TELEPORT := 15.0
## 移动速度（米/秒），与动画节奏匹配
const WALK_SPEED := 2.6
const RUN_SPEED := 5.5
## 位置/朝向平滑系数
const LERP_POS := 6.0
const LERP_YAW := 8.0
## 交互提示显示距离
const INTERACT_RANGE := 3.0

## 动画名（探针 probe_plush 实测：AnimationPlayer 在根级，小写无前缀）
const ANIM_IDLE := &"idle"
const ANIM_WALK := &"walk"
const ANIM_RUN := &"run"
const ANIM_WAVE := &"wave"

var owner_player: CharacterBody3D
var _is_waving := false

# AnimationPlayer 在 glb 实例内部（Plush/glb 根/AnimationPlayer），非本节点直接子级
@onready var anim_player: AnimationPlayer = $Plush/AnimationPlayer
@onready var interact_prompt: Label3D = $InteractPrompt


func _ready() -> void:
	add_to_group("partners")
	_apply_plush_material()
	if anim_player and anim_player.has_animation(ANIM_IDLE):
		anim_player.play(ANIM_IDLE)
	if anim_player and anim_player.has_animation(ANIM_WAVE):
		anim_player.get_animation(ANIM_WAVE).loop_mode = Animation.LOOP_NONE
	# 模型自带 Y 立方体型，缩放到与机器人协调的高度（约 0.9 米）
	scale = Vector3.ONE * 0.9


func _apply_plush_material() -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for surface in mi.mesh.get_surface_count():
			mi.set_surface_override_material(surface, PLUSH_MAT)


func _physics_process(delta: float) -> void:
	if owner_player == null or not is_instance_valid(owner_player):
		return
	var to_player := owner_player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	_update_interact_prompt(distance)

	if _is_waving:
		return # 挥手期间原地不动

	if distance > DIST_TELEPORT:
		global_position = owner_player.global_position - to_player.normalized() * 2.0
		_play(ANIM_IDLE)
		return

	var target_speed := 0.0
	if distance > DIST_WALK:
		target_speed = RUN_SPEED
		_play(ANIM_RUN)
	elif distance > DIST_IDLE:
		target_speed = WALK_SPEED
		_play(ANIM_WALK)
	else:
		_play(ANIM_IDLE)

	if target_speed > 0.0 and distance > 0.01:
		var dir := to_player / distance
		# 直接沿方向推进 speed*delta（lerp 目标点会随距离缩短而步长趋零）
		global_position += dir * target_speed * delta
		# 面向移动方向（模型正面 +Z）
		var target_yaw := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-LERP_YAW * delta))
	else:
		# 待机时面对主人
		var target_yaw := atan2(to_player.x, to_player.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-LERP_YAW * delta))


func _update_interact_prompt(distance: float) -> void:
	if interact_prompt:
		interact_prompt.visible = distance <= INTERACT_RANGE


## 玩家按 E 打招呼：挥手一次后回待机（与 villager.say_hello 同模式）
func say_hello() -> void:
	if _is_waving:
		return
	# AnimationPlayer 缺失时直接放弃，避免 _is_waving 卡死导致跟随停摆
	if anim_player == null or not anim_player.has_animation(ANIM_WAVE):
		return
	_is_waving = true
	anim_player.play(ANIM_WAVE)
	if not anim_player.animation_finished.is_connected(_on_wave_finished):
		anim_player.animation_finished.connect(_on_wave_finished)


func _on_wave_finished(anim_name: StringName) -> void:
	if anim_name == ANIM_WAVE:
		_is_waving = false
		_play(ANIM_IDLE)


func _play(state: StringName) -> void:
	if anim_player and anim_player.has_animation(state) and anim_player.current_animation != String(state):
		anim_player.play(state)
