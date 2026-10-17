extends Node3D

## 飞行坐骑端到端回归测试（窗口模式，程序模拟按键）。
## 测项：①W 前进 ②松手静止（无自动飞）③C 落地 ④全程不穿地
## 运行：godot --path . res://tools/probe_flight_test.tscn
## 输出：每项 PASS/FAIL + 最终结果，退出码 0=全过 1=有失败

var _terrain_data: Terrain3DData = null
var _couch: Node3D = null
var _player: CharacterBody3D = null
var _fails: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("TEST-FAIL: 需窗口模式")
		get_tree().quit(1)
		return

	if _no_player_mode:
		# 最小战场：只有沙发，无 level/地形/玩家（隔离 hover_couch 自身）
		_couch = (load("res://scenes/vehicles/hover_couch.tscn") as PackedScene).instantiate()
		add_child(_couch)
		_couch.seats = {1: 0}
		printerr("[T] 最小战场：仅沙发")
		await get_tree().physics_frame
		var pos0m := _couch.global_position
		Input.action_press("move_forward")
		await _sleep(2.0)
		Input.action_release("move_forward")
		var d0m: float = (_couch.global_position - pos0m).length()
		_check(d0m >= 25.0, "最小战场 W 位移 %.1fm (期望≥25)" % d0m)
		printerr("[T] 最小战场结论: ", "PASS=沙发自身问题已修复, FAIL=hover_couch 自身有 bug")
		get_tree().quit(0)
		return

	var level: Node3D = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	# M19 二分诊断：禁用 level 全部子树（除 Environment/TerrainStarter + Environment/Vehicles 链）
	# M19：把沙发挪到 Terrain3D 开阔平原（避开 GridMap 建筑与同步器缓存干扰）
	_couch = level.get_node_or_null("Environment/Vehicles/couch_1")
	var env := level.get_node("Environment")
	for child in env.get_children():
		if child.name in ["TerrainStarter", "Vehicles"]:
			continue
		child.process_mode = Node.PROCESS_MODE_DISABLED
	for child in level.get_children():
		if child.name != "Environment":
			child.process_mode = Node.PROCESS_MODE_DISABLED
	printerr("[T] 已禁用 Environment(TerrainStarter/Vehicles 除外) 与 level 其余子树")
	if _couch and _terrain_data:
		var open_pos := Vector3(60, 0, 60)
		open_pos.y = _terrain_data.get_height(open_pos) + 0.8
		_couch.global_position = open_pos
		printerr("[T] 沙发已传送到开阔平原 ", open_pos)

	# 等 terrain 就绪
	var starter := level.get_node_or_null("Environment/TerrainStarter")
	var waited := 0.0
	while waited < 60.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if starter != null and starter.terrain != null:
			break
	_terrain_data = starter.terrain.data
	printerr("[T] terrain 就绪 (%.1fs)" % waited)

	# 生成玩家 + 直连沙发（绕 RPC，直测驾驶逻辑）
	# NO-PLAYER 对照：本轮禁用玩家（排查 mounted 跟随对沙发的影响）
	var players_container := level.get_node_or_null("PlayersContainer") as Node3D
	if not _no_player_mode:
		_player = (load("res://scenes/level/player.tscn") as PackedScene).instantiate()
		_player.name = "1"
		players_container.add_child(_player, true)
		for i in 30:
			await get_tree().physics_frame
	var main_menu: Node = level.get_node("MainMenuUI")
	main_menu.call("hide_menu")
	# 玩家相机制 current（真实游戏路径；否则 StartupCamera 抢占导致驾驶朝向错）
	if _player != null:
		var player_cam := _player.find_children("*", "Camera3D", true, false)
		if player_cam.size() > 0:
			(player_cam[0] as Camera3D).make_current()
			printerr("[T] 玩家相机已接管")

	_couch = level.get_node_or_null("Environment/Vehicles/couch_1")
	if _couch == null:
		# 兜底：玩家生成前 terrain 未就绪时补发逻辑可能没跑，手动放一台
		_couch = (load("res://scenes/vehicles/hover_couch.tscn") as PackedScene).instantiate()
		_couch.name = "couch_1"
		level.get_node("Environment/Vehicles").add_child(_couch)
		_couch.global_position = _player.global_position + Vector3(3, 0.5, -3)
	# M19 诊断：probe 无 peer，MultiplayerSynchronizer 无同步意义——删除以排除嫌疑
	var sync_node := _couch.get_node_or_null("MultiplayerSynchronizer")
	if sync_node:
		_couch.remove_child(sync_node)   # 立即移除（queue_free 延迟一帧不彻底）
		printerr("[T] 已立即移除 MultiplayerSynchronizer")
	# 玩家上车（直接设置状态，等价 sync_seats 的本地效果）
	if not _no_player_mode:
		_couch.seats = {1: 0}
		_player.set_mounted(_couch, 0)
	else:
		_couch.seats = {1: 0}   # 无玩家对照：仍设座位让驾驶分支跑
	await get_tree().physics_frame
	var start_pos: Vector3 = _couch.global_position
	printerr("[T] 测试开始 pos=", start_pos)
	printerr("[T] couch 实例=", _couch.get_instance_id(), " 路径=", _couch.get_path())
	var veh := level.get_node("Environment/Vehicles")
	for c in veh.get_children():
		printerr("[T] Vehicles 子节点: ", c.name, " id=", c.get_instance_id(), " pos=", c.global_position)

	# ===== 测 1：W 前进 2s，水平位移应 ≥ 25m =====
	var pos0 := _couch.global_position
	Input.action_press("move_forward")
	await _sleep(2.0)
	Input.action_release("move_forward")
	var d1: float = Vector2(_couch.global_position.x - pos0.x, _couch.global_position.z - pos0.z).length()
	_check(d1 >= 25.0, "W 前进 2s 位移 %.1fm (期望≥25)" % d1)

	# ===== 测 2：松手 1s，位移应 < 2m（无自动飞）=====
	var pos1 := _couch.global_position
	await _sleep(1.0)
	var d2: float = (_couch.global_position - pos1).length()
	_check(d2 < 2.0, "松手 1s 漂移 %.2fm (期望<2)" % d2)

	# ===== 测 3：C 下降 3s，应贴地（y ≈ 地形+0.3±0.5）=====
	Input.action_press("crouch")
	await _sleep(3.0)
	Input.action_release("crouch")
	var gy: float = _terrain_data.get_height(_couch.global_position)
	var diff: float = _couch.global_position.y - gy
	printerr("[T] 落地诊断: pos=%s get_height(pos)=%.2f y-gy=%.2f" % [_couch.global_position, gy, diff])
	for off in [Vector3(0,0,0), Vector3(10,0,0), Vector3(-10,0,0), Vector3(0,0,10), Vector3(0,0,-10)]:
		var sp: Vector3 = _couch.global_position + off
		printerr("[T]   h(%+.0f,%+.0f)=%.2f" % [sp.x, sp.z, _terrain_data.get_height(sp)])
	_check(diff < 1.0, "C 落地：y-地形=%.2fm (期望<1)" % diff)

	# ===== 全程穿地检查（测试期间记录的最小 y-地形差）=====
	_check(_min_ground_gap > -0.5, "全程不穿地：最小间隙 %.2fm (期望≥-0.5)" % _min_ground_gap)

	# ===== 测 5：下车后玩家不沉地（走真实 sync_seats drop 链路）=====
	_couch.seats = {}   # 服务器语义：座位清空
	_couch.sync_seats({})   # 直调同步（call_local，触发 drop 逻辑）
	var drop_gap: float = _player.global_position.y - _terrain_data.get_height(_player.global_position)
	_check(drop_gap > -0.5 and drop_gap < 3.0, "下车站立：y-地形=%.2fm (期望 0~3)" % drop_gap)
	# 下车后走两步验证碰撞恢复
	Input.action_press("move_forward")
	await _sleep(0.8)
	Input.action_release("move_forward")
	var walk_gap: float = _player.global_position.y - _terrain_data.get_height(_player.global_position)
	_check(walk_gap > -0.5 and walk_gap < 3.0, "下车行走：y-地形=%.2fm (期望 0~3)" % walk_gap)
	printerr("[T] 行走诊断: pos=%s y-地形=%.2f player._terrain_probe=%s" % [
		_player.global_position, walk_gap, _player._terrain_probe])

	if _fails.is_empty():
		printerr("[T] ★★★ 全部 PASS ★★★")
		get_tree().quit(0)
	else:
		printerr("[T] 失败 %d 项: %s" % [_fails.size(), ", ".join(_fails)])
		get_tree().quit(1)


var _min_ground_gap := 999.0
var _no_player_mode := false  # 对照实验开关


func _physics_process(_delta: float) -> void:
	if _couch != null and _terrain_data != null:
		var gap: float = _couch.global_position.y - _terrain_data.get_height(_couch.global_position)
		_min_ground_gap = minf(_min_ground_gap, gap)


func _check(ok: bool, label: String) -> void:
	printerr(("[T] PASS  " if ok else "[T] FAIL  ") + label)
	if not ok:
		_fails.append(label)


func _sleep(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
