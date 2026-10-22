extends Node3D

## M50 重影取证：只用玩家自己的相机（不新建、不摆机位），按真键连拍。
##
## 之前 m48 探针自己造相机拍"验尸照"，玩家实际看到的画面一次都没拍到 —— 用户 2026-10-22
## 第 N 次报"移动/飞行有重影"，这次改成逐帧录、不做任何视觉干预。
##
## 同时每帧清点该玩家实体下**所有可见 MeshInstance3D**：
##   名称 + 世界 AABB 中心 + 尺寸 + 是否 Skinned
## 若出现两组位置相近、尺寸相近的网格 → 就是模型级重影，不再是猜。
##
## 用法（必须窗口模式，headless 出不了图）：
##   godot --path . res://tools/m50_ghost_probe.tscn

const BASE_DIR := "res://screenshots/m50/"
const WALK_SHOTS := 8
const FLY_SHOTS := 6
const FRAMES_PER_SHOT := 4

var _level: Node3D
var _me: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE_DIR))
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("G50: headless 出不了图，必须窗口模式")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "重影", "blue")
	await get_tree().create_timer(6.0).timeout
	var cs = _level.get("class_select_ui")
	if cs != null and cs.has_method("close_panel"):
		cs.close_panel()
	await get_tree().create_timer(0.6).timeout

	_me = _find_player()
	if _me == null:
		printerr("G50: !! 找不到本地玩家")
		get_tree().quit(0)
		return

	var cam := get_viewport().get_camera_3d()
	printerr("G50: 相机=%s 玩家=%s 屏幕=%s" % [
		str(cam.name) if cam else "<null>", str(_me.name), str(get_viewport().get_visible_rect().size)])
	printerr("G50: 相机父链=%s" % _parent_chain(cam))

	_dump_hpbar()
	_dump_meshes("idle")
	# 对照帧：单独关掉玩家血条
	var _hb := _me.get_node_or_null("HealthBar") as Node3D
	if _hb != null:
		_hb.visible = false
		await _shot("n00_nohpbar.png")
		_hb.visible = true
	await _shot("w00_idle.png")

	# ---- 走路连拍 ----
	printerr("G50: === 按 W 走路连拍 ===")
	Input.action_press("move_forward")
	for i in WALK_SHOTS:
		for f in FRAMES_PER_SHOT:
			await get_tree().physics_frame
		_dump_meshes("walk%d" % i)
		await _shot("w%02d_walk.png" % (i + 1))
	Input.action_release("move_forward")
	await get_tree().create_timer(0.4).timeout

	# ---- 飞行连拍（召唤沙发 + 上座 + 前进）----
	printerr("G50: === 召唤坐骑，飞行连拍 ===")
	if _me.has_method("_summon_mount"):
		_me.call("_summon_mount", true, -1)
	await get_tree().create_timer(3.0).timeout
	printerr("G50: 骑乘状态 mounted=%s" % str(_me.get("mounted_vehicle")))
	_dump_meshes("mounted")
	await _shot("f00_mounted.png")
	Input.action_press("move_forward")
	for i in FLY_SHOTS:
		for f in FRAMES_PER_SHOT:
			await get_tree().physics_frame
		_dump_meshes("fly%d" % i)
		await _shot("f%02d_fly.png" % (i + 1))
	Input.action_release("move_forward")

	print("G50: 结束，截图在 " + BASE_DIR)
	get_tree().quit(0)


func _find_player() -> Node3D:
	var pc := _level.get_node_or_null("PlayersContainer")
	if pc == null:
		return null
	return pc.get_node_or_null("1") as Node3D


func _parent_chain(n: Node) -> String:
	var parts: Array[String] = []
	var cur := n
	while cur != null:
		parts.append(String(cur.name))
		cur = cur.get_parent()
	return "/".join(parts)


## 清点玩家实体下所有**可见**网格：位置/尺寸/是否蒙皮。
## 重影的硬判据是「两组同名或同尺寸网格中心相距 < 1m」，不是肉眼看。
func _dump_meshes(tag: String) -> void:
	if _me == null:
		return
	var rows: Array[String] = []
	var total := 0
	var stack: Array[Node] = [_me]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi != null and mi.is_visible_in_tree() and mi.mesh != null:
			total += 1
			var ab: AABB = mi.mesh.get_aabb()
			var c: Vector3 = mi.global_transform * ab.get_center()
			var s: Vector3 = ab.size * mi.global_transform.basis.get_scale()
			var skinned := mi.skin != null
			rows.append("%s|%s|%s|%s" % [
				String(mi.name),
				"(%.2f,%.2f,%.2f)" % [c.x, c.y, c.z],
				"(%.2f,%.2f,%.2f)" % [s.x, s.y, s.z],
				"skin" if skinned else "static"])
		for ch in n.get_children():
			stack.append(ch)
	printerr("G50[%s]: 可见网格 %d 个" % [tag, total])
	for r in rows:
		printerr("G50[%s]:   %s" % [tag, r])


func _dump_hpbar() -> void:
	var hb := _me.get_node_or_null("HealthBar")
	if hb == null:
		printerr("G50[血条]: 没有 HealthBar")
		return
	var sp := hb.get_node_or_null("Sprite3D") as Sprite3D
	printerr("G50[血条]: pos=" + str((hb as Node3D).position) + " scale=" + str((hb as Node3D).scale))
	if sp == null:
		return
	var ts := sp.texture.get_size() if sp.texture != null else Vector2.ZERO
	printerr("G50[血条]: pixel_size=" + str(sp.pixel_size) + " tex=" + str(ts) + " axis=" + str(sp.axis) + " billboard=" + str(sp.billboard) + " aabb=" + str(sp.get_aabb()))


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(BASE_DIR + fname)
	if err != OK:
		printerr("G50: !! 存图失败 " + fname + " err=" + str(err))
