@tool
extends Node
## M24 地形扫描探针：打印复活点周边高度网格（8m 步长），
## 用于选址怪物刷新点（找平地、避开断崖——村北/村东均实测有深渊）。
## 用法：godot --headless --path <项目> res://tools/probe_terrain.tscn

func _ready() -> void:
	var lvl = load("res://scenes/level/level.tscn").instantiate()
	lvl.name = "Level"
	get_tree().root.call_deferred("add_child", lvl)
	await get_tree().process_frame
	await get_tree().process_frame
	var starter := get_node_or_null("/root/Level/Environment/TerrainStarter")
	if starter == null or starter.terrain == null:
		printerr("SCAN: TerrainStarter/terrain 未就绪")
		get_tree().quit(1)
		return
	for i in 300:
		if starter.terrain != null and starter.terrain.data != null:
			break
		await get_tree().create_timer(0.1).timeout
	if starter.terrain == null or starter.terrain.data == null:
		printerr("SCAN: 地形数据未就绪")
		get_tree().quit(1)
		return
	var data = starter.terrain.data
	# 高度网格：x -80..120（村中心向东西），z 270..380（村南北），值=地表高度
	var header := "        "
	for z in range(270, 381, 8):
		header += "%5d" % z
	printerr("SCAN 高度图（行=x，列=z，值=地表高度）")
	printerr(header)
	for x in range(-80, 121, 8):
		var row := "x=%4d  " % x
		for z in range(270, 381, 8):
			row += "%5d" % int(data.get_height(Vector3(x, 0, z)))
		printerr(row)
	printerr("=== PROBE_TERRAIN_DONE ===")
	get_tree().quit(0)
