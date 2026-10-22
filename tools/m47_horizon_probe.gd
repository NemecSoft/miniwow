extends Node3D

## M47 地平线探针：定位截图中"地平线处那条深红硬边横带"到底是什么。
##
## 做法（不靠推理，只靠打射线）：
##   从玩家相机出发，在屏幕 4 个高度 × 3 个横坐标上 unproject 出射线，
##   做物理射线查询。命中 → 是真实几何体（打印节点名/层/距离）；
##   打空 → 是背景/天空渲染（那就是 Sky3D 的事）。
##
## 用法：godot --path . res://tools/m47_horizon_probe.tscn -- --world outland

var _level: Node3D
var _cam: Camera3D


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("HZP: headless 无渲染，必须窗口模式")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "探针", "blue")
	await get_tree().create_timer(5.0).timeout
	_cam = get_viewport().get_camera_3d()
	if _cam == null:
		printerr("HZP: 没有相机")
		get_tree().quit(0)
		return

	printerr("HZP: 相机位置=%s  前方=%s  朝向仰角=%.1f°" % [
		str(_cam.global_position.snapped(Vector3.ONE * 0.1)),
		str((-_cam.global_transform.basis.z).snapped(Vector3.ONE * 0.01)),
		rad_to_deg(asin(clampf(-_cam.global_transform.basis.z.dot(
			Planet.up_at(_cam.global_position)), -1.0, 1.0)))])

	var vp_size := get_viewport().get_visible_rect().size
	printerr("HZP: 视口 %s" % str(vp_size))
	for sy in [0.38, 0.44, 0.47, 0.50, 0.55]:
		for sx in [0.25, 0.5, 0.75]:
			_ray_at(Vector2(vp_size.x * sx, vp_size.y * sy), sx, sy)

	# 顺便把场景里"屏幕占位最大"的几个几何体列出来（AABB 投影覆盖法）
	printerr("HZP: ===== 场景内大型几何体（按 AABB 最大边长排序）=====")
	var big: Array = []
	_collect(_level, big)
	big.sort_custom(func(a, b): return a[1] > b[1])
	for i in mini(12, big.size()):
		printerr("HZP:   %-42s 最大边=%8.1f m  位置=%s" % [
			big[i][0], big[i][1], str((big[i][2] as Vector3).snapped(Vector3.ONE * 0.1))])
	printerr("HZP: 结束")
	get_tree().quit(0)


func _ray_at(screen_pos: Vector2, sx: float, sy: float) -> void:
	var origin: Vector3 = _cam.project_ray_origin(screen_pos)
	var dir: Vector3 = _cam.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 20000.0, 0xFFFFFFFF)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	var tag := "(%.2f,%.2f)" % [sx, sy]
	if hit.is_empty():
		printerr("HZP: 屏%s 射线打空 → 该处是背景/天空渲染" % tag)
		return
	var col: Object = hit.get("collider")
	var nm := "?"
	var path := ""
	if col is Node:
		nm = (col as Node).name
		path = str((col as Node).get_path())
	printerr("HZP: 屏%s 命中 %s  距相机=%.0fm  法线=%s" % [
		tag, nm, origin.distance_to(hit["position"] as Vector3),
		str((hit["normal"] as Vector3).snapped(Vector3.ONE * 0.01))])
	printerr("HZP:        路径=%s" % path)


func _collect(n: Node, out: Array) -> void:
	var g := n as GeometryInstance3D
	if g != null and g.is_visible_in_tree():
		var aabb: AABB = g.get_aabb()
		var sc: Vector3 = g.global_transform.basis.get_scale()
		var m: float = maxf(aabb.size.x * sc.x, maxf(aabb.size.y * sc.y, aabb.size.z * sc.z))
		if m > 400.0:
			out.append([str(g.get_path()), m, g.global_position])
	for c in n.get_children():
		_collect(c, out)
