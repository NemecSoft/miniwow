extends Node3D

## M47：定位"晴天下天空里那片白色竖条纹"。
##
## 手法：A/B 对照 —— 先拍基准图，然后逐个隐藏候选节点（天气系统 / 云层 / 天空），
## 每次隐藏拍一张。条纹在哪一步消失，凶手就是谁。
## 同时把所有 GPUParticles3D 的实际 emitting / amount / 位置打出来，
## 因为"看起来像雨"不等于"真的是雨"。

const BASE_DIR := "res://screenshots/m47/"

var _level: Node3D
var _player: Node3D


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("SKP: headless 出不了图")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "观感", "blue")
	await get_tree().create_timer(6.0).timeout

	for cl in _level.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for c in _level.find_children("*", "Control", true, false):
		(c as Control).visible = false

	_player = _find_player()
	_report_particles()

	# 相机抬头 25°，把天空那片条纹框进画面（平视时它在中上部）
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		printerr("SKP: 没有相机")
		get_tree().quit(0)
		return
	var p: Node3D = _player
	if p == null:
		printerr("SKP: 找不到玩家")
		get_tree().quit(0)
		return
	var up := Planet.up_at(p.global_position)
	cam.global_position = p.global_position + up * 2.0
	cam.look_at(p.global_position + up * 2.0 - p.global_transform.basis.z * 20.0 + up * 9.0, up)

	await get_tree().create_timer(0.6).timeout
	await _save("s00_base.png")

	# --- A/B：逐项关天空特征 ---
	var dome := _find_sky()
	if dome != null:
		var smat: ShaderMaterial = dome.get("sky_material")
		if smat != null:
			printerr("SKP: 找到 sky_material，开始逐项关")
			smat.set_shader_parameter("cumulus_visible", false)
			await get_tree().create_timer(0.5).timeout
			await _save("s10_no_cumulus.png")
			smat.set_shader_parameter("cumulus_visible", true)

			smat.set_shader_parameter("cirrus_visible", false)
			await get_tree().create_timer(0.5).timeout
			await _save("s11_no_cirrus.png")
			smat.set_shader_parameter("cirrus_visible", true)

			# 关掉大气（排除散射条纹）
			var old_atm: bool = smat.get_shader_parameter("atmosphere_visible") if smat.get_shader_parameter("atmosphere_visible") != null else true
			smat.set_shader_parameter("atmosphere_visible", false)
			await get_tree().create_timer(0.5).timeout
			await _save("s12_no_atm.png")
			smat.set_shader_parameter("atmosphere_visible", old_atm)

			printerr("SKP: planet_up = %s" % str(smat.get_shader_parameter("planet_up")))
			printerr("SKP: cumulus_coverage = %s" % str(smat.get_shader_parameter("cumulus_coverage")))
			printerr("SKP: cumulus_thickness = %s" % str(smat.get_shader_parameter("cumulus_thickness")))
		else:
			printerr("SKP: SkyDome 上没有 sky_material")
	else:
		printerr("SKP: 找不到 SkyDome")

	printerr("SKP: 结束")
	get_tree().quit(0)


func _ab(tag: String, node: Node) -> void:
	if node == null:
		printerr("SKP: 找不到节点，跳过 %s" % tag)
		return
	var n3 := node as Node3D
	var old := n3.visible if n3 != null else false
	if n3 != null:
		n3.visible = false
	await get_tree().create_timer(0.5).timeout
	await _save(tag)
	if n3 != null and is_instance_valid(n3):
		n3.visible = old


func _find_sky() -> Node:
	var n := _find_named("Sky3D")
	if n != null:
		return n
	return _find_named("SkyDome")


func _find_named(nm: String) -> Node:
	for n in get_tree().root.find_children("*", "", true, false):
		if (n as Node).name == nm:
			return n
	return null


func _report_particles() -> void:
	var arr := get_tree().root.find_children("*", "GPUParticles3D", true, false)
	printerr("SKP: 场景内 GPUParticles3D 共 %d 个" % arr.size())
	for n in arr:
		var g := n as GPUParticles3D
		printerr("SKP[P] %-24s emitting=%-5s amount=%-6d visible=%-5s r=%.1f pos=%s" % [
			str(g.name), str(g.emitting), g.amount, str(g.visible),
			g.global_position.length(), str(g.global_position.round())])
	# 天气状态
	var w := _find_named("WeatherSystem")
	if w != null and w.has_method("weather_name"):
		printerr("SKP: 当前天气 = %s" % str(w.call("weather_name")))
	else:
		printerr("SKP: 找不到 WeatherSystem 或没有 weather_name()")


func _find_player() -> Node3D:
	for n in get_tree().root.find_children("*", "CharacterBody3D", true, false):
		if not n.has_method("_planet_frame_step"):
			continue
		if n.has_method("is_bot") and n.call("is_bot"):
			continue
		return n as Node3D
	for n in get_tree().root.find_children("*", "CharacterBody3D", true, false):
		if n.has_method("_planet_frame_step"):
			return n as Node3D
	return null


func _save(fn: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE_DIR))
	img.save_png(ProjectSettings.globalize_path(BASE_DIR + fn))
	printerr("SKP: 已存 %s" % fn)
