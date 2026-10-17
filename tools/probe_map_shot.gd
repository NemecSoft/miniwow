extends Node3D

## M17 地图扩容视觉验证：加载真实 level 场景，俯瞰全图 + 四区域近景。

func _ready() -> void:
	var level: Node3D = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	# 关主菜单/HUD/聊天框，只看世界
	for ui_name in ["MainMenuUI", "HUD", "MultiplayerChatUI", "InventoryUI", "QuestUI"]:
		var ui := level.get_node_or_null(ui_name)
		if ui:
			ui.visible = false

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.55, 0.75)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.directional_shadow_max_distance = 250.0
	add_child(sun)

	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()

	# 1. 全图俯瞰（200x200）
	cam.position = Vector3(0, 150, 0.1)
	cam.look_at(Vector3(0, 0, 0), Vector3(0, 0, -1))
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	_shot("m17_overview.png")

	# 2. 东南狼群草原
	cam.position = Vector3(60, 25, 95)
	cam.look_at(Vector3(60, 0, 60))
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	_shot("m17_wolf_field.png")

	# 3. 西北石人峡谷
	cam.position = Vector3(-65, 25, -15)
	cam.look_at(Vector3(-65, 0, -65))
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	_shot("m17_golem_canyon.png")

	# 4. 东北亡灵墓地
	cam.position = Vector3(65, 25, -15)
	cam.look_at(Vector3(65, 0, -60))
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	_shot("m17_lich_grave.png")

	printerr("SHOT: 地图截图完成")
	get_tree().quit(0)


func _shot(file_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/shots/" + file_name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("SHOT: ", file_name)
