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
## M19-DM：巴巴婶婶的对话资源（Dialogue Manager .dialogue，编辑器导入为 .tres）
const DIALOGUE_RESOURCE: DialogueResource = preload("res://assets/dialogue/villager_auntie.dialogue")

@onready var anim_player: AnimationPlayer = $Model/AnimationPlayer
@onready var interact_prompt: Label3D = $InteractPrompt


## M43 性能：缓存玩家容器与本地玩家引用。
## 原实现每帧两次绝对路径 get_node_or_null("/root/Level/PlayersContainer")——
## 10 个村民 = 每秒 1200 次路径解析，纯为显示一个"按 E 交谈"提示，属于白烧 CPU。
## 容器由本地玩家进树事件刷新；本地玩家对象有效性靠 is_instance_valid 兜底。
var _players_container: Node = null
var _local_player: Node3D = null


func _ready() -> void:
	add_to_group("villagers")
	if interact_prompt:
		interact_prompt.visible = false
	if anim_player and anim_player.has_animation(ANIM_IDLE_TALKING):
		anim_player.play(ANIM_IDLE_TALKING)
	_bind_local_player()


## 缓存 PlayerContainer 与本地玩家；玩家上下线时由容器信号重取
func _bind_local_player() -> void:
	_players_container = get_node_or_null("/root/Level/PlayersContainer")
	if _players_container == null:
		return
	if not _players_container.child_entered_tree.is_connected(_on_players_changed):
		_players_container.child_entered_tree.connect(_on_players_changed)
	if not _players_container.child_exiting_tree.is_connected(_on_players_changed):
		_players_container.child_exiting_tree.connect(_on_players_changed)
	_on_players_changed(null)


func _on_players_changed(_node = null) -> void:
	if _players_container == null or not is_instance_valid(_players_container):
		_players_container = null
		_local_player = null
		return
	if not multiplayer.has_multiplayer_peer():
		_local_player = null
		return
	_local_player = _players_container.get_node_or_null(str(multiplayer.get_unique_id())) as Node3D


## M12：本地玩家 3 米内显示"按 E 交谈"头顶提示（世界空间，不动 UI 层）
func _physics_process(_delta: float) -> void:
	if interact_prompt == null:
		return
	var near := false
	if _local_player != null and is_instance_valid(_local_player):
		near = global_position.distance_to(_local_player.global_position) <= INTERACT_RANGE
	elif _players_container == null or not is_instance_valid(_players_container):
		# 容器可能晚于村民就绪（关卡加载顺序），低频重试绑定即可
		_bind_local_player()
	interact_prompt.visible = near


## M12：玩家按 E 交谈——播一次 Interact（挥手），播完自动回 Idle_Talking
func say_hello() -> void:
	if anim_player == null or not anim_player.has_animation(ANIM_INTERACT):
		return
	# AnimationFinished 里直接切待机（一次性动画播完自动回，不用计时器）
	if not anim_player.animation_finished.is_connected(_on_hello_finished):
		anim_player.animation_finished.connect(_on_hello_finished)
	anim_player.play(ANIM_INTERACT)


## M19-DM：E 键触发 NPC 对话（Dialogue Manager 4.1.0）。
## 先播挥手动画，再弹默认 balloon；鼠标/输入冻结由 level.gd 经
## DialogueManager.dialogue_started/dialogue_ended 信号统一管理。
func start_dialogue() -> void:
	say_hello()
	if DIALOGUE_RESOURCE == null:
		push_warning("[villager] 对话资源缺失")
		return
	DialogueManager.show_dialogue_balloon(DIALOGUE_RESOURCE, "start")


## M12：彩蛋——聊天指令 /dance 时村民一起跳
func dance() -> void:
	if anim_player == null or not anim_player.has_animation(ANIM_DANCE):
		return
	anim_player.play(ANIM_DANCE)


func _on_hello_finished(anim_name: StringName) -> void:
	if anim_name == ANIM_INTERACT and anim_player.has_animation(ANIM_IDLE_TALKING):
		anim_player.play(ANIM_IDLE_TALKING)
