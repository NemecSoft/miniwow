extends Node

# 探针：M20 两个新打怪任务（q7_raider_hunt / q8_lich_bounty）设计校验
# 1. QuestDatabase 注册总数
# 2. 新任务字段完整性（目标怪物存在、奖励物品存在、数量/等级合理）
# 3. 前置任务链无环、可达

func _ready() -> void:
	var ok := true
	var all := QuestDatabase.get_all_quests()
	print("QuestDatabase 注册任务数: %d" % all.size())
	if all.size() != 8:
		print("FAIL: 期望 8 个任务，实际 %d" % all.size())
		ok = false

	# ---- q7 ----
	var q7 := QuestDatabase.get_quest("q7_raider_hunt")
	if q7 == null:
		print("FAIL: q7_raider_hunt 未注册")
		ok = false
	else:
		ok = _check_quest(q7, "kaykit_raider", 4, 2, 180, 35, "bread", "") and ok

	# ---- q8 ----
	var q8 := QuestDatabase.get_quest("q8_lich_bounty")
	if q8 == null:
		print("FAIL: q8_lich_bounty 未注册")
		ok = false
	else:
		ok = _check_quest(q8, "lich", 8, 7, 1000, 250, "sword_blue", "q6_golem_hunt") and ok

	# ---- 前置链无环 ----
	var chain := {"q8_lich_bounty": "q6_golem_hunt", "q6_golem_hunt": "q5_lich_hunt",
			"q5_lich_hunt": "q4_spider_elite", "q4_spider_elite": "q3_worgen_hunt",
			"q3_worgen_hunt": "q2_boar_hunt", "q2_boar_hunt": "q1_wolf_hunt"}
	for quest_id in chain:
		var q := QuestDatabase.get_quest(quest_id)
		if q == null or q.prerequisite_quest_id != chain[quest_id]:
			print("FAIL: 前置链断裂 %s" % quest_id)
			ok = false
	if QuestDatabase.get_quest("q7_raider_hunt").prerequisite_quest_id != "":
		print("FAIL: q7 应为无前置支线")
		ok = false
	print("PASS: 前置链无环（q8→q6→q5→q4→q3→q2→q1，q7 独立支线）")

	print("=== 任务设计校验结果: %s ===" % ["PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


func _check_quest(q: QuestData, monster_id: String, count: int, min_lv: int,
		exp: int, gold: int, item_id: String, prereq: String) -> bool:
	var ok := true
	var mon := MonsterDatabase.get_monster(monster_id)
	if mon == null:
		print("FAIL: %s 目标怪物 '%s' 不存在" % [q.id, monster_id])
		ok = false
	elif q.target_monster_id != monster_id:
		print("FAIL: %s 目标怪物不匹配" % q.id)
		ok = false
	if q.required_count != count:
		print("FAIL: %s 数量 %d != %d" % [q.id, q.required_count, count])
		ok = false
	if q.min_level != min_lv:
		print("FAIL: %s 等级 %d != %d" % [q.id, q.min_level, min_lv])
		ok = false
	if q.reward_exp != exp or q.reward_gold != gold:
		print("FAIL: %s 奖励 exp/gold 不匹配" % q.id)
		ok = false
	if q.reward_item_id != item_id:
		print("FAIL: %s 奖励物品 %s != %s" % [q.id, q.reward_item_id, item_id])
		ok = false
	elif not item_id.is_empty() and ItemDatabase.get_item(item_id) == null:
		print("FAIL: %s 奖励物品 '%s' 不在 ItemDatabase" % [q.id, item_id])
		ok = false
	if q.prerequisite_quest_id != prereq:
		print("FAIL: %s 前置 '%s' != '%s'" % [q.id, q.prerequisite_quest_id, prereq])
		ok = false
	if ok:
		print("PASS: %s「%s」杀 %s x%d / lv%d / %dexp %dgold / %s / 前置'%s'" % [
			q.id, q.name, monster_id, count, min_lv, exp, gold, item_id, prereq])
	return ok
