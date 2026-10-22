extends Node3D

## M49 坐标读数验收：只验两件事
##   ① 屏幕上真的能看见 X / Y / Z 三行坐标（引擎自存帧，不是嘴上说）
##   ② 坐标条不和左上玩家面板重叠（打印两者矩形 + 相交判断）
##
## headless 是 dummy 渲染后端，永远出不了图，必须窗口模式跑。
## 用法：godot --path . res://tools/coord_shot.tscn

const BASE_DIR := "res://screenshots/m49/"

var _level: Node3D
var _player: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE_DIR))
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("C49: headless 出不了图，必须窗口模式")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "坐标", "blue")
	await get_tree().create_timer(6.0).timeout

	_player = _find_player()
	# 关掉进世界自动弹出的职业选择面板，避免它压住左上角读数
	var cs = _level.get("class_select_ui")
	if cs != null and cs.has_method("close_panel"):
		cs.close_panel()
	await get_tree().create_timer(0.5).timeout
	_report("出生")
	await get_tree().create_timer(0.8).timeout
	await _save("01_spawn.png")

	Input.action_press("move_forward")
	for i in 40:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	await get_tree().create_timer(0.5).timeout
	_report("按 W 走完")
	await _save("02_walk.png")

	# M 地图：Header 坐标标签应带 X/Y/Z 三个轴
	var wm = _level.get("world_map_ui")
	if wm != null:
		wm.open_map(_level)
		_level.call("_update_hud_for_menu") # 复现按 M 的真实路径：HUD 必须整体让位
		await get_tree().create_timer(1.2).timeout
		var lab := wm.get_node_or_null("Center/MapFrame/Header/Coords") as Label
		printerr("C49[地图]: Header 坐标 = " + (lab.text if lab != null else "<缺失>"))
		var cr2 := _level.get_node_or_null("HUD/CoordReadout") as Control
		if cr2 != null:
			printerr("C49[地图]: 开图后 HUD 内坐标条可见=" + str(cr2.is_visible_in_tree()) + "（应为 false，地图 Header 接管）")
		await _save("03_map.png")
		wm.close_map()

	print("C49: 结束（截图在 " + BASE_DIR + "）")
	get_tree().quit(0)


func _find_player() -> Node3D:
	var pc := _level.get_node_or_null("PlayersContainer")
	if pc == null:
		return null
	return pc.get_node_or_null("1") as Node3D


func _report(tag: String) -> void:
	var hud := _level.get_node_or_null("HUD")
	if hud == null:
		printerr("C49[" + tag + "]: !! 找不到 HUD")
		return
	var cr := hud.get_node_or_null("CoordReadout") as Control
	if cr == null:
		printerr("C49[" + tag + "]: !! HUD 下没有 CoordReadout")
		return
	var ptext := ""
	var dtext := ""
	for c in cr.find_children("*", "Label", true, false):
		var lab := c as Label
		if lab.get_theme_font_size("font_size") >= 14:
			ptext = lab.text
		else:
			dtext = lab.text
	var cr_rect := cr.get_global_rect()
	var real := "NULL"
	if _player != null and is_instance_valid(_player):
		var w := _player.global_position
		real = "X %.1f Y %.1f Z %.1f" % [w.x, w.y, w.z]
	printerr("C49[" + tag + "]: 可见=" + str(cr.is_visible_in_tree()) + " 矩形=" + str(cr_rect) + " | 世界=" + real)
	printerr("C49[" + tag + "]: 坐标行 = " + ptext)
	printerr("C49[" + tag + "]: 辅助行 = " + dtext)
	# 玩家面板（左上 PanelContainer）是否被压住
	for c in hud.find_children("*", "PanelContainer", true, false):
		var pc := c as PanelContainer
		var r := pc.get_global_rect()
		if r.position.x > 60.0 or r.size.y < 40.0:
			continue
		var hit := r.intersects(cr_rect)
		printerr("C49[" + tag + "]: 左上玩家面板 " + str(r) + " 与坐标条相交=" + str(hit))


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := BASE_DIR + fname
	var err := img.save_png(path)
	printerr("C49: 已存 " + fname + " (err=" + str(err) + ")")
