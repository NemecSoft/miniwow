extends Node3D

## M41 地形黑屏诊断探针（窗口模式，必须真实 Vulkan；headless 是 dummy 后端出不了图）。
##
## 纪律（用户硬要求）：颜色/画面类问题 = 单变量实验 + 像素读回，不做纸上着色器推导。
## 步骤：
##   1) dump 地形材质/纹理/数据状态
##   2) 基准截图（当前 M_forest 材质）
##   3) 单变量 A：换成 demo 原版 M_terrain.tres
##   4) 单变量 B：M_forest + world_background = 2（demo 原值）
##   5) 单变量 C：M_forest + macro_variation_enabled = false
## 每步读回 5 个采样点像素（天空/中心/下方/左下/右下）。
##
## 用法：godot --path <项目> res://tools/m41_terrain_diag.tscn

const OUT := "res://screenshots/m41/"
const FOREST_MAT := "res://assets/terrain_forest/M_forest.tres"
const DEMO_MAT := "res://assets/terrain_demo/data/M_terrain.tres"

var _level: Node3D
var _cam: Camera3D
var _terrain: Terrain3D = null
var _base_mat: Terrain3DMaterial = null
var _t := 0.0


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("M41: 检测到 headless dummy 后端，无法渲染，退出")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "诊断", "blue")
	await get_tree().create_timer(2.0).timeout
	for n in ["MainMenuUI", "MultiplayerChatUI", "ClassSelectUI", "DialogueUI",
			"WorldMapUI", "SettingsUI", "InventoryUI", "QuestTrackerUI"]:
		var ui := _level.get_node_or_null(n)
		if ui != null and ui is CanvasItem:
			(ui as CanvasItem).visible = false
	var pc := _level.get_node_or_null("PlayersContainer")
	if pc != null:
		for c in pc.get_children():
			c.process_mode = Node.PROCESS_MODE_DISABLED
	_cam = Camera3D.new()
	_cam.name = "M41Cam"
	add_child(_cam)
	_cam.make_current()
	# 机位：森林区俯视地面，能同时看到天空和地面
	_cam.global_position = Vector3(0, 6, -30)
	_cam.look_at(Vector3(0, 0, -75))
	printerr("M41: 探针就绪，开始")


func _physics_process(delta: float) -> void:
	if _cam == null:
		return
	_cam.make_current()
	_t += delta
	if _step_done(1) and _t >= 7.0:
		_step1()
	elif _step_done(2) and _t >= 8.0:
		_step2()
	elif _step_done(3) and _t >= 10.0:
		_step3()
	elif _step_done(4) and _t >= 12.5:
		_step4()
	elif _step_done(5) and _t >= 15.0:
		_step5()
	elif _step_done(6) and _t >= 17.5:
		printerr("M41: 诊断结束")
		get_tree().quit(0)


var _done := 0


func _step_done(n: int) -> bool:
	return _done < n


func _step1() -> void:
	_done = 1
	_dump_state()
	_shot("m41_a_base.png")


func _step2() -> void:
	_done = 2
	if _terrain == null:
		return
	var m := load(DEMO_MAT) as Terrain3DMaterial
	if m == null:
		printerr("M41: ✗ demo 材质 load 失败")
		return
	_terrain.material = m
	printerr("M41: 已换 demo 材质 M_terrain.tres")
	await get_tree().create_timer(1.2).timeout
	_shot("m41_b_demomat.png")


func _step3() -> void:
	_done = 3
	if _terrain == null:
		return
	_terrain.material = _base_mat
	_terrain.material.world_background = 2
	printerr("M41: 已恢复 M_forest，world_background=2")
	await get_tree().create_timer(1.2).timeout
	_shot("m41_c_wb2.png")


func _step4() -> void:
	_done = 4
	if _terrain == null:
		return
	_terrain.material.world_background = 0
	_terrain.material.macro_variation_enabled = false
	printerr("M41: world_background=0，macro_variation_enabled=false")
	await get_tree().create_timer(1.2).timeout
	_shot("m41_d_nomacro.png")


func _step5() -> void:
	_done = 5
	if _terrain == null:
		return
	_terrain.material.macro_variation_enabled = true
	_terrain.material.auto_shader_enabled = false
	printerr("M41: macro 恢复，auto_shader_enabled=false")
	await get_tree().create_timer(1.2).timeout
	_shot("m41_e_noautoshader.png")


func _find_terrain() -> Terrain3D:
	for c in _level.find_children("*", "Terrain3D", true, false):
		return c as Terrain3D
	return null


func _dump_state() -> void:
	_terrain = _find_terrain()
	if _terrain == null:
		printerr("M41: ✗ 找不到 Terrain3D 节点")
		return
	_base_mat = _terrain.material
	var t := _terrain
	printerr("M41: terrain=", str(t.get_path()))
	printerr("M41: material=", str(_base_mat),
			" path=", (_base_mat.resource_path if _base_mat != null else "null"))
	if _base_mat != null:
		printerr("M41:   world_background=", _base_mat.world_background)
		printerr("M41:   auto_shader_enabled=", _base_mat.auto_shader_enabled)
		printerr("M41:   macro_variation_enabled=", _base_mat.macro_variation_enabled)
		printerr("M41:   dual_scaling_enabled=", _base_mat.dual_scaling_enabled)
		printerr("M41:   projection_enabled=", _base_mat.projection_enabled)
		var sh = _base_mat.get("shader")
		printerr("M41:   shader=", str(sh))
		if sh is Shader:
			printerr("M41:   shader.resource_path=", (sh as Shader).resource_path)
	printerr("M41: assets=", str(t.assets))
	if t.assets != null:
		printerr("M41:   texture_list.size=", t.assets.texture_list.size())
		for i in t.assets.texture_list.size():
			var ta: Terrain3DTextureAsset = t.assets.texture_list[i]
			printerr("M41:   tex[", i, "] name=", ta.name,
					" alb=", str(ta.albedo_texture), " nrm=", str(ta.normal_texture))
	printerr("M41: region_count=", t.region_count)
	if t.data != null:
		var hv: float = t.data.get_height(Vector3(0, 0, 0))
		printerr("M41: height(0,0,0)=", hv, " is_nan=", is_nan(hv))
		var h2: float = t.data.get_height(Vector3(0, 0, -60))
		printerr("M41: height(0,0,-60)=", h2, " is_nan=", is_nan(h2))


func _shot(name: String) -> void:
	_cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	_cam.make_current()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("M41: ✗ img null ", name)
		return
	var path := ProjectSettings.globalize_path(OUT + name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	var w := img.get_width()
	var h := img.get_height()
	var pts := [
		["sky", Vector2i(w / 2, int(h * 0.10))],
		["center", Vector2i(w / 2, h / 2)],
		["lower", Vector2i(w / 2, int(h * 0.80))],
		["left", Vector2i(int(w * 0.18), int(h * 0.78))],
		["right", Vector2i(int(w * 0.82), int(h * 0.78))],
	]
	var txt := ""
	for p in pts:
		var c: Color = img.get_pixel(p[1].x, p[1].y)
		txt += str(p[0]) + "=(" \
			+ str(snappedf(c.r, 0.001)) + "," \
			+ str(snappedf(c.g, 0.001)) + "," \
			+ str(snappedf(c.b, 0.001)) + ") "
	printerr("M41: PIXEL ", name, " ", txt)
