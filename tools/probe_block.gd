@tool
extends Node
## M20-Bot 障碍诊断：bot 卡在 (-28,3,50) 时，查询该位置周围的碰撞体。

func _ready() -> void:
	var lvl = load("res://scenes/level/level.tscn").instantiate()
	lvl.name = "Level"
	get_tree().root.call_deferred("add_child", lvl)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(3.0).timeout

	var center := Vector3(-28, 3, 50)
	var space: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 6.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = 0xFFFFFFFF
	var results: Array = space.intersect_shape(query, 32)
	print("== (-28,3,50) 半径 6m 内碰撞体: %d 个 ==" % results.size())
	for r in results:
		var collider: Object = r.get("collider")
		var collider_node: Node = collider as Node
		var path_str: String = str(collider_node.get_path()) if collider_node != null else "?"
		# 只列环境类（排除 bot 自身/玩家）
		if not path_str.begins_with("/root/Level/PlayersContainer"):
			print("  碰撞体: %s" % path_str)

	# 同时看看 bot 在哪、在干什么
	for bot_id in [9001]:
		var bot := get_node_or_null("/root/Level/PlayersContainer/%d" % bot_id)
		if bot != null:
			print("bot%d pos=%s 速度=%s" % [bot_id, bot.global_position, bot.velocity])
	print("=== PROBE_BLOCK_DONE ===")
	get_tree().quit(0)
