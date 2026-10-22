extends Node3D
## M40 像素验收探针（窗口模式，走真实 Vulkan；本机 headless 是 dummy 后端无法出图）。
## 覆盖五类：暴风雨 / 法术三元素 / 小精灵光环 / 飞机 / 短剑。
## 引擎自存帧：get_viewport().get_texture().get_image().save_png()
## 用法（窗口模式，勿加 --headless）：
##   godot --path <项目> res://tools/m40_shot.tscn
## 输出到 res://screenshots/m40/

const SHOT_DIR := "res://screenshots/m40/"
var _level: Node3D
var _cam: Camera3D
var _step := 0
var _elapsed := 0.0
var _busy := false


func _ready() -> void:
	var lvl_scene := load("res://scenes/level/level.tscn") as PackedScene
	var level := lvl_scene.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", level)
	_level = level
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("M40-SHOT: 检测到 headless 显示后端（dummy），无法离屏渲染，退出")
		get_tree().quit(0)
		return
	# 窗口模式：模拟主机开局
	level._on_host_pressed("验收员", "blue")
	await get_tree().create_timer(2.0).timeout
	for ui_name in ["MainMenuUI", "MultiplayerChatUI", "ClassSelectUI", "DialogueUI", "WorldMapUI"]:
		var ui := _level.get_node_or_null(ui_name)
		if ui != null:
			ui.visible = false
	_disable_local_cameras()
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	printerr("M40-SHOT: 开始渲染")
	for c in get_tree().root.get_children():
		printerr("M40-DIAG: root 下=", c.name, " (", c.get_class(), ")")
	for c in _level.get_children():
		printerr("M40-DIAG: level 下=", c.name, " (", c.get_class(), ")")
	var pc2 := _level.get_node_or_null("PlayersContainer")
	if pc2 != null:
		for c in pc2.get_children():
			printerr("M40-DIAG: PlayersContainer 下=", c.name)
	else:
		printerr("M40-DIAG: level 里没有 PlayersContainer!")
	for c in get_tree().root.find_children("*", "Camera3D", true, false):
		printerr("M40-DIAG: 全局相机=", str((c as Node).get_path()),
				" current=", str((c as Camera3D).current))


func _disable_local_cameras() -> void:
	# M40 澄清：诊断证实 @Camera3D@878 是探针自身 _cam（自动命名），玩家相机 current 全为 false，
	# 从来没有竞争——此处只停玩家子树处理即可；free 相机会导致段错误（EXIT 139），严禁。
	var pc := _level.get_node_or_null("PlayersContainer")
	if pc != null:
		for child in pc.get_children():
			child.process_mode = Node.PROCESS_MODE_DISABLED


func _physics_process(delta: float) -> void:
	if _cam == null:
		return
	_cam.make_current()  # 每帧抢回镜头，防玩家相机 make_current 覆盖
	_elapsed += delta
	if _busy:
		return
	if _step == 0 and _elapsed >= 1.0:
		_step = 1
		_take_storm()
	elif _step == 1 and _elapsed >= 5.0:
		_step = 2
		_take_spells()
	elif _step == 2 and _elapsed >= 9.0:
		_step = 3
		_take_partner()
	elif _step == 3 and _elapsed >= 13.0:
		_step = 4
		_take_airplane()
	elif _step == 4 and _elapsed >= 17.0:
		_step = 5
		_take_sword()
	elif _step == 5 and _elapsed >= 21.0:
		printerr("M40-SHOT: 结束，共 5 张")
		get_tree().quit(0)


