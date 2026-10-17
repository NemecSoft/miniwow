class_name QuestUI
extends CanvasLayer

## MiniWoW 任务面板（M4）：靠近卫兵队长·卡尔按 E 打开。
## 列出全部任务：可接（接取按钮）/ 进行中（进度）/ 可交付（交付按钮+奖励预览）/ 已完成（灰色）。
## 接取与交付都走 RPC 到服务器权威结算；quest_state_changed 信号驱动实时刷新。

signal quest_closed

var current_player: Character = null

@onready var gold_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/TitleBar/GoldLabel
@onready var quest_list: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBoxContainer/ScrollContainer/QuestList
@onready var empty_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/EmptyLabel
@onready var close_button: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/TitleBar/CloseButton
@onready var interact_prompt: Label = $InteractPrompt


func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	visible = false
	interact_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()


func open_quest_log(player: Character) -> void:
	current_player = player
	if player and not player.gold_changed.is_connected(_on_gold_changed):
		player.gold_changed.connect(_on_gold_changed)
	if player and not player.quest_state_changed.is_connected(_on_quest_state_changed):
		player.quest_state_changed.connect(_on_quest_state_changed)
	refresh()
	visible = true


func close_quest_log() -> void:
	visible = false
	if current_player and current_player.gold_changed.is_connected(_on_gold_changed):
		current_player.gold_changed.disconnect(_on_gold_changed)
	if current_player and current_player.quest_state_changed.is_connected(_on_quest_state_changed):
		current_player.quest_state_changed.disconnect(_on_quest_state_changed)
	current_player = null


func refresh() -> void:
	if current_player == null:
		return
	gold_label.text = tr("金币: %d") % current_player.gold
	_build_quest_list()


func set_prompt_visible(value: bool) -> void:
	interact_prompt.visible = value and not visible


func _on_close_pressed() -> void:
	close_quest_log()
	quest_closed.emit()


func _on_gold_changed(total: int) -> void:
	gold_label.text = tr("金币: %d") % total


func _on_quest_state_changed() -> void:
	refresh()


func _build_quest_list() -> void:
	for child in quest_list.get_children():
		child.queue_free()
	var visible_count := 0
	for quest in QuestDatabase.get_all_quests():
		var status := current_player.get_quest_status(quest.id)
		if status == "unknown":
			continue
		if status == "locked":
			# 锁定的任务只显示一行灰色提示，不提供按钮
			visible_count += 1
			quest_list.add_child(_create_locked_row(quest))
			continue
		visible_count += 1
		quest_list.add_child(_create_quest_row(quest, status))
	empty_label.visible = visible_count == 0


func _create_locked_row(quest: QuestData) -> Control:
	var label := Label.new()
	label.text = tr("【%s】 —— 尚未开放") % tr(quest.name)
	label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(460, 0)
	return label


func _create_quest_row(quest: QuestData, status: String) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.14, 0.9)
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	var title_color := Color(0.9, 0.9, 0.9)
	if status == "ready":
		title_color = Color(1.0, 0.85, 0.3)
	elif status == "active":
		title_color = Color(0.65, 0.9, 0.65)
	elif status == "done":
		title_color = Color(0.45, 0.45, 0.45)

	var name_label := Label.new()
	name_label.text = "【%s】" % tr(quest.name)
	name_label.add_theme_color_override("font_color", title_color)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var objective_label := Label.new()
	if status == "done":
		objective_label.text = tr("%s —— 已完成") % tr(quest.objective_text)
	elif status == "ready":
		objective_label.text = tr("%s %d/%d（可交付）") % [
			tr(quest.objective_text), current_player.get_quest_count(quest.id), quest.required_count
		]
	else:
		objective_label.text = "%s %d/%d" % [
			tr(quest.objective_text), current_player.get_quest_count(quest.id), quest.required_count
		]
	objective_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(objective_label)

	if status != "done":
		var reward_label := Label.new()
		reward_label.text = tr("奖励：%s") % quest.get_reward_summary()
		reward_label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.95))
		reward_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(reward_label)

	if status == "available" or status == "ready":
		var button := Button.new()
		button.text = tr("接取") if status == "available" else tr("交付")
		button.custom_minimum_size = Vector2(72, 40)
		var quest_id := quest.id # lambda 捕获中间变量
		button.pressed.connect(func(): _on_action_pressed(quest_id, status))
		hbox.add_child(button)

	return panel


func _on_action_pressed(quest_id: String, status: String) -> void:
	if current_player == null:
		return
	if status == "available":
		current_player.request_accept_quest.rpc_id(1, quest_id)
	elif status == "ready":
		current_player.request_turn_in_quest.rpc_id(1, quest_id)
	refresh() # 服务器权威值随后经 quest_state_changed 再次刷新
