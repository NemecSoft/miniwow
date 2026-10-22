extends Node3D

## M47：为什么"按 W 原地踏步"——直接问物理世界：四周有没有墙。
##
## 广场 arena.tscn 里有 12 个 Boundary/Diagonal 碰撞墙，都是平面地图时代
## 的"围墙"，搬到球面上后如果坐标没跟着变换，就会横在广场中间挡人。
## 这里沿当地切平面打 16 条射线，谁挡路一目了然。

var _level: Node3D
var _player: Node3D


func _ready() -> void:
	Network.SERVER_PORT = 8091          # 不抢正在运行的游戏实例的 8080
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("WBP: 需要窗口模式")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "诊断", "blue")
	await get_tree().create_timer(6.0).timeout

	_player = _find_player()
	if _player == null:
		printerr("WBP: 找不到玩家")
		get_tree().quit(0)
		return

	# ===== 关键：把玩家放到广场中心（用户实际站的地方）=====
	# 出生点在草地上，那里地形无碰撞、射线打空，测不出"地台与吸附打架"。
	var arena := _find_named("Arena")
	if arena is Node3D:
		var gp: Vector3 = (arena as Node3D).global_position
		var u: Vector3 = Planet.up_at(gp)
		_player.global_position = gp + u * 1.5
		printerr("WBP: 已传送到广场中心 %s (r=%.1f)" % [str(gp.round()), gp.length()])
		await get_tree().create_timer(1.2).timeout

	var p: Vector3 = _player.global_position
	var up: Vector3 = Planet.up_at(p)
	printerr("WBP: 玩家 r=%.2f  pos=%s" % [p.length(), str(p.round())])

	# 当地正交基
	var f: Vector3 = _player.global_transform.basis.z
	f = (f - up * f.dot(up)).normalized()
	var rt: Vector3 = f.cross(up).normalized()

	var space := _player.get_world_3d().direct_space_state
	var hits := 0
	for i in 16:
		var ang: float = TAU * float(i) / 16.0
		var d: Vector3 = (f * cos(ang) + rt * sin(ang)).normalized()
		var q := PhysicsRayQueryParameters3D.create(p + up * 0.6, p + up * 0.6 + d * 6.0)
		q.collision_mask = 0xFFFFFFFF
		q.exclude = [_player.get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		var deg: int = int(round(rad_to_deg(ang)))
		if hit.is_empty():
			printerr("WBP[%3d°] 6m 内无阻挡" % deg)
		else:
			hits += 1
			var col: Object = hit["collider"]
			var nm: String = str(col.get("name")) if col != null else "?"
			var path: String = str(col.get_path()) if (col is Node) else "?"
			printerr("WBP[%3d°] 命中距离=%.2f m  物体=%s  路径=%s" % [
				deg, (p + up * 0.6).distance_to(hit["position"]), nm, path])
	printerr("WBP: 16 个方向里有 %d 个被挡（<6m）" % hits)

	# 脚下射线：验证 _ground_radius_at() 的前提——脚下到底有没有碰撞面
	var q2 := PhysicsRayQueryParameters3D.create(p + up * 1.0, p - up * 3.0)
	q2.collision_mask = 2
	q2.exclude = [_player.get_rid()]
	var h2: Dictionary = space.intersect_ray(q2)
	if h2.is_empty():
		printerr("WBP[脚下] 射线打空 → 站在地形网格上（无碰撞）")
	else:
		var hp: Vector3 = h2["position"]
		printerr("WBP[脚下] 命中 r=%.3f  (玩家 r=%.3f，差 %.3f m)  物体=%s" % [
			hp.length(), p.length(), hp.length() - p.length(), str(h2["collider"].get("name"))])
	printerr("WBP[脚下] mesh_height 地面 r=%.3f" % (Planet.RADIUS + Planet.mesh_height(up)))
	printerr("WBP[状态] mounted=%s  grounded=%s" % [
		str(_player.get("mounted_vehicle")), str(_player.get("_grounded"))])

	# 逐帧看"吸附"为什么没把 0.27m 的悬空压掉
	printerr("WBP: ===== 逐帧吸附诊断（8 帧）=====")
	for i in 8:
		await get_tree().physics_frame
		var q: Vector3 = _player.global_position
		var u2: Vector3 = Planet.up_at(q)
		var gr: float = Planet.RADIUS + Planet.mesh_height(u2)
		var vv: Vector3 = _player.get("velocity")
		printerr("WBP[F] 帧%d r=%.4f 地面r=%.4f gap=%.4f v·up=%+.4f |v|=%.3f grounded=%s" % [
			i, q.length(), gr, q.length() - gr, vv.dot(u2), vv.length(),
			str(_player.get("_grounded"))])
	# 站在广场上按 W：这才是用户报的"原地踏步"场景
	printerr("WBP: ===== 广场上按 W 30 帧 =====")
	var s0: Vector3 = _player.global_position
	Input.action_press("move_forward")
	for i in 30:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var tot: Vector3 = _player.global_position - s0
	var u3: Vector3 = Planet.up_at(s0)
	printerr("WBP[行走] 总位移=%.3f m  水平=%.3f m  垂直=%.3f m" % [
		tot.length(), (tot - u3 * tot.dot(u3)).length(), tot.dot(u3)])

	printerr("WBP: 结束")
	get_tree().quit(0)


func _find_named(nm: String) -> Node:
	for n in get_tree().root.find_children("*", "", true, false):
		if (n as Node).name == nm:
			return n
	return null


func _find_player() -> Node3D:
	for n in get_tree().root.find_children("*", "CharacterBody3D", true, false):
		if not n.has_method("_planet_frame_step"):
			continue
		if n.has_method("is_bot") and n.call("is_bot"):
			continue
		return n as Node3D
	return null
