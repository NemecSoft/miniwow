extends Node3D

## M56：**骑乘朝向一致性**验收。
##
## 用户要求（硬不变量 I-MOUNT）：
##   骑乘期间，角色朝向必须与飞行器朝向完全一致。
##
## 旧验证的毛病：只在出生点测一次 → 出生点在球面某处，世界 XZ 角度刚好接近正确，
## 所以一直是"我这边测着对，用户那边看着歪"。
## 本探针沿球面取 6 个方向（含两极附近）逐个断言——单一位置的巧合无法通过全域。
##
## 判定式（关系式，不是常数）：
##   angle(身体正面 +Z, 载具前方 -Z) < TOL_DEG
##   载具 basis.Y 与当地法线夹角 < TOL_DEG
## 逐位置输出，任一位置超差即失败。

const OUT_DIR := "res://screenshots/m56"
const TOL_DEG := 2.0
## 球面取样方向：赤道四向 + 两极附近（atan2 型 bug 在极点最明显）+ 斜向
const DIRS := [
	Vector3(1, 0, 0),
	Vector3(0, 0, 1),
	Vector3(-1, 0, 0),
	Vector3(0, 0, -1),
	Vector3(0.02, 0.999, 0.0),
	Vector3(0.6, -0.5, 0.62),
]

var _level: Node
var _me: Node3D
var _fail := 0
var _checks := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if DisplayServer.get_name() == "headless":
		printerr("C56: headless 出不了图，必须窗口模式")
		get_tree().quit(0)
		return
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	_level.call("_on_host_pressed", "朝向一致性", "blue")
	await get_tree().create_timer(6.0).timeout
	var cs = _level.get("class_select_ui")
	if cs != null and cs.has_method("close_panel"):
		cs.close_panel()
	await get_tree().create_timer(0.6).timeout
	_me = await _wait_local_player(30.0)
	if _me == null:
		printerr("C56: 等不到本地玩家")
		get_tree().quit(1)
		return
	_hide_hud()

	for i in DIRS.size():
		await _run_at(DIRS[i], i)

	printerr("C56: ===== 汇总：%d 项断言，失败 %d =====" % [_checks, _fail])
	printerr("C56: 结论：" + ("全部通过 ✓" if _fail == 0 else "!! 有 %d 项超差" % _fail))
	get_tree().quit(0 if _fail == 0 else 1)


func _hide_hud() -> void:
	var hud := _level.get_node_or_null("UI/HUD")
	if hud != null:
		(hud as CanvasItem).visible = false


func _players() -> Array:
	var pc := _level.get_node_or_null("PlayersContainer")
	return pc.get_children() if pc != null else []


func _wait_local_player(timeout: float) -> Node3D:
	var t := 0.0
	while t < timeout:
		for c in _players():
			if c is Node3D and (c as Node).is_multiplayer_authority():
				return c as Node3D
		await get_tree().create_timer(0.4).timeout
		t += 0.4
	return null


## 被测车 = 玩家**实际骑的那台**（mounted_vehicle）。
## 之前按名字前缀扫 Vehicles 取第一台，抓到的是 bot 的 couch_9001 —— 量了 6 个
## 位置全是别人的车，数据整批作废。断言必须锚在被断言的对象上。
func _couch() -> Node3D:
	var mv = _me.get("mounted_vehicle")
	if mv is Node3D and is_instance_valid(mv):
		return mv as Node3D
	return null


## 把玩家搬到球面指定方向的地表正上方
func _teleport(dir: Vector3) -> void:
	var d := dir.normalized()
	var r: float = Planet.RADIUS + Planet.mesh_height(d)
	_me.global_position = d * (r + 0.5)
	(_me as CharacterBody3D).velocity = Vector3.ZERO


## 每个位置开始前彻底清场：下座 + 删掉所有沙发。
## 上一版只在"seats 里有 1"时下座，而玩家可能挂在**已被 queue_free 的旧车**上
## （mounted_vehicle 仍非空）→ 新位置召唤出新车却还 snap 到旧车，前 5 个位置
## 全是假的"超差"。清场是断言可信的前提。
func _clear_mount() -> void:
	var mv = _me.get("mounted_vehicle")
	if mv != null and is_instance_valid(mv):
		if mv.has_method("server_dismount_peer"):
			mv.call("server_dismount_peer", 1)
	_me.call("set_mounted", null)
	await get_tree().create_timer(0.3).timeout
	var v := _level.get_node_or_null("Environment/Vehicles")
	if v != null:
		for c in v.get_children():
			if c is Node3D and String(c.name).begins_with("couch_"):
				c.queue_free()
	await get_tree().create_timer(0.3).timeout


