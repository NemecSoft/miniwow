extends Node3D

## M55：悬浮沙发朝向取证。
##
## 之前所有"朝向对不对"的判断都是我在代码里读公式，从没量过**模型实际长什么样**：
##   · 沙发模型的长轴（座面左右方向）在本地是 X 还是 Z？
##   · 靠背（最高的那块）在座位的哪一侧？
##   · 沙发的 -Z（代码认定的"前方"）与玩家身体正面差多少度？
##
## 本工具做三件事：
##   1. 召唤沙发并上座（走真实的 _summon_mount，不模拟）；
##   2. 打印 CouchModel 内部每个网格在**沙发局部空间**的 AABB —— 长轴/靠背位置一目了然；
##   3. 用四个固定机位各拍一张（俯视 / 正后 / 正侧 / 玩家视角），带坐标轴标记。

const OUT_DIR := "res://screenshots/m55"

var _level: Node
var _me: Node3D
var _couch: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if DisplayServer.get_name() == "headless":
		printerr("C55: headless 出不了图，必须窗口模式")
		get_tree().quit(0)
		return
	# 本探针是独立场景，关卡要自己加载（不能用 current_scene）
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	_level.call("_on_host_pressed", "沙发朝向", "blue")
	await get_tree().create_timer(6.0).timeout
	var cs = _level.get("class_select_ui")
	if cs != null and cs.has_method("close_panel"):
		cs.close_panel()
	await get_tree().create_timer(0.6).timeout
	_me = await _wait_local_player(30.0)
	# 等真正站稳再召唤：刚出生时位置还在被传送，召唤锚点会落到旧位置（实测差 230m）
	await _wait_grounded(_me, 15.0)
	if _me == null:
		printerr("C55: 等不到本地玩家")
		get_tree().quit(0)
		return
	await get_tree().create_timer(2.5).timeout
	_hide_hud()

	printerr("C55: ==== 召唤沙发 ====")
	_me.call("_summon_mount", true)
	_couch = await _wait_couch(8.0)
	if _couch == null:
		printerr("C55: !! 沙发没生成")
		get_tree().quit(0)
		return
	await get_tree().create_timer(1.5).timeout

	_report()
	await _shoot_all()
	printerr("C55: 结束")
	get_tree().quit(0)


func _hide_hud() -> void:
	var hud := _level.get_node_or_null("UI/HUD")
	if hud != null:
		(hud as CanvasItem).visible = false


func _players() -> Array:
	var pc := _level.get_node_or_null("PlayersContainer")
	return pc.get_children() if pc != null else []


func _wait_grounded(p: Node3D, timeout: float) -> void:
	var t := 0.0
	while t < timeout:
		var pos: Vector3 = p.global_position
		var up: Vector3 = Planet.up_at(pos)
		var gap: float = pos.length() - (Planet.RADIUS + Planet.mesh_height(up))
		if absf(gap) < 2.0:
			printerr("C55: 玩家已站稳，离地 %+.2fm（等了 %.1fs）" % [gap, t])
			return
		await get_tree().create_timer(0.3).timeout
		t += 0.3
	printerr("C55: !! 玩家 %.1fs 内没站稳" % timeout)


func _wait_local_player(timeout: float) -> Node3D:
	var t := 0.0
	while t < timeout:
		for c in _players():
			if c is Node3D and (c as Node).is_multiplayer_authority():
				return c as Node3D
		await get_tree().create_timer(0.4).timeout
		t += 0.4
	return null


func _wait_couch(timeout: float) -> Node3D:
	var t := 0.0
	while t < timeout:
		var v := _level.get_node_or_null("Environment/Vehicles")
		if v != null:
			for c in v.get_children():
				if c is Node3D and String(c.name).begins_with("couch_"):
					return c as Node3D
		await get_tree().create_timer(0.3).timeout
		t += 0.3
	return null


