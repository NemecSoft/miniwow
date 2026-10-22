extends Node3D

## M42 坐骑朝向探针：上坐骑瞬间"莫名转向"的量化定位。
## 记录三个量在上座前后的变化（度）：
##   ① 玩家根节点 rotation.y（相机弹簧臂的父节点，直接决定镜头世界朝向）
##   ② 身体节点世界朝向（玩家实际看到的角色朝向）
##   ③ 相机世界朝向（玩家感知到的"画面转了没有"）
## 用法：godot --path <项目> res://tools/mount_yaw_probe.tscn

const OUT := "res://screenshots/m42/mount/"

var _level: Node3D
var _player: Node3D


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "探", "blue")
	await get_tree().create_timer(5.0).timeout
	for cl in _level.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for c in _level.find_children("*", "Control", true, false):
		(c as Control).visible = false
	_player = _find_player()
	if _player == null:
		printerr("MTP: 找不到玩家")
		get_tree().quit(0)
		return
	await get_tree().create_timer(1.0).timeout

	# ① 出生默认状态
	_snap("A_出生")

	# ② 模拟"玩家右键转身 100° 后停下"：根节点跟随相机转身，身体转向前进方向
	_player.rotation.y += deg_to_rad(100.0)
	var body: Node3D = _player.get("_body")
	if body != null and body.has_method("snap_rotation_to"):
		var a := deg_to_rad(35.0)
		body.call("snap_rotation_to", Vector3(sin(a), 0.0, cos(a)))
	await get_tree().create_timer(0.3).timeout
	_snap("B_转身后")
	await _save("m1_before_mount.png")

	# ③ 上坐骑（等价于按 X）
	_player.call("_summon_mount", true)
	await get_tree().create_timer(1.4).timeout
	_snap("C_上坐骑后")
	await _save("m2_after_mount.png")

	# ④ 再等 1 秒看是否持续漂移
	await get_tree().create_timer(1.0).timeout
	_snap("D_上座1秒后")

	# ⑤ 模拟按住 W 飞行 1.6 秒：身体应当跟着车头转向（不能倒着坐飞）
	Input.action_press("move_forward")
	await get_tree().create_timer(1.6).timeout
	_snap("E_前进中")
	await _save("m3_flying.png")
	Input.action_release("move_forward")
	await get_tree().create_timer(1.0).timeout
	_snap("F_松开后")

	# ⑥ 下座再上座（第二次召唤走"复用载具"路径），确认依旧零跳变
	_player.call("_recall_mount")
	await get_tree().create_timer(1.2).timeout
	_snap("G_下座后")
	var yaw_g := rad_to_deg(_player.rotation.y)
	_player.call("_summon_mount", true)
	await get_tree().create_timer(1.4).timeout
	_snap("H_二次上座")
	printerr("MTP: 二次上座根节点变化=", snappedf(rad_to_deg(_player.rotation.y) - yaw_g, 0.1), " 度")

	printerr("MTP: 结束")
	get_tree().quit(0)


func _find_player() -> Node3D:
	var pc := _level.get_node_or_null("PlayersContainer")
	if pc == null:
		return null
	for c in pc.get_children():
		if c is Node3D:
			return c as Node3D
	return null


func _yaw(v: Vector3) -> float:
	return rad_to_deg(atan2(v.x, v.z))


func _snap(tag: String) -> void:
	var body: Node3D = _player.get("_body")
	var cam := get_viewport().get_camera_3d()
	var root_d := rad_to_deg(_player.rotation.y)
	var body_d := NAN
	if body != null:
		body_d = _yaw(body.global_transform.basis.z)
	var cam_d := NAN
	if cam != null:
		cam_d = _yaw(-cam.global_transform.basis.z)
	printerr("MTP[", tag, "] 根=", snappedf(root_d, 0.1),
		" 身体=", snappedf(body_d, 0.1),
		" 相机=", snappedf(cam_d, 0.1))


func _save(fname: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("MTP: img null ", fname)
		return
	var path := ProjectSettings.globalize_path(OUT + fname)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("MTP: 已存 ", fname)
