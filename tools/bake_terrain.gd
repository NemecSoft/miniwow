extends Node3D

## 地形烘焙工具：运行时生成高度图 → import → 保存为 region 文件。
## 产出 assets/terrain3d_world/（terrain3d_X-Y.res），此后 terrain_starter
## 用 data_directory 加载（官方已验证的渲染路径，且可在编辑器里继续雕刻）。
## 窗口模式跑：godot --path . res://tools/bake_terrain.tscn

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("BAKE-FAIL: 必须窗口模式（GDExtension 渲染依赖）")
		get_tree().quit(1)
		return

	var starter := Node3D.new()
	starter.set_script(load("res://scripts/environment/terrain_starter.gd"))
	add_child(starter)

	# 等 create_terrain 完成（terrain 非空即高度图已导入）
	for i in 1800:
		await get_tree().process_frame
		if starter.terrain != null and starter.terrain.data.get_region_count() > 0:
			break
	var terrain: Terrain3D = starter.terrain
	if terrain == null:
		printerr("BAKE-FAIL: 地形未生成")
		get_tree().quit(1)
		return

	var region_count: int = terrain.data.get_region_count()
	printerr("BAKE: regions=", region_count)
	var out_dir := ProjectSettings.globalize_path("res://assets/terrain3d_world")
	DirAccess.make_dir_recursive_absolute(out_dir)
	terrain.data.save_directory("res://assets/terrain3d_world")
	printerr("BAKE: 已保存到 assets/terrain3d_world/")
	get_tree().quit(0)
