extends Node3D

## M48 身体视觉/朝向验收探针（支持单人 / 双端）
##
## 背景：用户 2026-10-22 连续两次退单——
##   "人走路是重影的，方向也不对！你的检查方式不对，优化你自己的检查方式"。
##
## 以前的检查错在哪：
##   · 只量"离地多少米"（_report_ground），量不出"屏幕上是不是两个模型叠着"
##   · 只检查本地玩家，而用户看的是**双端**画面里的远端玩家
##
## 本探针三条判据，全部输出可核对数值：
##   1) 重影：枚举**每个**玩家子树里 is_visible_in_tree() 的 MeshInstance3D，
##      按顶层祖先分组。分组数 > 1 = 机器人和 KayKit 同时可见 = 真重影。
##      另报"玩家间最近距离"，判断是不是两个人叠在一起。
##   2) 方向：每个玩家打印 根 yaw / body 世界 yaw / 速度世界 yaw / 相机 yaw。
##      模型正面 = 局部 +Z → body 世界 yaw 必须 ≈ atan2(切平面速度)。
##      远端玩家速度不同步时 |vh|≈0，此时只报 body yaw 的**两轮变化量**：
##      变化量为 0 = 朝向从未同步 = 铁证。
##   3) 人眼：自建第三人称相机（不用玩家 spring arm，避免被每帧覆盖），
##      拍 Idle 一张 + 走路中连拍。
##
## 用法（必须窗口模式，headless 出不了图）：
##   单人：godot --path . res://tools/m48_body_probe.tscn -- --tag solo
##   双端：进程A  godot --path . res://tools/m48_body_probe.tscn -- --tag host --auto host
##         进程B  godot --path . res://tools/m48_body_probe.tscn -- --tag join --auto join
## 产出：screenshots/m48/<tag>_a_idle.png / <tag>_b_walk0..2.png

const BASE_DIR := "res://screenshots/m48/"
const WALK_FRAMES := 22

var _tag := ""
var _auto := ""
var _level: Node3D
var _me: Node3D
var _cam: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--tag" and i + 1 < args.size():
			_tag = args[i + 1] + "_"
		if args[i] == "--auto" and i + 1 < args.size():
			_auto = args[i + 1]
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("M48: headless 出不了图，必须窗口模式")
		get_tree().quit(0)
		return
	if _auto == "":
		_level.call("_on_host_pressed", "验收", "blue")
	else:
		printerr("M48: 走 level 自己的 --auto %s 联机" % _auto)

	_me = await _wait_local_player(20.0)
	if _me == null:
		printerr("M48: 等不到本地玩家")
		get_tree().quit(0)
		return
	# 双端验收的前提是"另一端真的在画面里"：host 必须等 join 连上再开拍，
	# 否则会拍到一场独角戏，把"远端朝向不同步"这个核心问题漏掉。
	if _auto == "host":
		await _wait_remote_player(30.0)
	await get_tree().create_timer(3.0).timeout # 等远端玩家/同步稳定
	_hide_hud()

	print_rich_lines("=== 第一轮：全员外观 + 朝向 ===")
	_dump_all("R1")
	_make_cam()
	await _tick(20)
	await _save("a_idle.png")

	printerr("M48: === 按 W 前进，连拍 ===")
	Input.action_press("move_forward")
	for k in 3:
		await _tick(WALK_FRAMES)
		_dump_all("W%d" % k)
		await _save("b_walk%d.png" % k)
	Input.action_release("move_forward")

	# 【关键一步】只按 W 走路验不出朝向同步：出生朝向恰好就等于前进方向，
	# body.rotation.y 从头到尾都是 0，同步坏了也"看起来对"。
	# 必须制造一次 90° 转向，让远端玩家的 body 朝向来一次可观测的跳变。
	printerr("M48: === 按 A 左移 90° 转向：验远端朝向是否跟着转 ===")
	Input.action_press("move_left")
	for k in 2:
		await _tick(WALK_FRAMES)
		_dump_all("A%d" % k)
		await _save("c_left%d.png" % k)
	Input.action_release("move_left")

	# 双人合影：把相机拉到两人连线的侧上方，一张图里同时看到两个角色。
	# 单看自己视角永远看不出"另一个人到底几层、朝向对不对"。
	await _photo_duo("d_duo.png")

	print_rich_lines("=== 第二轮：松手后再看一次（远端朝向是否变化）===")
	await _tick(20)
	_dump_all("R2")
	printerr("M48: 结束")
	get_tree().quit(0)


