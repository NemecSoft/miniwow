extends Node

## 地形数据诊断：高度图采样 + 纹理/网格资产完整性（headless 可跑）。

func _ready() -> void:
	var starter := Node3D.new()
	starter.set_script(load("res://scripts/environment/terrain_starter.gd"))
	add_child(starter)
	for i in 600:
		await get_tree().process_frame
		if starter.terrain != null and starter.terrain.data != null:
			var tex_count: int = starter.terrain.assets.get_texture_count()
			var mesh_count: int = starter.terrain.assets.get_mesh_count()
			printerr("[T] texture_count=", tex_count, " mesh_count=", mesh_count)
			for ti in tex_count:
				var ta: Terrain3DTextureAsset = starter.terrain.assets.get_texture(ti)
				printerr("[T] tex[%d] name=%s albedo=%s" % [ti, ta.name, ta.albedo_texture != null])
			for mi in mesh_count:
				var ma: Terrain3DMeshAsset = starter.terrain.assets.get_mesh_asset(mi)
				printerr("[T] mesh[%d] name=%s scene=%s" % [mi, ma.name, ma.scene_file != null])
			var samples := {
				"山区(-620,-580)": Vector3(-620, 0, -580),
				"山2(180,-520)": Vector3(180, 0, -520),
				"丘陵(400,300)": Vector3(400, 0, 300),
				"主城(0,0)": Vector3(0, 0, 0),
				"主城边缘(80,0)": Vector3(80, 0, 0),
			}
			for key in samples:
				printerr("[H] ", key, " -> ", "%.2f" % starter.terrain.data.get_height(samples[key]))
			var river0: float = starter.terrain.data.get_height(Vector3(starter._river_x(0.0), 0, 0.0))
			var river300: float = starter.terrain.data.get_height(Vector3(starter._river_x(-300.0), 0, -300.0))
			printerr("[H] 河心(z=0) -> ", "%.2f" % river0, "  河心(z=-300) -> ", "%.2f" % river300)
			break
	printerr("[T] done")
	get_tree().quit(0)
