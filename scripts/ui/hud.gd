class_name HUD
extends CanvasLayer

## MiniWoW 战斗 HUD（M1）。
## 绑定本地玩家后订阅属性信号；目标框由玩家的准星选择驱动。

@onready var player_name_label: Label = $PlayerFrame/NameLabel
@onready var player_level_label: Label = $PlayerFrame/LevelLabel
@onready var gold_label: Label = $PlayerFrame/GoldLabel
@onready var stats_label: Label = $PlayerFrame/StatsLabel
@onready var hp_bar: ProgressBar = $PlayerFrame/HPBar
@onready var mp_bar: ProgressBar = $PlayerFrame/MPBar
@onready var xp_bar: ProgressBar = $PlayerFrame/XPBar
@onready var xp_label: Label = $PlayerFrame/XPLabel
@onready var quest_tracker: PanelContainer = $QuestTracker
@onready var quest_list: VBoxContainer = $QuestTracker/Margin/VBox/QuestList
@onready var target_frame: Panel = $TargetFrame
@onready var target_name_label: Label = $TargetFrame/NameLabel
@onready var target_hp_bar: ProgressBar = $TargetFrame/HPBar
@onready var skill_overlays: Array[ColorRect] = [
	$SkillBar/SkillSlot1/CooldownOverlay,
	$SkillBar/SkillSlot2/CooldownOverlay,
	$SkillBar/SkillSlot3/CooldownOverlay,
	$SkillBar/SkillSlot4/CooldownOverlay,
]
@onready var skill_icons: Array[TextureRect] = [
	$SkillBar/SkillSlot1/Icon,
	$SkillBar/SkillSlot2/Icon,
	$SkillBar/SkillSlot3/Icon,
	$SkillBar/SkillSlot4/Icon,
]
@onready var skill_name_labels: Array[Label] = [
	$SkillBar/SkillSlot1/CooldownLabel,
	$SkillBar/SkillSlot2/CooldownLabel,
	$SkillBar/SkillSlot3/CooldownLabel,
	$SkillBar/SkillSlot4/CooldownLabel,
]
@onready var death_panel: PanelContainer = $DeathPanel
@onready var release_button: Button = $DeathPanel/CenterContainer/VBoxContainer/ReleaseButton

const SKILL_BAR_SLOTS := 4 ## 槽位 0 = 普攻（左键），1~3 = 职业技能（1/2/3 键）

var player: Character = null
var target_node: Node = null
var target_attributes: AttributeSet = null
var _slot_skill_ids: Array[String] = ["basic_attack", "", "", ""] ## 各槽位对应的技能 id


func _ready() -> void:
	release_button.pressed.connect(_on_release_pressed)


func bind_player(new_player: Character) -> void:
	player = new_player
	var attrs := CombatMath.get_attribute_set(player)
	if attrs == null:
		return
	player.gold_changed.connect(_on_player_gold_changed)
	player.level_changed.connect(_on_player_level_changed)
	player.experience_changed.connect(_on_player_experience_changed)
	player.quest_state_changed.connect(_on_quest_state_changed)
	player.class_changed.connect(_on_player_class_changed)
	gold_label.text = tr("金币: %d") % player.gold
	hp_bar.max_value = attrs.max_hp
	hp_bar.value = attrs.hp
	mp_bar.max_value = attrs.max_mp
	mp_bar.value = attrs.mp
	attrs.hp_changed.connect(_on_player_hp_changed)
	attrs.mp_changed.connect(_on_player_mp_changed)
	set_player_stats(attrs.atk, attrs.def)
	set_experience(player.experience, LevelData.exp_to_next(player.level))
	_refresh_level_label()
	refresh_quest_tracker()
	# M5：已选职业则直接绑定技能栏；未选则由职业选择界面驱动
	if not player.player_class.is_empty():
		var class_data := ClassDatabase.get_class_data(player.player_class)
		if class_data:
			bind_class_skills(class_data.skill_ids)


## M5：绑定职业技能到 HUD 技能栏（槽位 1~3 对应 1/2/3 键；槽位 0 永远是普攻）
func bind_class_skills(skill_ids: Array) -> void:
	for i in SKILL_BAR_SLOTS:
		var skill_id := "basic_attack" if i == 0 else String(skill_ids[i - 1]) if i - 1 < skill_ids.size() else ""
		_slot_skill_ids[i] = skill_id
		var skill := SkillDatabase.get_skill(skill_id) if not skill_id.is_empty() else null
		if skill:
			skill_icons[i].texture = skill.icon
			skill_name_labels[i].text = tr(skill.skill_name)
		else:
			skill_icons[i].texture = null
			skill_name_labels[i].text = "-"


func _on_player_class_changed(_class_id: String) -> void:
	_refresh_level_label()