func print_rich_lines(s: String) -> void:
	printerr("M48: %s" % s)


func _tick(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		_follow_cam()


func _wait_remote_player(timeout: float) -> void:
	var t := 0.0
	while t < timeout:
		for c in _players():
			var n := c as Node
			if n.is_multiplayer_authority():
				continue # 自己
			# bot 的 authority 是 900x，也"不是本地"，但它是服务器本地生成的，
			# 不算真远端 —— 必须排除，否则单人也能骗过这个等待。
			if PeerQuery.is_bot_peer(n.get_multiplayer_authority()):
				continue
			printerr("M48: 真人远端玩家 %s 已就位（等了 %.1fs）" % [n.name, t])
			return
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	printerr("M48: !! 等不到真人远端玩家（%.1fs），本次只能验单人" % timeout)


func _wait_local_player(timeout: float) -> Node3D:
	var t := 0.0
	while t < timeout:
		var pc := _level.get_node_or_null("PlayersContainer")
		if pc != null:
			for c in pc.get_children():
				var n3 := c as Node3D
				if n3 != null and n3.is_multiplayer_authority():
					return n3
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	return null


func _hide_hud() -> void:
	for cl in _level.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for c in _level.find_children("*", "Control", true, false):
		(c as Control).visible = false


func _players() -> Array:
	var out := []
	var pc := _level.get_node_or_null("PlayersContainer")
	if pc == null:
		return out
	for c in pc.get_children():
		if c is Node3D:
			out.append(c)
	return out


## 全员 dump：重影 + 叠人 + 朝向
func _dump_all(round_tag: String) -> void:
	var ps := _players()
	printerr("M48: [%s] 玩家数=%d 本地id=%d" % [round_tag, ps.size(), multiplayer.get_unique_id()])
	for p in ps:
		var n3 := p as Node3D
		var pos := n3.global_position
		var r := pos.length()
		var dir := pos.normalized() if r > 1.0 else Vector3.UP
		var h := Planet.mesh_height(dir)
		printerr("M48:   %s auth=%d 本地=%s pos=%s r=%.1f 地表差=%+.2fm" % [
			n3.name, n3.get_multiplayer_authority(), str(n3.is_multiplayer_authority()),
			str(pos.snapped(Vector3.ONE * 0.1)), r, r - (Planet.RADIUS + h)])
		_dump_visuals(n3)
		_dump_body_flags(n3)
		_report_orient(n3, round_tag)
	# 两两最近距离：判断是否叠在一起
	for i in ps.size():
		for j in range(i + 1, ps.size()):
			var a := (ps[i] as Node3D).global_position
			var b := (ps[j] as Node3D).global_position
			printerr("M48:   距离 %s <-> %s = %.2fm" % [
				(ps[i] as Node).name, (ps[j] as Node).name, a.distance_to(b)])


func _dump_visuals(p: Node3D) -> void:
	var groups := {}
	var total := 0
	var stack: Array[Node] = [p]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).is_visible_in_tree():
			total += 1
			# 分组键必须精确到"哪一套模型"：两套视觉都挂在 GodotRobot3D 下
			# （RobotArmature = 机器人 / InfantryVisual = KayKit 步兵），
			# 只按顶层祖先分组会把"两套都可见"误判成 1 组。
			var key := "其他"
			var cur: Node = n
			while cur != null and cur != p:
				if cur.name == "RobotArmature" or cur.name == "InfantryVisual":
					key = String(cur.name)
					break
				cur = cur.get_parent()
			groups[key] = int(groups.get(key, 0)) + 1
		for c in n.get_children():
			stack.append(c)
	var verdict := "正常" if groups.size() <= 1 else "!!重影"
	printerr("VIS[%s]: mesh=%d 分组=%d %s 明细=%s" % [
		p.name, total, groups.size(), verdict, str(groups)])
	if groups.size() > 1:
		printerr("VIS[%s]: !! 两套模型同时可见 = %s" % [p.name, str(groups.keys())])


func _dump_body_flags(p: Node3D) -> void:
	var b := p.get_node_or_null("GodotRobot3D") as Node3D
	if b == null:
		printerr("BODY[%s]: 找不到 GodotRobot3D" % p.name)
		return
	var alt := b.get_node_or_null("InfantryVisual") as Node3D
	var arm := b.get_node_or_null("RobotArmature") as Node3D
	printerr("BODY[%s]: use_alt=%s | alt_vis=%s alt_rot_y=%.3f | arm_vis=%s" % [
		p.name, str(b.get("use_alt_body")),
		("null" if alt == null else str(alt.visible)),
		(0.0 if alt == null else alt.rotation.y),
		("null" if arm == null else str(arm.visible))])


