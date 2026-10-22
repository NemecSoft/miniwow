@tool
extends BTAction
## M20-Bot：bot 任务官交互节点（接取/交付）。
## 先校验与任务官距离（interact_radius），再调 request_accept_quest /
## request_turn_in_quest（服务器本地调用，sender==0 过权威检查）。
## 任务官节点路径：level.tscn 的 Environment/QuestGiver。

const QUEST_GIVER_PATH := "/root/Level/Environment/QuestGiver"

## accept = 接取黑板 quest_id；turn_in = 交付黑板 quest_id
@export var action: String = "accept"
@export var interact_radius: float = 3.5


func _tick(_delta: float) -> Status:
	var bot: Node3D = agent as Node3D
	if bot == null:
		return FAILURE
	# M20c 死亡中断：见 bt_bot_move_to.gd _is_bot_dead 注释（selector 卡分支事故）
	var attr_set: Node = bot.get("attribute_set")
	if attr_set != null and not attr_set.is_alive():
		return FAILURE
	var quest_id := str(blackboard.get_var(&"quest_id", ""))
	if quest_id.is_empty():
		return FAILURE

	var giver := bot.get_tree().current_scene.get_node_or_null(QUEST_GIVER_PATH)
	if giver == null:
		return FAILURE
	if bot.global_position.distance_to(giver.global_position) > interact_radius:
		return FAILURE # 还没走到位，由上层 MoveTo 负责

	match action:
		"accept":
			bot.request_accept_quest(quest_id)
		"turn_in":
			bot.request_turn_in_quest(quest_id)
		_:
			return FAILURE
	return SUCCESS


func _generate_name() -> String:
	return "BotQuest:%s" % action
