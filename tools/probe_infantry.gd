extends Node

## M18b-3 探针：步兵 KayKit 人形外观目视截图（Idle/跑/挥砍/转圈/格挡）。
## 注意：必须开窗口跑（frame_post_draw 依赖渲染），不能 --headless。
## 运行方式：godot --path . res://tools/probe_infantry.tscn

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

	var main_menu: Node = level.get_node("MainMenuUI")
	main_menu.call("hide_menu")
	player.set_physics_process(false)

	# M18b-3：切步兵人形视觉 + 传送到空旷地面（中央广场有木桩/NPC 挡视线）
	var body: Node = player.get("_body")
	body.set("use_alt_body", true)
	player.global_position = Vector3(40, 0.2, 40)
	printerr("PROBE: alt_visual=", body.get("alt_visual"),
		" visible=", (body.get("alt_visual") as Node3D).visible if body.get("alt_visual") else "null")

	# 相机正对玩家
	var cam := Camera3D.new()
	cam.position = player.global_position + Vector3(0, 2.0, 3.2)
	add_child(cam)
	cam.look_at(player.global_position + Vector3(0, 1.0, 0))
	cam.make_current()

	await _wait(0.6)
	_dump_state(body, "idle前")
	body.call("play_animation_state", &"Idle", true) # 玩家物理被禁，手动播待机防 T-pose
	await _wait(0.5)
	await _shot("infantry_idle.png")

	body.call("play_animation_state", &"Run", true)
	await _wait(0.5)
	await _shot("infantry_run.png")

	body.call("play_animation_state", &"SwordSlash", true)
	await _wait(0.35)
	await _shot("infantry_slash.png")

	body.call("play_animation_state", &"Attack1", true)
	await _wait(0.5)
	await _shot("infantry_whirl.png")

	body.call("play_animation_state", &"Block", true)
	await _wait(0.5)
	await _shot("infantry_block.png")

	body.call("play_animation_state", &"Dodge", true)
	await _wait(0.25)
	await _shot("infantry_dodge.png")

	printerr("PROBE-DONE")
	get_tree().quit(0)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _dump_state(body: Node, tag: String) -> void:
	var alt := body.get("alt_visual") as Node3D
	var arm := (body as Node3D).get_node_or_null("RobotArmature") as Node3D
	var mannequin := alt.get_node_or_null("VisualRoot/Mannequin") as Node3D
	printerr("STATE[", tag, "] alt=", alt.visible, " arm=", arm.visible if arm else "null",
		" mannequin_in_tree=", mannequin.is_visible_in_tree() if mannequin else "null",
		" mannequin_pos=", mannequin.global_position if mannequin else "null")


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/shots/" + file_name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("SHOT: ", file_name)
