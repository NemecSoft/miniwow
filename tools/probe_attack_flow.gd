extends Node

## M16c 探针：完整链路复现"挥拳后一直低头"。
## 实例化真 player（level 环境），持剑普攻 → 等动画播完 → 检查动画状态与 is_attacking。
## 运行方式：godot --headless --path . res://tools/probe_attack_flow.tscn

func _ready() -> void:
	var level_scene := load("res://scenes/level/level.tscn") as PackedScene
	var level := level_scene.instantiate()
	get_tree().root.call_deferred("add_child", level)
	await get_tree().process_frame
	var players_container := level.get_node_or_null("PlayersContainer") as Node3D
	var player_scene := load("res://scenes/level/player.tscn") as PackedScene
	var player_instance := player_scene.instantiate() as CharacterBody3D
	player_instance.name = "1"
	players_container.add_child(player_instance, true)
	for i in range(30):
		await get_tree().physics_frame
	var player := players_container.get_node_or_null("1") as CharacterBody3D
	if player == null:
		printerr("PROBE-FAIL: 玩家未生成")
		get_tree().quit(1)
		return

	var body: Node = player.get("_body")
	var anim_player := player.get_node("GodotRobot3D/AnimationPlayer") as AnimationPlayer

	# 关主菜单 + 显示 HUD（验证 M16c HUD 显隐），并禁玩家物理防 _freeze 干扰
	var main_menu: Node = level.get_node("MainMenuUI")
	main_menu.call("hide_menu")
	var hud: CanvasLayer = level.get_node("HUD")
	printerr("PROBE: HUD visible=", hud.visible, "（关菜单后应为 true）")
	player.set_physics_process(false)

	# 相机对着玩家（视觉复现低头 bug）
	var cam := Camera3D.new()
	cam.position = player.global_position + Vector3(0, 1.6, 3.0)
	add_child(cam)
	cam.look_at(player.global_position + Vector3(0, 1.0, 0))
	cam.make_current()

	# 装备铁剑（持剑分支）
	var inv = player.get("player_inventory")
	if inv:
		var idx: int = inv.get_slot_index_of("sword_iron")
		if idx >= 0:
			inv.equip_from_slot(idx, 0)
			await get_tree().process_frame

	# 记录 finished 信号
	anim_player.animation_finished.connect(func(n: StringName) -> void:
		printerr("PROBE-FINISHED: ", n)
	)

	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	_shot("m16c_0_idle.png")

	# 模拟走路：禁物理后直接驱动动画（绕过 _freeze 覆盖）
	body.call("play_animation_state", &"Run")
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	_shot("m16c_1_run.png")
	printerr("PROBE: 走路 state=", body._current_state)

	# 挥拳（持剑 → SwordSlash）
	player.call("_play_attack_animation", &"Attack1")
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	_shot("m16c_2_attack.png")
	printerr("PROBE: 攻击中 state=", body._current_state,
		" is_attacking=", player.get("is_attacking"))

	# 等播完 + 继续走路（复现"走路低头"）
	await get_tree().create_timer(1.2).timeout
	printerr("PROBE: 播完后 state=", body._current_state,
		" is_attacking=", player.get("is_attacking"))
	body.call("play_animation_state", &"Run")
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	_shot("m16c_3_run_after.png")
	printerr("PROBE: 攻击后走路 state=", body._current_state)
	get_tree().quit(0)


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/shots/" + file_name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("SHOT: ", file_name)


func animation_player_path(player: Node) -> String:
	var ap := player.get_node_or_null("GodotRobot3D/AnimationPlayer") as AnimationPlayer
	var body_ap := (player.get("_body") as Node).get("animation_player") as AnimationPlayer
	return "signal_target=%s body_export=%s same=%s" % [
		"ok" if ap else "null", "ok" if body_ap else "null", ap == body_ap]
