extends Node3D
## M25f 劫持回归探针（窗口模式）——坐骑生命周期约定 M6/M7/M8：
##   ① bot 召唤自动驾驶沙发 → 打 bot_only 标记、Prompt 隐藏
##   ② 玩家在 bot 沙发旁按 E（request_mount）→ 必须被拒绝（M6）
##   ③ 服务器直调 server_mount_peer(玩家) → 必须被拒绝（M6）
##   ④ 玩家骑自己的沙发时靠近另一台空车按 E → 必须被拒绝（M7 一骑一席）
##   ⑤ 白盒注入"玩家被困 bot 沙发当乘客"终态 → 按 X → 必须下座落回地面，
##      且 bot 沙发继续存在不被收回（M8 自救键）
## 用法：godot --path <项目> res://tools/probe_mount_hijack.tscn

var _level: Node3D
var _cam: Camera3D
var _elapsed := 0.0
var _steps := []
var _step_idx := 0
var _done := false
var _bot_couch: Node3D = null
var _phase := 0
var _results := {}

func _ready() -> void:
	var level: Node3D = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	get_tree().root.call_deferred("add_child", level)
	_level = level
	await get_tree().process_frame
	await get_tree().process_frame
	level._on_host_pressed("验收员", "blue")
	await get_tree().create_timer(1.0).timeout
	for ui_name in ["MainMenuUI", "MultiplayerChatUI"]:
		var ui := level.get_node_or_null(ui_name)
		if ui:
			ui.visible = false
	var local_player: Node = level.get_node_or_null("PlayersContainer/1")
	if local_player != null:
		local_player.request_choose_class.rpc_id(1, "warrior")
	var class_ui := level.get_node_or_null("ClassSelectUI")
	if class_ui:
		class_ui.visible = false
	var cam := (local_player.get_node_or_null("Camera3D") as Camera3D) if local_player != null else null
	if cam:
		cam.enabled = false
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	_steps = [
		{"time": 6.5, "name": "m25f_01_bot_couch_reject.png", "pos": Vector3(14, 8, 82), "look": Vector3(8, 3, 74)},
		{"time": 12.5, "name": "m25f_02_player_escape.png", "pos": Vector3(14, 8, 82), "look": Vector3(8, 3, 74)},
	]
	printerr("HIJACK: 劫持回归开始")


func _seats_of(couch: Node) -> Dictionary:
	if couch == null:
		return {}
	var sv = couch.get("seats")
	return sv if sv != null else {}


func _player() -> Node:
	return _level.get_node_or_null("PlayersContainer/1")


func _assert(tag: String, ok: bool, detail: String) -> void:
	_results[tag] = ok
	printerr("HIJACK_TEST[%s]: %s — %s" % [tag, "PASS" if ok else "FAIL", detail])


