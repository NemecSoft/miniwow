@tool
extends BTAction
## M20-Bot：bot 复活节点。调 request_respawn() 后立即 SUCCESS。
## 由 BTCheckBotState(dead) 分支的上层 Sequence 调用。

func _tick(_delta: float) -> Status:
	var bot: Node = agent
	if bot == null:
		return FAILURE
	# M24：好感度结算——协作中阵亡 = "一起做任务失败"，按性格对玩家加厌恶
	RelationshipManager.on_bot_died(bot)
	bot.request_respawn()
	RelationshipManager.clear_dead(bot.get_multiplayer_authority())
	return SUCCESS


func _generate_name() -> String:
	return "BotRespawn"
