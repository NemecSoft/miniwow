extends Node3D
## 浮空城预览：实例化 city_zone（全程序化生成）+ 相机对准中央广场方尖碑，渲染一帧存图退出

func _ready() -> void:
	var zone: Node3D = load("res://scripts/level/city_zone.gd").new()
	zone.name = "CityZone"
	add_child(zone)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("b9d6e4")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("f5fbff")
	e.ambient_light_energy = 0.8
	e.fog_enabled = true
	e.fog_light_color = Color("b9d6e4")
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff0d7")
	sun.light_energy = 2.25
	sun.rotation_degrees = Vector3(-48, -30, 0)
	add_child(sun)

	var cam := Camera3D.new()
	# 找到方尖碑实际位置对准拍（glb 根节点名含 monument）
	await get_tree().process_frame
	var monument: Node3D = null
	for child in zone.get_children():
		if "onument" in child.name:
			monument = child
			break
	var target := Vector3(46.0, 6.0, 6.5)
	if monument != null:
		target = monument.global_position + Vector3(0, 6.0, 0)
		print("MONUMENT AT: ", monument.global_position)
	else:
		print("MONUMENT NOT FOUND")
	cam.position = target + Vector3(17.0, 9.0, 20.0)
	add_child(cam)
	cam.current = true
	cam.look_at(target)  # 必须入树后再 look_at（局部 look_at 需全局 transform 生效）
	cam.fov = 55.0

	await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://../city_monument_ingame.png")
	print("CITY_PREVIEW_SAVED")
	get_tree().quit()
