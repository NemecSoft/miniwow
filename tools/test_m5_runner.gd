extends Node

## M5 自动化测试（以独立测试场景方式运行，保证 autoload 单例可用）：
## host 一个真实 level 场景，验证 三职业属性差异 / 12 技能全链路
## （弹道命中、减速、增益、治疗、HOT、AoE、斩杀条件、冷却拒绝、职业切换）。
## 运行方式：godot --headless --path . res://tools/test_m5.tscn

var _failures: Array[String] = []


func _ready() -> void:
	var level_scene := load("res://scenes/level/level.tscn") as PackedScene
	if level_scene == null:
		_fail("无法加载 level.tscn")
		_report()
		return
	var level := level_scene.instantiate()
	# 必须挂到场景树根下并保持场景原名 "Level"（怪物/飘字按 /root/Level/... 绝对路径查找）
	get_tree().root.call_deferred("add_child", level)
	await get_tree().process_frame
	# headless 下模板的 start_host/_add_player 都会跳过本地(peer 1)玩家，手动补上
	var players_container := level.get_node_or_null("PlayersContainer") as Node3D
	if players_container == null:
		_fail("找不到 PlayersContainer")
		_report()
		return
	var player_scene := load("res://scenes/level/player.tscn") as PackedScene
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
	var effects := level.get_node_or_null("Environment/Effects") as Node

	# ===== 1. 数据完整性 =====
	# M18b：步兵加入，4 职业 × 4 技能 = 16
	_check("4 个职业全部注册", ClassDatabase.get_all_classes().size() == 4)
	var class_skill_total := 0
	for class_data in ClassDatabase.get_all_classes():
		_check("%s 有 4 个技能" % class_data.display_name, class_data.skill_ids.size() == 4)
		for skill_id in class_data.skill_ids:
			var skill := SkillDatabase.get_skill(skill_id)
			if skill == null:
				_fail("%s 的技能 '%s' 未注册" % [class_data.display_name, skill_id])
			else:
				class_skill_total += 1
				if skill.icon == null:
					_fail("技能 '%s' 缺少图标" % skill_id)
	_check("职业技能合计 16 个且全部注册", class_skill_total == 16)

	# ===== 2. 选择法师：基础属性按职业生效 =====
	player.request_choose_class("mage")
	await get_tree().process_frame
	_check("选择法师后 player_class=mage", player.player_class == "mage")
	_check("法师生命上限 100（Lv1 无成长）", attrs.max_hp == 100, "实际 max_hp=%d" % attrs.max_hp)
	_check("法师法力上限 80", attrs.max_mp == 80, "实际 max_mp=%d" % attrs.max_mp)
	_check("法师攻击 10 基础 + 2 铁剑", attrs.atk == 12, "实际 atk=%d" % attrs.atk)

	# ===== 3. 火球术：弹道生成 → 飞行 → 命中掉血 =====
	var dummy1 := _spawn_dummy(level, player.global_position + Vector3(6, 0, 0))
	player._set_target(dummy1)
	var mp_before := attrs.mp
	player.try_use_skill("m_fireball")
	await get_tree().process_frame
	_check("火球术扣除 10 点法力", attrs.mp == mp_before - 10, "实际 mp=%d" % attrs.mp)
	var projectile_seen := _has_projectile(effects)
	_check("火球术生成弹道节点", projectile_seen)
	for i in range(45): # 18 米/秒飞 6 米约 0.35 秒，留足余量
		await get_tree().process_frame
	_check("火球命中木桩掉血", dummy1.attribute_set.hp < dummy1.attribute_set.max_hp, "实际 hp=%d/%d" % [dummy1.attribute_set.hp, dummy1.attribute_set.max_hp])
	_check("命中后弹道被移除", not _has_projectile(effects))

	# ===== 4. 冰箭：命中 + 减速 =====
	var dummy2 := _spawn_dummy(level, player.global_position + Vector3(5, 0, 2))
	player._set_target(dummy2)
	mp_before = attrs.mp
	player.try_use_skill("m_frostbolt")
	await get_tree().process_frame
	_check("冰箭扣除 12 点法力", attrs.mp == mp_before - 12, "实际 mp=%d" % attrs.mp)
	for i in range(50):
		await get_tree().process_frame
	_check("冰箭命中木桩掉血", dummy2.attribute_set.hp < dummy2.attribute_set.max_hp)
	_check("冰箭附加减速（移速系数 0.45）", dummy2.attribute_set.current_speed_multiplier() < 1.0, "实际系数=%f" % dummy2.attribute_set.current_speed_multiplier())

	# ===== 5. 奥术强化：攻击增益 =====
	var atk_before := attrs.atk
	mp_before = attrs.mp
	player.try_use_skill("m_arcane_power")
	await get_tree().process_frame
	_check("奥术强化扣除 20 点法力", attrs.mp == mp_before - 20, "实际 mp=%d" % attrs.mp)
	_check("奥术强化攻击 +8", attrs.atk == atk_before + 8, "实际 atk=%d（原 %d）" % [attrs.atk, atk_before])

	# ===== 6. 冷却拒绝：释放后立刻再放不生效 =====
	mp_before = attrs.mp
	player.try_use_skill("m_arcane_power") # 还在 30 秒 CD
	await get_tree().process_frame
	_check("冷却中再次释放被拒绝（不扣蓝）", attrs.mp == mp_before, "实际 mp=%d" % attrs.mp)

	# ===== 7. 切换战士：属性重算 + 斩杀条件 =====
	player.request_choose_class("warrior")
	await get_tree().process_frame
	_check("切换战士后 player_class=warrior", player.player_class == "warrior")
	_check("战士生命上限 160", attrs.max_hp == 160, "实际 max_hp=%d" % attrs.max_hp)
	_check("战士法力上限 30", attrs.max_mp == 30, "实际 max_mp=%d" % attrs.max_mp)
	var dummy3 := _spawn_dummy(level, player.global_position + Vector3(0, 0, 3))
	player._set_target(dummy3)
	mp_before = attrs.mp
	player.try_use_skill("w_execute") # 满血目标：斩杀条件不满足
	await get_tree().process_frame
	_check("满血目标斩杀被拒绝（不扣蓝）", attrs.mp == mp_before, "实际 mp=%d" % attrs.mp)
	_check("斩杀被拒后木桩满血", dummy3.attribute_set.hp == dummy3.attribute_set.max_hp)
	dummy3.attribute_set.apply_damage(750) # 1000 血打到 250（25%），满足斩杀线
	await get_tree().process_frame
	player.try_use_skill("w_execute")
	await get_tree().process_frame
	_check("残血目标斩杀放行（扣 15 蓝）", attrs.mp == mp_before - 15, "实际 mp=%d" % attrs.mp)
	_check("斩杀造成大量伤害", dummy3.attribute_set.hp < 250, "实际 hp=%d" % dummy3.attribute_set.hp)

	# ===== 8. 旋风斩：自身 AoE =====
	var dummy4 := _spawn_dummy(level, player.global_position + Vector3(2.5, 0, 0))
	var dummy5 := _spawn_dummy(level, player.global_position + Vector3(-2.5, 0, 0))
	var dummy4_hp_before: int = dummy4.attribute_set.hp
	var dummy5_hp_before: int = dummy5.attribute_set.hp
	mp_before = attrs.mp
	player.try_use_skill("w_whirlwind")
	await get_tree().process_frame
	_check("旋风斩扣除 15 点法力", attrs.mp == mp_before - 15, "实际 mp=%d" % attrs.mp)
	_check("旋风斩命中右侧木桩", dummy4.attribute_set.hp < dummy4_hp_before, "实际 hp=%d（原 %d）" % [dummy4.attribute_set.hp, dummy4_hp_before])
	_check("旋风斩命中左侧木桩", dummy5.attribute_set.hp < dummy5_hp_before, "实际 hp=%d（原 %d）" % [dummy5.attribute_set.hp, dummy5_hp_before])
	var far_dummy := _spawn_dummy(level, player.global_position + Vector3(0, 0, 8))
	var far_hp_before: int = far_dummy.attribute_set.hp
	player.try_use_skill("w_whirlwind") # CD 6 秒，这次会被冷却拒绝——先等 CD
	for i in range(400): # 等 6.7 秒过 CD
		await get_tree().process_frame
	attrs.restore_mp(30)
	await get_tree().process_frame
	player.try_use_skill("w_whirlwind")
	await get_tree().process_frame
	_check("旋风斩不命中 8 米外目标", far_dummy.attribute_set.hp == far_hp_before, "实际 hp=%d（原 %d）" % [far_dummy.attribute_set.hp, far_hp_before])

	# ===== 9. 盾墙：防御增益（先回满蓝）=====
	attrs.restore_mp(30)
	await get_tree().process_frame
	var def_before := attrs.def
	mp_before = attrs.mp
	player.try_use_skill("w_shield_wall")
	await get_tree().process_frame
	_check("盾墙扣除 12 点法力", attrs.mp == mp_before - 12, "实际 mp=%d" % attrs.mp)
	_check("盾墙防御 +10", attrs.def == def_before + 10, "实际 def=%d（原 %d）" % [attrs.def, def_before])

	# ===== 10. 切换牧师：治疗 / HOT /  AoE 治疗 =====
	player.request_choose_class("priest")
	await get_tree().process_frame
	_check("切换牧师后 player_class=priest", player.player_class == "priest")
	_check("牧师生命上限 120", attrs.max_hp == 120, "实际 max_hp=%d" % attrs.max_hp)
	attrs.apply_damage(40)
	await get_tree().process_frame
	var hp_after_hurt := attrs.hp
	mp_before = attrs.mp
	player.try_use_skill("p_flash_heal") # 无队友目标 → 治疗自己
	await get_tree().process_frame
	var expected_heal := int(120.0 * 0.3)
	_check("快速治疗扣除 18 点法力", attrs.mp == mp_before - 18, "实际 mp=%d" % attrs.mp)
	_check("快速治疗恢复 30%% 生命", attrs.hp == hp_after_hurt + expected_heal, "实际 hp=%d（%d+%d）" % [attrs.hp, hp_after_hurt, expected_heal])

	# ===== 11. 恢复：HOT 持续治疗 =====
	# 注意：headless 无渲染，process 帧率不封顶（远快于真实时间），
	# "等 N 个 process 帧 ≈ N/60 秒"的换算不成立，HOT 计时必须用 physics 帧（固定 60/秒真实时间）。
	attrs.clear_effects() # 清掉前序残留，避免干扰
	attrs.apply_damage(60)
	await get_tree().process_frame
	var hot_start_hp := attrs.hp
	mp_before = attrs.mp
	player.try_use_skill("p_renew")
	await get_tree().process_frame
	_check("恢复扣除 16 点法力", attrs.mp == mp_before - 16, "实际 mp=%d" % attrs.mp)
	for i in range(140): # 140 个 physics 帧 = 2.3 秒真实时间，至少 2 次 tick
		await get_tree().physics_frame
	_check("恢复 HOT 持续回血", attrs.hp > hot_start_hp, "实际 hp=%d（起始 %d）" % [attrs.hp, hot_start_hp])
	attrs.clear_effects() # HOT 测完清场，防止残留 tick 在后续精确断言前偷偷回血

	# ===== 12. 神圣新星：AoE 伤害 + 自我治疗 =====
	var nova_dummy1 := _spawn_dummy(level, player.global_position + Vector3(3, 0, 0))
	var nova_dummy2 := _spawn_dummy(level, player.global_position + Vector3(0, 0, -3))
	attrs.apply_damage(30)
	await get_tree().process_frame
	var nova_self_hp := attrs.hp
	var nova_d1_hp: int = nova_dummy1.attribute_set.hp
	var nova_d2_hp: int = nova_dummy2.attribute_set.hp
	mp_before = attrs.mp
	player.try_use_skill("p_holy_nova")
	await get_tree().process_frame
	_check("神圣新星扣除 22 点法力", attrs.mp == mp_before - 22, "实际 mp=%d" % attrs.mp)
	_check("神圣新星伤害近处怪物 A", nova_dummy1.attribute_set.hp < nova_d1_hp)
	_check("神圣新星伤害近处怪物 B", nova_dummy2.attribute_set.hp < nova_d2_hp)
	var expected_nova_heal := int(120.0 * 0.12)
	_check("神圣新星治疗自己 12%% 生命", attrs.hp == nova_self_hp + expected_nova_heal, "实际 hp=%d（%d+%d）" % [attrs.hp, nova_self_hp, expected_nova_heal])

	# ===== 13. 惩击：远程瞬发（先回满蓝，前面治疗消耗太多）=====
	attrs.restore_mp(60)
	await get_tree().process_frame
	var smite_dummy := _spawn_dummy(level, player.global_position + Vector3(9, 0, 0))
	player._set_target(smite_dummy)
	var smite_hp_before: int = smite_dummy.attribute_set.hp
	mp_before = attrs.mp
	player.try_use_skill("p_smite")
	await get_tree().process_frame
	_check("惩击扣除 8 点法力", attrs.mp == mp_before - 8, "实际 mp=%d" % attrs.mp)
	_check("惩击命中 9 米外目标", smite_dummy.attribute_set.hp < smite_hp_before)

	# ===== 14. 超出射程拒绝 =====
	var far_target := _spawn_dummy(level, player.global_position + Vector3(0, 0, 30))
	player._set_target(far_target)
	mp_before = attrs.mp
	player.try_use_skill("p_smite") # 射程 10 米
	await get_tree().process_frame
	_check("超出射程释放被拒绝（不扣蓝）", attrs.mp == mp_before, "实际 mp=%d" % attrs.mp)

	_report()


## 在指定位置生成一个训练木桩（不会动、无 AI，是稳定的测试靶子）
func _spawn_dummy(level: Node, world_position: Vector3) -> Node3D:
	var dummy_scene := load("res://scenes/monsters/training_dummy.tscn") as PackedScene
	var dummy := dummy_scene.instantiate() as Node3D
	dummy.name = "TestDummy_%d" % randi()
	dummy.position = world_position
	level.add_child(dummy)
	return dummy


func _has_projectile(effects: Node) -> bool:
	if effects == null:
		return false
	for child in effects.get_children():
		if String(child.name).begins_with("Proj_"):
			return true
	return false


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
		print("test_m5: 全部通过")
		get_tree().quit(0)
	else:
		print("test_m5: %d 项失败" % _failures.size())
		get_tree().quit(1)
