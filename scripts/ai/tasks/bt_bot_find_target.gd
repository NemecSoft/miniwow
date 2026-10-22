@tool
extends BTAction
## M20-Bot：bot 找任务目标怪节点。
## 依据黑板 target_monster_id 在 Environment/Monsters 下找最近的存活怪物，
## 写入黑板 target_node；找不到返回 FAILURE。
## 依赖：level.tscn 中怪物统一挂在 Environment/Monsters 容器下。

const MONSTERS_PATH := "/root/Level/Environment/Monsters"


func _tick(_delta: float) -> Status:
	# M20c 死亡中断：见 bt_bot_move_to.gd _is_bot_dead 注释（selector 卡分支事故）
	var agent_node: Node = agent
	if agent_node == null or not is_instance_valid(agent_node):
		return FAILURE
	var agent_attrs: Node = agent_node.get("attribute_set")
	if agent_attrs != null and not agent_attrs.is_alive():
		return FAILURE
	var monster_id := str(blackboard.get_var(&"target_monster_id", ""))
	if monster_id.is_empty():
		return FAILURE

	var bot: Node3D = agent as Node3D
	if bot == null:
		return FAILURE

	var container := bot.get_tree().current_scene.get_node_or_null(MONSTERS_PATH)
	if container == null:
		return FAILURE

	# M24 目标迟滞：已有目标仍有效（同 monster_id、活着、15m 内）就沿用——
	# 否则狼群游荡时"最近怪"频繁换人，bot 在目标间震荡，永远差一步进攻击圈
	# （headless 实测：4 bot 抱团 90s 追狼零伤害，位置来回摆动）
	if blackboard.has_var(&"target_node"):
		var current: Node3D = blackboard.get_var(&"target_node", null)
		if current != null and is_instance_valid(current) \
				and str(current.get("monster_id")) == monster_id:
			var cattrs: Node = current.get("attribute_set")
			if cattrs != null and cattrs.is_alive() \
					and bot.global_position.distance_to(current.global_position) < 15.0:
				return SUCCESS

	var best: Node3D = null
	var best_dist := INF
	for child in container.get_children():
		if str(child.get("monster_id")) != monster_id:
			continue
		var attr_set: Node = child.get("attribute_set")
		if attr_set == null or not attr_set.is_alive():
			continue
		var dist: float = bot.global_position.distance_to(child.global_position)
		if dist < best_dist:
			best_dist = dist
			best = child

	if best == null:
		return FAILURE
	blackboard.set_var(&"target_node", best)
	return SUCCESS


func _generate_name() -> String:
	return "BotFindTarget %s" % [LimboUtility.decorate_var(&"target_monster_id")]