## 打印沙发局部的几何事实：长轴、靠背位置、各轴世界方向。
func _report() -> void:
	var up: Vector3 = Planet.up_at(_couch.global_position)
	var cb: Basis = _couch.global_transform.basis
	var fwd: Vector3 = -cb.z # 代码认定的沙发"前方"（-Z）
	fwd = (fwd - up * fwd.dot(up)).normalized()

	printerr("C55[沙发]: 位置=%s 离地=%.2fm" % [
		str(_couch.global_position.snapped(Vector3(0.01, 0.01, 0.01))),
		_couch.global_position.length() - (Planet.RADIUS + Planet.mesh_height(up))])
	printerr("C55[沙发]: basis.Y 与法线夹角 = %.1f°（应 0°）" % rad_to_deg(cb.y.angle_to(up)))
	printerr("C55[沙发]: -Z(前) = %s" % str(fwd.snapped(Vector3(0.001, 0.001, 0.001))))

	# 玩家身体正面：3d_godot_robot 的模型正面是 +Z
	var body: Node3D = _me.get("_body")
	if body is Node3D:
		var bz: Vector3 = (body as Node3D).global_transform.basis.z
		bz = (bz - up * bz.dot(up)).normalized()
		printerr("C55[玩家]: 身体正面(+Z) = %s | 与沙发前方夹角 = %.1f°" % [
			str(bz.snapped(Vector3(0.001, 0.001, 0.001))),
			rad_to_deg(bz.angle_to(fwd))])
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var cz: Vector3 = -cam.global_transform.basis.z
			cz = (cz - up * cz.dot(up)).normalized()
			printerr("C55[相机]: 视线水平分量与沙发前方夹角 = %.1f°" % rad_to_deg(cz.angle_to(fwd)))

	# 每个网格在沙发局部空间的 AABB（关键：长轴在哪、靠背在哪一侧）
	var inv: Transform3D = _couch.global_transform.affine_inverse()
	var total := AABB()
	var first := true
	var rows: Array[String] = []
	for n in _couch.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var rel: Transform3D = inv * mi.global_transform
		var ab: AABB = mi.mesh.get_aabb()
		# 八个角变换到沙发空间求外接盒（含旋转）
		var box := AABB()
		var firstc := true
		for i in 8:
			var c: Vector3 = ab.get_endpoint(i)
			var w: Vector3 = rel * c
			if firstc:
				box = AABB(w, Vector3.ZERO)
				firstc = false
			else:
				box = box.expand(w)
		if first:
			total = box
			first = false
		else:
			total = total.merge(box)
		rows.append("%s size=(%.2f,%.2f,%.2f) y=[%.2f,%.2f] z=[%.2f,%.2f]" % [
			String(mi.name), box.size.x, box.size.y, box.size.z,
			box.position.y, box.end.y, box.position.z, box.end.z])
	for r in rows:
		printerr("C55[网格] " + r)
	if not first:
		printerr("C55[总计] 沙发局部 AABB: size=(%.2f, %.2f, %.2f)  长轴=%s" % [
			total.size.x, total.size.y, total.size.z,
			"X(左右·正确)" if total.size.x >= total.size.z else "Z(前后·模型躺错了方向)"])

	# 座位 0 在沙发局部的位置：靠背应在其 +Z 侧（座位后方）
	var seat0: Vector3 = Vector3.ZERO
	if _couch.has_method("get_seat_offset"):
		seat0 = _couch.get_seat_offset(0)
	printerr("C55[座位0] 局部 = %s（局部 +Z 是沙发后方）" % str(seat0))
	_analyze_backrest(inv)


## 沙发"靠背"在局部哪一侧？取顶点数据直接统计：z 正向 / 负向各侧的最高点。
## 靠背是整张沙发最高的部分，它所在的一侧就是**坐的人面朝的反方向**（背后）。
## 这是几何事实，不依赖任何"我觉得看起来像"。
func _analyze_backrest(inv: Transform3D) -> void:
	var hi_pos_z := -INF
	var hi_neg_z := -INF
	var cnt_pos := 0
	var cnt_neg := 0
	for n in _couch.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var mesh := mi.mesh
		var rel: Transform3D = inv * mi.global_transform
		for s in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(s)
			if arr.size() == 0:
				continue
			var verts = arr[Mesh.ARRAY_VERTEX]
			if verts == null:
				continue
			for v in verts:
				var w: Vector3 = rel * (v as Vector3)
				if absf(w.z) < 0.05:
					continue
				if w.z > 0.0:
					cnt_pos += 1
					hi_pos_z = maxf(hi_pos_z, w.y)
				else:
					cnt_neg += 1
					hi_neg_z = maxf(hi_neg_z, w.y)
	if hi_pos_z == -INF or hi_neg_z == -INF:
		printerr("C55[靠背]: 顶点不足，无法判定")
		return
	var back_side := "+Z" if hi_pos_z > hi_neg_z else "-Z"
	printerr("C55[靠背]: +Z 侧最高 y=%.2f（%d 顶点）| -Z 侧最高 y=%.2f（%d 顶点）→ 靠背在 %s 侧" % [
		hi_pos_z, cnt_pos, hi_neg_z, cnt_neg, back_side])
	printerr("C55[靠背]: 结论 —— 沙发模型的\"坐面朝外\"方向 = %s（与代码认定的前方 -Z %s）" % [
		"-Z" if back_side == "+Z" else "+Z",
		"一致" if back_side == "+Z" else "相反(差180°)"])


func _shoot_all() -> void:
	var up: Vector3 = Planet.up_at(_couch.global_position)
	var cb: Basis = _couch.global_transform.basis
	var fwd: Vector3 = -cb.z
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var right: Vector3 = fwd.cross(up).normalized()
	var c := _couch.global_position

	await _shoot(c + up * 11.0, c, fwd, "a_top")            # 俯视，画面上方=沙发前方
	await _shoot(c - fwd * 9.0 + up * 3.2, c, up, "b_back") # 正后方看
	await _shoot(c + right * 9.0 + up * 3.2, c, up, "c_side")
	await _shoot(c + right * 9.0, c, fwd, "d_top_side")     # 斜侧俯视


## 接管**玩家自己的相机**：新建的 Camera3D 会被玩家的相机每帧抢回 current，
## 之前拍的俯视图其实还是玩家视角（离沙发 230m，只有一个白点）。
## 这里直接改玩家相机，并 top_level 脱离 SpringArm，避免被覆盖。
func _shoot(from: Vector3, to: Vector3, screen_up: Vector3, tag: String) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		printerr("C55[拍摄]: 没有相机")
		return
	var f := (to - from).normalized()
	var r := f.cross(screen_up)
	if r.length_squared() < 0.0001:
		r = f.cross(Vector3.RIGHT)
	r = r.normalized()
	var u := r.cross(f).normalized()
	cam.top_level = true
	cam.global_transform = Transform3D(Basis(r, u, -f), from)
	cam.fov = 60.0
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := "%s/%s.png" % [OUT_DIR, tag]
	img.save_png(ProjectSettings.globalize_path(p))
	printerr("C55[已存] " + p)
