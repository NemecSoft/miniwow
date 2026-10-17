class_name RogueHealthBar
extends Node3D

## M18b-6：roguelite 双层头顶血条。
## 结构与数值照抄 godot-roguelite Components/health_bar.tscn / health_bar.gd：
## 彩色前条（立即跳变）+ 灰色后条（0.2s 缓动跟随，形成掉血残影）。
## 适配层：原版由 HealthComponent 信号驱动；MiniWoW 无该组件，
## 改为 monster.gd / player.gd 在血量同步接收端直接调 set_health()。

@export var health_color: Color = Color(0.8901961, 0.2901961, 0.25882354, 1)

@onready var front_progress_bar: ProgressBar = $SubViewport/FrontProgressBar
@onready var health_progress_bar: ProgressBar = $SubViewport/HealthProgressBar
@onready var sprite_3d: Sprite3D = $Sprite3D

func _ready() -> void:
	front_progress_bar.value = 100.0
	health_progress_bar.value = 100.0
	# resource_local_to_scene 保证多实例各自改色不串（tscn 中已声明）
	front_progress_bar.get_theme_stylebox("fill").bg_color = health_color

func set_health(current: float, max_value: float) -> void:
	if max_value <= 0.0:
		return
	# 原版逻辑：彩条立即跳到目标百分比，灰条 0.2s 从彩条旧值滑过去（残影）
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	var target_health_percentage := (current / max_value) * 100.0
	tween.tween_property(health_progress_bar, "value", target_health_percentage, 0.2) \
			.from(front_progress_bar.value)
	front_progress_bar.value = target_health_percentage

func fade_out() -> void:
	# 原版 defeat()：0.2s 淡出（死亡时调用）
	var tween = create_tween()
	tween.tween_property(sprite_3d, "transparency", 1.0, 0.2).from(0.0)
