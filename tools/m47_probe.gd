extends Node3D

## M47 探针：重力/朝向 + 坐骑召唤，全部量化，不靠推理。
##
## 用户报的两件事：
##   1「角色的重力方向不对」——量 根节点 basis.y 与当地法线夹角、up_direction、
##     着地法线、body 子节点朝向、相机朝向
##   2「坐骑给我弄去哪里了」——调 _summon_mount，量车的位置/朝向/与玩家的距离
##
## 用法：godot --path . res://tools/m47_probe.tscn -- --world outland

var _level: Node3D
var _player: Node3D


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("M47P: headless 不跑物理，必须窗口模式")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "探针", "blue")
	await get_tree().create_timer(5.0).timeout
	_player = _find_player()
	if _player == null:
		printerr("M47P: 找不到玩家")
		get_tree().quit(0)
		return

	await _probe_gravity("静止")
	# 走两步再量（移动中朝向是否还正）
	for i in 40:
		_player.global_position += -_player.global_transform.basis.z * 0.08
		await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	await _probe_gravity("走两步后")

	await _probe_slide()
	await _probe_vehicle()
	printerr("M47P: 结束")
	get_tree().quit(0)


func _probe_gravity(tag: String) -> void:
	var pos: Vector3 = _player.global_position
	var up := Planet.up_at(pos)
	var by: Vector3 = _player.global_transform.basis.y.normalized()
	var ang := rad_to_deg(acos(clampf(by.dot(up), -1.0, 1.0)))
	printerr("M47P[%s] 位置r=%.1f up=%s" % [tag, pos.length(), str(up.snapped(Vector3.ONE * 0.01))])
	printerr("M47P[%s]   根节点 basis.y=%s  与当地法线夹角=%.1f°" % [
		tag, str(by.snapped(Vector3.ONE * 0.01)), ang])
	printerr("M47P[%s]   up_direction=%s  is_on_floor=%s  velocity=%s  |v·up|=%.2f" % [
		tag, str((_player.get("up_direction") as Vector3).snapped(Vector3.ONE * 0.01)),
		str(_player.call("is_on_floor")),
		str((_player.get("velocity") as Vector3).snapped(Vector3.ONE * 0.1)),
		(_player.get("velocity") as Vector3).dot(up)])
	# 着地法线：物理引擎认为的"地面朝向"
	var fn: Vector3 = _player.call("get_floor_normal")
	if fn.length_squared() > 0.001:
		printerr("M47P[%s]   floor_normal=%s 与法线夹角=%.1f°" % [
			tag, str(fn.snapped(Vector3.ONE * 0.01)),
			rad_to_deg(acos(clampf(fn.dot(up), -1.0, 1.0)))])
	# 身体模型（视觉）
	var body := _player.get_node_or_null("Body") as Node3D
	if body == null:
		for c in _player.get_children():
			if c is Node3D and c.name != "CollisionShape3D":
				body = c as Node3D
				break
	if body != null:
		var bby: Vector3 = body.global_transform.basis.y.normalized()
		printerr("M47P[%s]   身体节点 %s basis.y=%s 与法线夹角=%.1f°" % [
			tag, body.name, str(bby.snapped(Vector3.ONE * 0.01)),
			rad_to_deg(acos(clampf(bby.dot(up), -1.0, 1.0)))])
	# 相机
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var cu: Vector3 = cam.global_transform.basis.y.normalized()
		printerr("M47P[%s]   相机 basis.y=%s 与法线夹角=%.1f°" % [
			tag, str(cu.snapped(Vector3.ONE * 0.01)),
			rad_to_deg(acos(clampf(cu.dot(up), -1.0, 1.0)))])


func _probe_slide() -> void:
	# 用户原话「角色一直在像被风吹一样」= 松手后仍有水平残余速度滑行。
	# 这里不按键，直接塞一个 6 m/s 的切平面初速，看几帧内自己停住。
	printerr("M47P[滑行] ===== 塞 6m/s 切平面初速 → 不按键，看是否自行停下 =====")
	var up := Planet.up_at(_player.global_position)
	var fwd: Vector3 = _player.global_transform.basis.z
	fwd -= up * fwd.dot(up)
	if fwd.length_squared() < 0.001:
		fwd = up.cross(Vector3.RIGHT)
	fwd = fwd.normalized()
	_player.set("velocity", fwd * 6.0)
	var p0: Vector3 = _player.global_position
	for i in 8:
		await get_tree().physics_frame
		var v: Vector3 = _player.get("velocity")
		var u2 := Planet.up_at(_player.global_position)
		var vr2: float = v.dot(u2)
		var vh2: Vector3 = v - u2 * vr2
		printerr("M47P[滑行] 帧%2d  vh=%5.2f m/s  vr=%6.2f  距起点=%.3f m" % [
			i, vh2.length(), vr2, _player.global_position.distance_to(p0)])
	# 第二段：带垂直分量，验证刹车不吃掉重力/跳跃
	_player.set("velocity", fwd * 6.0 + up * 8.0)
	await get_tree().physics_frame
	var v3: Vector3 = _player.get("velocity")
	var u3 := Planet.up_at(_player.global_position)
	printerr("M47P[滑行] 混合速度后 1 帧：vr=%.2f（应仍 >0，垂直分量被保留）  vh=%.2f" % [
		v3.dot(u3), (v3 - u3 * v3.dot(u3)).length()])
	var d: float = _player.global_position.distance_to(p0)
	printerr("M47P[滑行] 结论：8 帧总位移 %.3f m（阈值 < 0.45m 判通过）" % d)


func _probe_vehicle() -> void:
	var vehicles := _level.get_node_or_null("Environment/Vehicles")
	printerr("M47P[坐骑] Vehicles 节点=%s 已有子节点=%s" % [
		str(vehicles != null), str(vehicles.get_child_count()) if vehicles else "-"])
	if vehicles == null:
		return
	_player.call("_summon_mount", true, _player.get_multiplayer_authority(),
		Vector3(), INF, "couch")
	await get_tree().create_timer(1.2).timeout
	printerr("M47P[坐骑] 召唤后子节点数=%d" % vehicles.get_child_count())
	for c in vehicles.get_children():
		var v := c as Node3D
		if v == null:
			continue
		var up := Planet.up_at(v.global_position)
		var vy: Vector3 = v.global_transform.basis.y.normalized()
		printerr("M47P[坐骑] %s 位置=%s r=%.1f 距玩家=%.1fm  basis.y=%s 与法线夹角=%.1f°" % [
			v.name, str(v.global_position.snapped(Vector3.ONE * 0.1)),
			v.global_position.length(), v.global_position.distance_to(_player.global_position),
			str(vy.snapped(Vector3.ONE * 0.01)),
			rad_to_deg(acos(clampf(vy.dot(up), -1.0, 1.0)))])
		printerr("M47P[坐骑]   mounted_vehicle=%s" % str(_player.get("mounted_vehicle")))


func _find_player() -> Node3D:
	var pc := _level.get_node_or_null("PlayersContainer")
	if pc == null:
		return null
	for c in pc.get_children():
		if c is Node3D:
			return c as Node3D
	return null
