extends Node3D
## M21 Bot 战斗截图探针：实例化真实 level，相机跟拍两个 bot，
## 覆盖「进城接任务 → 出城 → 接近狼 → 战斗 → 掉落」全流程。
## 存在理由：OS 级截屏（GDI）截不到 Vulkan 全屏/被其他窗口盖住，
## 必须从 Godot 内部 get_viewport().get_texture().get_image() 拿帧。
##
## 用法（窗口模式，勿加 headless——截图需要真实渲染）：
##   godot --path <项目> res://tools/probe_bot_shot.tscn

const TOTAL_SEC := 55.0
const SHOT_INTERVAL := 8.0
const SHOTS := 8

var _elapsed := 0.0
var _shot_idx := 0
var _cam: Camera3D
var _level: Node3D
var _class_chosen := false  ## M22：t0 截完职业选择界面后自动选战士
var _next_assist := 6.0     ## M24：玩家首次协战时刻（选完职业缓一拍）
var _last_diag := -1        ## M24：诊断打印节拍
var _total_sec := 55.0      ## headless 社交验证模式自动延长（跑完任务全环）


## M24：每 10 秒打印一次 bot 位置/任务进度（协作链路排障）
func _diag() -> void:
	var cur := int(_elapsed)
	if cur % 10 != 0 or cur == _last_diag:
		return
	_last_diag = cur
	var container := _level.get_node_or_null("PlayersContainer")
	if container == null:
		return
	for child in container.get_children():
		if not str(child.name).begins_with("90"):
			continue
		var attrs: Node = child.get("attribute_set")
		var alive: bool = attrs != null and attrs.is_alive()
		var progress: Dictionary = child.get("_quest_progress")
		printerr("SOCIAL_DIAG: bot%s pos=%.0f,%.0f alive=%s atk=%s class='%s' quests=%s done=%s" % [
			child.name, (child as Node3D).global_position.x,
			(child as Node3D).global_position.z, alive,
			attrs.get("atk") if attrs != null else "?",
			child.get("player_class"), progress,
			child.get("_quests_done")])
	var player := container.get_node_or_null("1")
	if player != null:
		printerr("SOCIAL_DIAG: player pos=%.0f,%.0f quests=%s" % [
			(player as Node3D).global_position.x,
			(player as Node3D).global_position.z, player.get("_quest_progress")])
	var monsters := _level.get_node_or_null("Environment/Monsters")
	if monsters != null:
		for m in monsters.get_children():
			var attrs: Node = m.get("attribute_set")
			if attrs == null:
				continue
			if int(attrs.hp) < int(attrs.max_hp):
				printerr("SOCIAL_DIAG: %s hp=%d/%d" % [m.name, attrs.hp, attrs.max_hp])


## M24：本地玩家攻击最近的活狼（服务器权威 request_attack，制造玩家+bot 协作）
func _assist_nearest_wolf() -> void:
	var player := _level.get_node_or_null("PlayersContainer/1")
	if player == null:
		return
	var monsters := _level.get_node_or_null("Environment/Monsters")
	if monsters == null:
		return
	var best: Node3D = null
	var best_dist := INF
	for child in monsters.get_children():
		# M24 修正：只打狼（与 bot 的 q1 任务怪一致）——此前打"最近怪"
		# 全打到 Raider 身上，玩家与 bot 永远不同目标，协作对无法建立
		if str(child.get("monster_id")) != "wolf":
			continue
		var attrs: Node = child.get("attribute_set")
		if attrs == null or not attrs.is_alive():
			continue
		var dist: float = (player as Node3D).global_position.distance_to((child as Node3D).global_position)
		if dist < best_dist:
			best_dist = dist
			best = child
	if best != null and best_dist < 60.0:
		# 探针专用：贴到狼旁再攻击（basic_attack 有距离校验，站村口够不着）
		(player as Node3D).global_position = (best as Node3D).global_position + Vector3(1.5, 0.5, 0)
		printerr("ASSIST_DIAG: 玩家传送贴脸 %s dist=%.1f" % [best.name, best_dist])  # 临时诊断
		player.request_attack.rpc_id(1, str((player as Node).get_path_to(best)), "basic_attack")


