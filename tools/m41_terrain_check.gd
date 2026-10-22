extends Node3D

## M41 地形修复验证（精简版）：进世界 → 隐藏全部 UI → 俯视地面截图 + 像素读回。
## 用法（窗口模式）：godot --path <项目> res://tools/m41_terrain_check.tscn
## 关键：职业选择面板是 Control（会在 host 后自动弹出），必须统一隐藏，否则
## 采样点全落在棕色木板上，会误判成"地面修好了"。

const OUT := "res://screenshots/m41/"

var _level: Node3D
var _cam: Camera3D


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("M41: headless dummy 后端，退出")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "验证", "blue")
	await get_tree().create_timer(3.0).timeout
	_hide_all_ui()
	var pc := _level.get_node_or_null("PlayersContainer")
	if pc != null:
		for c in pc.get_children():
			c.process_mode = Node.PROCESS_MODE_DISABLED
	_cam = Camera3D.new()
	_cam.name = "M41Cam"
	add_child(_cam)
	_cam.make_current()
	_cam.global_position = Vector3(0, 6, -30)
	_cam.look_at(Vector3(0, 0, -75))
	await get_tree().create_timer(4.5).timeout
	_hide_all_ui()
	_dump_state()
	await _shot("m41_fix_check.png")
	get_tree().quit(0)


func _hide_all_ui() -> void:
	_level.set("class_select_visible", false)
	for cl in _level.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for c in _level.find_children("*", "Control", true, false):
		(c as Control).visible = false


func _dump_state() -> void:
	var t: Terrain3D = null
	for c in _level.find_children("*", "Terrain3D", true, false):
		t = c as Terrain3D
		break
	if t == null:
		printerr("M41: ✗ 无 Terrain3D")
		return
	printerr("M41: material=", str(t.material),
			" path=", (t.material.resource_path if t.material != null else "null"))
	var so = t.material.shader_override
	printerr("M41: shader_override=", str(so),
			" path=", ((so as Shader).resource_path if so is Shader else "null"),
			" code_len=", ((so as Shader).code.length() if so is Shader else -1))
	printerr("M41: texture_list=", t.assets.texture_list.size(),
			" world_bg=", t.material.world_background,
			" macro=", t.material.macro_variation_enabled,
			" auto_shader=", t.material.auto_shader_enabled)
	if t.assets.texture_list.size() > 0:
		var ta: Terrain3DTextureAsset = t.assets.texture_list[0]
		printerr("M41: tex0=", ta.name, " alb=", str(ta.albedo_texture))
	var hv: float = t.data.get_height(Vector3(0, 0, -50))
	printerr("M41: height(0,0,-50)=", hv, " nan=", is_nan(hv))
	# 打印方法表，找刷新 shader/材质 的正确 API
	for m in t.material.get_method_list():
		var mn := str(m.get("name", ""))
		if mn.contains("update") or mn.contains("shader") or mn.contains("material"):
			printerr("M41: MAT_METHOD ", mn)
	for m in t.get_method_list():
		var mn2 := str(m.get("name", ""))
		if mn2.contains("update") or mn2.contains("asset") or mn2.contains("shader") or mn2.contains("material"):
			printerr("M41: T_METHOD ", mn2)


func _shot(name: String) -> void:
	_cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	_cam.make_current()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("M41: ✗ img null")
		return
	var path := ProjectSettings.globalize_path(OUT + name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	var w := img.get_width()
	var h := img.get_height()
	var pts := [
		["sky", Vector2i(w / 2, int(h * 0.10))],
		["far", Vector2i(w / 2, int(h * 0.45))],
		["mid", Vector2i(w / 2, int(h * 0.62))],
		["near", Vector2i(w / 2, int(h * 0.88))],
		["left", Vector2i(int(w * 0.2), int(h * 0.85))],
		["right", Vector2i(int(w * 0.8), int(h * 0.85))],
	]
	var txt := ""
	for p in pts:
		var c: Color = img.get_pixel(p[1].x, p[1].y)
		txt += str(p[0]) + "=(" \
			+ str(snappedf(c.r, 0.001)) + "," \
			+ str(snappedf(c.g, 0.001)) + "," \
			+ str(snappedf(c.b, 0.001)) + ") "
	printerr("M41: PIXEL ", txt)
