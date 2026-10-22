extends Node3D

## M51 视觉元凶排查：把"角色脚下的橙色拖尾"和"空中那块淡青色横带"揪出来。
##
## 方法：不猜。先列出所有粒子 + 所有半透明网格（带路径/位置/尺寸），
## 再逐类隐藏拍对照帧 —— 差异区域就是元凶。
##
## 用法：godot --path . res://tools/m51_culprit.tscn

const BASE_DIR := "res://screenshots/m51/"

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
		printerr("C51: headless 出不了图")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "排查", "blue")
	await get_tree().create_timer(6.0).timeout
	var cs = _level.get("class_select_ui")
	if cs != null and cs.has_method("close_panel"):
		cs.close_panel()
	_me = _find_player()
	await get_tree().create_timer(0.8).timeout

	# 跑起来，让"移动时才有"的东西出现
	Input.action_press("move_forward")
	for i in 12:
		await get_tree().physics_frame
	_list_particles()
	await _shot("a_base_moving.png")

	var parts := _all_particles()
	for p in parts:
		(p as Node3D).visible = false
	await get_tree().create_timer(0.3).timeout
	await _shot("b_no_particles.png")
	for p in parts:
		(p as Node3D).visible = true

	var translucent := _all_translucent()
	for m in translucent:
		(m as Node3D).visible = false
	await get_tree().create_timer(0.3).timeout
	await _shot("c_no_translucent.png")
	for m in translucent:
		(m as Node3D).visible = true
	Input.action_release("move_forward")

	print("C51: 结束")
	get_tree().quit(0)


func _find_player() -> Node3D:
	var pc := _level.get_node_or_null("PlayersContainer")
	return pc.get_node_or_null("1") as Node3D if pc != null else null


func _path_of(n: Node) -> String:
	var parts: Array[String] = []
	var cur := n
	while cur != null and cur != get_tree().root:
		parts.append(String(cur.name))
		cur = cur.get_parent()
	parts.reverse()
	return "/".join(parts)


func _all_particles() -> Array:
	var out: Array = []
	for p in get_tree().root.find_children("*", "GPUParticles3D", true, false):
		out.append(p)
	for p in get_tree().root.find_children("*", "CPUParticles3D", true, false):
		out.append(p)
	return out


func _list_particles() -> void:
	var list := _all_particles()
	printerr("C51: 场景粒子共 %d 个" % list.size())
	for p in list:
		var n3 := p as Node3D
		var g := n3.global_position
		var extra := ""
		if p is GPUParticles3D:
			var gp := p as GPUParticles3D
			extra = "amount=%d lifetime=%.1f emitting=%s local=%s" % [
				gp.amount, gp.lifetime, str(gp.emitting), str(gp.local_coords)]
		printerr("C51[粒子]: %s | 世界(%.2f,%.2f,%.2f) | %s" % [
			_path_of(p), g.x, g.y, g.z, extra])


## 半透明网格：透明通道 < 1 或材质 transparency 非 DISABLED，且世界尺寸够大（能糊住画面）
func _all_translucent() -> Array:
	var out: Array = []
	for m in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if _is_translucent(mi) and mi.get_aabb().size.length() > 3.0:
			out.append(mi)
	return out


func _is_translucent(mi: MeshInstance3D) -> bool:
	if mi.material_override is StandardMaterial3D:
		var mo := mi.material_override as StandardMaterial3D
		if mo.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mo.albedo_color.a < 0.99:
			return true
	for i in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(i)
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.albedo_color.a < 0.99:
				return true
	return false


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(BASE_DIR + fname)
	printerr("C51: 已存 " + fname)
