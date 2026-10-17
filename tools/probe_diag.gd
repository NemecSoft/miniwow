extends Node

## 综合诊断探针（2026-10-16 用户反馈三大问题）：
## 1. 打击动画没变化——实测持剑/空手 try_attack 后 AnimationPlayer 真实状态
## 2. 掉落物捡不起来——实测 E 键动画 RPC 后服务器拾取时间戳是否被设置（M9 改名嫌疑）
## 3. 234 技能失效——实测 player_class 为空/非空时技能槽行为
## 运行：godot --headless --path . res://tools/probe_diag.tscn


func _ready() -> void:
	var level_scene := load("res://scenes/level/level.tscn") as PackedScene
	var level := level_scene.instantiate()
	get_tree().root.call_deferred("add_child", level)
	await get_tree().process_frame
	var players_container := level.get_node_or_null("PlayersContainer") as Node3D
	var player_scene := load("res://scenes/level/player.tscn") as PackedScene
	var player_instance := player_scene.instantiate() as CharacterBody3D
	player_instance.name = "1"
	players_container.add_child(player_instance, true)
	for i in range(30):
		await get_tree().process_frame
	var player := players_container.get_node_or_null("1") as CharacterBody3D
	if player == null:
		print("DIAG: 玩家未生成")
		get_tree().quit()
		return

	await _diag_strike_animation(player)
	await _diag_pickup(player)
	_diag_skills(player)
	get_tree().quit()


# ===== 1. 打击动画 =====

func _diag_strike_animation(player: CharacterBody3D) -> void:
	var body := player.get_node_or_null("GodotRobot3D")
	var anim := body.get_node_or_null("AnimationPlayer") as AnimationPlayer
	print("DIAG: === 打击动画诊断 ===")
	print("DIAG: 玩家职业=", player.get("player_class"), " 背包存在=", player.get("player_inventory") != null)
	var inv = player.get("player_inventory")
	if inv:
		print("DIAG: 武器栏='", inv.equipped_weapon.item_id, "' _is_unarmed=", player._is_unarmed())

	# 持剑普攻（模拟有目标 try_attack 路径中的动画部分）
	player._play_attack_animation(&"Attack1")
	await get_tree().process_frame
	print("DIAG: 持剑普攻 → 状态=", body._current_state, " 播放中=", anim.is_playing(),
		" 速度=", anim.speed_scale, " 当前动画=", anim.current_animation)

	# 等动画播完看 finished 是否触发复位
	for i in range(100):
		await get_tree().process_frame
		if not anim.is_playing():
			break
	print("DIAG: 播完后 is_attacking=", player.get("is_attacking"), " _current_state=", body._current_state)

	# 空手普攻
	if inv:
		inv.equipped_weapon = InventorySlot.new()
	player._play_attack_animation(&"Attack1")
	await get_tree().process_frame
	print("DIAG: 空手普攻 → 状态=", body._current_state, " 速度=", anim.speed_scale,
		" is_attacking=", player.get("is_attacking"))
	player._on_animation_finished(&"Pickup")

	# Attack1 动画本身时长
	if anim.has_animation(&"Attack1"):
		print("DIAG: Attack1 时长=", anim.get_animation(&"Attack1").length, "s")
	if anim.has_animation(&"Pickup"):
		print("DIAG: Pickup 时长=", anim.get_animation(&"Pickup").length, "s")
	# 恢复铁剑
	if inv:
		var idx: int = inv.get_slot_index_of("sword_iron")
		if idx >= 0:
			inv.equip_from_slot(idx, Item.ItemType.WEAPON)


# ===== 2. 拾取（E 键路径）=====

func _diag_pickup(player: CharacterBody3D) -> void:
	print("DIAG: === 拾取诊断 ===")
	print("DIAG: 修前模拟——E 键发 Pickup 动画 RPC（服务器 request_animation_state）")
	player.request_animation_state(&"Pickup", 500, 1.0)
	await get_tree().process_frame
	print("DIAG: 服务器拾取时间戳=", player.get("_server_pickup_animation_started_msec"),
		"（-1 = 永远不设 = E 键拾取必然失败！）")

	# 对照：旧动画名 Emote2
	player.request_animation_state(&"Emote2", 501, 1.0)
	await get_tree().process_frame
	print("DIAG: 发 Emote2 时间戳=", player.get("_server_pickup_animation_started_msec"),
		"（>0 = 旧名仍走通）")

	# 世界掉落链路：直接 spawn 鸡腿再检测
	var world_drops := get_tree().root.get_node_or_null("Level/Environment/ItemContainer") as WorldDrops
	print("DIAG: WorldDrops 节点=", world_drops != null)
	if world_drops:
		var before: int = world_drops.get_child_count()
		world_drops.spawn_drop("chicken_leg", 1, player.global_position + Vector3(1, 0.5, 0))
		await get_tree().process_frame
		await get_tree().process_frame
		print("DIAG: spawn 后掉落物数=", world_drops.get_child_count(), "（前=", before, "）")
		var items: Array = player._get_collectible_items_in_front()
		print("DIAG: 玩家身边可拾取数=", items.size(), "（PICKUP_RANGE=2.5 球形检测）")


# ===== 3. 技能 =====

func _diag_skills(player: CharacterBody3D) -> void:
	print("DIAG: === 技能诊断 ===")
	print("DIAG: player_class='", player.get("player_class"), "'（空 = 234 必然静默失效）")
	# 模拟 _try_use_class_skill 的判定
	if str(player.get("player_class")).is_empty():
		print("DIAG: 实锤——未选职业时 _try_use_class_skill 第一行 return，1 键普攻不受影响（try_attack 不查职业）")
	# 选职业后再看槽位技能解析
	player.player_class = "warrior"
	var class_data := ClassDatabase.get_class_data("warrior")
	print("DIAG: 选战士后槽位技能=", class_data.skill_ids)
	# 服务器结算侧：无目标时 heavy_strike 解析
	player.current_target_path = ""
	var resolved: String = player._resolve_skill_target_path(SkillDatabase.get_skill("heavy_strike"))
	print("DIAG: 无目标时重击目标解析='", resolved, "'（空 = 静默失败）")
	# 盾墙（SELF）不受目标影响
	var resolved2: String = player._resolve_skill_target_path(SkillDatabase.get_skill("w_shield_wall"))
	print("DIAG: 无目标时盾墙目标解析='", resolved2, "'（非空 = 应该能放）")
	# 法力检查
	var attrs = player.get("attribute_set")
	print("DIAG: 当前 mp=", attrs.mp, "/", attrs.max_mp,
		"（重击需 10、旋风 15、盾墙 12）")
