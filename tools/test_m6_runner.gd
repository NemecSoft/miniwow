extends Node

## M6 自动化测试（独立测试场景方式运行，autoload 单例可用）：
## A. 多语言：默认中文 / 英中切换 / 翻译表覆盖（UI+资源）/ auto_translate 静态文本 /
##    持久化 / 语言按钮接线。
## B. 蓝天白云场景：天空渐变（亮蓝/浅地平线/无近黑地底）、环境光来自天空、
##    SSAO 关闭（无黑块风险）、雾色与天空一致且明亮、暖阳高能量、云层（数量/材质/
##    不投影/高度）、亮色地面贴图（平均亮度阈值 + 场景引用）。
## 运行方式：godot --headless --path . res://tools/test_m6.tscn

var _failures: Array[String] = []


func _ready() -> void:
	await _test_i18n()
	await _test_sky()
	_report()


# ===== A. 多语言 =====

func _test_i18n() -> void:
	# 强制已知起点（清掉上次运行可能残留的偏好）
	LanguageManager.set_language("zh_CN")
	await get_tree().process_frame

	_check("默认语言为 zh_CN", LanguageManager.current_locale == "zh_CN")
	_check("TranslationServer locale = zh_CN", TranslationServer.get_locale() == "zh_CN")

	# 中文（默认）：键即原文
	_check("中文：创建主机", tr("创建主机") == "创建主机")
	_check("中文：金币格式串", tr("金币: %d") == "金币: %d")
	_check("中文：退出游戏", tr("退出游戏") == "退出游戏")
	_check("未知键回键本身", tr("不存在的键XYZ") == "不存在的键XYZ")

	# 资源数据键（中文界面 = 原文）
	var iron_sword := ItemDatabase.get_item("sword_iron")
	_check("铁剑物品存在", iron_sword != null)
	if iron_sword:
		_check("物品键=铁剑", iron_sword.name == "铁剑")
		_check("物品描述键", not iron_sword.description.is_empty())
	var fireball := SkillDatabase.get_skill("m_fireball")
	_check("火球术技能存在", fireball != null)
	if fireball:
		_check("技能键=火球术", fireball.skill_name == "火球术")
	var q1 := QuestDatabase.get_quest("q1_wolf_hunt")
	_check("任务 q1 存在", q1 != null)
	if q1:
		_check("任务名键=林缘试炼", q1.name == "林缘试炼")
	var wolf := MonsterDatabase.get_monster("wolf")
	_check("野狼怪物存在", wolf != null)
	if wolf:
		_check("怪物键=野狼", wolf.display_name == "野狼")
	var warrior := ClassDatabase.get_class_data("warrior")
	_check("战士职业存在", warrior != null)
	if warrior:
		_check("职业键=战士", warrior.display_name == "战士")

	# 切英文
	LanguageManager.set_language("en_US")
	await get_tree().process_frame
	_check("切换后 locale = en_US", TranslationServer.get_locale() == "en_US")
	_check("英文：创建主机", tr("创建主机") == "Create Host")
	_check("英文：退出游戏", tr("退出游戏") == "Quit Game")
	_check("英文：金币格式串", tr("金币: %d") == "Gold: %d")
	_check("英文：物品键", tr("铁剑") == "Iron Sword")
	_check("英文：面包描述键", tr("香喷喷的烤面包，恢复 30 点生命。") == "A freshly baked loaf, restores 30 HP.")
	_check("英文：技能键", tr("火球术") == "Fireball")
	_check("英文：任务名键", tr("林缘试炼") == "Trial at the Forest Edge")
	_check("英文：怪物键", tr("野狼") == "Wolf")
	_check("英文：职业键", tr("战士") == "Warrior")
	_check("英文：播报格式串", tr("%s 升到了 Lv.%d！") == "%s reached Lv.%d!")
	_check("英文：斩杀技能名", tr("斩杀") == "Execute")
	_check("英文：顿号分隔符", tr("、") == ", ")
	_check("英文：仍未知键回键", tr("不存在的键XYZ") == "不存在的键XYZ")

	# 语言按钮文本
	_check("英文下按钮显示 Language: English", LanguageManager.language_button_text() == "Language: English")

	# toggle 回中文
	LanguageManager.toggle_language()
	await get_tree().process_frame
	_check("toggle 回 zh_CN", TranslationServer.get_locale() == "zh_CN")
	_check("toggle 后中文恢复", tr("创建主机") == "创建主机")
	_check("中文下按钮显示 语言：中文", LanguageManager.language_button_text() == "语言：中文")

	# 持久化：set_language 应写入 user://settings.cfg
	LanguageManager.set_language("en_US")
	var config := ConfigFile.new()
	var load_error := config.load("user://settings.cfg")
	_check("偏好文件可读取", load_error == OK)
	if load_error == OK:
		_check("偏好文件记录 en_US", str(config.get_value("language", "locale", "")) == "en_US")
	LanguageManager.set_language("zh_CN")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))

	# auto_translate：静态文本节点启用自动翻译（Label.text 读出的是原文，
	# 显示用内部翻译文本，因此断言 can_auto_translate() 这个真正开关）
	LanguageManager.set_language("en_US")
	await get_tree().process_frame
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	label.text = "创建主机"
	add_child(label)
	var label3d := Label3D.new()
	label3d.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	label3d.text = "创建主机"
	add_child(label3d)
	await get_tree().process_frame
	_check("Label 已启用自动翻译（英文下显示 Create Host）", label.can_auto_translate())
	_check("Label3D 名牌已启用自动翻译（英文下显示 Create Host）", label3d.can_auto_translate())
	LanguageManager.set_language("zh_CN")
	await get_tree().process_frame
	label.queue_free()
	label3d.queue_free()

	# tscn 静态文本：主菜单场景根挂 auto_translate，Host 按钮继承生效
	var menu_scene := load("res://scenes/ui/main_menu_ui.tscn") as PackedScene
	var menu := menu_scene.instantiate()
	add_child(menu)
	await get_tree().process_frame
	var host_button := menu.get_node_or_null("MainContainer/MainMenu/Buttons/Host") as Button
	var menu_lang_button := menu.get_node_or_null("MainContainer/MainMenu/Option4/Language") as Button
	_check("主菜单 Host 按钮存在", host_button != null)
	if host_button:
		_check("主菜单根节点 auto_translate = Always", menu.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_ALWAYS)
		_check("Host 按钮继承自动翻译", host_button.can_auto_translate())
	_check("主菜单语言按钮存在", menu_lang_button != null)
	if menu_lang_button:
		_check("语言按钮禁用自动翻译（文本由代码管理）",
			menu_lang_button.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED)
		_check("语言按钮初始文本为 语言：中文", menu_lang_button.text == "语言：中文")
	menu.queue_free()

	# 翻译覆盖：所有资源的用户可见字段都必须有英文译文
	_check("英文翻译表条目 >= 120", LanguageManager.EN_MESSAGES.size() >= 120,
		"实际 %d 条" % LanguageManager.EN_MESSAGES.size())
	var coverage_gaps: Array[String] = []
	for skill in SkillDatabase.get_all_skills():
		if not LanguageManager.EN_MESSAGES.has(skill.skill_name):
			coverage_gaps.append("技能名:" + skill.skill_name)
		if not LanguageManager.EN_MESSAGES.has(skill.description):
			coverage_gaps.append("技能描述:" + skill.id)
	for item in ItemDatabase.get_all_items().values():
		if not LanguageManager.EN_MESSAGES.has(item.name):
			coverage_gaps.append("物品名:" + item.id)
		if not LanguageManager.EN_MESSAGES.has(item.description):
			coverage_gaps.append("物品描述:" + item.id)
	for quest in QuestDatabase.get_all_quests():
		if not LanguageManager.EN_MESSAGES.has(quest.name):
			coverage_gaps.append("任务名:" + quest.id)
		if not LanguageManager.EN_MESSAGES.has(quest.description):
			coverage_gaps.append("任务描述:" + quest.id)
		if not LanguageManager.EN_MESSAGES.has(quest.objective_text):
			coverage_gaps.append("任务目标:" + quest.id)
	for monster in MonsterDatabase.get_all_monsters():
		if not LanguageManager.EN_MESSAGES.has(monster.display_name):
			coverage_gaps.append("怪物名:" + monster.id)
	for class_data in ClassDatabase.get_all_classes():
		if not LanguageManager.EN_MESSAGES.has(class_data.display_name):
			coverage_gaps.append("职业名:" + class_data.id)
		if not LanguageManager.EN_MESSAGES.has(class_data.description):
			coverage_gaps.append("职业描述:" + class_data.id)
	_check("全部资源字段均有英文译文", coverage_gaps.is_empty(), "缺失: %s" % ", ".join(coverage_gaps))


