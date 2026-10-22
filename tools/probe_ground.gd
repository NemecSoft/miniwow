extends Node3D
## M25：对比 Terrain3D 数据高度 vs 物理射线地面（村区一致性检查）。

func _ready() -> void:
	var level: Node3D = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	get_tree().root.call_deferred("add_child", level)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var starter := level.get_node("Environment/TerrainStarter")
	var t = starter.terrain
	var space := get_viewport().world_3d.direct_space_state
	for p in [Vector2(0, 70), Vector2(8, 74), Vector2(-8, 66), Vector2(0, 95), Vector2(20, 98), Vector2(0, 320), Vector2(-20, -12)]:
		var from := Vector3(p.x, 90, p.y)
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -120, 0))
		var hit := space.intersect_ray(query)
		var phys: float = (hit.position.y as float) if not hit.is_empty() else -99.0
		var terr: float = -99.0
		if t != null and t.data != null:
			terr = t.data.get_height(Vector3(p.x, 0.0, p.y))
		printerr("GND (%.0f, %.0f): 物理=%.2f terrain数据=%.2f" % [p.x, p.y, phys, terr])
	printerr("SCAN_DONE")
	get_tree().quit()