## 等级标签附带职业名（Lv.3 · 法师）
func _refresh_level_label() -> void:
	if player == null:
		return
	var suffix := ""
	if not player.player_class.is_empty():
		var class_data := ClassDatabase.get_class_data(player.player_class)
		if class_data:
			suffix = " · " + tr(class_data.display_name)
	player_level_label.text = "Lv.%d%s" % [player.level, suffix]


## M3：装备加成变化时由玩家调用（换装/登录同步）
func set_player_stats(atk: int, def_value: int) -> void:
	if stats_label:
		stats_label.text = tr("攻 %d · 防 %d") % [atk, def_value]


## M4：等级/经验刷新
func _on_player_level_changed(new_level: int) -> void:
	_refresh_level_label()


func set_experience(current: int, needed: int) -> void:
	if needed <= 0: # 满级
		xp_bar.max_value = 1.0
		xp_bar.value = 1.0
		xp_label.text = tr("已满级")
		return
	xp_bar.max_value = float(needed)
	xp_bar.value = float(clampi(current, 0, needed))
	xp_label.text = tr("经验 %d/%d") % [current, needed]


func _on_player_experience_changed(current: int, needed: int) -> void:
	set_experience(current, needed)


## M4：任务追踪（右侧面板）：列出进行中/可交付任务与进度
func refresh_quest_tracker() -> void:
	if quest_list == null:
		return
	for child in quest_list.get_children():
		child.queue_free()
	if player == null:
		quest_tracker.visible = false
		return
	var has_entries := false
	for quest in QuestDatabase.get_all_quests():
		var status := player.get_quest_status(quest.id)
		if status != "active" and status != "ready":
			continue
		has_entries = true
		var row := VBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label := Label.new()
		name_label.text = "【%s】" % tr(quest.name)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if status == "ready":
			name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		else:
			name_label.add_theme_color_override("font_color", Color(0.65, 0.9, 0.65))
		var progress_label := Label.new()
		progress_label.text = "%s %d/%d" % [
			tr(quest.objective_text), player.get_quest_count(quest.id), quest.required_count
		]
		progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if status == "ready":
			progress_label.text += tr("（可交付）")
			progress_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		else:
			progress_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		row.add_child(name_label)
		row.add_child(progress_label)
		quest_list.add_child(row)
	quest_tracker.visible = has_entries


func _on_quest_state_changed() -> void:
	refresh_quest_tracker()


func set_target(new_target: Node) -> void:
	if new_target == null:
		clear_target()
		return
	target_node = new_target
	target_attributes = CombatMath.get_attribute_set(new_target)
	if target_attributes == null:
		clear_target()
		return
	target_frame.visible = true
	target_name_label.text = _get_target_display_name(new_target)
	target_hp_bar.max_value = target_attributes.max_hp
	target_hp_bar.value = target_attributes.hp
	if not target_attributes.hp_changed.is_connected(_on_target_hp_changed):
		target_attributes.hp_changed.connect(_on_target_hp_changed)


func clear_target() -> void:
	if target_attributes and target_attributes.hp_changed.is_connected(_on_target_hp_changed):
		target_attributes.hp_changed.disconnect(_on_target_hp_changed)
	target_node = null
	target_attributes = null
	target_frame.visible = false


func _get_target_display_name(node: Node) -> String:
	if node is TrainingDummy:
		return "%s Lv.%d" % [tr(node.display_name), node.level]
	if node is Monster:
		return "%s Lv.%d" % [tr(node.data.display_name), node.data.level]
	if node is Character and node.nickname:
		return "%s Lv.%d" % [node.nickname.text, node.level]
	return str(node.name)


func show_death_panel() -> void:
	death_panel.visible = true


func hide_death_panel() -> void:
	death_panel.visible = false


func _process(_delta: float) -> void:
	if player == null:
		return
	for i in SKILL_BAR_SLOTS:
		# 冷却遮罩：剩余冷却比例（0 = 不在冷却）
		skill_overlays[i].scale.y = player.get_skill_cooldown_ratio(_slot_skill_ids[i])
		# 蓝耗不足：图标压暗提示
		var skill := SkillDatabase.get_skill(_slot_skill_ids[i]) if not _slot_skill_ids[i].is_empty() else null
		var mp_cost := skill.mp_cost if skill else 0
		var attrs := CombatMath.get_attribute_set(player)
		var affordable := attrs == null or attrs.mp >= mp_cost
		skill_icons[i].modulate = Color(1, 1, 1, 1) if affordable else Color(0.45, 0.45, 0.5, 1)


func _on_player_hp_changed(current: int, maximum: int) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current


func _on_player_gold_changed(total: int) -> void:
	gold_label.text = tr("金币: %d") % total


func _on_player_mp_changed(current: int, maximum: int) -> void:
	mp_bar.max_value = maximum
	mp_bar.value = current


func _on_target_hp_changed(current: int, _maximum: int) -> void:
	target_hp_bar.value = current


func _on_release_pressed() -> void:
	if player:
		player.request_respawn_action()
