extends Node3D

## M16 视觉验证：播放重定向 Strike 动画，截取 idle / 出拳中段 / 收拳 三张图。
## 窗口模式运行：godot --path . res://tools/probe_strike_shot.tscn

func _ready() -> void:
	# 环境：天光 + 平行光 + 地面参考（无环境渲染会全黑）
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.55, 0.75)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10, 10)
	floor_mesh.mesh = plane
	floor_mesh.position.y = -0.02
	add_child(floor_mesh)

	# 机器人（手动注入 Strike——robot_body.tscn 无脚本，Body 注入逻辑不生效）
	var body_scene: PackedScene = load("res://scenes/monsters/robot_body.tscn")
	var body := body_scene.instantiate()
	add_child(body)
	var anim_player := body.get_node("AnimationPlayer") as AnimationPlayer
	var lib := anim_player.get_animation_library(&"")
	lib.add_animation(&"Strike", load("res://assets/animations/retarget/strike_jab.tres"))

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.2, 3.2)
	cam.rotation_degrees = Vector3(-8, 0, 0)
	add_child(cam)
	cam.make_current()
	# 侧机位（出拳方向在 +Z，侧看最清楚）
	var side_cam := Camera3D.new()
	side_cam.position = Vector3(3.0, 1.2, 0.6)
	add_child(side_cam)
	side_cam.look_at(Vector3(0, 0.8, 0))

	await get_tree().process_frame
	await get_tree().process_frame

	# 1. idle 基准帧（库内名 Idle-loop，若缺失用 T-pose）
	if anim_player.has_animation(&"Idle-loop"):
		anim_player.play(&"Idle-loop")
	await RenderingServer.frame_post_draw
	_shot("m16_idle.png")

	# 2. Strike 全程 8 帧（0.87s 动作逐段检查，正/侧双机位）
	anim_player.play(&"Strike")
	for i in range(8):
		await get_tree().create_timer(0.11).timeout
		await RenderingServer.frame_post_draw
		_shot("m16_strike_%d.png" % i)
	# 侧机位重播一遍，拍出拳瞬间（t≈0.28）与抱架（t≈0.05）
	anim_player.play(&"Strike")
	await get_tree().create_timer(0.05).timeout
	await RenderingServer.frame_post_draw
	_shot_side("m16_side_guard.png")
	await get_tree().create_timer(0.23).timeout
	await RenderingServer.frame_post_draw
	_shot_side("m16_side_punch.png")

	# ---- M16b 验证 1：SwordSlash 挥剑动画（替换旋风斩）----
	lib.add_animation(&"SwordSlash", load("res://assets/animations/retarget/sword_slash.tres"))
	anim_player.play(&"SwordSlash")
	await get_tree().create_timer(0.05).timeout
	await RenderingServer.frame_post_draw
	_shot_side("m16b_slash_start.png")
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	_shot_side("m16b_slash_mid.png")
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	_shot_side("m16b_slash_late.png")

	# ---- M16b 验证 2：小跟班官方材质（贴图配色）----
	var partner_scene: PackedScene = load("res://scenes/npcs/partner.tscn")
	var partner := partner_scene.instantiate()
	add_child(partner)
	partner.position = Vector3(1.2, 0, 0.6)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shot("m16b_partner_mat.png")

	printerr("SHOT: 截图完成")
	get_tree().quit(0)


func _shot_side(file_name: String) -> void:
	var prev := get_viewport().get_camera_3d()
	(_side_cam_node()).make_current()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/shots/" + file_name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("SHOT: ", path)
	prev.make_current()


var _side_cam: Camera3D


func _side_cam_node() -> Camera3D:
	if _side_cam == null:
		for child in get_children():
			if child is Camera3D and child.position.x > 1.0:
				_side_cam = child
	return _side_cam


func _shot(file_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/shots/" + file_name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("SHOT: ", path)
