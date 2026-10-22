extends Node3D
## M25d/M25c 验收探针（窗口模式，勿加 headless）：
##   ① 村中心广角——出生无坐骑（Environment/Vehicles 应为空）
##   ② 村南怪区——怪物贴地站立（贴地约定验证）
##   ③ 玩家 X 召唤——沙发生成并立即骑上
##   ④ 再按 X——下座 + 沙发立即消失（无人骑坐骑不显示）
##   ⑤ bot 召唤上座——同款召唤即骑机制
## 用法：godot --path <项目> res://tools/probe_m25c_accept.tscn

var _level: Node3D
var _cam: Camera3D
var _elapsed := 0.0
var _steps := []          # [{time, name, pos, look}]
var _step_idx := 0
var _done := false
var _mount_shown := false
var _recall_shown := false
var _bot_mount_shown := false
var _watch := {}

func lp2() -> Node:
	return _level.get_node_or_null("PlayersContainer/1")

func _ready() -> void:
	var level: Node3D = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	get_tree().root.call_deferred("add_child", level)
	_level = level
	await get_tree().process_frame
	await get_tree().process_frame
	level._on_host_pressed("验收员", "blue")
	await get_tree().create_timer(1.0).timeout
	# 关主菜单/聊天 UI，保留 HUD
	for ui_name in ["MainMenuUI", "MultiplayerChatUI"]:
		var ui := level.get_node_or_null(ui_name)
		if ui:
			ui.visible = false
	# 自动选战士并关职业面板
	var local_player: Node = level.get_node_or_null("PlayersContainer/1")
	if local_player != null:
		local_player.request_choose_class.rpc_id(1, "warrior")
	var class_ui := level.get_node_or_null("ClassSelectUI")
	if class_ui:
		class_ui.visible = false
	# 禁用本地玩家相机，跟拍相机接管
	var cam := (local_player.get_node_or_null("Camera3D") as Camera3D) if local_player != null else null
	if cam:
		cam.enabled = false
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	_steps = [
		{"time": 3.0, "name": "m25c_01_village_no_mount.png", "pos": Vector3(14, 13, 88), "look": Vector3(0, 3, 74)},
		{"time": 6.5, "name": "m25c_02_monsters_grounded.png", "pos": Vector3(2, 24, 112), "look": Vector3(0, 2, 92)},
		{"time": 9.5, "name": "m25c_03_player_summon_ride.png", "pos": Vector3.ZERO, "look": Vector3.ZERO},   # 跟玩家
		{"time": 13.0, "name": "m25c_04_after_recall.png", "pos": Vector3.ZERO, "look": Vector3.ZERO},      # 跟玩家
		{"time": 16.4, "name": "m25c_05_bot_mounted.png", "pos": Vector3.ZERO, "look": Vector3.ZERO},       # 跟 bot（召唤后 0.4s 抢拍）
	]
	printerr("ACCEPT: 验收开始")


func _physics_process(delta: float) -> void:
	if _cam == null:
		return
	_elapsed += delta
	# 到点动作
	if not _mount_shown and _elapsed >= 8.0:
		_mount_shown = true
		var lp: Node = _level.get_node_or_null("PlayersContainer/1")
		if lp != null and lp.has_method("_summon_mount"):
			lp._summon_mount(true)
			printerr("ACCEPT: 玩家 X 召唤即骑已触发")
	if not _recall_shown and _elapsed >= 12.0:
		_recall_shown = true
		var lp: Node = _level.get_node_or_null("PlayersContainer/1")
		if lp != null and lp.get("mounted_vehicle") != null:
			lp.mounted_vehicle.request_dismount.rpc_id(1)  # 下座
			lp._recall_mount()                              # 收回
			printerr("ACCEPT: 玩家再按 X 下座+收车已触发")
	if not _bot_mount_shown and _elapsed >= 16.0:
		_bot_mount_shown = true
		var container := _level.get_node_or_null("PlayersContainer")
		for child in container.get_children():
			if str(child.name).begins_with("90") and child.has_method("bot_summon_and_mount"):
				# 演示专用：临时停掉 bot 行为树（否则 bot 距目标 <9m 时 BT 立刻判"到达"收车，拍不到骑乘画面）
				var bt := child.get_node_or_null("BTPlayer")
				if bt != null:
					bt.process_mode = Node.PROCESS_MODE_DISABLED
				child.bot_summon_and_mount()
				printerr("ACCEPT: bot %s 召唤上座已触发 mounted=%s" % [child.name, child.get("mounted_vehicle")])
				break
	# 到点截图
	while _step_idx < _steps.size() and _elapsed >= float(_steps[_step_idx]["time"]):
		var step: Dictionary = _steps[_step_idx]
		_step_idx += 1
		var focus: Vector3
		if step.pos == Vector3.ZERO:
			var track: Node = null
			if step.name.ends_with("bot_mounted.png"):
				track = _find_first_bot()
			else:
				track = _level.get_node_or_null("PlayersContainer/1")
			focus = (track as Node3D).global_position if track != null else Vector3(0, 3, 70)
			_cam.global_position = focus + Vector3(0, 5.0, -8.0)
			_cam.look_at(focus + Vector3(0, 1.2, 0), Vector3.UP)
		else:
			_cam.global_position = step.pos
			_cam.look_at(step.look, Vector3.UP)
		_log_vehicles(step.name)
		_do_shot_async(str(step.name))
	if _elapsed >= 20.0 and not _done:
		_done = true
		printerr("ACCEPT: 验收结束")
		get_tree().quit(0)


func _find_first_bot() -> Node:
	var container := _level.get_node_or_null("PlayersContainer")
	if container == null:
		return null
	for child in container.get_children():
		if str(child.name).begins_with("90"):
			return child
	return null


func _log_vehicles(tag: String) -> void:
	var vehicles := _level.get_node_or_null("Environment/Vehicles")
	if vehicles == null:
		printerr("ACCEPT[%s]: Vehicles 容器不存在" % tag)
		return
	var info := []
	for v in vehicles.get_children():
		var seats_v = v.get("seats")
		var seats: Dictionary = seats_v if seats_v != null else {}
		info.append("%s(seats=%s)" % [v.name, seats.keys()])
	printerr("ACCEPT[%s]: 载具 %d 台 %s" % [tag, vehicles.get_child_count(), info])


func _do_shot_async(file_name: String) -> void:
	await get_tree().create_timer(0.4).timeout
	await get_tree().create_timer(0.3).timeout
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://screenshots/" + file_name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("SHOT: ", file_name)
