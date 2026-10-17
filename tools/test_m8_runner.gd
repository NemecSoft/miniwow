extends Node

## M8 自动化测试（独立测试场景运行，保证 autoload 单例可用）：
## 世界掉落物理系统——怪物死亡掉宝到地上、E 拾取入包、满包拒绝、
## 3 分钟过期、despawn 广播、鸡腿消耗品注册与掉落表接入。
## 运行方式：godot --headless --path . res://tools/test_m8.tscn

var _failures: Array[String] = []


func _ready() -> void:
	var level_scene := load("res://scenes/level/level.tscn") as PackedScene
	if level_scene == null:
		_fail("无法加载 level.tscn")
		_report()
		return
	var level := level_scene.instantiate()
	get_tree().root.call_deferred("add_child", level)
	await get_tree().process_frame
	var players_container := level.get_node_or_null("PlayersContainer") as Node3D
	var item_container := level.get_node_or_null("Environment/ItemContainer") as WorldDrops
	if players_container == null or item_container == null:
		_fail("找不到 PlayersContainer 或 ItemContainer(WorldDrops)")
		_report()
		return
	var player_scene := load("res://scenes/level/player.tscn") as PackedScene
	var player_instance := player_scene.instantiate() as CharacterBody3D
	player_instance.name = "1"
	players_container.add_child(player_instance, true)
	for i in range(30):
		await get_tree().process_frame
	var player := players_container.get_node_or_null("1") as CharacterBody3D
	if player == null:
		_fail("玩家未生成")
		_report()
		return

	await _test_chicken_leg()
	await _test_loot_tables()
	await _test_spawn(player, item_container)
	await _test_pickup(player, item_container)
	await _test_full_inventory(player, item_container)
	await _test_despawn(item_container)
	await _test_expiry(item_container)
	await _test_pickup_anim(player)
	_report()


# ===== 1. 鸡腿消耗品注册 =====

func _test_chicken_leg() -> void:
	var item := ItemDatabase.get_item("chicken_leg")
	_check("鸡腿物品已注册", item != null)
	if item == null:
		return
	_check("鸡腿为消耗品", item.item_type == Item.ItemType.CONSUMABLE)
	_check("鸡腿回血 35", item.heal_amount == 35, "实际=%d" % item.heal_amount)
	_check("鸡腿可堆叠", item.stackable)
	_check("鸡腿有图标", item.icon != null)
	_check("鸡腿有掉落场景", not item.scene_path.is_empty() and load(item.scene_path) != null)
	# 使用链路：request_use_consumable 存在（M3 已建，复用）
	_check("面包仍在售（商人保底）", ItemDatabase.get_item("bread") != null)


# ===== 2. 怪物掉落表接入鸡腿 =====

func _test_loot_tables() -> void:
	var with_chicken := 0
	for data in MonsterDatabase.get_all_monsters():
		for entry in data.loot_table:
			if entry and entry.item_id == "chicken_leg":
				with_chicken += 1
				var item := ItemDatabase.get_item(entry.item_id)
				_check("%s 的鸡腿条目有效" % data.id, item != null and entry.chance > 0.0)
				break
	_check("6 种怪物全部接入鸡腿掉落", with_chicken == 6, "实际=%d" % with_chicken)


# ===== 3. 世界掉落物生成 =====

func _test_spawn(player: CharacterBody3D, item_container: WorldDrops) -> void:
	var before := item_container.get_child_count()
	item_container.spawn_drop("chicken_leg", 2, player.global_position)
	await get_tree().process_frame
	_check("生成后容器子节点 +1", item_container.get_child_count() == before + 1,
		"实际=%d" % item_container.get_child_count())
	var drop := item_container.get_child(item_container.get_child_count() - 1) as ItemRigidBody3D
	if drop == null:
		_fail("掉落物不是 ItemRigidBody3D")
		return
	_check("掉落物 item_id=chicken_leg", drop.item_id == "chicken_leg")
	_check("掉落物 quantity=2（堆叠）", drop.quantity == 2, "实际=%d" % drop.quantity)
	_check("掉落物在 actor 层（可被拾取区检测）", drop.collision_layer == 4)
	var sync := drop.get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
	_check("掉落物带 MultiplayerSynchronizer（位姿同步）", sync != null)
	var expiry: Dictionary = item_container.get("_drop_expiry")
	_check("过期计时已登记", expiry != null and expiry.has(drop))
	# 清理：等掉落物入队后 despawn
	await get_tree().physics_frame
	item_container.remove_drop(drop)
	await get_tree().process_frame


# ===== 4. E 拾取入包 =====

