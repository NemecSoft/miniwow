extends Node3D

## 官方 demo 地形数据对照实验：Terrain3D + data_directory + 官方资产，截图验证渲染。
## 窗口模式跑：godot --path . res://tools/probe_official_terrain.tscn

func _ready() -> void:
	var t := Terrain3D.new()
	t.data_directory = "res://assets/terrain3d_demo"
	t.assets = load("res://assets/terrain3d_demo/assets.tres")
	var mat := Terrain3DMaterial.new()
	mat.world_background = Terrain3DMaterial.NONE
	t.material = mat
	add_child(t)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)

	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.position = Vector3(0, 60, 200)
	cam.look_at(Vector3(0, 10, 0))

	for i in 120:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/shots/official_terrain.png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("SHOT: official_terrain.png data_regions=", t.data.get_region_count())
	get_tree().quit(0)
