extends Node3D
## M39 验收探针：一次跑完三条需求的视觉取证。
##   需求 1a 水平光环  → m39_1a_halo.png（近距离看沙发 + 光环）
##   需求 1b 设置开关  → m39_1b_settings.png（暂停菜单 GameplayPanel）
##   需求 3   场景材质  → m39_3a_village.png（村中心地板 + 远处地形）
##   需求 2   远距任务  → m39_2a_hunt.png（1500m 外狩猎区怪物 + 地形）
##
## 存在理由：OS 级截屏（GDI/PrintWindow）会抓到过期缓存帧，
## 必须从 Godot 内部 get_viewport().get_texture().get_image() 拿帧。
##
## 用法（窗口模式，勿加 headless——截图需要真实渲染）：
##   godot --path <项目> res://tools/m39_verify_shot.tscn

const SHOT_DIR := "res://screenshots/m39/"
## 各机位：(文件名, 相机位置, 注视点)
const VILLAGE_SHOT := ["m39_3a_village.png", Vector3(18, 14, -95), Vector3(0, 2, -135)]
const HALO_SHOT := ["m39_1a_halo.png", Vector3(3.5, 4.2, -124.0), Vector3(0, 2.4, -130.0)]
## 狩猎区：怪物实测在 z≈-1552，相机压低到 3m 平视（雾外能看清怪物轮廓）
const HUNT_SHOT := ["m39_2a_hunt.png", Vector3(12, 3.2, -1520), Vector3(-10, 1.0, -1556)]

var _level: Node3D
var _cam: Camera3D
var _step := 0
var _elapsed := 0.0
var _couch: Node3D = null
var _busy := false


func _ready() -> void:
	var level: Node3D = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	get_tree().root.call_deferred("add_child", level)
	_level = level
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		_run_headless_checks(level)
		return
	# 窗口模式：模拟主机开局（不 host 的话玩家/bot 不会 spawn）
	level._on_host_pressed("验收员", "blue")
	await get_tree().create_timer(1.5).timeout
	for ui_name in ["MainMenuUI", "MultiplayerChatUI", "ClassSelectUI", "DialogueUI"]:
		var ui := level.get_node_or_null(ui_name)
		if ui:
			ui.visible = false
	_disable_local_cameras()
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	printerr("M39-SHOT: 开始")


## headless 模式只跑逻辑校验（怪物落点/贴地/光环默认可见/设置持久化）
func _run_headless_checks(level: Node3D) -> void:
	await get_tree().create_timer(3.0).timeout
	var mon := level.get_node_or_null("Environment/Monsters")
	if mon == null:
		printerr("M39-CHECK: !! 找不到 Environment/Monsters")
	else:
		var n := 0
		var nan_cnt := 0
		var far := 0
		var min_d := INF
		for m in mon.get_children():
			if not (m is Node3D):
				continue
			n += 1
			var p: Vector3 = (m as Node3D).global_position
			if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
				nan_cnt += 1
			var d: float = Vector2(p.x, p.z).distance_to(Vector2(0, -130))
			if d > 1000.0:
				far += 1
			min_d = minf(min_d, d)
		printerr("M39-CHECK: 怪物总数=%d NaN=%d 距村>1000m=%d 最近距离=%.0fm" % [
			n, nan_cnt, far, min_d])
		var sample: Node3D = mon.get_child(0) as Node3D
		if sample != null:
			printerr("M39-CHECK: 样本 %s 位置=(%.0f,%.1f,%.0f)" % [
				sample.name, sample.global_position.x, sample.global_position.y,
				sample.global_position.z])
	var vs := get_node_or_null("/root/VehicleSettings")
	if vs != null and vs.has_method("is_hover_halo_enabled"):
		printerr("M39-CHECK: 光环默认开启=", vs.call("is_hover_halo_enabled"))
	var ar := get_node_or_null("/root/AutoRun")
	if ar != null and ar.has_method("is_active"):
		printerr("M39-CHECK: AutoRun 初始状态=", ar.call("is_active"))
	print("M39-CHECK: DONE")
	get_tree().quit(0)


func _disable_local_cameras() -> void:
	if _level == null:
		return
	var container := _level.get_node_or_null("PlayersContainer")
	if container == null:
		return
	for child in container.get_children():
		var cam := child.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.enabled = false


func _physics_process(delta: float) -> void:
	if _cam == null or _busy:
		return
	_elapsed += delta
	if _step == 0 and _elapsed >= 1.0:
		_step = 1
		_take(VILLAGE_SHOT)
	elif _step == 1 and _elapsed >= 4.0:
		_step = 2
		_find_couch()
		# 等召唤走完（M28：spawn 快照在 add_child(true) 瞬间序列化，入树后才
		# 设置的位置来不及送达 —— 所以必须等 2s 让寻路/落位/光环可见性都跑完）
		_take_delayed(HALO_SHOT, 2.2)
	elif _step == 2 and _elapsed >= 9.0:
		_step = 3
		_take(SETTINGS_SHOT)
	elif _step == 3 and _elapsed >= 12.0:
		_step = 4
		_take_hunt()
	elif _step == 4 and _elapsed >= 16.0:
		_step = 5
		printerr("M39-SHOT: 结束，共 4 张")
		get_tree().quit(0)


