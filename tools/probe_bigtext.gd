extends Node
## M26 探针：host 端"巨大单字糊屏"根因定位。
## 复现 host 自动挂机场景（起服 + bot 挂树开打），随后 dump 全场景
## Label3D 状态（text/scale/pixel_size/outline/global_position/相机距离），
## 按 scale 与像素尺寸找异常源。
## 用法：headless 跑 tools/probe_bigtext.tscn

const WAIT_SECONDS := 12.0

var _elapsed := 0.0
var _dumped := false


func _ready() -> void:
	printerr("BIGTEXT: 加载 level 并起服（复现 host 挂机）")
	var packed := load("res://scenes/level/level.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	Network.start_host("ProbeHost", "blue")


func _process(delta: float) -> void:
	if _dumped:
		_elapsed += delta
		if _elapsed > 1.0:
			get_tree().quit()
		return
	_elapsed += delta
	if _elapsed < WAIT_SECONDS:
		return
	_dumped = true
	_dump_labels()


func _dump_labels() -> void:
	var labels: Array[Node] = []
	_collect(get_tree().root, labels)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		printerr("BIGTEXT: 无 3D 相机")
		return
	printerr("BIGTEXT: 共 %d 个 Label3D，相机=%s pos=%s" % [labels.size(), camera.name, str(camera.global_position)])
	var vp_h := get_viewport().get_visible_rect().size.y
	for n in labels:
		var l := n as Label3D
		var dist := l.global_position.distance_to(camera.global_position)
		var aabb := l.get_aabb()
		var half_h: float = aabb.size.y * 0.5
		var top_px: Vector2 = camera.unproject_position(l.global_position + Vector3.UP * half_h)
		var bot_px: Vector2 = camera.unproject_position(l.global_position - Vector3.UP * half_h)
		var screen_h: float = absf(top_px.y - bot_px.y)
		if screen_h > 60.0 or dist < 4.0:
			printerr("BIGTEXT: [cam] %s dist=%.2fm screen_h=%.0fpx text=%s" % [
				l.get_path(), dist, screen_h, str(l.text)])
	# 另外全量列一遍（截断显示），按 scale 降序
	var sorted := labels.duplicate()
	sorted.sort_custom(func(a, b):
		return (a as Label3D).scale.length() > (b as Label3D).scale.length())
	for i in mini(15, sorted.size()):
		var l := sorted[i] as Label3D
		printerr("BIGTEXT: [top%d] %s scale=%s pixel=%.3f text=%s" % [
			i, l.get_path(), str(l.scale), l.pixel_size, str(l.text)])
	# 全量按 pixel_size 降序（找巨大像素尺寸）
	var by_pixel := labels.duplicate()
	by_pixel.sort_custom(func(a, b):
		return (a as Label3D).pixel_size > (b as Label3D).pixel_size)
	for i in by_pixel.size():
		var l := by_pixel[i] as Label3D
		printerr("BIGTEXT: [px%d] %s pixel=%.4f scale=%s text=%s pos=%s" % [
			i, l.get_path(), l.pixel_size, str(l.scale), str(l.text), str(l.global_position)])
	# M26 追加：dump 所有 scale 非 (1,1,1) 的 Node3D（找异常放大的父链节点）
	var nodes: Array[Node] = []
	_collect_nodes(get_tree().root, nodes)
	for n in nodes:
		var n3 := n as Node3D
		if n3 == null:
			continue
		var smax: float = maxf(maxf(absf(n3.scale.x), absf(n3.scale.y)), absf(n3.scale.z))
		if absf(smax - 1.0) > 0.01:
			printerr("BIGTEXT: [scale!] %s scale=%s class=%s" % [
				n3.get_path(), str(n3.scale), n3.get_class()])


func _collect_nodes(n: Node, out: Array[Node]) -> void:
	out.append(n)
	for c in n.get_children():
		_collect_nodes(c, out)


func _collect(n: Node, out: Array[Node]) -> void:
	if n is Label3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
