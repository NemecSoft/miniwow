extends Node3D

## Sky3D 玩家视角验证：level + 玩家实例 + 玩家自己的相机（用户实际画面路径）。
## 窗口模式跑：godot --path . res://tools/probe_sky_shot.tscn

func _ready() -> void:
	var level: Node3D = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame

	# 等地形生成/加载完成（首次生成 2048² 高度图需数十秒，轮询 starter.terrain）
	var starter := level.get_node_or_null("Environment/TerrainStarter")
	var waited := 0.0
	while waited < 300.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if starter != null and starter.terrain != null:
			break
	printerr("[PlayerShot] 地形等待 %.1f 秒, terrain=%s" % [waited, starter.terrain != null if starter else false])

	# 手动生成玩家（复刻 probe_infantry 模式）
	var players_container := level.get_node_or_null("PlayersContainer") as Node3D
	var player_scene := load("res://scenes/level/player.tscn") as PackedScene
	var player := player_scene.instantiate() as CharacterBody3D
	player.name = "1"
	players_container.add_child(player, true)
	for i in 30:
		await get_tree().physics_frame
	var main_menu: Node = level.get_node("MainMenuUI")
	main_menu.call("hide_menu")

	# 找玩家自己的相机（用户实际画面用的就是它）
	await get_tree().create_timer(1.0).timeout
	var cam := player.find_children("*", "Camera3D", true, false)
	printerr("[PlayerShot] 玩家相机数量=", cam.size())
	if cam.size() > 0:
		(cam[0] as Camera3D).make_current()
	printerr("[PlayerShot] 当前相机=", get_viewport().get_camera_3d())

	var sky3d := level.get_node_or_null("Environment/Sky3D")
	if sky3d and sky3d.tod:
		var sun: DirectionalLight3D = sky3d.sun
		printerr("[PlayerShot] time=%.2f sun_energy=%.2f ambient=%.2f contrib=%.2f" % [
			sky3d.tod.current_time, sun.light_energy,
			sky3d.environment.ambient_light_energy,
			sky3d.environment.ambient_light_sky_contribution])

	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	_shot("sky_player_view.png")

	# 贫瘠之地三景：出生地/绿洲/丘陵河床
	var cam2 := Camera3D.new()
	add_child(cam2)
	cam2.make_current()
	cam2.position = Vector3(0, 70, 380)
	cam2.look_at(Vector3(0, 60, 300))
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	_shot("barrens_spawn.png")
	cam2.position = Vector3(60, 45, -220)
	cam2.look_at(Vector3(60, 34, -280))
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	_shot("barrens_oasis.png")
	cam2.position = Vector3(-120, 75, -420)
	cam2.look_at(Vector3(-240, 45, -300))
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	_shot("barrens_hills.png")
	# 沙发飞行器特写
	cam2.position = Vector3(11, 63.8, 320)
	cam2.look_at(Vector3(6, 62, 314))
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	_shot("hover_couch.png")
	printerr("SHOT: 完成")
	get_tree().quit(0)




func _shot(file_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/shots/" + file_name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("SHOT: ", file_name)
