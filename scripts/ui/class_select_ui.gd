class_name ClassSelectUI
extends CanvasLayer

## MiniWoW 职业选择界面（M5）：出生首次弹出，之后可在村庄找职业训练师重新选择。
## 卡片由 ClassDatabase 数据驱动（职业描述 + 4 个技能预览），选择走 RPC 服务器权威结算。

signal class_select_closed

const CLASS_COLORS := {
	"warrior": Color(1.0, 0.5, 0.35),
	"mage": Color(0.55, 0.7, 1.0),
	"priest": Color(1.0, 0.85, 0.45),
	"infantry": Color(0.62, 0.68, 0.75),
}

var current_player: Character = null

@onready var card_container: GridContainer = $CenterContainer/Panel/MarginContainer/VBoxContainer/CardContainer
@onready var close_button: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/TitleBar/CloseButton
@onready var interact_prompt: Label = $InteractPrompt


func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close_pressed)
	_build_cards()


func open(player: Character) -> void:
	current_player = player
	if player and not player.class_changed.is_connected(_on_player_class_changed):
		player.class_changed.connect(_on_player_class_changed)
	visible = true


func close_panel() -> void:
	visible = false
	if current_player and current_player.class_changed.is_connected(_on_player_class_changed):
		current_player.class_changed.disconnect(_on_player_class_changed)
	current_player = null
	class_select_closed.emit()


func set_prompt_visible(value: bool) -> void:
	interact_prompt.visible = value and not visible


## 数据驱动生成职业卡（M23：Grid 自动排列，每行最多 4 张，新职业自动换行）
func _build_cards() -> void:
	for child in card_container.get_children():
		child.queue_free()
	var classes := ClassDatabase.get_all_classes()
	# 列数 = min(4, 职业数)：3 职业一行三张，5+ 职业自动换行
	card_container.columns = mini(4, maxi(1, classes.size()))
	for class_data in classes:
		var color: Color = CLASS_COLORS.get(class_data.id, Color(0.8, 0.8, 0.8))
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(190, 0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # 等宽拉伸填满网格
		card.add_theme_constant_override("separation", 6)

		# M23：卡顶 3D 模型预览（外观与游戏内一致：步兵 KayKit，其余 GodotRobot）
		var preview := ClassPreviewViewport.new()
		preview.show_class(class_data.id, color, class_data.id == "infantry")
		card.add_child(preview)

		var name_label := Label.new()
		name_label.text = tr(class_data.display_name)
		name_label.add_theme_font_size_override("font_size", 22)
		name_label.add_theme_color_override("font_color", color)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(name_label)

		var desc_label := Label.new()
		desc_label.text = tr(class_data.description)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size = Vector2(180, 0)
		desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL  # 撑开剩余高度→按钮贴底对齐
		desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		desc_label.add_theme_font_size_override("font_size", 13)
		card.add_child(desc_label)

		var stats_label := Label.new()
		stats_label.text = tr("生命 %d · 法力 %d\n攻击 %d · 防御 %d") % [
			class_data.base_max_hp, class_data.base_max_mp, class_data.base_atk, class_data.base_def
		]
		stats_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		stats_label.add_theme_font_size_override("font_size", 13)
		card.add_child(stats_label)

		var skills_label := Label.new()
		var lines := PackedStringArray()
		for i in class_data.skill_ids.size():
			var skill := SkillDatabase.get_skill(class_data.skill_ids[i])
			if skill:
				lines.append("%d %s" % [i + 1, tr(skill.skill_name)])
		skills_label.text = "\n".join(lines)
		skills_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
		skills_label.add_theme_font_size_override("font_size", 13)
		card.add_child(skills_label)

		var button := Button.new()
		button.text = tr("成为%s") % tr(class_data.display_name)
		button.theme_type_variation = &"PrimaryButton"  # M22：吃主题主按钮变体
		button.custom_minimum_size = Vector2(0, 36)
		var class_id: String = class_data.id # lambda 捕获副本
		button.pressed.connect(func(): _on_class_pressed(class_id))
		card.add_child(button)

		card_container.add_child(card)


func _on_class_pressed(class_id: String) -> void:
	if current_player:
		current_player.request_choose_class.rpc_id(1, class_id)
	# 选择后由 class_changed 信号关闭；断线等异常情况下给个兜底延迟
	close_panel()


func _on_player_class_changed(_class_id: String) -> void:
	close_panel()


func _on_close_pressed() -> void:
	close_panel()
