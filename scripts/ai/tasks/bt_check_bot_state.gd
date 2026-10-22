@tool
extends BTCondition
## M20-Bot：bot 状态查询条件节点。
## mode 决定检查内容，命中时 SUCCESS 并把相关 id 写入黑板（供后续节点使用）：
##   "dead"           —— bot 已死亡（attribute_set.is_alive() == false）
##   "quest_ready"    —— 有目标已完成待交付的任务 → 黑板 quest_id
##   "quest_available"—— 有可接取的新任务 → 黑板 quest_id
##   "quest_active"   —— 有进行中的击杀任务 → 黑板 quest_id + target_monster_id
## 其余情况 FAILURE。

enum Mode { DEAD, QUEST_READY, QUEST_AVAILABLE, QUEST_ACTIVE }

@export var mode: Mode = Mode.QUEST_ACTIVE


func _tick(_delta: float) -> Status:
	var bot: Node = agent
	if bot == null:
		return FAILURE

	match mode:
		Mode.DEAD:
			var attr_set: Node = bot.get("attribute_set")
			if attr_set != null and not attr_set.is_alive():
				return SUCCESS
			return FAILURE

		Mode.QUEST_READY:
			for quest in QuestDatabase.get_all_quests():
				if bot.get_quest_status(quest.id) == "ready":
					blackboard.set_var(&"quest_id", quest.id)
					return SUCCESS
			return FAILURE

		Mode.QUEST_AVAILABLE:
			for quest in QuestDatabase.get_all_quests():
				if bot.get_quest_status(quest.id) == "available":
					blackboard.set_var(&"quest_id", quest.id)
					return SUCCESS
			return FAILURE

		Mode.QUEST_ACTIVE:
			for quest in QuestDatabase.get_all_quests():
				if quest.objective_type != QuestData.ObjectiveType.KILL_MONSTER:
					continue
				if bot.get_quest_status(quest.id) == "active":
					blackboard.set_var(&"quest_id", quest.id)
					blackboard.set_var(&"target_monster_id", quest.target_monster_id)
					return SUCCESS
			return FAILURE

	return FAILURE


func _generate_name() -> String:
	return "BotState: %s" % ["死亡", "可交付", "可接取", "作战中"][mode]
