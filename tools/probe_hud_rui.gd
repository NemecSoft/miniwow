extends Node
## 探针：验证 HUD 的 Reactive UI 视图层（M19-Reactive）。
## 以场景方式运行（autoload 完整加载）：实例化 hud.tscn → 检查 RUI 渲染树
## → bind_class_skills → 死亡面板显隐 → 输出结论并退出。

var _fails: Array[String] = []
var _checks := 0


func _ready() -> void:
	var hud_scene := load("res://scenes/ui/hud.tscn") as PackedScene
	var hud := hud_scene.instantiate()
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. RUI 根节点挂载：HUD(CanvasLayer) 下应有 Control 根
	var rui_root: Control = null
	for child in hud.get_children():
		if child is Control:
			rui_root = child
	_checks += 1
	if rui_root == null:
		_fails.append("HUD 下未找到 RUI 渲染的 Control 根")
	else:
		print("PASS: RUI 根 Control 已挂载，子节点 %d 个" % rui_root.get_child_count())

	# 2. 组件树关键面板
	var labels: Array[Label] = []
	var bars: Array[ProgressBar] = []
	var panels: Array[PanelContainer] = []
	_collect(rui_root if rui_root else hud, labels, bars, panels)
	_checks += 1
	if panels.is_empty():
		_fails.append("组件树中没有 PanelContainer（面板样式未渲染）")
	else:
		print("PASS: PanelContainer x%d" % panels.size())

	# 3. bind_class_skills：槽位 0 恒为普攻（名称以 SkillDatabase 实际技能名为准）
	hud.bind_class_skills(["skill_2", "skill_3", "skill_4"])
	await get_tree().process_frame
	await get_tree().process_frame
	labels.clear()
	bars.clear()
	panels.clear()
	_collect(rui_root if rui_root else hud, labels, bars, panels)
	_checks += 1
	var basic_skill := SkillDatabase.get_skill("basic_attack")
	var basic_name: String = tr(basic_skill.skill_name) if basic_skill else ""
	var found_basic := false
	for l in labels:
		if l.text == basic_name:
			found_basic = true
	if not found_basic:
		_fails.append("技能栏未渲染出普攻槽名称（期望 %s）" % basic_name)
	else:
		print("PASS: bind_class_skills 后技能名称已刷新（普攻槽「%s」在）" % basic_name)

	# 4. 三条进度条（HP/MP/XP）
	_checks += 1
	if bars.size() < 3:
		_fails.append("进度条不足 3 条（HP/MP/XP），实际 %d" % bars.size())
	else:
		print("PASS: 进度条 x%d" % bars.size())

	# 5. 死亡面板显隐
	hud.show_death_panel()
	await get_tree().process_frame
	await get_tree().process_frame
	panels.clear()
	_collect_panels(rui_root if rui_root else hud, panels)
	_checks += 1
	var death_on := false
	for p in panels:
		if p.visible and p.size.x >= 600.0:
			death_on = true
	if not death_on:
		_fails.append("show_death_panel 后面板未显示")
	else:
		print("PASS: 死亡面板显示")
	hud.hide_death_panel()
	await get_tree().process_frame
	await get_tree().process_frame
	panels.clear()
	_collect_panels(rui_root if rui_root else hud, panels)
	_checks += 1
	var death_off := true
	for p in panels:
		if p.visible and p.size.x >= 600.0:
			death_off = false
	if not death_off:
		_fails.append("hide_death_panel 后面板未隐藏")
	else:
		print("PASS: 死亡面板隐藏")

	print("")
	if _fails.is_empty():
		print("PROBE PASS: %d/%d 项通过" % [_checks, _checks])
	else:
		print("PROBE FAIL: %d 项失败" % _fails.size())
		for f in _fails:
			print("  - %s" % f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _collect(node: Node, labels: Array, bars: Array, panels: Array) -> void:
	for child in node.get_children():
		if child is Label:
			labels.append(child)
		elif child is ProgressBar:
			bars.append(child)
		elif child is PanelContainer:
			panels.append(child)
		_collect(child, labels, bars, panels)


func _collect_panels(node: Node, panels: Array) -> void:
	for child in node.get_children():
		if child is PanelContainer:
			panels.append(child)
		_collect_panels(child, panels)
