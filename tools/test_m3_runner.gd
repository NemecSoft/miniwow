extends Node

## M3 自动化测试（以独立测试场景方式运行，保证 autoload 单例可用）：
## host 一个真实 level 场景，验证 装备加成 / 购买 / 出售 / 消耗品 / 穿卸重算 / 掉落表数据。
## 运行方式：godot --headless --path . res://tools/test_m3.tscn

var _failures: Array[String] = []


func _ready() -> void:
	var level_scene := load("res://scenes/level/level.tscn") as PackedScene
	if level_scene == null:
		_fail("无法加载 level.tscn")
		_report()
		return
	var level := level_scene.instantiate()
	add_child(level)
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
	# 等待玩家生成
	for i in range(30):
		await get_tree().process_frame
	var player := players_container.get_node_or_null("1") as Character
	if player == null:
		print("DIAG | PlayersContainer children: %s" % str(players_container.get_children().map(func(n): return n.name)))
		_fail("玩家未生成")
		_report()
		return

	# ===== 1. 起始装备加成 =====
	var attrs = player.attribute_set
	var inventory = player.get_inventory()
	_check("新手武器自动穿上", inventory.equipped_weapon.item_id == "sword_iron")
	_check("新手帽子自动穿上", inventory.equipped_hat.item_id == "cap")
	# M14：开局默认战士——属性 = 职业基础(14/6) + 装备加成(2/1)
	_check("攻击含装备加成 战士14+2=16", attrs.atk == 16, "实际 atk=%d" % attrs.atk)
	_check("防御含装备加成 战士6+1=7", attrs.def == 7, "实际 def=%d" % attrs.def)
	_check("起始面包 3 个", inventory.get_slot(inventory.get_slot_index_of("bread")).quantity == 3)

	# ===== 2. 购买 =====
	player.add_gold(500)
	player.request_buy_item("sword_green")
	await get_tree().process_frame
	_check("购买精铁剑扣 90 金币", player.gold == 410, "实际 gold=%d" % player.gold)
	_check("精铁剑入包", inventory.get_slot_index_of("sword_green") >= 0)
	player.spend_gold(200) # 余额 210，买不起 220 的亡灵利刃
	player.request_buy_item("sword_blue")
	await get_tree().process_frame
	_check("金币不足时购买被拒绝", player.gold == 210 and inventory.get_slot_index_of("sword_blue") < 0)

	# ===== 3. 出售 =====
	var bone_slot := inventory.get_slot_index_of("bone")
	player.request_sell_item(bone_slot)
	await get_tree().process_frame
	_check("出售骨头得 1 金币", player.gold == 211, "实际 gold=%d" % player.gold)
	_check("骨头已移出背包", inventory.get_slot_index_of("bone") < 0)

	# ===== 4. 消耗品（M14：战士满血 160）=====
	attrs.apply_damage(20) # HP 160 -> 140
	await get_tree().process_frame
	_check("受伤后 HP=140", attrs.hp == 140, "实际 HP=%d" % attrs.hp)
	var bread_slot := inventory.get_slot_index_of("bread")
	player.request_use_consumable(bread_slot)
	await get_tree().process_frame
	_check("吃面包回到满血 160（封顶）", attrs.hp == 160, "实际 HP=%d" % attrs.hp)
	_check("面包数量 3->2", inventory.get_slot(inventory.get_slot_index_of("bread")).quantity == 2)

	# ===== 5. 穿卸装备重算 =====
	var green_slot := inventory.get_slot_index_of("sword_green")
	player.request_equip_item(green_slot, Item.ItemType.WEAPON)
	await get_tree().process_frame
	_check("换上精铁剑攻击 战士14+4=18", attrs.atk == 18, "实际 atk=%d" % attrs.atk)
	_check("铁剑回到背包", inventory.get_slot_index_of("sword_iron") >= 0)
	player.request_unequip_item(Item.ItemType.WEAPON)
	await get_tree().process_frame
	_check("卸下武器攻击回到 战士基础 14", attrs.atk == 14, "实际 atk=%d" % attrs.atk)

	# ===== 6. 掉落表数据完整性 =====
	var monster_dir := DirAccess.open("res://resources/monsters")
	if monster_dir == null:
		_fail("无法打开 resources/monsters")
	else:
		var loot_item_count := 0
		for file_name in monster_dir.get_files():
			if not file_name.ends_with(".tres"):
				continue
			var data := load("res://resources/monsters/" + file_name) as MonsterData
			if data == null:
				_fail("怪物数据加载失败: " + file_name)
				continue
			for entry in data.loot_table:
				loot_item_count += 1
				if ItemDatabase.get_item(entry.item_id) == null:
					_fail("%s 掉落表引用了不存在的物品 '%s'" % [file_name, entry.item_id])
		if _failures.is_empty():
			print("PASS | %d 种怪物共 %d 条掉落且全部有效" % [6, loot_item_count])

	_report()


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
		print("test_m3: 全部通过")
		get_tree().quit(0)
	else:
		print("test_m3: %d 项失败" % _failures.size())
		get_tree().quit(1)