func _report_orient(p: Node3D, round_tag: String) -> void:
	var b := p.get_node_or_null("GodotRobot3D") as Node3D
	if b == null:
		return
	var pos := p.global_position
	if not pos.is_finite() or pos.length() < 1.0:
		return
	var up := Planet.up_at(pos)
	var v: Vector3 = p.velocity
	var vh := v - up * v.dot(up)
	var body_yaw := _world_yaw(b.global_transform.basis.z, up)
	var v_yaw := _world_yaw(vh, up)
	var diff_txt := "无速度"
	if vh.length() > 0.5:
		diff_txt = "%+.1f°" % rad_to_deg(angle_difference(v_yaw, body_yaw))
	printerr("ORI[%s|%s]: |vh|=%.3f v=%s up=%s v_yaw=%+.1f° bodyYaw=%+.1f° 差=%s | 根y=%.3f bodyY=%.3f" % [
		p.name, round_tag, vh.length(),
		str(v.snapped(Vector3.ONE * 0.01)), str(up.snapped(Vector3.ONE * 0.01)),
		rad_to_deg(v_yaw), rad_to_deg(body_yaw),
		diff_txt, p.rotation.y, b.rotation.y])


func _world_yaw(dir: Vector3, up: Vector3) -> float:
	var d := dir - up * dir.dot(up)
	if d.length_squared() < 1e-8:
		return 0.0
	d = d.normalized()
	var e1 := up.cross(Vector3.FORWARD)
	if e1.length_squared() < 1e-4:
		e1 = up.cross(Vector3.RIGHT)
	e1 = e1.normalized()
	var e2 := up.cross(e1).normalized()
	return atan2(d.dot(e2), d.dot(e1))


func _make_cam() -> void:
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.near = 0.05
	_level.add_child(_cam)
	_cam.current = true
	_follow_cam()


func _follow_cam() -> void:
	if _cam == null or _me == null:
		return
	var pos := _me.global_position
	if not pos.is_finite():
		return
	var up := Planet.up_at(pos)
	# 模型正面 = 局部 +Z（见 3d_godot_robot.gd 的 apply_rotation 语义），
	# 所以"背后" = -basis.z。写成 +basis.z 会把机位放到角色正前方，拍出正脸。
	var back: Vector3 = -_me.global_transform.basis.z
	back = back - up * back.dot(up)
	if back.length_squared() < 1e-6:
		back = up.cross(Vector3.RIGHT)
	back = back.normalized()
	_cam.global_position = pos + up * 1.35 + back * 4.6
	_cam.look_at(pos + up * 0.85, up)


func _find_remote_human() -> Node3D:
	for c in _players():
		var n := c as Node3D
		if n == null or n.is_multiplayer_authority():
			continue
		if PeerQuery.is_bot_peer(n.get_multiplayer_authority()):
			continue
		return n
	return null


## 双人合影：相机拉到两人连线的侧上方，一张图里同时看到两个角色。
## 只看自己视角永远回答不了"另一个人到底几层、朝向对不对"。
func _photo_duo(fname: String) -> void:
	var remote := _find_remote_human()
	if remote == null or _cam == null:
		printerr("M48: 没有真人远端，跳过合影")
		return
	var a := _me.global_position
	var b := remote.global_position
	var mid := (a + b) * 0.5
	var up := Planet.up_at(mid)
	var sep := b - a
	sep = sep - up * sep.dot(up)
	if sep.length_squared() < 1e-4:
		printerr("M48: 两人重合，跳过合影")
		return
	sep = sep.normalized()
	var side := up.cross(sep).normalized()
	var dist: float = maxf(7.0, a.distance_to(b) * 0.9)
	_cam.global_position = mid + side * dist + up * 2.4
	_cam.look_at(mid, up)
	await get_tree().process_frame
	printerr("M48: 合影间距=%.2fm 机位距中点=%.1fm" % [a.distance_to(b), dist])
	await _save(fname)


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("M48: img null ", fname)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE_DIR))
	var path := ProjectSettings.globalize_path(BASE_DIR + _tag + fname)
	var err := img.save_png(path)
	printerr("M48: 已存 %s (err=%d)" % [_tag + fname, err])
