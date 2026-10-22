extends Node3D

## MultiMesh instance_count 行为实验（必须窗口模式：headless 读不回真实数据）
##   godot --path <项目> res://tools/mm_probe.tscn

func _ready() -> void:
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 1.0
	sph.radial_segments = 6
	sph.rings = 3

	# A：满额写入，count 不改（对照：应该正常）
	var a := MultiMesh.new()
	a.transform_format = MultiMesh.TRANSFORM_3D
	a.mesh = sph
	a.instance_count = 100
	for i in 100:
		a.set_instance_transform(i, Transform3D(Basis(), Vector3(1500 + i, 0, 0)))
	printerr("A 满额100 -> count=%d aabb=%s" % [a.instance_count, str(a.get_aabb())])

	# B：先按 100 设，只写 50，最后 count=50（怀疑：这一步清空数据）
	var b := MultiMesh.new()
	b.transform_format = MultiMesh.TRANSFORM_3D
	b.mesh = sph
	b.instance_count = 100
	for i in 50:
		b.set_instance_transform(i, Transform3D(Basis(), Vector3(1500 + i, 0, 0)))
	printerr("B 写入50(改小前) aabb=%s" % str(b.get_aabb()))
	b.instance_count = 50
	printerr("B 改小到50 -> count=%d aabb=%s inst49=%s" % [
		b.instance_count, str(b.get_aabb()), str(b.get_instance_transform(49).origin)])

	# C：从 0 直接拉到实际数量，再写
	var c := MultiMesh.new()
	c.transform_format = MultiMesh.TRANSFORM_3D
	c.mesh = sph
	var xs: Array[Transform3D] = []
	for i in 50:
		xs.append(Transform3D(Basis(), Vector3(1500 + i, 0, 0)))
	c.instance_count = xs.size()
	for i in xs.size():
		c.set_instance_transform(i, xs[i])
	printerr("C 先collect再设count -> count=%d aabb=%s inst49=%s" % [
		c.instance_count, str(c.get_aabb()), str(c.get_instance_transform(49).origin)])

	# D：use_colors 在设 count 之前（外域岩石用的顺序）
	var d := MultiMesh.new()
	d.transform_format = MultiMesh.TRANSFORM_3D
	d.use_colors = true
	d.mesh = sph
	d.instance_count = 50
	for i in 50:
		d.set_instance_transform(i, Transform3D(Basis(), Vector3(1500 + i, 0, 0)))
		d.set_instance_color(i, Color.RED)
	printerr("D use_colors前置 -> count=%d aabb=%s" % [d.instance_count, str(d.get_aabb())])

	get_tree().quit(0)
