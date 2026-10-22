extends Node3D

## M54 移动平滑度验收（窗口模式，因为 headless 不建玩家）。
##
## 判据不是"看起来还行"，而是**逐帧位移的均匀性**：
##   走路/飞行各 60 帧，记录每帧切平面位移，输出 均值/最小/最大/标准差。
## 标准差接近 0 = 没有一顿一顿；最大最小相差一个数量级 = 还在打架。
## 同时统计落地粒子生成次数（必须为 0）。

const FRAMES := 60

var _level: Node3D
var _me: Node3D


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("S54: headless 不建玩家，必须窗口模式")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "平滑", "blue")
	await get_tree().create_timer(6.0).timeout
	var cs = _level.get("class_select_ui")
	if cs != null and cs.has_method("close_panel"):
		cs.close_panel()
	await get_tree().create_timer(0.6).timeout
	_me = _find_player()
	if _me == null:
		printerr("S54: !! 没有玩家")
		get_tree().quit(0)
		return

	await _measure("走路")

	# 飞行
	if _me.has_method("_summon_mount"):
		_me.call("_summon_mount", true, -1)
	await get_tree().create_timer(3.0).timeout
	if _me.get("mounted_vehicle") == null:
		printerr("S54: !! 没骑上坐骑，飞行段跳过")
	else:
		await _measure("飞行")

	get_tree().quit(0)


func _measure(tag: String) -> void:
	var prev: Vector3 = _me.global_position
	var prev_up: Vector3 = Planet.up_at(prev)
	var ds: Array[float] = []
	Input.action_press("move_forward")
	# 预热 20 帧：跳过起步加速段，只测稳定巡航的均匀性
	for i in 20:
		await get_tree().physics_frame
	prev = _me.global_position
	for i in FRAMES:
		await get_tree().physics_frame
		var p: Vector3 = _me.global_position
		# 只量切平面位移（球面上"走了多远"不等于世界坐标差）
		var up: Vector3 = Planet.up_at(p)
		var d: Vector3 = p - prev
		var tangential: float = (d - up * d.dot(up)).length()
		ds.append(tangential)
		prev = p
		prev_up = up
	Input.action_release("move_forward")

	var sum := 0.0
	var mn := 1e9
	var mx := -1e9
	for v in ds:
		sum += v
		mn = minf(mn, v)
		mx = maxf(mx, v)
	var mean: float = sum / float(ds.size())
	var var_sum := 0.0
	for v in ds:
		var_sum += (v - mean) * (v - mean)
	var sd: float = sqrt(var_sum / float(ds.size()))
	var land := get_tree().root.find_children("*LandParticles*", "GPUParticles3D", true, false).size()
	printerr("S54[%s]: 每帧位移 均值=%.4f 最小=%.4f 最大=%.4f 标准差=%.5f | 落地粒子=%d" % [
		tag, mean, mn, mx, sd, land])
	printerr("S54[%s]: 极差/均值 = %.2f（<0.35 视为平滑）" % [tag, (mx - mn) / maxf(mean, 0.0001)])
	var zero_at: Array[String] = []
	for i in ds.size():
		if ds[i] < mean * 0.2:
			zero_at.append("%d(%.4f)" % [i, ds[i]])
	printerr("S54[%s]: 异常帧(<20%%均值): %s" % [tag, "无" if zero_at.is_empty() else ", ".join(zero_at)])


func _find_player() -> Node3D:
	var pc := _level.get_node_or_null("PlayersContainer")
	return pc.get_node_or_null("1") as Node3D if pc != null else null
