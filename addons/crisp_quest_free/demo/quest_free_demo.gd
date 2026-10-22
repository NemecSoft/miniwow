extends Control
## Crisp Quest Free demo: a small RPG screen made of plain Godot controls styled by the Theme.
## The slider drives the mana bar and the Equip button heals the hero a little.

@onready var _slider: HSlider = %ManaSlider
@onready var _mana: ProgressBar = %Mana
@onready var _health: ProgressBar = %Health
@onready var _equip: Button = %EquipButton


func _ready() -> void:
	_slider.value_changed.connect(_on_slider_changed)
	_equip.pressed.connect(_on_equip_pressed)
	_on_slider_changed(_slider.value)


func _on_slider_changed(value: float) -> void:
	_mana.value = value


func _on_equip_pressed() -> void:
	_health.value = 20.0 if _health.value >= _health.max_value else minf(_health.value + 10.0, _health.max_value)


## Used by tests/test_addon.gd: returns an empty string when the demo wiring works.
func self_check() -> String:
	if not is_equal_approx(_mana.value, _slider.value):
		return "mana bar does not follow the slider"
	return ""
