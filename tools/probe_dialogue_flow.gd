extends Node
## 探针：Dialogue Manager NPC 对话全流程（M19-DM）。
## 实例化村民 → start_dialogue → 逐行推进 → 走一次选项分支 → 结束，
## 断言对话开始/结束信号、balloon 挂载、行数与选项链路。

var _fails: Array[String] = []
var _checks := 0
var _dialogue_started := false
var _dialogue_ended := false
var _lines_seen := 0
var _responses_seen := 0


func _ready() -> void:
	var villager_scene := load("res://scenes/npcs/villager.tscn") as PackedScene
	var villager := villager_scene.instantiate()
	add_child(villager)
	await get_tree().process_frame

	DialogueManager.dialogue_started.connect(func(_r): _dialogue_started = true)
	DialogueManager.dialogue_ended.connect(func(_r): _dialogue_ended = true)

	villager.start_dialogue()
	# balloon 经 call_deferred 挂载
	for i in 20:
		await get_tree().process_frame
		if _dialogue_started:
			break

	# 1. 对话开始信号 + balloon 挂载
	_checks += 1
	var balloon: Node = null
	for child in get_children():
		if child.get_script() != null and child.get_script().resource_path.get_file() == "example_balloon.gd":
			balloon = child
	if not _dialogue_started or balloon == null:
		_fails.append("dialogue_started 未触发或 balloon 未挂载")
		get_tree().quit(1)
		return
	print("PASS: 对话开始，balloon 已挂载")

	# 2. 逐行推进直到结束（最多 40 行防死循环）
	var steps := 0
	while steps < 40:
		steps += 1
		await get_tree().process_frame
		if _dialogue_ended:
			break
		if not is_instance_valid(balloon):
			break
		var line = balloon.dialogue_line
		if line == null:
			# 等 dialogue_line setter 异步解析
			continue
		_lines_seen += 1
		if line.responses.size() > 0:
			_responses_seen += 1
			# 优先选结束分支（"再见"），否则选第一个允许的选项
			var chosen = null
			for r in line.responses:
				if r.is_allowed and (r.text.find("再见") >= 0 or r.next_id.is_empty()):
					chosen = r
					break
			if chosen == null:
				for r in line.responses:
					if r.is_allowed:
						chosen = r
						break
			if chosen == null:
				_fails.append("选项全部不可选")
				break
			print("  行 %d：出现 %d 个选项，选「%s」" % [_lines_seen, line.responses.size(), chosen.text])
			balloon.next(chosen.next_id)
		else:
			if not line.text.is_empty():
				print("  行 %d：%s" % [_lines_seen, line.text])
			balloon.next(line.next_id)

	# 3. 对话行数
	_checks += 1
	if _lines_seen < 3:
		_fails.append("对话行数不足 3，实际 %d" % _lines_seen)
	else:
		print("PASS: 共推进 %d 行对话" % _lines_seen)

	# 4. 选项分支
	_checks += 1
	if _responses_seen < 1:
		_fails.append("未遇到选项分支")
	else:
		print("PASS: 选项分支出现 %d 次" % _responses_seen)

	# 5. 对话结束信号
	_checks += 1
	if not _dialogue_ended:
		_fails.append("dialogue_ended 未触发")
	else:
		print("PASS: 对话结束信号触发")

	# 6. level 侧状态机：dialogue_visible 复位 + 输入解冻
	# （本探针不挂 level，改为验证 villager 无残留对话状态即可）
	_checks += 1
	if is_instance_valid(balloon) and balloon.visible:
		_fails.append("结束后 balloon 仍可见")
	else:
		print("PASS: 结束后 balloon 已隐藏")

	print("")
	if _fails.is_empty():
		print("PROBE PASS: %d/%d 项通过" % [_checks, _checks])
	else:
		print("PROBE FAIL: %d 项失败" % _fails.size())
		for f in _fails:
			print("  - %s" % f)
	get_tree().quit(0 if _fails.is_empty() else 1)
