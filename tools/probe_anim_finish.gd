extends Node3D

## M16c 探针：验证烘焙动画 SwordSlash 播完是否触发 animation_finished。
## 若不触发 → is_attacking 永不复位 → Idle/Run 全被攻击锁拦截 → 模型定格末帧（低头）。

func _ready() -> void:
	var body_scene: PackedScene = load("res://scenes/monsters/robot_body.tscn")
	var body := body_scene.instantiate()
	add_child(body)
	var anim_player := body.get_node("AnimationPlayer") as AnimationPlayer
	var lib := anim_player.get_animation_library(&"")
	lib.add_animation(&"SwordSlash", load("res://assets/animations/retarget/sword_slash.tres"))
	lib.add_animation(&"Strike", load("res://assets/animations/retarget/strike_jab.tres"))

	anim_player.animation_finished.connect(func(anim_name: StringName) -> void:
		printerr("FINISHED: ", anim_name, " at ", Time.get_ticks_msec())
	)

	await get_tree().process_frame
	printerr("PROBE: 播 SwordSlash @1.5x，length=", lib.get_animation(&"SwordSlash").length)
	anim_player.play(&"SwordSlash", -1, 1.5)
	# 理论播完时间 1.53/1.5 ≈ 1.02s，等 2 秒足够
	await get_tree().create_timer(2.0).timeout
	printerr("PROBE: 2 秒后 is_playing=", anim_player.is_playing(),
		" 当前=", anim_player.current_animation,
		" position=", anim_player.current_animation_position)

	# 对照组：原版 Attack1 @1.5x
	printerr("PROBE: 播 Attack1 @1.5x，length=", lib.get_animation(&"Attack1").length)
	anim_player.play(&"Attack1", -1, 1.5)
	await get_tree().create_timer(2.0).timeout
	printerr("PROBE: 2 秒后 is_playing=", anim_player.is_playing(),
		" 当前=", anim_player.current_animation)
	get_tree().quit(0)
