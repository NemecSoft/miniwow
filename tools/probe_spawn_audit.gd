extends Node3D
## M25d/M25c 验证探针：出生贴地约定 + 坐骑生命周期约定。
## 1. 等 terrain 就绪 + level._snap_ground_actors 贴地完成后，逐怪对比
##    home_position（静态刷新锚点，跑动不影响）与 GroundQuery 解析高度；
##    差 > 0.5 = 未贴地 FAIL；GroundQuery NAN = 非法刷点（掉洞）FAIL；
## 2. 检查 Environment/Vehicles 下的空车（无骑手沙发 = 违反 M3，FAIL）。

func _ready() -> void:
	var level: Node3D = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	get_tree().root.call_deferred("add_child", level)
	# 等 15 秒：terrain 异步创建 + _snap_ground_actors（最多等 10 秒）执行完毕
	await get_tree().create_timer(15.0).timeout
	var starter := level.get_node_or_null("Environment/TerrainStarter")
	var terrain_data: Terrain3DData = null
	if starter != null and starter.terrain != null:
		terrain_data = starter.terrain.data
	var monsters := level.get_node_or_null("Environment/Monsters")
	var fail := 0
	if monsters == null:
		printerr("AUDIT FAIL: 找不到 Monsters 容器")
		fail += 1
	else:
		for m in monsters.get_children():
			var home: Vector3 = m.get("home_position")
			var body := m as Node3D
			if body == null or home == Vector3.ZERO:
				continue
			var exclude: Array[RID] = []
			var col := body as CollisionObject3D
			if col != null:
				exclude.append(col.get_rid())
			var h := GroundQuery.resolve(get_viewport().world_3d, terrain_data, home, exclude)
			if is_nan(h):
				fail += 1
				printerr("AUDIT FAIL %s: 刷点 (%.0f,%.0f) 无地面（掉洞）" % [body.name, home.x, home.z])
				continue
			var diff := absf(home.y - (h + 0.05))
			var ok := diff <= 0.5
			if not ok:
				fail += 1
			printerr("AUDIT %s %s: home_y=%.2f ground=%.2f diff=%.2f" % [
				"OK  " if ok else "FAIL", body.name, home.y, h, diff])
	# 坐骑检查：headless 下 bot 未长途骑行时 Vehicles 应为空；有车则必须有骑手
	var vehicles := level.get_node_or_null("Environment/Vehicles")
	if vehicles != null:
		for v in vehicles.get_children():
			var seats_v = v.get("seats")
			var seats: Dictionary = seats_v if seats_v != null else {}
			if seats.is_empty():
				fail += 1
				printerr("AUDIT FAIL: 无人骑乘的坐骑 %s 仍存在" % v.name)
			else:
				printerr("AUDIT OK   : 坐骑 %s 骑手=%s" % [v.name, seats.keys()])
	printerr("AUDIT_DONE fail=%d" % fail)
	get_tree().quit()
