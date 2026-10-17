extends Node

## M4 自动化测试（以独立测试场景方式运行，保证 autoload 单例可用）：
## host 一个真实 level 场景，验证 击杀经验 / 升级成长 / 满级封顶 / 任务接取-进度-交付全链 / 前置锁定。
## 运行方式：godot --headless --path . res://tools/test_m4.tscn

var _failures: Array[String] = []


func _ready() -> void:
	var level_scene := load("res://scenes/level/level.tscn") as PackedScene
	if level_scene == null:
		_fail("无法加载 level.tscn")
		_report()
		return
	var level := level_scene.instantiate()
	# 必须挂到场景树根下并保持场景原名 "Level"：
	# monster.gd 的 _get_player_nodes() 与伤害飘字都按 /root/Level/... 绝对路径查找。
	# _ready() 期间场景树仍在搭建，直接 add_child 到 root 会被拒，用 call_deferred。
	get_tree().root.call_deferred("add_child", level)
	await get_tree().process_frame
	# headless 下模板的 start_host/_add_player 都会跳过本地(peer 1)玩家，
	# 这里手动实例化玩家挂进 PlayersContainer，等价于 host 玩家
	var players_container := level.get_node_or_null("PlayersContainer") as Node3D
	if players_container == null:
		_fail("找不到 PlayersContainer")
		_report()
		return
	var player_scene := load("res://scenes/level/player.tscn") as PackedScene
	if player_scene == null:
		_fail("无法加载 player.tscn")
		_report()
		return
	var player_instance := player_scene.instantiate() as Character
	player_instance.name = "1"
	players_container.add_child(player_instance, true)
	player_instance.nickname.text = "Tester"
	for i in range(30):
		await get_tree().process_frame
	var player := players_container.get_node_or_null("1") as Character
	if player == null:
		_fail("玩家未生成")
		_report()
		return

	var attrs := player.attribute_set
	var monsters := level.get_node_or_null("Environment/Monsters") as Node3D
	if monsters == null:
		_fail("找不到 Monsters 容器")
		_report()
		return

	# ===== 1. 初始状态 =====
	_check("初始等级 Lv.1", player.level == 1, "实际 level=%d" % player.level)
	_check("初始经验 0", player.experience == 0)
	_check("升到 Lv2 需要 80 经验", LevelData.exp_to_next(1) == 80)

	# ===== 2. 击杀经验（用野猪测，三只狼留给任务）=====
	_kill_monster(monsters, "Boar1")
	await get_tree().process_frame
	_check("击杀野猪获得 15 经验", player.experience == 15, "实际 exp=%d" % player.experience)

	# ===== 3. 任务接取与进度 =====
	_check("未接任务时 q1 可接", player.get_quest_status("q1_wolf_hunt") == "available")
	_check("q6 因前置未完成被锁定", player.get_quest_status("q6_golem_hunt") == "locked")
	player.request_accept_quest("q1_wolf_hunt")
	await get_tree().process_frame
	_check("接取 q1 后进行中", player.get_quest_status("q1_wolf_hunt") == "active")
	_check("q1 初始进度 0", player.get_quest_count("q1_wolf_hunt") == 0)
	_kill_monster(monsters, "Wolf1")
	await get_tree().process_frame
	_check("杀第 1 只狼后进度 1/3", player.get_quest_count("q1_wolf_hunt") == 1, "实际 %d" % player.get_quest_count("q1_wolf_hunt"))
	_kill_monster(monsters, "Boar2") # 错误目标：不应推进
	await get_tree().process_frame
	_check("击杀野猪不推进狼任务", player.get_quest_count("q1_wolf_hunt") == 1)
	_kill_monster(monsters, "Wolf2")
	await get_tree().process_frame
	_check("杀第 2 只狼后进度 2/3", player.get_quest_count("q1_wolf_hunt") == 2, "实际 %d" % player.get_quest_count("q1_wolf_hunt"))
	_kill_monster(monsters, "Wolf3")
	await get_tree().process_frame
	_check("杀第 3 只狼后进度 3/3", player.get_quest_count("q1_wolf_hunt") == 3)
	_check("q1 目标完成可交付", player.get_quest_status("q1_wolf_hunt") == "ready")

	# ===== 4. 交付奖励 =====
	var gold_before := player.gold
	player.request_turn_in_quest("q1_wolf_hunt")
	await get_tree().process_frame
	_check("交付 q1 后标记完成", player.get_quest_status("q1_wolf_hunt") == "done")
	_check("交付 q1 得 20 金币", player.gold == gold_before + 20, "实际 gold=%d" % player.gold)
	_check("交付 q1 得 100 经验", player.experience == 86, "实际 exp=%d（166 总经验 - 80 升级消耗）" % player.experience)
	_check("交付 q1 后升到 Lv.2", player.level == 2, "实际 level=%d" % player.level)
	_check("q2 前置满足可接", player.get_quest_status("q2_boar_hunt") == "available")

	# ===== 5. 升级成长 =====
	var exp_before := player.experience
	var level_before := player.level
	player.add_experience(500)
	await get_tree().process_frame
	_check("大量经验后升级", player.level > level_before, "Lv.%d -> Lv.%d" % [level_before, player.level])
	# M14：开局默认战士——成长基于职业基础（战士 max_hp 160 / atk 14）
	var expected_max_hp := 160 + (player.level - 1) * 25
	_check("升级后生命上限成长 战士160+25/级", attrs.max_hp == expected_max_hp, "实际 max_hp=%d" % attrs.max_hp)
	var expected_atk := 14 + (player.level - 1) * 3 + 2 # +2 新手铁剑
	_check("升级后攻击成长 战士14+3/级", attrs.atk == expected_atk, "实际 atk=%d" % attrs.atk)
	_check("升级满血", attrs.hp == attrs.max_hp)

	# ===== 6. 满级封顶 =====
	player.add_experience(999999)
	await get_tree().process_frame
	_check("满级 Lv.10", player.level == 10, "实际 level=%d" % player.level)
	_check("满级后经验封顶 0", player.experience == 0, "实际 exp=%d" % player.experience)
	_check("满级 exp_to_next=0", LevelData.exp_to_next(10) == 0)

	# ===== 7. 任务数据完整性 =====
	var quest_dir := DirAccess.open("res://resources/quests")
	if quest_dir == null:
		_fail("无法打开 resources/quests")
	else:
		var quest_count := 0
		for file_name in quest_dir.get_files():
			if not file_name.ends_with(".tres"):
				continue
			var quest := load("res://resources/quests/" + file_name) as QuestData
			if quest == null:
				_fail("任务数据加载失败: " + file_name)
				continue
			quest_count += 1
			if not quest.target_monster_id.is_empty() and load("res://resources/monsters/%s.tres" % quest.target_monster_id) == null:
				_fail("%s 目标怪物 '%s' 不存在" % [file_name, quest.target_monster_id])
			if not quest.reward_item_id.is_empty() and ItemDatabase.get_item(quest.reward_item_id) == null:
				_fail("%s 奖励物品 '%s' 不存在" % [file_name, quest.reward_item_id])
		if _failures.is_empty():
			print("PASS | %d 个任务数据全部有效" % quest_count)

	_report()


func _kill_monster(monsters: Node3D, monster_name: String) -> void:
	var monster := monsters.get_node_or_null(monster_name) as Monster
	if monster == null:
		_fail("找不到怪物 " + monster_name)
		return
	monster.apply_combat_damage(99999, 1, false)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS | %s" % label)
	else:
		_fail("%s%s" % [label, (" | " + detail) if not detail.is_empty() else ""])


func _fail(message: String) -> void:
	_failures.append(message)
	print("FAIL | %s" % message)


func _report() -> void:
	if _failures.is_empty():
		print("test_m4: 全部通过")
		get_tree().quit(0)
	else:
		print("test_m4: %d 项失败" % _failures.size())
		get_tree().quit(1)