# ===== B. 蓝天白云场景 =====

func _test_sky() -> void:
	var level_scene := load("res://scenes/level/level.tscn") as PackedScene
	if level_scene == null:
		_fail("无法加载 level.tscn")
		return
	var level := level_scene.instantiate()
	get_tree().root.call_deferred("add_child", level)
	await get_tree().process_frame
	await get_tree().process_frame

	# 语言切换按钮（暂停菜单，游戏内入口）
	var pause_lang := level.get_node_or_null("PauseMenuUI/Overlay/Panel/MarginContainer/Buttons/Language") as Button
	_check("暂停菜单语言按钮已挂载", pause_lang != null)
	if pause_lang:
		_check("暂停菜单语言按钮初始文本 = 语言：中文", pause_lang.text == "语言：中文")

	# --- 环境与天空 ---
	var world_env := level.get_node_or_null("Environment/WorldEnvironment") as WorldEnvironment
	if world_env == null:
		_fail("找不到 WorldEnvironment")
		return
	var env := world_env.environment
	_check("环境资源存在", env != null)
	_check("背景模式 = 天空盒（任意角度无黑底）", env.background_mode == Environment.BG_SKY)
	var sky := env.sky
	_check("天空资源存在", sky != null)
	if sky and sky.sky_material is ProceduralSkyMaterial:
		var mat := sky.sky_material as ProceduralSkyMaterial
		var top := mat.sky_top_color
		var horizon := mat.sky_horizon_color
		var ground_bottom := mat.ground_bottom_color
		_check("天顶为蓝色（B 通道最高）", top.b > top.r and top.b > top.g,
			"实际 top=%s" % str(top))
		_check("天顶明亮（B >= 0.4）", top.b >= 0.4, "实际 top.b=%.2f" % top.b)
		_check("地平线浅亮（亮度 >= 0.75）", horizon.get_luminance() >= 0.75,
			"实际 horizon=%s" % str(horizon))
		_check("地平线偏蓝白（B >= R）", horizon.b >= horizon.r, "实际 horizon=%s" % str(horizon))
		_check("地底不许近黑（亮度 >= 0.3）", ground_bottom.get_luminance() >= 0.3,
			"实际 ground_bottom=%s" % str(ground_bottom))
	else:
		_fail("天空材质不是 ProceduralSkyMaterial")

	# --- 光照 ---
	_check("环境光来源 = 天空（阴影区不死黑）", env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY)
	_check("SSAO 已关闭（消除缝隙黑块风险）", env.ssao_enabled == false)
	var fog := env.fog_light_color
	_check("雾色明亮（亮度 >= 0.7）", fog.get_luminance() >= 0.7, "实际 fog=%s" % str(fog))
	_check("雾色偏蓝（B > R）", fog.b > fog.r, "实际 fog=%s" % str(fog))
	_check("雾效启用且不浓（密度 <= 0.004）", env.fog_enabled and env.fog_density <= 0.004)

	var sun := level.get_node_or_null("Environment/DirectionalLight3D") as DirectionalLight3D
	if sun == null:
		_fail("找不到 DirectionalLight3D")
	else:
		_check("太阳能量充足（>= 1.2）", sun.light_energy >= 1.2, "实际=%.2f" % sun.light_energy)
		_check("太阳为暖白色（R >= B）", sun.light_color.r >= sun.light_color.b,
			"实际=%s" % str(sun.light_color))
		_check("太阳投影开启且柔化", sun.shadow_enabled and sun.shadow_blur > 0.0)

	# --- 云层 ---
	var clouds := level.get_node_or_null("Environment/CloudLayer") as Node3D
	if clouds == null:
		_fail("找不到 CloudLayer")
	else:
		var clusters := 0
		var blobs := 0
		var white_ok := true
		var no_shadow_ok := true
		var height_ok := true
		for child in clouds.get_children():
			if child is Node3D:
				clusters += 1
				var c := child as Node3D
				if c.position.y < 40.0 or c.position.y > 95.0:
					height_ok = false
				for sub in c.get_children():
					if sub is MeshInstance3D:
						blobs += 1
						var mi := sub as MeshInstance3D
						if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
							no_shadow_ok = false
						if mi.material_override is StandardMaterial3D:
							var m := mi.material_override as StandardMaterial3D
							if m.albedo_color.r < 0.9 or m.albedo_color.g < 0.9 or m.albedo_color.b < 0.9:
								white_ok = false
		_check("云层 >= 10 朵", clusters >= 10, "实际=%d" % clusters)
		_check("云朵由多球体构成（>= 30 个）", blobs >= 30, "实际=%d" % blobs)
		_check("云材质为白色", white_ok)
		_check("云不投影（无动态云影黑斑）", no_shadow_ok)
		_check("云高度合理（40~95 米）", height_ok)

	# --- 地面贴图：亮色替代 ---
	var ground_image := Image.new()
	var img_error := ground_image.load("res://assets/environment/textures/prototype_ground.png")
	_check("亮色地面贴图存在", img_error == OK)
	if img_error == OK:
		var lum_sum := 0.0
		var samples := 0
		for y in range(0, ground_image.get_height(), 16):
			for x in range(0, ground_image.get_width(), 16):
				lum_sum += ground_image.get_pixel(x, y).get_luminance()
				samples += 1
		var avg_lum := lum_sum / float(maxi(1, samples))
		_check("地面平均亮度 >= 0.5（告别近黑地面）", avg_lum >= 0.5, "实际=%.3f" % avg_lum)

	# --- 场景引用切换 ---
	var arena := load("res://scenes/level/arena.tscn") as PackedScene
	_check("竞技场场景可加载", arena != null)
	var arena_instance := arena.instantiate()
	var ground_mesh := arena_instance.get_node_or_null("Geometry/GroundMesh") as MeshInstance3D
	if ground_mesh and ground_mesh.mesh is BoxMesh:
		var box := ground_mesh.mesh as BoxMesh
		if box.material is StandardMaterial3D:
			var floor_mat := box.material as StandardMaterial3D
			var tex := floor_mat.albedo_texture
			_check("竞技场地面已换亮色贴图", tex != null and tex.resource_path.ends_with("prototype_ground.png"),
				"实际=%s" % (tex.resource_path if tex else "null"))
		else:
			_fail("竞技场地面材质类型异常")
	else:
		_fail("找不到竞技场 GroundMesh")
	arena_instance.free()

	# 树材质明亮化
	var tree_scene := load("res://scenes/environment/tree.tscn") as PackedScene
	if tree_scene:
		var tree_instance := tree_scene.instantiate()
		var leaf := tree_instance.get_node_or_null("Leaves") as MeshInstance3D
		if leaf and leaf.mesh is SphereMesh:
			pass # 树叶为多球体组合，具体子节点略
		tree_instance.free()

	# --- 头顶名牌 WoW 化（小号字 + 身份配色）---
	await _test_nametags()