func _physics_process(delta: float) -> void:
	if _cam == null or _done:
		return
	_elapsed += delta
	var player := _player()

	# ===== 阶段 1（t=3）：bot 召唤自动驾驶沙发 =====
	if _phase == 0 and _elapsed >= 3.0:
		_phase = 1
		var container := _level.get_node_or_null("PlayersContainer")
		for child in container.get_children():
			if str(child.name).begins_with("90") and child.has_method("bot_summon_and_mount"):
				var bt := child.get_node_or_null("BTPlayer")
				if bt != null:
					bt.process_mode = Node.PROCESS_MODE_DISABLED  # 演示停 BT，防到达收车
				child.bot_summon_and_mount()
				_bot_couch = child.get("mounted_vehicle")
				var prompt := _bot_couch.get_node_or_null("Prompt") as Label3D if _bot_couch != null else null
				printerr("HIJACK: bot %s 召唤沙发 bot_only=%s seats=%s prompt=%s" % [
					child.name, _bot_couch.get("bot_only") if _bot_couch else "?",
					_seats_of(_bot_couch).keys(),
					(prompt.visible if prompt != null else "无Prompt节点")])
				break

	# ===== 阶段 2（t=4.5）：把玩家挪到 bot 沙发旁（复现事故距离），按 E =====
	if _phase == 1 and _elapsed >= 4.5:
		_phase = 2
		if _bot_couch != null and player != null:
			player.global_position = _bot_couch.global_position + Vector3(1.5, 0.0, 0.0)
			# E 键等价路径：沙发 _unhandled_input → request_mount
			_bot_couch.request_mount.rpc_id(1)
			await get_tree().create_timer(0.3).timeout
			var s: Dictionary = _seats_of(_bot_couch)
			_assert("M6_E上座拒绝", not s.has(1) and player.get("mounted_vehicle") == null,
				"bot沙发 seats=%s 玩家mounted=%s" % [s.keys(), str(player.get("mounted_vehicle"))])
			# 另一入口：服务器直调
			var ok2: bool = _bot_couch.server_mount_peer(1)
			var s2: Dictionary = _seats_of(_bot_couch)
			_assert("M6_直调拒绝", not ok2 and not s2.has(1),
				"server_mount_peer(1) 返回=%s seats=%s" % [ok2, s2.keys()])

	# ===== 阶段 3（t=7）：玩家 X 召唤自己的沙发（正常链路回归）=====
	if _phase == 2 and _elapsed >= 7.0:
		_phase = 3
		if player != null and player.has_method("_summon_mount"):
			player._summon_mount(true)
			await get_tree().create_timer(0.4).timeout
			var own := _level.get_node_or_null("Environment/Vehicles/couch_1")
			var s: Dictionary = _seats_of(own)
			_assert("M2_召唤即骑", s.has(1) and player.get("mounted_vehicle") == own,
				"couch_1 seats=%s" % s.keys())

	# ===== 阶段 4（t=9）：一骑一席——骑着自己沙发时靠近空车按 E =====
	if _phase == 3 and _elapsed >= 9.0:
		_phase = 4
		var vehicles := _level.get_node_or_null("Environment/Vehicles")
		var scene := load("res://scenes/vehicles/hover_couch.tscn") as PackedScene
		var spare := scene.instantiate()
		spare.name = "couch_777"  # 非 bot 空车（玩家名下车）
		vehicles.add_child(spare, true)
		spare.global_position = player.global_position + Vector3(1.5, 0.0, 0.0)
		spare.request_mount.rpc_id(1)
		await get_tree().create_timer(0.3).timeout
		var s: Dictionary = _seats_of(spare)
		_assert("M7_一骑一席", not s.has(1) and player.get("mounted_vehicle") != spare,
			"空车 seats=%s 玩家仍骑=%s" % [s.keys(), str(player.get("mounted_vehicle"))])
		spare.queue_free()

	# ===== 阶段 5（t=11）：玩家按 X 下座收车（M8 正常路径）=====
	if _phase == 4 and _elapsed >= 11.0:
		_phase = 5
		if player != null and player.get("mounted_vehicle") != null:
			player.mounted_vehicle.request_dismount.rpc_id(1)
			player._recall_mount()
			await get_tree().create_timer(0.4).timeout
			var own := _level.get_node_or_null("Environment/Vehicles/couch_1")
			_assert("M8_自己的车下座即收", own == null and player.get("mounted_vehicle") == null,
				"couch_1 存在=%s" % (own != null))

	# ===== 阶段 6（t=13）：白盒注入"被困 bot 沙发乘客"终态 → X 自救 =====
	if _phase == 5 and _elapsed >= 13.0:
		_phase = 6
		if _bot_couch != null and is_instance_valid(_bot_couch) and player != null:
			# 复现真实场景：bot 沙发在巡航高度（地面+10m），bot 被座位跟随钉在座上
			_bot_couch.global_position = Vector3(_bot_couch.global_position.x, 12.0, _bot_couch.global_position.z)
			await get_tree().create_timer(0.2).timeout
			# 注入旧 bug 的终态（M6 上线后新玩家进不来，历史兼容/防御验证）
			_bot_couch.seats[1] = 1
			player.set_mounted(_bot_couch, 1)
			player.global_position = _bot_couch.global_position + Vector3(-0.55, 1.1, 0.35)
			# 按 X：对当前骑乘物下座 + 只收自己的车
			player.mounted_vehicle.request_dismount.rpc_id(1)
			player._recall_mount()
			await get_tree().create_timer(0.6).timeout
			var s: Dictionary = _seats_of(_bot_couch)
			# 真实自救：从巡航高度下座 → 落回地面（2.25 地板 +0.5），沙发留给 bot
			var escaped: bool = player.get("mounted_vehicle") == null and not s.has(1) \
				and is_instance_valid(_bot_couch) and player.global_position.y < 4.0
			_assert("M8_被困自救", escaped,
				"玩家mounted=%s bot沙发seats=%s 车存活=%s 玩家y=%.2f" % [
					str(player.get("mounted_vehicle")), s.keys(),
					is_instance_valid(_bot_couch), player.global_position.y])

	# 截图
	while _step_idx < _steps.size() and _elapsed >= float(_steps[_step_idx]["time"]):
		var step: Dictionary = _steps[_step_idx]
		_step_idx += 1
		_cam.global_position = step.pos
		_cam.look_at(step.look, Vector3.UP)
		_log_vehicles(str(step.name))
		_do_shot_async(str(step.name))
	if _elapsed >= 17.0 and not _done:
		_done = true
		var fails := 0
		for k in _results:
			if not _results[k]:
				fails += 1
		printerr("HIJACK: 回归结束 fail=%d（共 %d 项）" % [fails, _results.size()])
		get_tree().quit(0)


func _log_vehicles(tag: String) -> void:
	var vehicles := _level.get_node_or_null("Environment/Vehicles")
	if vehicles == null:
		return
	var info := []
	for v in vehicles.get_children():
		var seats_v = v.get("seats")
		var seats: Dictionary = seats_v if seats_v != null else {}
		info.append("%s(seats=%s bot_only=%s)" % [v.name, seats.keys(), str(v.get("bot_only"))])
	printerr("HIJACK[%s]: 载具 %d 台 %s" % [tag, vehicles.get_child_count(), info])


func _do_shot_async(file_name: String) -> void:
	await get_tree().create_timer(0.4).timeout
	await get_tree().create_timer(0.3).timeout
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://screenshots/" + file_name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("SHOT: ", file_name)