func _test_pickup(player: CharacterBody3D, item_container: WorldDrops) -> void:
	var inv: Object = player.get("player_inventory")
	var count_before := _count_item(inv, "chicken_leg")
	item_container.spawn_drop("chicken_leg", 2, player.global_position)
	await get_tree().process_frame
	# 等物理帧：掉落物弹跳静止 + 被 InfrontArea3D 检测
	for i in range(40):
		await get_tree().physics_frame
	var drop := item_container.get_child(item_container.get_child_count() - 1) as ItemRigidBody3D
	if drop == null:
		_fail("拾取测试：掉落物丢失")
		return
	# 服务器本地权威路径直接结算（免输入时序依赖）
	player._server_pickup()
	await get_tree().process_frame
	var count_after := _count_item(inv, "chicken_leg")
	_check("拾取后背包鸡腿 +2", count_after == count_before + 2,
		"实际 %d -> %d" % [count_before, count_after])
	_check("掉落物已移除", not is_instance_valid(drop) or not drop.is_inside_tree(), "仍在树内")


# ===== 5. 满包拒绝 =====

func _test_full_inventory(player: CharacterBody3D, item_container: WorldDrops) -> void:
	var inv: Object = player.get("player_inventory")
	# 注意：骨头可堆叠（max_stack=99），逐个 add 只会叠进同一格，永远塞不满。
	# 按堆叠上限批量灌，直到所有基础格被骨头占满。
	var guard := 0
	while inv.get_first_empty_slot() >= 0 and guard < 50:
		var remaining: int = inv.add_item(ItemDatabase.get_item("bone"), 99)
		if remaining > 0:
			print("DIAG: bone 入包被拒 remaining=%d guard=%d" % [remaining, guard])
			break
		guard += 1
	# 鸡腿同样可堆叠（max_stack=8）：先把已有鸡腿堆叠灌满，
	# 否则"满包"时它仍能挤进旧堆叠，测不出拒绝入包。
	var leg_guard := 0
	while leg_guard < 20:
		if inv.add_item(ItemDatabase.get_item("chicken_leg"), 99) > 0:
			break
		leg_guard += 1
	print("DIAG: 塞包结束 空格位=%d 激活格=%d 鸡腿数=%d" % [
		inv.get_first_empty_slot(), inv.get_active_slot_count(), _count_item(inv, "chicken_leg")])
	_check("背包已塞满（满包前提）", inv.get_first_empty_slot() < 0)
	var count_before := _count_item(inv, "chicken_leg")
	item_container.spawn_drop("chicken_leg", 1, player.global_position)
	await get_tree().process_frame
	for i in range(40):
		await get_tree().physics_frame
	player._server_pickup()
	await get_tree().process_frame
	var count_after := _count_item(inv, "chicken_leg")
	_check("满包时鸡腿数量不变（拒绝入包）", count_after == count_before,
		"实际 %d -> %d" % [count_before, count_after])
	var still_has_drop := false
	for child in item_container.get_children():
		if child is ItemRigidBody3D and (child as ItemRigidBody3D).item_id == "chicken_leg":
			still_has_drop = true
	_check("满包时掉落物保留在地上", still_has_drop)
	# 清场：腾出背包 + 清掉落物
	inv.remove_item("bone", 999)
	for child in item_container.get_children():
		if child is ItemRigidBody3D:
			item_container.remove_drop(child)
	await get_tree().process_frame


# ===== 6. despawn 广播移除 =====

func _test_despawn(item_container: WorldDrops) -> void:
	item_container.spawn_drop("bone", 1, Vector3(0, 0, 0))
	await get_tree().process_frame
	var drop := item_container.get_child(item_container.get_child_count() - 1) as Node
	if drop == null:
		_fail("despawn 测试：掉落物未生成")
		return
	item_container.despawn_drop(item_container.get_path_to(drop))
	await get_tree().process_frame
	_check("despawn 后节点已移除", not drop.is_inside_tree())


# ===== 7. 3 分钟过期登记 =====

func _test_expiry(item_container: WorldDrops) -> void:
	_check("过期时限 = 180 秒", WorldDrops.DESPAWN_SECONDS == 180.0)


# ===== 8. Pickup 动画白名单与播放 =====

func _test_pickup_anim(player: CharacterBody3D) -> void:
	var anim := player.get_node_or_null("GodotRobot3D/AnimationPlayer") as AnimationPlayer
	if anim == null:
		_fail("玩家找不到 AnimationPlayer")
		return
	player._request_animation(&"Pickup", true)
	_check("Pickup 动画通过白名单播放", anim.current_animation == "Pickup",
		"实际=%s" % anim.current_animation)
	player._on_animation_finished(&"Pickup")
	_check("Pickup 播完 is_collecting 复位", not player.is_collecting)


# ===== 工具 =====

func _count_item(inv: Object, item_id: String) -> int:
	var total := 0
	for i in range(inv.get_active_slot_count()):
		var slot: Object = inv.get_slot(i)
		if slot and str(slot.get("item_id")) == item_id:
			total += int(slot.get("quantity"))
	return total


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS | %s" % name)
	else:
		var msg := "FAIL | %s%s" % [name, (" -> " + detail) if not detail.is_empty() else ""]
		print(msg)
		_failures.append(msg)


func _fail(msg: String) -> void:
	print("FAIL | %s" % msg)
	_failures.append(msg)


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("=== M8 测试全部通过 ===")
	else:
		print("=== M8 测试失败 %d 项 ===" % _failures.size())
		for f in _failures:
			print("  " + f)
	get_tree().quit(1 if not _failures.is_empty() else 0)
