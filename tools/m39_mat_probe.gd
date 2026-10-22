extends Node3D
## M39 材质诊断探针：确认 Terrain3D 实际加载的材质与平铺参数，
## 并用 A/B 两套参数各存一帧对比（俯视，看清纹理密度）。
##
## 用法（窗口模式）：
##   godot --path . res://tools/m39_mat_probe.tscn

const SHOT_DIR := "res://screenshots/m39/"
var _level: Node3D
var _cam: Camera3D
var _step := 0
var _busy := false


func _ready() -> void:
	var level: Node3D = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	get_tree().root.call_deferred("add_child", level)
	_level = level
	await get_tree().process_frame
	await get_tree().process_frame
	var starter := level.get_node_or_null("Environment/TerrainStarter")
	var terrain: Terrain3D = starter.terrain if starter != null else null
	if terrain == null:
		printerr("MAT-PROBE: !! terrain 为 null")
	else:
		var m: Terrain3DMaterial = terrain.material
		printerr("MAT-PROBE: material_path=", m.resource_path if m != null else "<null>")
		var assets: Terrain3DAssets = terrain.assets
		for i in range(assets.get_texture_count()):
			var ta: Terrain3DTextureAsset = assets.get_texture(i)
			printerr("MAT-PROBE: slot%d %s albedo=%s uv_scale=%s color=%s" % [i, ta.get_name(),
				str(ta.albedo_texture), str(ta.uv_scale), str(ta.albedo_color)])
	# Arena GridMap 的 MeshLibrary 材质
	var arena := level.get_node_or_null("Environment/KaykitArena")
	if arena != null:
		var gm := arena.get_node_or_null("Floormap") as GridMap
		if gm != null:
			var lib: MeshLibrary = gm.mesh_library
			printerr("MAT-PROBE: arena lib=", lib.resource_path if lib else "null")
			if lib != null:
				for item in lib.get_item_list():
					var mesh: Mesh = lib.get_item_mesh(item)
					if mesh == null:
						continue
					for si in range(mesh.get_surface_count()):
						var mat: Material = mesh.surface_get_material(si)
						var sm := mat as StandardMaterial3D
						printerr("MAT-PROBE: item=%d surf=%d mat=%s triplanar=%s albedo=%s" % [
							item, si, (sm.resource_name if sm else str(mat)),
							(sm.uv1_triplanar if sm else "-"),
							(str(sm.albedo_texture.resource_path) if sm and sm.albedo_texture else "none")])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	level._on_host_pressed("材质员", "blue")
	await get_tree().create_timer(1.5).timeout
	for ui_name in ["MainMenuUI", "MultiplayerChatUI", "ClassSelectUI", "DialogueUI", "HUD"]:
		var ui := level.get_node_or_null(ui_name)
		if ui:
			ui.visible = false
	for child in level.get_node_or_null("PlayersContainer").get_children():
		var cam := child.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.enabled = false
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()


func _physics_process(_delta: float) -> void:
	if _cam == null or _busy:
		return
	# 俯视村中心：看清地板 + 地形纹理
	if _step == 0:
		_step = 1
		_shot("m39_diag_a_overhead.png", Vector3(0, 60, -130), Vector3(0, 0, -130))
	elif _step == 1:
		_step = 2
		# 平视村中心：看清墙面与地板
		_shot("m39_diag_b_eye.png", Vector3(6, 3.2, -118), Vector3(0, 1.6, -132))
	elif _step == 2:
		_step = 3
		# 村外草地：看地形材质
		_shot("m39_diag_c_grass.png", Vector3(0, 6, -230), Vector3(20, 2, -340))
	elif _step == 3:
		_step = 4
		printerr("MAT-PROBE: 结束")
		get_tree().quit(0)


func _shot(file_name: String, pos: Vector3, look: Vector3) -> void:
	_busy = true
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(SHOT_DIR + file_name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("MAT-PROBE: ", file_name)
	_busy = false