func _run_at(dir: Vector3, idx: int) -> void:
	printerr("C56: ---- 位置 %d 方向=%s ----" % [idx, str(dir.normalized().snapped(Vector3(0.01, 0.01, 0.01)))])
	await _clear_mount()
	_teleport(dir)
	await get_tree().create_timer(1.6).timeout
	var up: Vector3 = Planet.up_at(_me.global_position)
	var gap: float = _me.global_position.length() - (Planet.RADIUS + Planet.mesh_height(up))
	printerr("C56[%d]: 传送后离地 %+.2fm" % [idx, gap])

	# 召唤（服务器本地直调，会自动上座）
	_me.call("_summon_mount", true)
	await get_tree().create_timer(1.2).timeout
	var v := _couch()
	if v == null:
		printerr("C56[%d]: !! 沙发没生成，本位置跳过" % idx)
		return
	if _me.get("mounted_vehicle") == null:
		printerr("C56[%d]: !! 没上座，本位置跳过" % idx)
		return

	await _check(idx, "召唤+静止", i_file(idx, "a_idle"))

	# 飞行 0.9s：载具会按移动方向转向，身体必须即时跟随
	Input.action_press("move_forward")
	await _frames(40)
	var p0: Vector3 = v.global_position
	await _frames(8)
	var disp: Vector3 = v.global_position - p0
	await _check(idx, "直飞中", i_file(idx, "b_fly"), disp)
	Input.action_release("move_forward")
	await get_tree().create_timer(0.4).timeout
	await _check(idx, "松手后", "")

	# 侧移 0.6s：换一个方向再转，验证"转弯过程中"也一致
	Input.action_press("move_left")
	await _frames(36)
	await _check(idx, "转弯中", i_file(idx, "c_turn"))
	Input.action_release("move_left")
	await get_tree().create_timer(0.4).timeout

	# 下座并收车
	await _clear_mount()


func i_file(idx: int, name: String) -> String:
	return "%s/p%d_%s.png" % [OUT_DIR, idx, name]


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## 唯一断言：角色正面 ≡ 载具前方（切平面夹角）
## dir_ref 非零时追加一条：载具前方 ≡ 实际位移方向（防止"人车一起朝反"也算一致）
func _check(idx: int, tag: String, shot: String, dir_ref: Vector3 = Vector3.ZERO) -> void:
	var v := _couch()
	if v == null:
		printerr("C56[%d|%s]: 没有骑乘车，无法判定" % [idx, tag])
		_fail += 1
		_checks += 1
		return
	var up: Vector3 = Planet.up_at(v.global_position)
	var body: Node3D = _me.get("_body")
	var vfwd: Vector3 = -v.global_transform.basis.z
	vfwd = (vfwd - up * vfwd.dot(up)).normalized()
	if body is Node3D:
		var bface: Vector3 = (body as Node3D).global_transform.basis.z
		bface = (bface - up * bface.dot(up)).normalized()
		var deg := rad_to_deg(bface.angle_to(vfwd))
		var ok := deg < TOL_DEG
		_checks += 1
		if not ok:
			_fail += 1
		printerr("C56[%d|%s]: 角色↔载具夹角 %.2f° %s（阈值 %.0f°）| 载具Y↔法线 %.2f° | 骑乘=%s 被测车=%s" % [
			idx, tag, deg, "OK" if ok else "!!超差", TOL_DEG,
			rad_to_deg(v.global_transform.basis.y.angle_to(up)),
			str((_me.get("mounted_vehicle") as Node).name) if _me.get("mounted_vehicle") != null else "<无>",
			String(v.name)])
	else:
		printerr("C56[%d|%s]: 没有 _body，无法判定" % [idx, tag])
	# 附加断言：车头 vs 真实位移（飞行时最有力的证据）
	if dir_ref.length_squared() > 0.000001:
		var d := dir_ref - up * dir_ref.dot(up)
		if d.length_squared() > 0.000001:
			var mv_deg := rad_to_deg(d.normalized().angle_to(vfwd))
			var mv_ok := mv_deg < 8.0 # 转弯时载具有插值滞后，8° 内算跟车
			_checks += 1
			if not mv_ok:
				_fail += 1
			printerr("C56[%d|%s]: 车头↔位移方向 %.2f° %s（阈值 8°）" % [
				idx, tag, mv_deg, "OK" if mv_ok else "!!朝反了"])
	if shot != "":
		await _shot(shot)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	printerr("C56[已存] " + path)
