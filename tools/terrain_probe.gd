extends Node3D

## M47：地形整体消失排查。
## 量 6 个 Face 节点是否还在、visible、网格 AABB、世界位置；
## 同时量玩家半径、海平面、以及"物件 vs 地形"的径向差。

var _level: Node3D


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	_level.call("_on_host_pressed", "诊断", "blue")
	await get_tree().create_timer(6.0).timeout

	printerr("TP: R=%.1f SEA=%.1f" % [Planet.RADIUS, Planet.SEA_LEVEL])

	# 1) 所有 Face 节点
	var faces := get_tree().root.find_children("Face*", "MeshInstance3D", true, false)
	printerr("TP: MeshInstance3D 名字带 Face 的 = %d 个" % faces.size())
	for f in faces:
		var mi := f as MeshInstance3D
		var mesh := mi.mesh
		var aabb := mesh.get_aabb() if mesh != null else AABB()
		printerr("TP[F] %-12s visible=%-5s parent=%-14s origin=%s  aabb.size=%s" % [
			str(mi.name), str(mi.is_visible_in_tree()), str(mi.get_parent().name),
			str(mi.global_transform.origin.round()), str(aabb.size.round())])

	# 2) PlanetSurface 下所有子节点
	for nm in ["PlanetSurface", "Environment"]:
		var n := _find_named(nm)
		if n == null:
			printerr("TP: 找不到节点 %s" % nm)
			continue
		printerr("TP[%s] visible=%s origin=%s children=%d" % [
			nm, str((n as Node3D).is_visible_in_tree()),
			str((n as Node3D).global_transform.origin), n.get_child_count()])
		for ch in n.get_children():
			var c3 := ch as Node3D
			if c3 != null:
				printerr("TP[%s]   - %-18s (%s) visible=%s r=%.1f" % [
					nm, str(ch.name), ch.get_class(), str(c3.is_visible_in_tree()),
					c3.global_position.length()])

	# 3) 玩家
	var p := _find_player()
	if p != null:
		var dir := p.global_position.normalized()
		var up := Planet.up_at(p.global_position)
		var sea_r: float = Planet.RADIUS + Planet.SEA_LEVEL
		printerr("TP: 玩家 r=%.2f  (海面 r=%.1f  地形mesh=%.2f  解析=%.2f)" % [
			p.global_position.length(), sea_r,
			Planet.mesh_height(dir), Planet.height_at(dir)])
		printerr("TP: 玩家 in_ocean=%s  pos=%s" % [
			str(p.global_position.length() < sea_r), str(p.global_position.round())])
		printerr("TP: 相机 r=%.1f" % [
			get_viewport().get_camera_3d().global_position.length() if get_viewport().get_camera_3d() else -1.0])
	else:
		printerr("TP: 找不到玩家节点")

	# 4) 存档配置
	printerr("TP: 光照模式=%s" % Planet.light_mode_name())

	printerr("TP: 结束")
	get_tree().quit(0)


func _find_named(nm: String) -> Node:
	for n in get_tree().root.find_children("*", "", true, false):
		if (n as Node).name == nm:
			return n
	return null


func _find_player() -> Node3D:
	# 玩家脚本有 _planet_frame_step()，用它当指纹；再排除 bot
	for n in get_tree().root.find_children("*", "CharacterBody3D", true, false):
		if not n.has_method("_planet_frame_step"):
			continue
		if n.has_method("is_bot") and n.call("is_bot"):
			continue
		return n as Node3D
	for n in get_tree().root.find_children("*", "CharacterBody3D", true, false):
		if n.has_method("_planet_frame_step"):
			return n as Node3D
	return null
