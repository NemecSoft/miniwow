extends Node3D

## M47-D：验证 M 键世界地图是不是**圆盘**。
## 直接调 open_map 并拍引擎帧，人眼确认圆盘 + 地形是否真的按球面采样。

const OUT_DIR := "res://screenshots/m47"
var _level: Node3D


func _ready() -> void:
	Network.SERVER_PORT = 8095
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("MDP: 需要窗口模式")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "诊断", "blue")
	for i in 40:
		await get_tree().create_timer(0.5).timeout
		var pc := _level.get_node_or_null("PlayersContainer")
		if pc != null and pc.get_child_count() > 0:
			break
	var ui := _level.get_node_or_null("ClassSelectUI")
	if ui != null:
		ui.queue_free()
	await get_tree().create_timer(1.0).timeout

	var map := _level.get_node_or_null("WorldMapUI")
	if map == null:
		printerr("MDP: 没有 WorldMapUI")
		get_tree().quit(0)
		return
	printerr("MDP: 打开地图…")
	var t0 := Time.get_ticks_msec()
	map.call("open_map", _level)
	printerr("MDP: open_map 耗时 %d ms" % (Time.get_ticks_msec() - t0))
	await get_tree().create_timer(1.2).timeout
	await _shot("m47d_map_disk")
	printerr("MDP: 结束")
	get_tree().quit(0)


func _shot(base: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("MDP: 取帧失败")
		return
	img.save_png("%s/%s.png" % [OUT_DIR, base])
	printerr("MDP: 已存 " + base + ".png")