func _test_nametags() -> void:
	var root := get_tree().root

	# 参数统一：pixel_size 0.02 / font_size 16 / 描边 6（三处场景）
	var nametag_targets := [
		["res://scenes/monsters/monster.tscn", "NameLabel", "怪物名牌"],
		["res://scenes/monsters/training_dummy.tscn", "NameLabel", "木桩名牌"],
		["res://scenes/level/player.tscn", "PlayerNick/Nickname", "玩家名牌"],
	]
	for target in nametag_targets:
		var scene := load(target[0]) as PackedScene
		if scene == null:
			_fail("无法加载 %s" % target[0])
			continue
		var instance := scene.instantiate()
		if instance is Monster:
			instance.monster_id = "wolf" # _ready 前设好，取普通怪数据
		root.call_deferred("add_child", instance)
		await get_tree().process_frame
		await get_tree().process_frame
		var label := instance.get_node_or_null(target[1]) as Label3D
		var who: String = target[2]
		if label == null:
			_fail("%s 找不到名牌节点（%s）" % [who, target[1]])
		else:
			_check("%s pixel_size=0.02（小号字，历史 bug 0.06 已修复）" % who,
				is_equal_approx(label.pixel_size, 0.02), "实际=%.3f" % label.pixel_size)
			_check("%s font_size=16" % who, label.font_size == 16, "实际=%d" % label.font_size)
			_check("%s 细描边=6" % who, label.outline_size == 6, "实际=%d" % label.outline_size)
		instance.free()

	# 颜色分级：普通白 / 精英金 / 仇恨橙红（monster.gd _name_color）
	var monster_scene := load("res://scenes/monsters/monster.tscn") as PackedScene
	var normal_monster := monster_scene.instantiate()
	normal_monster.monster_id = "wolf"
	root.call_deferred("add_child", normal_monster)
	await get_tree().process_frame
	await get_tree().process_frame
	var normal_label := normal_monster.get_node_or_null("NameLabel") as Label3D
	if normal_label:
		_check("怪物名牌文本含等级（名字 Lv.X 格式）", normal_label.text.containsn("Lv."),
			"实际=%s" % normal_label.text)
	var normal_color := normal_monster._name_color(false) as Color
	_check("普通怪名牌为白色（三通道接近）",
		absf(normal_color.r - normal_color.g) < 0.05 and absf(normal_color.g - normal_color.b) < 0.05
		and normal_color.r >= 0.8, "实际=%s" % str(normal_color))
	var aggro_color := normal_monster._name_color(true) as Color
	_check("被激怒怪名牌为橙红（R 高 B 低）", aggro_color.r > 0.9 and aggro_color.b < 0.5,
		"实际=%s" % str(aggro_color))
	normal_monster.free()

	var elite_monster := monster_scene.instantiate()
	elite_monster.monster_id = "spider_elite"
	root.call_deferred("add_child", elite_monster)
	await get_tree().process_frame
	await get_tree().process_frame
	var elite_color := elite_monster._name_color(false) as Color
	_check("精英怪名牌为金色（R>G>B 且明亮）",
		elite_color.r > elite_color.g and elite_color.g > elite_color.b and elite_color.r >= 0.9,
		"实际=%s" % str(elite_color))
	var elite_label := elite_monster.get_node_or_null("NameLabel") as Label3D
	if elite_label:
		_check("精英名牌带（精英）标识", elite_label.text.containsn("（精英）"),
			"实际=%s" % elite_label.text)
	elite_monster.free()


# ===== 工具 =====

func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS  %s" % name)
	else:
		var message := "FAIL  %s" % name
		if not detail.is_empty():
			message += "  （%s）" % detail
		print(message)
		_failures.append(message)


func _fail(message: String) -> void:
	print("FAIL  %s" % message)
	_failures.append(message)


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("=== M6 测试全部通过 ===")
	else:
		print("=== M6 测试失败 %d 项 ===" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)
