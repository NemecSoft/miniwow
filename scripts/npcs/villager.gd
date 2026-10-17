class_name Villager
extends CharacterBody3D

## MiniWoW 村民 NPC（M12）：巴巴婶婶。
## 使用 Quaternius 通用模型 + Universal Animation Library Standard 动画库（CC0），
## 动画与机器人骨骼不兼容，故走原生模型（设计文档 5.8）。
## 静态、不可被打、无 AI；level.gd 检测 3 米内"按 E 交谈"，
## 交谈时播 Interact（挥手）一次后回待机。

## 导入后动画名（glb 导入去掉 _Loop 后缀，见探针 probe_villager）
const ANIM_IDLE_TALKING := &"Idle_Talking"
const ANIM_INTERACT := &"Interact"
const ANIM_DANCE := &"Dance"
const INTERACT_RANGE := 3.0

@onready var anim_player: AnimationPlayer = $Model/AnimationPlayer
@onready var interact_prompt: Label3D = $InteractPrompt


func _ready() -> void:
	add_to_group("villagers")
	if interact_prompt:
		interact_prompt.visible = false
	if anim_player and anim_player.has_animation(ANIM_IDLE_TALKING):
		anim_player.play(ANIM_IDLE_TALKING)


## M12：本地玩家 3 米内显示"按 E 交谈"头顶提示（世界空间，不动 UI 层）
func _physics_process(_delta: float) -> void:
	if interact_prompt == null:
		return
	var near := false
	if multiplayer.has_multiplayer_peer() and is_inside_tree():
		var players_container := get_node_or_null("/root/Level/PlayersContainer")
		if players_container:
			var local := players_container.get_node_or_null(str(multiplayer.get_unique_id())) as Node3D
			near = local != null and global_position.distance_to(local.global_position) <= INTERACT_RANGE
	interact_prompt.visible = near


## M12：玩家按 E 交谈——播一次 Interact（挥手），播完自动回 Idle_Talking
func say_hello() -> void:
	if anim_player == null or not anim_player.has_animation(ANIM_INTERACT):
		return
	# AnimationFinished 里直接切待机（一次性动画播完自动回，不用计时器）
	if not anim_player.animation_finished.is_connected(_on_hello_finished):
		anim_player.animation_finished.connect(_on_hello_finished)
	anim_player.play(ANIM_INTERACT)


## M12：彩蛋——聊天指令 /dance 时村民一起跳
func dance() -> void:
	if anim_player == null or not anim_player.has_animation(ANIM_DANCE):
		return
	anim_player.play(ANIM_DANCE)


func _on_hello_finished(anim_name: StringName) -> void:
	if anim_name == ANIM_INTERACT and anim_player.has_animation(ANIM_IDLE_TALKING):
		anim_player.play(ANIM_IDLE_TALKING)
