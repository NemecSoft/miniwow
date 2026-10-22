extends Node3D

## M53 屏幕点命中去查：把"画面里那块淡青色横带"到底是什么问出来。
## 从玩家相机对指定屏幕点发射线，逐个剔除已命中体，列出沿途所有对象。

var _level: Node3D


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("P53: headless 无法取相机")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "查点", "blue")
	await get_tree().create_timer(6.0).timeout
	var cs = _level.get("class_select_ui")
	if cs != null and cs.has_method("close_panel"):
		cs.close_panel()
	await get_tree().create_timer(0.6).timeout

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		printerr("P53: 没有相机")
		get_tree().quit(0)
		return
	var vp := get_viewport().get_visible_rect().size
	printerr("P53: 视口 " + str(vp))
	# 青带大致在画面 (52%~73% 宽, 42% 高) 之间
	for frac in [Vector2(0.52, 0.42), Vector2(0.62, 0.42), Vector2(0.72, 0.42)]:
		_cast_at(cam, Vector2(vp.x * frac.x, vp.y * frac.y), frac)
	get_tree().quit(0)


func _cast_at(cam: Camera3D, screen_pos: Vector2, frac: Vector2) -> void:
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	printerr("P53[%.2f,%.2f]: 屏幕(%d,%d) 方向=%s" % [
		frac.x, frac.y, int(screen_pos.x), int(screen_pos.y), str(dir.snapped(Vector3.ONE * 0.01))])
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	for i in 6:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 4000.0)
		q.collide_with_areas = true
		q.collide_with_bodies = true
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var col = hit["collider"]
		var hp: Vector3 = hit["position"]
		printerr("P53[%.2f,%.2f]:   #%d 距离%.1fm → %s" % [
			frac.x, frac.y, i, origin.distance_to(hp),
			str(col.get_path()) if col is Node else str(col)])
		exclude.append(hit["rid"])
