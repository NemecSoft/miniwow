class_name MainMenuUI
extends Control

signal host_pressed(nickname: String, skin: String)
signal join_pressed(nickname: String, skin: String, address: String)
signal quit_pressed

const SKIN_OPTIONS: Array[String] = ["Blue", "Yellow", "Green", "Red"] ## 外观值（传给 Network）
const SKIN_LABELS: Array[String] = ["蓝色", "黄色", "绿色", "红色"] ## 外观显示名（翻译键）
const SAFE_AREA_MARGIN := 24.0

@onready var skin_input: OptionButton = $MainContainer/MainMenu/Option2/SkinInput
@onready var nick_input: LineEdit = $MainContainer/MainMenu/Option1/NickInput
@onready var address_input: LineEdit = $MainContainer/MainMenu/Option3/AddressInput
@onready var main_container: VBoxContainer = $MainContainer
@onready var language_button: Button = $MainContainer/MainMenu/Option4/Language


func _ready() -> void:
	_refresh_skin_options()
	skin_input.select(0)
	_refresh_language_button()
	LanguageManager.language_changed.connect(_on_language_changed)
	resized.connect(_update_responsive_layout)
	call_deferred("_update_responsive_layout")


## 外观选项走翻译（M6 多语言）；id 存索引，get_skin() 再映射回英文值
func _refresh_skin_options() -> void:
	var selected := skin_input.selected
	skin_input.clear()
	for i in SKIN_LABELS.size():
		skin_input.add_item(tr(SKIN_LABELS[i]), i)
	skin_input.select(maxi(0, selected))


func _refresh_language_button() -> void:
	language_button.text = LanguageManager.language_button_text()


func _on_language_pressed() -> void:
	LanguageManager.toggle_language()


func _on_language_changed(_locale: String) -> void:
	_refresh_skin_options()
	_refresh_language_button()


func _on_host_pressed() -> void:
	var nickname = nick_input.text.strip_edges()
	var skin = get_skin()
	host_pressed.emit(nickname, skin)


func _on_join_pressed() -> void:
	var nickname = nick_input.text.strip_edges()
	var skin = get_skin()
	var address = address_input.text.strip_edges()
	join_pressed.emit(nickname, skin, address)


func _on_quit_pressed():
	quit_pressed.emit()


func show_menu():
	show()
	call_deferred("_update_responsive_layout")


func hide_menu():
	hide()


func is_menu_visible() -> bool:
	return visible


func _update_responsive_layout() -> void:
	if not main_container:
		return
	var available_size := Vector2(
		maxf(1.0, size.x - SAFE_AREA_MARGIN * 2.0), maxf(1.0, size.y - SAFE_AREA_MARGIN * 2.0)
	)
	var content_size := main_container.get_combined_minimum_size()
	if content_size.x <= 0.0 or content_size.y <= 0.0:
		return
	var scale_factor := minf(1.0, minf(available_size.x / content_size.x, available_size.y / content_size.y))
	main_container.pivot_offset = main_container.size * 0.5
	main_container.scale = Vector2.ONE * scale_factor


func get_skin() -> String:
	var index := skin_input.selected
	if index < 0 or index >= SKIN_OPTIONS.size():
		index = 0
	return SKIN_OPTIONS[index]
