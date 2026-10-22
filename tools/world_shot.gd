extends Node3D

## M45 星球验收探针：从星球外、村庄地面、高空、隘口、地狱火 5 个机位实拍。
## 用法（必须窗口模式，headless 是 dummy 渲染后端出不了图）：
##   godot --path <项目> res://tools/world_shot.tscn

const OUT := "res://screenshots/m45/"

var _level: Node3D
var _cam: Camera3D


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "巡星", "blue")
	await get_tree().create_timer(10.0).timeout
	for cl in _level.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for c in _level.find_children("*", "Control", true, false):
		(c as Control).visible = false

	_cam = Camera3D.new()
	_cam.fov = 68.0
	_cam.far = 30000.0
	_cam.near = 0.1
	_level.add_child(_cam)
	_cam.current = true

	# 村庄方向（面 0 原点）
	var home := Planet.dir_from_plane(0.0, -130.0)
	var up := home
	var north := Planet.dir_from_plane(0.0, -430.0)   # 隘口方向

	var shots := [
		# 星球全貌：从 6000m 外看整颗球
		["b1_planet.png", home * 6000.0, Vector3.ZERO],
		# 高空俯瞰卡利姆多（350m 高度，能看到地平线弧度）
		["b2_aerial.png", _ps(0.0, 60.0, 350.0), _ps(0.0, -620.0, 0.0)],
		# 村庄地面（第三人称高度）
		["b3_village.png", _ps(-34.0, 18.0, 5.0), _ps(24.0, -250.0, 4.0)],
		# 隘口（山谷通道）
		["b4_pass.png", _ps(40.0, -300.0, 16.0), _ps(36.0, -500.0, 2.0)],
		# 地狱火红土 + 火山
		["b5_hellfire.png", _ps(-10.0, -560.0, 12.0), _ps(20.0, -800.0, 50.0)],
	]
	for s in shots:
		await _shoot(s[0], s[1], s[2])
	printerr("WSHOT: 结束")
	get_tree().quit(0)


## 平面坐标 → 球面点（沿该点自己的法线抬高）
func _ps(x: float, z: float, lift: float = 0.0) -> Vector3:
	var p := Planet.plane_to_surface(x, z)
	return p + Planet.up_at(p) * lift


func _shoot(fname: String, pos: Vector3, target: Vector3) -> void:
	_cam.global_position = pos
	if (target - pos).length_squared() > 0.0001:
		_cam.look_at(target, Planet.up_at(pos))
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("WSHOT: img null ", fname)
		return
	var path := ProjectSettings.globalize_path(OUT + fname)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("WSHOT: 已存 ", fname)
