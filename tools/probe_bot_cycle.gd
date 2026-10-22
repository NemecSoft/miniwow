extends Node

## M20-Bot 行为环探针：实例化 level.tscn 后定时采样 bot 状态，
## 验证「接任务 → 打怪推进 → 交付 → 升级」全链路真实发生。
## 采样对象：bot 9001 / 9002（level.gd headless 自动 host + BotController 自动 spawn）。
## 成功判定：任一 bot 升级（level > 1）即提前收工；否则跑满 TOTAL_SEC。

const SAMPLE_INTERVAL := 2.0
const TOTAL_SEC := 300.0

var _elapsed := 0.0
var _last_snapshot := {}
var _done := false
var _fine_until := 10.0 ## 前 10 秒加密采样（0.5s），抓出生瞬间异常


func _ready() -> void:
	var lvl = load("res://scenes/level/level.tscn").instantiate()
	lvl.name = "Level" # 保 /root/Level 硬路径（Monsters/PlayersContainer/QuestGiver）
	# 必须挂到树根：挂在自己脚下会变成 /root/ProbeBotCycle/Level，所有 /root/Level 硬路径全废
	# _ready 期间树根还在装配子组件，直接 add_child 会报 "busy setting up children"，须 deferred
	get_tree().root.call_deferred("add_child", lvl)
	print("=== M20-Bot 行为环探针启动（%ds 采样窗口） ===" % TOTAL_SEC)


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed >= TOTAL_SEC:
		_finish(false)
		return
	var interval := 0.5 if _elapsed < _fine_until else SAMPLE_INTERVAL
	if fmod(_elapsed, interval) < delta:
		_sample()


func _sample() -> void:
	var any_level_up := false
	for bot_id in [9001, 9002]:
		var bot := get_node_or_null("/root/Level/PlayersContainer/%d" % bot_id)
		if bot == null:
			continue
		var parts: Array[String] = []
		parts.append("lv%d(%dexp)" % [bot.level, bot.experience])
		if bot.level > 1:
			any_level_up = true
		var quests: Array[String] = []
		for quest in QuestDatabase.get_all_quests():
			var st: String = bot.get_quest_status(quest.id)
			if st == "done":
				quests.append("%s:已完成" % quest.id)
				continue
			if st == "active" or st == "ready":
				quests.append("%s:%s %d/%d" % [quest.id, st, bot.get_quest_count(quest.id), quest.required_count])
		if quests.is_empty():
			parts.append("无进行中任务")
		else:
			parts.append(" | ".join(quests))
		var pos: Vector3 = bot.global_position
		var giver := get_node_or_null("/root/Level/Environment/QuestGiver")
		var dist_to_giver: float = pos.distance_to(giver.global_position) if giver != null else -1.0
		var vel: Vector3 = bot.velocity
		parts.append("pos(%.1f,%.1f,%.1f) v(%.1f,%.1f,%.1f) 距任务官%.0fm %s" % [
			pos.x, pos.y, pos.z, vel.x, vel.y, vel.z, dist_to_giver, "存活" if bot.attribute_set.is_alive() else "死亡"])
		print("[%4.0fs] bot%d %s" % [_elapsed, bot_id, " ".join(parts)])
		_last_snapshot[bot_id] = " ".join(parts)
	if any_level_up:
		_finish(true)


func _finish(success: bool) -> void:
	_done = true
	print("=== 采样结束（%s），最终状态 ===" % ("有 bot 升级，全链路打通" if success else "窗口内未升级"))
	for bot_id in _last_snapshot:
		print("bot%d: %s" % [bot_id, _last_snapshot[bot_id]])
	get_tree().quit(0)
