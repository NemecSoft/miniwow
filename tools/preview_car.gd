extends Node3D

## M31c 临时预览：渲染 roadster2 车模单帧存图后自动退出（验证 glb 材质/结构/喷焰位置）

func _ready() -> void:
	var car: Node3D = (load("res://scenes/vehicles/sports_car.tscn") as PackedScene).instantiate()
	add_child(car)
	# 环境光 + 平行光（模拟 tsl 氛围）
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff0d7")
	sun.light_energy = 2.25
	add_child(sun)
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("b9d6e4")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("f5fbff")
	env.ambient_light_energy = 1.2
	world_env.environment = env
	add_child(world_env)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(4.5, 2.2, -5.5)
	cam.look_at(Vector3(0, 0.5, 0))
	cam.make_current()
	# 喷焰全开（检查特效位置与朝向）
	car.set("lifting_sync", true)
	car.set("boosting_sync", true)
	for fx_name: String in ["LiftFX_FL", "LiftFX_FR", "LiftFX_RL", "LiftFX_RR", "BoostFX_L", "BoostFX_R"]:
		var fx := car.find_child(fx_name, false, false)
		if fx is Node3D:
			(fx as Node3D).visible = true
	await get_tree().create_timer(1.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://../car_preview.png")
	print("CAR_PREVIEW_SAVED")
	get_tree().quit(0)
