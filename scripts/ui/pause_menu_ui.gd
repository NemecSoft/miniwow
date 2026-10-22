class_name PauseMenuUI
extends Control

signal resume_pressed
signal main_menu_pressed
signal quit_pressed

const SAFE_AREA_MARGIN := 16.0

@onready var resume_button: Button = $Overlay/Panel/MarginContainer/Buttons/Resume
@onready var language_button: Button = $Overlay/Panel/MarginContainer/Buttons/Language
@onready var theme_button: Button = $Overlay/Panel/MarginContainer/Buttons/ThemeButton
@onready var panel: PanelContainer = $Overlay/Panel

# M37：声音设置控件
@onready var master_slider: HSlider = $Overlay/Panel/MarginContainer/Buttons/AudioPanel/MasterRow/MasterSlider
@onready var master_value: Label = $Overlay/Panel/MarginContainer/Buttons/AudioPanel/MasterRow/MasterValue
@onready var sfx_slider: HSlider = $Overlay/Panel/MarginContainer/Buttons/AudioPanel/SfxRow/SfxSlider
@onready var sfx_value: Label = $Overlay/Panel/MarginContainer/Buttons/AudioPanel/SfxRow/SfxValue
@onready var ambient_slider: HSlider = $Overlay/Panel/MarginContainer/Buttons/AudioPanel/AmbientRow/AmbientSlider
@onready var ambient_value: Label = $Overlay/Panel/MarginContainer/Buttons/AudioPanel/AmbientRow/AmbientValue
# M43：背景音乐单独一档
@onready var music_slider: HSlider = $Overlay/Panel/MarginContainer/Buttons/AudioPanel/MusicRow/MusicSlider
@onready var music_value: Label = $Overlay/Panel/MarginContainer/Buttons/AudioPanel/MusicRow/MusicValue
@onready var mute_button: CheckButton = $Overlay/Panel/MarginContainer/Buttons/AudioPanel/MuteButton

# M39：游戏设置控件（坐骑光环开关）
@onready var hover_halo_button: CheckButton = $Overlay/Panel/MarginContainer/Buttons/GameplayPanel/HoverHaloButton


func _ready() -> void:
	_refresh_language_button()
	_refresh_theme_button()
	LanguageManager.language_changed.connect(_on_language_changed)
	ThemeManager.theme_changed.connect(_on_theme_changed)
	resized.connect(_update_responsive_layout)
	call_deferred("_update_responsive_layout")
	_setup_audio_controls()
	_setup_gameplay_controls()
	hide()


func _refresh_language_button() -> void:
	language_button.text = LanguageManager.language_button_text()


func _on_language_pressed() -> void:
	LanguageManager.toggle_language()


func _on_language_changed(_locale: String) -> void:
	_refresh_language_button()


## M21-Theme：暂停菜单一键切换双主题
const THEME_LABELS := {"wow": "魔兽世界", "sc2": "星际争霸2"}


func _refresh_theme_button() -> void:
	theme_button.text = "界面主题：%s" % THEME_LABELS.get(ThemeManager.theme_id(), "??")


func _on_theme_pressed() -> void:
	ThemeManager.toggle_theme()


func _on_theme_changed(_theme_id: String) -> void:
	_refresh_theme_button()


func show_menu() -> void:
	show()
	call_deferred("_update_responsive_layout")
	# M37：每次打开菜单都从设置同步一次（可能被其它地方改过）
	_sync_from_settings()
	resume_button.grab_focus()


func hide_menu() -> void:
	hide()


func is_menu_visible() -> bool:
	return visible


func _update_responsive_layout() -> void:
	if not panel:
		return
	var available_size := Vector2(
		maxf(1.0, size.x - SAFE_AREA_MARGIN * 2.0), maxf(1.0, size.y - SAFE_AREA_MARGIN * 2.0)
	)
	var panel_size := panel.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		return
	var scale_factor := minf(1.0, minf(available_size.x / panel_size.x, available_size.y / panel_size.y))
	panel.pivot_offset = panel_size * 0.5
	panel.scale = Vector2.ONE * scale_factor


func _on_resume_pressed() -> void:
	resume_pressed.emit()


func _on_main_menu_pressed() -> void:
	main_menu_pressed.emit()


func _on_quit_pressed() -> void:
	quit_pressed.emit()


# ===== M37：声音设置 =====

func _setup_audio_controls() -> void:
	master_slider.value_changed.connect(_on_master_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	ambient_slider.value_changed.connect(_on_ambient_changed)
	music_slider.value_changed.connect(_on_music_changed)
	mute_button.toggled.connect(_on_mute_toggled)
	_sync_from_settings()


## 从 AudioSettings 读当前值刷新 UI（不触发 value_changed 回写）
func _sync_from_settings() -> void:
	var v := AudioSettings.get_volumes()
	master_slider.set_value_no_signal(v.x * 100.0)
	sfx_slider.set_value_no_signal(v.y * 100.0)
	ambient_slider.set_value_no_signal(v.z * 100.0)
	music_slider.set_value_no_signal(v.w * 100.0)
	master_value.text = AudioSettings.format_percent(v.x)
	sfx_value.text = AudioSettings.format_percent(v.y)
	ambient_value.text = AudioSettings.format_percent(v.z)
	music_value.text = AudioSettings.format_percent(v.w)
	mute_button.set_pressed_no_signal(AudioSettings.muted)
	# M39：坐骑光环开关也每次打开菜单时同步（可能在别处改过）
	_sync_gameplay_from_settings()


func _on_master_changed(value: float) -> void:
	AudioSettings.set_master_volume(value / 100.0)
	master_value.text = AudioSettings.format_percent(value / 100.0)
	# M37 取证：拉到 0 时打印总线实际状态（验证真静音而非"最小声"）
	if value <= 0.0:
		AudioSettings.debug_dump_buses()


func _on_sfx_changed(value: float) -> void:
	AudioSettings.set_sfx_volume(value / 100.0)
	sfx_value.text = AudioSettings.format_percent(value / 100.0)


func _on_ambient_changed(value: float) -> void:
	AudioSettings.set_ambient_volume(value / 100.0)
	ambient_value.text = AudioSettings.format_percent(value / 100.0)


## M43：背景音乐音量（独立 Music 总线，与音效/环境音分档）
func _on_music_changed(value: float) -> void:
	AudioSettings.set_music_volume(value / 100.0)
	music_value.text = AudioSettings.format_percent(value / 100.0)


func _on_mute_toggled(pressed: bool) -> void:
	AudioSettings.set_muted(pressed)


# ===== M39：游戏设置（坐骑光环）=====

func _setup_gameplay_controls() -> void:
	hover_halo_button.toggled.connect(_on_hover_halo_toggled)
	_sync_gameplay_from_settings()


## 从 VehicleSettings 读当前值刷新 UI（不触发 toggled 回写）
func _sync_gameplay_from_settings() -> void:
	hover_halo_button.set_pressed_no_signal(VehicleSettings.is_hover_halo_enabled())


func _on_hover_halo_toggled(pressed: bool) -> void:
	VehicleSettings.set_hover_halo(pressed)
