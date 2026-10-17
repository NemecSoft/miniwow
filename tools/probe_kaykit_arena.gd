extends Node

## M18b-4 探针：掠夺者 + roguelite 竞技场目视截图（需开窗口）。

func _ready() -> void:
	var level_scene := load("res://scenes/level/level.tscn") as PackedScene
	var level := level_scene.instantiate()
	get_tree().root.call_deferred("add_child", level)
	await get_tree().process_frame
	(level.get_node("MainMenuUI") as Node).call("hide_menu")
	for i in range(40):
		await get_tree().physics_frame
	# 相机1：竞技场全景
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 14, 92)
	cam.look_at(Vector3(0, 0, 70))
	cam.make_current()
	await RenderingServer.frame_post_draw
	await _shot("arena_wide.png")
	# 相机2：掠夺者近景
	var raider := level.get_node_or_null("Environment/Monsters/Raider1") as Node3D
	if raider:
		cam.position = raider.global_position + Vector3(0, 1.8, 2.6)
		cam.look_at(raider.global_position + Vector3(0, 0.9, 0))
		await RenderingServer.frame_post_draw
		await _shot("raider_close.png")
		printerr("PROBE: raider pos=", raider.global_position, " scale=", raider.scale)
	get_tree().quit(0)

func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/shots/" + file_name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("SHOT: ", file_name)
