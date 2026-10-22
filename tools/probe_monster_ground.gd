extends Node3D
## M25d 附加诊断：逐怪刷新点 (x,z) 扫描真实地面（物理射线 vs terrain 数据），
## 弄清村南怪区 z 88~104 的地面真相（audit 中 Raider y=-18 / Lich ground=4.17 存疑）。

const POINTS := [ Vector2(28, 102), Vector2(34, 98), Vector2(46, 92), Vector2(52, 88), Vector2(10, 98), Vector2(24, 96), Vector2(-34, 102), Vector2(-46, 96),
	Vector2(-40, 96), Vector2(-44, 100), Vector2(-36, 88), Vector2(-42, 92),
	Vector2(-38, 104), Vector2(-12, 96), Vector2(-16, 100), Vector2(-8, 104),
	Vector2(-4, 100), Vector2(-2, 104), Vector2(16, 100), Vector2(20, 104),
	Vector2(32, 100), Vector2(6, 100), Vector2(12, 102),
]

func _ready() -> void:
	var level: Node3D = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	get_tree().root.call_deferred("add_child", level)
	await get_tree().create_timer(12.0).timeout
	var starter := level.get_node_or_null("Environment/TerrainStarter")
	var t = starter.terrain if starter != null else null
	var space := get_viewport().world_3d.direct_space_state
	for p in POINTS:
		var from := Vector3(p.x, 60, p.y)
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -160, 0))
		var hit := space.intersect_ray(query)
		var phys: float = (hit.position.y as float) if not hit.is_empty() else -999.0
		var terr: float = -999.0
		if t != null and t.data != null:
			terr = t.data.get_height(Vector3(p.x, 0.0, p.y))
		printerr("GROUND (%.0f, %.0f): 物理=%.2f terrain=%.2f" % [p.x, p.y, phys, terr])
	printerr("SCAN_DONE")
	get_tree().quit()
