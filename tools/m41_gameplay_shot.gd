extends Node3D

## M41 真实观感截图：用玩家自己的相机（不做任何机位改动）拍进世界后的画面，
## 用来验证"玩家实际会看到什么"。只隐藏 HUD，不隐藏场景。
## 用法：godot --path <项目> res://tools/m41_gameplay_shot.tscn

const OUT := "res://screenshots/m41/gameplay/"

var _level: Node3D


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "观感", "blue")
	await get_tree().create_timer(5.0).timeout
	for cl in _level.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for c in _level.find_children("*", "Control", true, false):
		(c as Control).visible = false
	# 第 1 张：落点原地（正对村庄）
	await get_tree().create_timer(0.6).timeout
	await _save("g01_spawn.png")
	# 第 2 张：把玩家往后拉 12 米再看村庄，检验中远景地表有没有黑区/棋盘
	var p := _find_player()
	if p != null:
		p.global_position += Vector3(0, 0, 12)
		await get_tree().create_timer(1.2).timeout
		await _save("g02_back.png")
		# 第 3 张：抬高俯视，看整片地形
		p.global_position += Vector3(-18, 26, 22)
		await get_tree().create_timer(1.6).timeout
		await _save("g03_air.png")
	printerr("M41G: 结束")
	get_tree().quit(0)


func _find_player() -> Node3D:
	var pc := _level.get_node_or_null("PlayersContainer")
	if pc == null:
		return null
	for c in pc.get_children():
		if c is Node3D:
			return c as Node3D
	return null


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("M41G: img null ", fname)
		return
	var path := ProjectSettings.globalize_path(OUT + fname)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("M41G: 已存 ", fname)
