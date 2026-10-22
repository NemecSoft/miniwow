extends Node3D
## M25f 诊断：骑乘按住 W 前飞时，沙发 y 是否被地面钳制射线
## （射线擦中座位 0 骑手胶囊 → phys_ground=骑手头顶 → 每帧 maxf 上抬）逐步抬高。
## 用法：godot --path <项目> res://tools/probe_flight_climb.tscn

var _level: Node3D
var _elapsed := 0.0
var _couch: Node3D = null
var _log_t := 0.0

func _ready() -> void:
	var level: Node3D = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	get_tree().root.call_deferred("add_child", level)
	_level = level
	await get_tree().process_frame
	await get_tree().process_frame
	level._on_host_pressed("诊断员", "blue")
	await get_tree().create_timer(1.0).timeout
	for ui_name in ["MainMenuUI", "MultiplayerChatUI"]:
		var ui := level.get_node_or_null(ui_name)
		if ui:
			ui.visible = false
	var lp: Node = level.get_node_or_null("PlayersContainer/1")
	if lp != null:
		lp.request_choose_class.rpc_id(1, "warrior")
	var class_ui := level.get_node_or_null("ClassSelectUI")
	if class_ui:
		class_ui.visible = false
	# X 召唤即骑
	await get_tree().create_timer(1.0).timeout
	if lp != null and lp.has_method("_summon_mount"):
		lp._summon_mount(true)
	await get_tree().create_timer(0.6).timeout
	_couch = lp.get("mounted_vehicle") if lp != null else null
	printerr("CLIMB: 骑乘开始 couch_y=%.2f" % (_couch.global_position.y if _couch != null else -1.0))
	# 按住 W 前飞
	Input.action_press("move_forward")


func _physics_process(delta: float) -> void:
	if _couch == null or not is_instance_valid(_couch):
		return
	_elapsed += delta
	_log_t += delta
	if _log_t >= 0.5:
		_log_t = 0.0
		var lp: Node = _level.get_node_or_null("PlayersContainer/1")
		printerr("CLIMB: t=%.1f couch_y=%.2f player_y=%.2f pos=%s" % [
			_elapsed, _couch.global_position.y,
			lp.global_position.y if lp != null else -1.0,
			_couch.global_position])
	if _elapsed >= 6.0:
		Input.action_release("move_forward")
		printerr("CLIMB: 诊断结束")
		get_tree().quit(0)
