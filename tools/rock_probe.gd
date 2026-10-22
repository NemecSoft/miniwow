extends Node3D

## 外域岩石"看得见吗"隔离探针（窗口模式，读真实实例数据）
##   godot --path <项目> res://tools/rock_probe.tscn -- --world outland

func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	var level := scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", level)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(9.0).timeout

	var fs := level.get_node_or_null("Environment/ForestStarter")
	if fs == null:
		printerr("RP: no forest")
		get_tree().quit(1)
		return
	var mmi := fs.get_node_or_null("OutRocks0") as MultiMeshInstance3D
	if mmi == null:
		printerr("RP: no OutRocks0")
		get_tree().quit(1)
		return
	printerr("RP: OutRocks0 visible=%s in_tree=%s gt=%s" % [
		str(mmi.visible), str(mmi.is_visible_in_tree()), str(mmi.global_transform)])
	var mm := mmi.multimesh
	printerr("RP: count=%d aabb=%s mesh=%s" % [
		mm.instance_count, str(mm.get_aabb()), str(mm.mesh)])

	# 相机机位（与截图工具 c3 相同）
	var d := Planet.dir_of(0, 0.06, -0.28)
	var cam_pos: Vector3 = Planet.surface_pos(d) + d * 6.0
	printerr("RP: cam_pos=%s len=%.1f" % [str(cam_pos.snapped(Vector3.ONE * 0.1)), cam_pos.length()])

	# 找离相机最近的 8 个实例，并算出它们相对地表的露出高度
	var best: Array = []
	for i in mm.instance_count:
		var t := mm.get_instance_transform(i)
		var dist := t.origin.distance_to(cam_pos)
		if best.size() < 8:
			best.append([dist, i, t])
			best.sort_custom(func(a, b): return a[0] < b[0])
		elif dist < float(best[7][0]):
			best[7] = [dist, i, t]
			best.sort_custom(func(a, b): return a[0] < b[0])
	for b in best:
		var t: Transform3D = b[2]
		var up := t.origin.normalized()
		var surf: float = Planet.RADIUS + Planet.height_at(up)
		var ytop: float = t.origin.length() + t.basis.y.length() * 0.5
		printerr("RP: inst%d dist=%.0fm at=%s 半径y=%.1f 露出=%.1f" % [
			b[1], b[0], str(t.origin.snapped(Vector3.ONE * 0.1)),
			t.basis.y.length() * 0.5, ytop - surf])
	get_tree().quit(0)