func _ready() -> void:
	var level: Node3D = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	get_tree().root.call_deferred("add_child", level)
	_level = level
	await get_tree().process_frame
	await get_tree().process_frame
	# M24：headless 社交验证模式——无截图/无相机，纯跑协作链路看 SOCIAL 日志
	if DisplayServer.get_name() == "headless":
		_class_chosen = true
		_next_assist = 4.0
		_total_sec = 150.0  # 跑完「接任务→3杀→交任务→好感结算」全环
		_cam = Camera3D.new()  # 占位：_physics_process 以 _cam 判定就绪
		printerr("SHOT: headless 社交验证开始")
		return
	# 窗口模式不会自动 host（headless 分支才会）——模拟主机开局：
	# start_host + 隐藏主菜单 + _ensure_bots，本地玩家/bot 才会 spawn、HUD 才会绑定
	_total_sec = 150.0  # M24：窗口模式也跑全环（玩家协战→好感结算）
	level._on_host_pressed("跟拍员", "blue")
	await get_tree().create_timer(1.0).timeout
	# M22：本地玩家暂不选职业——t0 先截主题化的职业选择界面，
	# 选职业延到 _physics_process 里 _elapsed >= 1.5 时执行
	# 关主菜单/对话等 UI，保留 HUD（展示真实游戏界面）
	for ui_name in ["MainMenuUI", "MultiplayerChatUI"]:
		var ui := level.get_node_or_null(ui_name)
		if ui:
			ui.visible = false
	# 禁用本地玩家相机，避免抢 current（本地玩家留场供 HUD 显示）
	_disable_local_cameras()
	# 跟拍相机
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	printerr("SHOT: 跟拍开始")


func _disable_local_cameras() -> void:
	if _level == null:
		return
	var container := _level.get_node_or_null("PlayersContainer")
	if container == null:
		return
	for child in container.get_children():
		var name_str := str(child.name)
		if name_str.begins_with("9"):  # 9001/9002 bot 不管
			continue
		var cam := child.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.enabled = false


func _bot_focus() -> Vector3:
	"""两只 bot 的中点；找不到就回任务官附近。"""
	if _level == null:
		return Vector3(-20, 2.75, -12)
	var container := _level.get_node_or_null("PlayersContainer")
	if container == null:
		return Vector3(-20, 2.75, -12)
	var pts: Array = []
	for child in container.get_children():
		var name_str := str(child.name)
		if name_str.begins_with("90") and child is Node3D:
			pts.append((child as Node3D).global_position)
	if pts.is_empty():
		return Vector3(-20, 2.75, -12)
	var sum := Vector3.ZERO
	for p in pts:
		sum += p
	return sum / float(pts.size())


func _physics_process(delta: float) -> void:
	if _cam == null:  # _ready 的 await 期间引擎已开始跑 physics，相机还没建
		return
	_elapsed += delta
	# t0 截到职业选择界面后，延迟自动选战士并关面板（不挡后续跟拍）
	if not _class_chosen and _elapsed >= 1.5:
		_class_chosen = true
		var local_player := _level.get_node_or_null("PlayersContainer/1")
		if local_player != null:
			local_player.request_choose_class.rpc_id(1, "warrior")
		var class_ui := _level.get_node_or_null("ClassSelectUI")
		if class_ui:
			class_ui.visible = false
	# M24：玩家协战——每 2 秒对最近的活狼发起攻击，与 bot 构成"一起做任务"协作，
	# 验证好感度系统（协作对 → 任务结算 → 好感/厌恶）
	_diag()
	if _class_chosen and _elapsed >= _next_assist:
		_next_assist = _elapsed + 2.0
		_assist_nearest_wolf()
	if _shot_idx * SHOT_INTERVAL <= _elapsed and _shot_idx < SHOTS:
		_shot_idx += 1
		# 相机跟拍：bot 中点的后上方 45° 俯角
		var focus := _bot_focus()
		_cam.global_position = focus + Vector3(0, 9.0, 13.0)
		_cam.look_at(focus, Vector3.UP)
		# 截图协程独立跑，绝不在 _physics_process 里 await——
		# frame_post_draw 在窗口不可见时不触发，会把 quit 判断一起饿死（实测教训）
		_do_shot_async("bot_%02d_t%d.png" % [_shot_idx, int(_elapsed)])
	if _elapsed >= _total_sec:
		printerr("SHOT: 跟拍结束，共 %d 张" % _shot_idx)
		get_tree().quit(0)


func _do_shot_async(file_name: String) -> void:
	# 场景树计时器等待：窗口被遮挡/不可见时依然走时（frame_post_draw 不会）
	await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(0.3).timeout
	_shot(file_name)


func _shot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return  # headless 无渲染，跳过截图只跑逻辑
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://screenshots/" + file_name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("SHOT: ", file_name)