func _take_storm() -> void:
	_busy = true
	var storm := _level.get_node_or_null("StormSystem")
	printerr("M40-DIAG: storm=", storm)
	if storm != null and storm.has_method("set_storm"):
		storm.call("set_storm", true)
		await get_tree().create_timer(0.2).timeout
		var rain: Node = storm.get_node_or_null("Rain")
		if rain != null:
			printerr("M40-DIAG: rain emitting=", str((rain as GPUParticles3D).emitting),
					" pos=", str((rain as GPUParticles3D).global_position),
					" draw_pass=", str((rain as GPUParticles3D).draw_pass_1 != null))
		else:
			printerr("M40-DIAG: Rain 节点缺失")
	_cam.global_position = Vector3(0, 18, -90)
	_cam.look_at(Vector3(0, 6, -130))
	await get_tree().create_timer(2.5).timeout
	printerr("M40-DIAG: 当前相机=", get_viewport().get_camera_3d(), " 我方机位=", str(_cam.global_position))
	_capture("m40_storm.png")
	_busy = false


func _take_spells() -> void:
	_busy = true
	var scn := load("res://scenes/combat/projectile.tscn") as PackedScene
	var base := Vector3(2, 3, -110)
	var specs := [
		["m_fireball", Color(1, 0.45, 0.12)],
		["m_frostbolt", Color(0.5, 0.85, 1)],
		["m_arcane", Color(0.7, 0.4, 1)],
	]
	var i := 0
	for s in specs:
		var p := scn.instantiate() as Node3D
		_level.add_child(p)
		p.global_position = base + Vector3(-2 + i * 2, 0, 0)
		p.call("setup", Vector3(0, 0, -1), 0.0, 50.0, s[0], s[1])
		i += 1
	_cam.global_position = Vector3(0, 4, -102)
	_cam.look_at(base)
	await get_tree().create_timer(1.5).timeout
	_capture("m40_spells.png")
	_busy = false


func _take_partner() -> void:
	_busy = true
	var player := _level.get_node_or_null("PlayersContainer/1") as Node3D
	var pos := Vector3(0, 2, -120)
	if player != null:
		pos = player.global_position + Vector3(0, 1.5, 0)
	# M40：partner 挂在 /root/Level 下（player.gd _spawn_partner），不在玩家子树
	var partner: Node = _level.get_node_or_null("Partner")
	if partner != null and partner.has_method("set_aura_theme"):
		partner.call("set_aura_theme", Color(1.0, 0.5, 0.15))
	_cam.global_position = pos + Vector3(3, 1.5, 4)
	_cam.look_at(pos)
	await get_tree().create_timer(1.5).timeout
	_capture("m40_partner.png")
	_busy = false


func _take_airplane() -> void:
	_busy = true
	_cam.global_position = Vector3(70, 50, -40)
	_cam.look_at(Vector3(0, 48, -40))
	await get_tree().create_timer(1.0).timeout
	_capture("m40_airplane.png")
	_busy = false


func _take_sword() -> void:
	_busy = true
	var player := _level.get_node_or_null("PlayersContainer/1") as Node3D
	if player != null:
		var hand := player.get_node_or_null("GodotRobot3D/RobotArmature/Skeleton3D/LeftHandAttach")
		if hand != null:
			for w in hand.get_children():
				if w is Node3D:
					w.visible = (w.name == "SwordShort")
	var look: Vector3 = Vector3(0, 1.5, -115)
	var cam_pos: Vector3 = Vector3(2, 2, -110)
	if player != null:
		look = player.global_position + Vector3(0, 1.5, 0)
		cam_pos = player.global_position + Vector3(2.5, 2.0, 3.0)
	_cam.global_position = cam_pos
	_cam.look_at(look)
	await get_tree().create_timer(1.5).timeout
	_capture("m40_sword.png")
	_busy = false


func _capture(fname: String) -> void:
	if _cam:
		_cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	if _cam:
		_cam.make_current()
	await RenderingServer.frame_post_draw  # 确保取到的是本机位渲染完的新帧
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("M40-SHOT: 截图失败 img null", fname)
		return
	var path := ProjectSettings.globalize_path(SHOT_DIR + fname)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("M40-SHOT: 已存", fname)
