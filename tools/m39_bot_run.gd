extends Node3D
## M39 真实玩法验证：让 bot 自己走完「接任务 → 飞往 1500m 外狩猎区 → 打怪 → 飞回交任务」。
## 这是需求 2 的核心验收，探针相机不介入（避免 M39 取景系列的所有坑）。
##
## 做法：实例化真实 level → host → 让 bot 正常跑行为树 → 每 5s 打印 bot/沙发位置与任务进度。
## 相机：跟随 bot 的**第三人称背后**（复用玩家相机逻辑的相对偏移），
##       高度 = bot.position.y + 3.5，看向 bot 头部，天然保证在地表之上。
##
## 用法（窗口模式）：godot --path . res://tools/m39_bot_run.tscn

const TOTAL_SEC := 300.0
const SHOT_EVERY := 20.0

var _level: Node3D
var _cam: Camera3D
var _elapsed := 0.0
var _next_shot := 10.0
var _next_diag := 5.0
var _busy := false
var _last_leg := ""
var _ride_seen := false
var _max_dist := 0.0


func _ready() -> void:
	var level: Node3D = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	get_tree().root.call_deferred("add_child", level)
	_level = level
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		_run_headless(level)
		return
	level._on_host_pressed("验收员", "blue")
	await get_tree().create_timer(1.5).timeout
	for ui_name in ["MainMenuUI", "MultiplayerChatUI", "ClassSelectUI", "DialogueUI"]:
		var ui := level.get_node_or_null(ui_name)
		if ui:
			ui.visible = false
	for child in level.get_node_or_null("PlayersContainer").get_children():
		var cam := child.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.enabled = false
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	printerr("BOTRUN: 开始（真实玩法 bot 全流程验证）")


## headless：只跑行为树 + 位置追踪，不截图
func _run_headless(level: Node3D) -> void:
	await get_tree().create_timer(2.0).timeout
	var t := 0.0
	while t < 420.0:
		await get_tree().create_timer(5.0).timeout
		t += 5.0
		_diag()
	print("BOTRUN: headless 结束")
	get_tree().quit(0)


func _bot() -> Node3D:
	var c := _level.get_node_or_null("PlayersContainer")
	if c == null:
		return null
	for child in c.get_children():
		if str(child.name).begins_with("90"):
			return child as Node3D
	return null


func _diag() -> void:
	var b := _bot()
	if b == null:
		printerr("BOTRUN: 找不到 bot")
		return
	var p: Vector3 = b.global_position
	var d: float = Vector2(p.x, p.z).distance_to(Vector2(0, -130))
	_max_dist = maxf(_max_dist, d)
	var couch = b.get("mounted_vehicle")
	var riding := couch != null
	if riding:
		_ride_seen = true
	var leg := "未知"
	var prog = b.get("_quest_progress")
	var done = b.get("_quests_done")
	if riding:
		leg = "飞行中"
	elif d > 400.0:
		leg = "在狩猎区"
	elif d < 60.0:
		leg = "在村内"
	else:
		leg = "在路上"
	if leg != _last_leg:
		printerr("BOTRUN: 阶段变化 → " + leg + "（距村 " + str(int(d)) + "m）")
		_last_leg = leg
	# M29 铁律：本版本 GDScript 的多参格式化 `% [a,b]` 解析失败，一律 str() 拼接
	printerr("BOTRUN: t=" + str(int(_elapsed)) + "s pos=(" + str(int(p.x)) + ","
		+ str(snappedf(p.y, 0.1)) + "," + str(int(p.z)) + ") 距村="
		+ str(int(d)) + "m 骑行=" + str(riding) + " 任务进度=" + str(prog)
		+ " 已完成=" + str(done) + " 最远=" + str(int(_max_dist)) + "m")
	# M39：诊断 bot 卡在哪一步 —— 当前黑板目标 + 附近怪物数
	var bb = b.get("blackboard")
	if bb != null and bb.has_method("get_var"):
		var tgt = bb.get_var(&"target_node", null)
		var tname := "<null>"
		var tdist := -1.0
		if is_instance_valid(tgt):
			tname = str((tgt as Node).name)
			tdist = snappedf(Vector2(p.x, p.z).distance_to(
				Vector2((tgt as Node3D).global_position.x,
					(tgt as Node3D).global_position.z)), 0.1)
		printerr("BOTRUN:   黑板目标=" + tname + " 水平距离=" + str(tdist) + "m")
	var mon := _level.get_node_or_null("Environment/Monsters")
	var alive := 0
	var nearest := INF
	var nearest_name := "-"
	if mon != null:
		for m in mon.get_children():
			var at = m.get("attribute_set")
			if at == null or not at.is_alive():
				continue
			alive += 1
			var dd: float = Vector2(p.x, p.z).distance_to(
				Vector2((m as Node3D).global_position.x, (m as Node3D).global_position.z))
			if dd < nearest:
				nearest = dd
				nearest_name = str(m.name)
	printerr("BOTRUN:   活怪=" + str(alive) + " 最近=" + nearest_name + " "
		+ str(snappedf(nearest, 0.1)) + "m")


func _physics_process(delta: float) -> void:
	if _cam == null or _busy:
		return
	_elapsed += delta
	if _elapsed >= _next_diag:
		_next_diag = _elapsed + 5.0
		_diag()
	if _elapsed >= _next_shot:
		_next_shot = _elapsed + SHOT_EVERY
		_shot_async()
	if _elapsed >= TOTAL_SEC:
		printerr("BOTRUN: 结束。最远距离=" + str(int(_max_dist)) + "m 见过骑行=" + str(_ride_seen))
		get_tree().quit(0)


## 第三人称跟随：站在 bot 背后 8m、高 3.5m —— 必然在 bot 所在空间之上，
## 不会像 M39 取景那样把相机塞进地形里。
func _shot_async() -> void:
	_busy = true
	var b := _bot()
	if b != null:
		var p: Vector3 = b.global_position
		var yaw: float = b.global_rotation.y
		var back := Vector3(sin(yaw), 0.0, cos(yaw)) * 8.0
		_cam.global_position = p + back + Vector3(0, 3.5, 0)
		_cam.look_at(p + Vector3(0, 1.6, 0), Vector3.UP)
	await get_tree().create_timer(0.8).timeout
	await get_tree().create_timer(0.4).timeout
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(
		"res://screenshots/m39/m39_bot_t%03d.png" % int(_elapsed))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("BOTRUN: 截图 t=" + str(int(_elapsed)))
	_busy = false