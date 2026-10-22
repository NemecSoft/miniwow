extends Node3D

## M47-B：用户报"走路走不动 + 飞行钻地"的定量诊断。
##
## 截图证据：整个世界浮在"海面"上方 → 玩家在地表之下（< R），看到的是海洋球壳内壁。
## 这里只量事实，不做任何修改：
##   A 玩家实际半径 vs 地表半径 / 与 up 的夹角
##   B 地形 trimesh 碰撞体到底存在不存在、层对不对
##   C 真实按 W 30 帧的位移（区分"滑行"与"被挡"）
##   D 召唤沙发后的半径变化（钻地的方向）

var _level: Node3D
var _player: Node3D


func _ready() -> void:
	Network.SERVER_PORT = 8093          # 不抢游戏的 8080
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("MBP: 需要窗口模式")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "诊断", "blue")
	# 地形 38.8 万三角形碰撞 + 6 面网格生成约 4~6 秒，轮询等玩家出来
	for i in 40:
		await get_tree().create_timer(0.5).timeout
		_player = _find_player()
		if _player != null:
			break
	await get_tree().create_timer(1.0).timeout
	if _player == null:
		printerr("MBP: 找不到玩家")
		get_tree().quit(0)
		return

	_probe_terrain_collision()
	await _probe_player_state("开局")
	await _probe_walk()
	await _probe_mount()

	printerr("MBP: 结束")
	get_tree().quit(0)


func _probe_terrain_collision() -> void:
	printerr("MBP: ===== B 地形碰撞体清点 =====")
	var found := 0
	for n in get_tree().root.find_children("*", "StaticBody3D", true, false):
		var sb := n as StaticBody3D
		var cs := _first_shape(sb)
		if cs == null:
			continue
		var sh := cs.shape
		if sh == null:
			continue
		var cls := sh.get_class()
		if cls != "ConcavePolygonShape3D":
			continue
		found += 1
		var faces: int = sh.get_faces().size()
		printerr("MBP[COL] %s  layer=%d mask=%d  类型=%s  面顶点=%d  父=%s" % [
			str(sb.name), sb.collision_layer, sb.collision_mask, cls, faces,
			str(sb.get_parent().name)])
	printerr("MBP[COL] 共找到 %d 个凹面碰撞体" % found)


func _first_shape(n: Node) -> CollisionShape3D:
	for c in n.get_children():
		if c is CollisionShape3D:
			return c as CollisionShape3D
	return null


func _probe_player_state(tag: String) -> void:
	var p: Vector3 = _player.global_position
	var r := p.length()
	var up := Planet.up_at(p)
	var mh := Planet.mesh_height(up)
	var surf := Planet.RADIUS + mh
	printerr("MBP[%s] r=%.2f  地表r=%.2f  R=%.1f  mesh_h=%.2f  差=%+.3f m  is_on_floor=%s grounded=%s" % [
		tag, r, surf, Planet.RADIUS, mh, r - surf,
		str(_player.call("is_on_floor")), str(_player.get("_grounded"))])
	printerr("MBP[%s] up=(%.3f,%.3f,%.3f)  velocity=%s  mounted=%s" % [
		tag, up.x, up.y, up.z, str((_player.get("velocity") as Vector3).snapped(Vector3(0.01, 0.01, 0.01))),
		str(_player.get("mounted_vehicle") != null)])


func _probe_walk() -> void:
	printerr("MBP: ===== C 真实按 W 30 帧 =====")
	var start: Vector3 = _player.global_position
	var up0 := Planet.up_at(start)
	Input.action_press("move_forward")
	var prev := start
	var blocked := 0
	for i in 30:
		await get_tree().physics_frame
		var cur: Vector3 = _player.global_position
		if i % 6 == 0:
			var step := cur.distance_to(prev)
			if i > 0 and step < 0.01:
				blocked += 1
			printerr("MBP[W] 帧%02d 步长=%.3f  |v|=%.2f  r=%.2f  floor=%s" % [
				i, step, (_player.get("velocity") as Vector3).length(),
				cur.length(), str(_player.call("is_on_floor"))])
		prev = cur
	Input.action_release("move_forward")
	var total: Vector3 = _player.global_position - start
	var horiz: Vector3 = total - up0 * total.dot(up0)
	printerr("MBP[W] 总位移=%.3f m  切平面内=%.3f m  径向=%+.3f m  零位移采样=%d/5" % [
		total.length(), horiz.length(), total.dot(up0), blocked])
	await get_tree().create_timer(0.5).timeout


