extends Node3D

## 外域装饰探针（headless 可跑，不需要渲染）
## 用途：确认 MultiMeshInstance3D 到底有没有被建出来、实例变换落在哪。
##   godot --headless --path <项目> res://tools/outland_probe.tscn -- --world outland

func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	var level := scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", level)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(9.0).timeout

	printerr("PROBE: world=%s R=%.0f SEALEVEL=%.0f" % [
		Planet.world_id(), Planet.RADIUS, Planet.SEA_LEVEL])
	var fs := level.get_node_or_null("Environment/ForestStarter")
	if fs == null:
		printerr("PROBE: 找不到 ForestStarter")
		get_tree().quit(1)
		return
	printerr("PROBE: ForestStarter xf=%s visible=%s" % [str(fs.global_transform), str(fs.visible)])
	for c in fs.get_children():
		if c is MultiMeshInstance3D:
			var mmi := c as MultiMeshInstance3D
			var mm := mmi.multimesh
			if mm == null:
				printerr("PROBE: %s multimesh=null" % mmi.name)
				continue
			var n := mm.instance_count
			var info := ""
			if n > 0:
				var t := mm.get_instance_transform(0)
				info = " | inst0 origin=%s len=%.1f basisY=%s aabb=%s" % [
					str(t.origin.snapped(Vector3.ONE * 0.1)),
					t.origin.length(),
					str(t.basis.y.snapped(Vector3.ONE * 0.01)),
					str(mm.get_aabb())]
			printerr("PROBE: %s count=%d visible=%s in_tree_vis=%s aabb=%s%s" % [
				mmi.name, n, str(mmi.visible), str(mmi.is_visible_in_tree()),
				str(mmi.custom_aabb), info])
	# 抽查面 4（影月谷）中心的解析高度
	var d4 := Planet.dir_of(4, 0.0, -0.26)
	printerr("PROBE: face4 u=0 v=-0.26 dir=%s h=%.1f" % [
		str(d4.snapped(Vector3.ONE * 0.01)), Planet.height_at(d4)])
	var d0 := Planet.dir_of(0, 0.06, -0.28)
	printerr("PROBE: face0 u=0.06 v=-0.28 h=%.1f" % Planet.height_at(d0))
	get_tree().quit(0)
