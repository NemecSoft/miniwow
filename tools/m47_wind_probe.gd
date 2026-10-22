extends Node3D

## M47 风感探针 v2：**真的按键**。
##
## 上一版探针只塞 velocity 就判"通过"，但用户实际玩还是滑 —— 说明测法漏了
## 真实操作路径。这里用 Input.action_press 程序化按住 W/A，完整复现
## 「按住走 → 松手 → 是否还继续滑」。
##
## 用法：godot --path . res://tools/m47_wind_probe.tscn -- --world outland

var _level: Node3D
var _player: Node3D
var _last: Vector3


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("WNP: headless 无物理，必须窗口模式")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "探针", "blue")
	await get_tree().create_timer(5.0).timeout
	_player = _find_player()
	if _player == null:
		printerr("WNP: 找不到玩家")
		get_tree().quit(0)
		return
	printerr("WNP: 玩家=%s  r=%.1f" % [_player.name, _player.global_position.length()])

	await _watch("A 完全不按键（应原地不动）", 2.0)

	await _probe_walk()

	await _watch("C 松手后（关键！应 <0.5m）", 3.0)

	Input.action_press("move_left")
	await _watch("D 按住 A", 1.2)
	Input.action_release("move_left")

	await _watch("E 松手后（关键！应 <0.5m）", 3.0)

	# 跳跃后落地，看落地瞬间会不会被弹飞
	Input.action_press("jump")
	await get_tree().create_timer(0.15).timeout
	Input.action_release("jump")
	await _watch("F 跳跃落地后", 3.0)

	# G：逐帧细诊 —— 定位"velocity=0 却在匀速平移"的真凶
	# H：召唤坐骑 —— 最贴近用户操作的路径（按 X 召唤 → 自动上座 → 会不会被带走）
	printerr("WNP: ===== H 召唤坐骑后 =====")
	_player.call("_summon_mount", true,
		_player.get_multiplayer_authority(), Vector3(), INF, "couch")
	await get_tree().create_timer(1.0).timeout
	await _watch("H 召唤并上座后（不按键，应 <0.5m）", 3.0)
	var hv = _player.get("mounted_vehicle")
	printerr("WNP[H] mounted_vehicle=%s  seats=%s" % [
		hv.name if hv else "无", str(hv.get("seats")) if hv else "-"])
	if hv != null:
		_player.call("set_mounted", null)
		await get_tree().create_timer(0.4).timeout

	printerr("WNP: ===== G 逐帧细诊（12 帧）=====")
	var prev: Vector3 = _player.global_position
	for i in 12:
		await get_tree().physics_frame
		var cur: Vector3 = _player.global_position
		var v: Vector3 = _player.get("velocity")
		var veh := _player.get("mounted_vehicle") as Node3D
		var ar := get_node_or_null("/root/AutoRun")
		var ar_on := false
		if ar != null and ar.has_method("is_active"):
			ar_on = bool(ar.call("is_active"))
		printerr("WNP[G] 帧%02d 步长=%.3f  v=%.2f  r=%.1f  AutoRun=%s  veh=%s pos=%s seats=%s" % [
			i, cur.distance_to(prev), v.length(), cur.length(), str(ar_on),
			veh.name if veh else "无",
			str(veh.global_position.snapped(Vector3.ONE * 0.1)) if veh else "-",
			str(veh.get("seats")) if veh else "-"])
		prev = cur

	printerr("WNP: 结束")
	get_tree().quit(0)


func _watch(tag: String, dur: float) -> void:
	var p0: Vector3 = _player.global_position
	_last = p0
	var t := 0.0
	var max_speed := 0.0
	var samples := 0
	var line := ""
	while t < dur:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
		samples += 1
		var p: Vector3 = _player.global_position
		var v: Vector3 = _player.get("velocity")
		max_speed = maxf(max_speed, v.length())
		if samples <= 8 or samples % 10 == 0:
			line += "%.1fs:移%.2f v%.2f | " % [t, p.distance_to(p0), v.length()]
			_last = p
	var total: float = _player.global_position.distance_to(p0)
	printerr("WNP[%s] 总位移=%.3f m  峰值速度=%.2f m/s" % [tag, total, max_speed])
	printerr("WNP[%s]   轨迹 %s" % [tag, line])


func _find_player() -> Node3D:
	var pc := _level.get_node_or_null("PlayersContainer")
	if pc == null:
		return null
	for c in pc.get_children():
		if c is Node3D:
			return c as Node3D
	return null


## 按 W 行走细诊：位移到底有没有发生，方向和"角色认为的前方"是否一致。
## 用户症状「按 W 原地踏步不走」—— 必须同时看位置变化与 basis.z 的符号。
func _probe_walk() -> void:
	printerr("WNP: ===== W 行走细诊 =====")
	var start: Vector3 = _player.global_position
	var up0: Vector3 = Planet.up_at(start)
	Input.action_press("move_forward")
	var prev: Vector3 = start
	for i in 30:
		await get_tree().physics_frame
		if i % 6 != 0:
			continue
		var cur: Vector3 = _player.global_position
		var v: Vector3 = _player.get("velocity")
		var bas: Basis = _player.global_transform.basis
		var fwd: Vector3 = _player.get("_fwd")
		var up: Vector3 = Planet.up_at(cur)
		# basis.z 应该等于 _fwd（见 align_basis 的 z = f.cross(y)）；
		# 而前进键给的是 -basis.z。若 basis.z 与 _fwd 同向，按 W 就是往 -_fwd 走。
		printerr("WNP[W] 帧%02d 步长=%.3f |v|=%.2f v·up=%.2f basis.z·_fwd=%.3f (-basis.z)·_fwd=%.3f" % [
			i, cur.distance_to(prev), v.length(), v.dot(up),
			bas.z.dot(fwd), (-bas.z).dot(fwd)])
		prev = cur
	Input.action_release("move_forward")
	var total: Vector3 = _player.global_position - start
	var flat: Vector3 = total - up0 * total.dot(up0)
	printerr("WNP[W] 按 W 共 30 帧：总位移=%.3f m  水平位移=%.3f m" % [total.length(), flat.length()])