func _probe_mount() -> void:
	printerr("MBP: ===== D 召唤沙发（按 X）=====")
	var r0: float = _player.global_position.length()
	# 模拟**真的按 X**：构造 InputEventAction 走 _unhandled_input 完整分支。
	# 直接 call("_summon_mount") 会绕过"已骑乘则下座"的判断，召唤出第二辆车。
	_press_mount()
	await get_tree().create_timer(2.5).timeout
	var veh: Variant = _player.get("mounted_vehicle")
	if veh == null:
		printerr("MBP[D] 未上座（mounted=null），跳过")
		return
	_report_mount_state("召唤后", veh)

	printerr("MBP: ===== E 按空格（应沿当地法线上升）=====")
	Input.action_press("jump")
	await get_tree().create_timer(1.0).timeout
	Input.action_release("jump")
	await get_tree().create_timer(0.3).timeout
	_report_mount_state("上升 1s 后", veh)

	printerr("MBP: ===== F 按 C（应下降但不穿地）=====")
	Input.action_press("crouch")
	await get_tree().create_timer(2.5).timeout
	Input.action_release("crouch")
	await get_tree().create_timer(0.3).timeout
	_report_mount_state("下降 2.5s 后", veh)

	printerr("MBP: ===== G 按 W 飞行 1s =====")
	var before: Vector3 = _player.global_position
	Input.action_press("move_forward")
	await get_tree().create_timer(1.0).timeout
	Input.action_release("move_forward")
	await get_tree().create_timer(0.2).timeout
	var moved: Vector3 = _player.global_position - before
	_report_mount_state("飞行 1s 后", veh)
	printerr("MBP[G] 飞行位移=%.2f m" % moved.length())

	printerr("MBP: ===== H 再按 X 下座，然后立刻走路 =====")
	_press_mount()                        # 走真分支：骑乘中再按 X = 下座并收回
	await get_tree().create_timer(2.0).timeout
	_report_mount_state("下座后", null)
	await _probe_walk()


## 构造一次真实的 X 键按下事件，交给 _unhandled_input 处理。
func _press_mount() -> void:
	var ev := InputEventAction.new()
	ev.action = "mount"
	ev.pressed = true
	_player.call("_unhandled_input", ev)


func _report_mount_state(tag: String, veh: Variant) -> void:
	var p: Vector3 = _player.global_position
	var up := Planet.up_at(p)
	var surf: float = Planet.RADIUS + Planet.mesh_height(up)
	var r := p.length()
	var verdict := "OK" if r >= surf - 0.05 else "!!钻地!!"
	printerr("MBP[" + tag + "] 玩家 r=" + str(snappedf(r, 0.01)) \
		+ "  地表 r=" + str(snappedf(surf, 0.01)) \
		+ "  差=" + str(snappedf(r - surf, 0.01)) + " m  " + verdict)
	if veh is Node3D:
		var v := veh as Node3D
		var vp := v.global_position
		var vs: float = Planet.RADIUS + Planet.mesh_height(Planet.up_at(vp))
		printerr("MBP[" + tag + "] 沙发 r=" + str(snappedf(vp.length(), 0.01)) \
			+ "  与地表差=" + str(snappedf(vp.length() - vs, 0.01)) + " m")


func _find_player() -> Node3D:
	var pc := _level.get_node_or_null("PlayersContainer")
	if pc != null:
		var names: Array[String] = []
		for c in pc.get_children():
			names.append(str(c.name))
			if c is Node3D:
				return c as Node3D
		if not names.is_empty():
			printerr("MBP: PlayersContainer 子节点=%s" % ", ".join(names))
	else:
		printerr("MBP: 没有 PlayersContainer 节点")
	return null