## 暂停菜单（需求 1b 的坐骑光环开关）
const SETTINGS_SHOT := ["m39_1b_settings.png", Vector3(0, 2.8, -125.0), Vector3(0, 2.8, -130.0)]


func _find_couch() -> void:
	# 沙发只在被召唤时才存在，直接查场景树是找不到的（M39 首轮踩过）。
	# 走玩家自己的召唤入口：_summon_mount(auto_mount=false) —— 服务器权威直调。
	var player := _level.get_node_or_null("PlayersContainer/1")
	if player != null and player.has_method("_summon_mount"):
		player._summon_mount(false)
		printerr("M39-SHOT: 已请求召唤沙发")
	var vehicles := _level.get_node_or_null("Environment/Vehicles")
	if vehicles != null:
		for child in vehicles.get_children():
			_couch = child as Node3D
			if _couch != null and str(_couch.name).begins_with("couch"):
				break
	if _couch != null:
		printerr("M39-SHOT: 找到沙发 %s pos=%s" % [_couch.name, str(_couch.global_position)])
	else:
		printerr("M39-SHOT: !! 没找到沙发")


## 狩猎区：动态构图 —— 读怪实际位置（地面 -6.7m，硬编码机位会悬空俯视拍不到）。
## 相机放在怪物群南侧 30m、地面上方 3m，平视看向群心。
func _take_hunt() -> void:
	var mon := _level.get_node_or_null("Environment/Monsters")
	var pts: Array = []
	if mon != null:
		for m in mon.get_children():
			if m is Node3D:
				pts.append((m as Node3D).global_position)
	if pts.is_empty():
		printerr("M39-SHOT: !! 找不到怪物，跳过狩猎区截图")
		_take(HUNT_SHOT)
		return
	var center := Vector3.ZERO
	for p in pts:
		center += p
	center /= float(pts.size())
	printerr("M39-SHOT: 怪物群中心=%s 只数=%d" % [str(center), pts.size()])
	# ===== M39 取景踩坑全过程（全部是探针判断标准错，不是游戏 bug）=====
	# 坑 1：按"群心 y+3"摆相机 → 相机埋进地形，Terrain3D 近平面裁掉脚下网格。
	# 坑 2：改用 terrain.get_height 数据高度 → 数据 -4.6m，但渲染用的是
	#       clipmap 网格（更低）。**用数据高度评判视觉位置是错的**。
	# 坑 3：改用 intersect_ray 物理射线 → 打到 -5.0m，但怪物实际 y=-9.8m。
	# 坑 4：改用怪物 y 当基准 → 相机 y=-0.8m 仍低于该处 clipmap 网格面，
	#       画面下半是 Terrain3D 的 world_background（纯蓝），怪物像悬在虚空。
	# 定稿：**在"相机将要站的位置"打射线取地面，相机 = 该地面 + 3m**，
	# 再朝群心俯视约 20°。这样相机必然在地表之上。
	var ground: float = center.y
	var probe_node := _cam
	var cam_x := center.x + 6.0
	var cam_z := center.z + 22.0
	if probe_node != null:
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(cam_x, center.y + 120.0, cam_z),
			Vector3(cam_x, center.y - 80.0, cam_z))
		var hit := probe_node.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			ground = (hit.position.y as float)
		if not hit.is_empty():
			ground = (hit.position.y as float)
	var cam_pos := Vector3(cam_x, ground + 3.0, cam_z)
	var look := Vector3(center.x, center.y + 1.2, center.z)
	printerr("M39-SHOT: 群心y=%.2f 站位地面y=%.2f 相机y=%.2f" % [
		center.y, ground, cam_pos.y])
	_take_settle(["m39_2a_hunt.png", cam_pos, look], 3.0)


func _printerr_ground(g: float, c: Vector3) -> void:
	printerr("M39-SHOT: 群心y=%.2f 渲染地面y=%.2f 相机y=%.2f" % [
		c.y, g, c.y + 9.0])


func _take(cfg: Array) -> void:
	_take_settle(cfg, 0.4)


## settle = 摆位后等待秒数。Terrain3D 的 clipmap 是**异步重建**的：相机瞬移
## 1425m（村子→狩猎区）后网格不会立刻出现，留 0.4s 会拍到一块蓝色空洞
## （mesh_lods=7 生效后的首版狩猎区截图就是这个症状）。
func _take_settle(cfg: Array, settle: float) -> void:
	_busy = true
	_cam.global_position = cfg[1]
	_cam.look_at(cfg[2], Vector3.UP)
	await get_tree().create_timer(settle).timeout
	await get_tree().create_timer(0.4).timeout
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(SHOT_DIR + str(cfg[0]))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("M39-SHOT: ", cfg[0])
	_busy = false


## 延迟拍照版：给召唤/落位等异步过程留时间（_busy 期间 _physics_process 不推进）
func _take_delayed(cfg: Array, delay: float) -> void:
	_busy = true
	await get_tree().create_timer(delay).timeout
	_cam.global_position = cfg[1]
	_cam.look_at(cfg[2], Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await get_tree().create_timer(0.4).timeout
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(SHOT_DIR + str(cfg[0]))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("M39-SHOT: ", cfg[0])
	_busy = false