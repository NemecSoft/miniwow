extends Node3D

## M41 小精灵粒子特写探针：近距离分别拍默认星尘（白蓝）与火焰主题（暖橙）。
## 用法：godot --path <项目> res://tools/m41_partner_shot.tscn

const OUT := "res://screenshots/m41/partner/"

var _level: Node3D
var _cam: Camera3D
var _partner: Node3D = null


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "特写", "blue")
	await get_tree().create_timer(3.0).timeout
	_hide_all_ui()
	var pc := _level.get_node_or_null("PlayersContainer")
	if pc != null:
		for c in pc.get_children():
			c.process_mode = Node.PROCESS_MODE_DISABLED
			# 玩家会挡在云朵前面（伙伴悬在玩家正上方），拍特写必须隐身
			if c is Node3D:
				(c as Node3D).visible = false
	_partner = _level.get_node_or_null("Partner") as Node3D
	if _partner == null:
		printerr("M41P: ✗ 找不到 Partner")
		get_tree().quit(0)
		return
	printerr("M41P: partner=", str(_partner.get_path()), " pos=", str(_partner.global_position))
	_cam = Camera3D.new()
	_cam.name = "PartnerCam"
	add_child(_cam)
	_cam.make_current()
	await get_tree().create_timer(1.5).timeout
	var halo := _partner.get_node_or_null("AuraHalo") as MeshInstance3D
	# 云朵几何中心比节点原点高约 0.80 局部（×0.5 缩放 = 0.40 世界），对准它才拍得正
	var ctr := Vector3(0, 0.40, 0)
	var near := Vector3(1.20, 0.30, 1.55)
	var look := ctr
	# A/B：先关光晕，只留粒子
	if halo != null:
		halo.visible = false
	await _shot(near, look, "m41p_a_nohalo.png")
	# 再开光晕
	if halo != null:
		halo.visible = true
	await get_tree().process_frame
	await _shot(near, look, "m41p_b_halo.png")
	# 火焰主题
	if _partner.has_method("set_aura_theme"):
		_partner.call("set_aura_theme", Color(1.0, 0.52, 0.16))
	printerr("M41P: 已切火焰主题")
	await get_tree().create_timer(1.6).timeout
	await _shot(near, look, "m41p_c_fire.png")
	# 恢复星尘主题，再拍一张接近真实第三人称距离的观感图
	if _partner.has_method("set_aura_theme"):
		_partner.call("set_aura_theme", Color(0.72, 0.86, 1.0))
	await get_tree().create_timer(1.2).timeout
	await _shot(Vector3(2.8, 1.2, 2.6), Vector3(0, 0.1, 0), "m41p_d_far.png")
	printerr("M41P: 结束")
	get_tree().quit(0)


func _hide_all_ui() -> void:
	_level.set("class_select_visible", false)
	for cl in _level.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for c in _level.find_children("*", "Control", true, false):
		(c as Control).visible = false


func _shot(offset: Vector3, look_offset: Vector3, fname: String) -> void:
	if _partner == null:
		return
	var p := _partner.global_position
	_cam.global_position = p + offset
	_cam.look_at(p + look_offset)
	_cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	_cam.make_current()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("M41P: img null ", fname)
		return
	var path := ProjectSettings.globalize_path(OUT + fname)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("M41P: 已存 ", fname)
