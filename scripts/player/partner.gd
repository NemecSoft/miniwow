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
	# M19：漂浮伙伴无互动——交互提示永久隐藏
	if interact_prompt:
		interact_prompt.visible = false
	# 模型自带 Y 立方体型，缩放到与机器人协调的高度（约 0.9 米）
	scale = Vector3.ONE * 0.5


func _apply_plush_material() -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for surface in mi.mesh.get_surface_count():
			mi.set_surface_override_material(surface, PLUSH_MAT)


## M19 漂浮模式（原神派蒙式）：小型、悬空跟随、正弦浮动、无交互
const HOVER_HEIGHT := 1.6          # 悬浮高度（玩家脚底起算）
const HOVER_SIDE := 0.9            # 右侧偏移
const HOVER_BACK := 0.8            # 后方偏移
const HOVER_AMPLITUDE := 0.12      # 上下浮动幅度
const HOVER_FREQ := 2.0            # 浮动频率
const FOLLOW_LERP := 5.0           # 位置平滑
var _hover_t := 0.0


func _physics_process(delta: float) -> void:
	if owner_player == null or not is_instance_valid(owner_player):
		return
	_hover_t += delta
	var hover_wave: float = sin(_hover_t * TAU * HOVER_FREQ) * HOVER_AMPLITUDE

	# 目标点：玩家右后上方的漂浮位（随玩家朝向旋转）
	var offset := owner_player.global_transform.basis * Vector3(HOVER_SIDE, 0, HOVER_BACK)
	var target := owner_player.global_position + Vector3(offset.x, HOVER_HEIGHT, offset.z)
	target.y += hover_wave

	# 瞬移兜底（传送/重生后快速归位）
	if global_position.distance_to(target) > 15.0:
		global_position = target
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-FOLLOW_LERP * delta))

	# 面朝主人
	var to_player := owner_player.global_position - global_position
	rotation.y = lerp_angle(rotation.y, atan2(to_player.x, to_player.z), 1.0 - exp(-8.0 * delta))

	# 漂浮时播放待机动画
	_play(ANIM_IDLE)


## M19 模型替换接口：传入新模型场景替换默认 Plush（保留漂浮/跟随行为）
func set_model(model_scene: PackedScene) -> void:
	var old := $Plush
	if old:
		old.queue_free()
	var inst := model_scene.instantiate()
	inst.name = "Plush"
	add_child(inst)
	_apply_plush_material()


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
