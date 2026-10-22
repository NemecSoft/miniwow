extends Node3D

## M46 双星球验收探针：按 --world 拍对应星球。
##
## 用法（必须窗口模式，headless 是 dummy 渲染后端出不了图）：
##   godot --path <项目> res://tools/planet_shot.tscn -- --world outland
##   godot --path <项目> res://tools/planet_shot.tscn            (默认 azeroth)
##
## 输出到 screenshots/m46/<星球>_*.png

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
	await get_tree().create_timer(11.0).timeout
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

	var tag := Planet.world_id()
	var shots: Array = []
	if Planet.world_id() == "outland":
		# 整颗外域（R=1500，4600m 外刚好填满画面）
		shots.append(["c1_outland_planet.png",
			Planet.dir_from_plane(0.0, -130.0) * 4600.0, Vector3.ZERO])
		# 断崖边缘：能同时看到大陆弧线 + 虚空
		shots.append(["c2_outland_edge.png",
			_fp(0, 0.02, -0.30, 260.0), _fp(0, 0.0, -0.62, 0.0)])
		# 地狱火半岛地面
		shots.append(["c3_hellfire.png",
			_fp(0, 0.04, -0.12, 5.0), _fp(0, 0.0, -0.40, 2.0)])
		# 赞加沼泽蘑菇林
		shots.append(["c4_zangarmarsh.png",
			_fp(1, 0.02, -0.12, 5.0), _fp(1, 0.0, -0.42, 6.0)])
		# 纳格兰草原 + 浮空岛
		shots.append(["c5_nagrand.png",
			_fp(2, 0.0, -0.24, 8.0), _fp(2, 0.0, -0.56, 26.0)])
		# 刀锋山石刺
		shots.append(["c6_bladeedge.png",
			_fp(3, 0.0, -0.22, 10.0), _fp(3, 0.0, -0.54, 40.0)])
		# 影月谷邪能水晶
		shots.append(["c7_shadowmoon.png",
			_fp(4, 0.0, -0.12, 6.0), _fp(4, 0.0, -0.44, 10.0)])
		# 虚空风暴破碎岛
		shots.append(["c8_netherstorm.png",
			_fp(5, 0.0, -0.12, 8.0), _fp(5, 0.0, -0.44, 24.0)])
	else:
		var home := Planet.dir_from_plane(0.0, -130.0)
		shots.append(["a1_azeroth_planet.png", home * 6000.0, Vector3.ZERO])
		shots.append(["a2_azeroth_village.png",
			_ps(-34.0, 18.0, 5.0), _ps(24.0, -250.0, 4.0)])
	for s in shots:
		await _shoot(str(s[0]), s[1], s[2])
	printerr("PSHOT[%s]: 结束" % tag)
	get_tree().quit(0)


## 平面坐标 → 球面点（沿该点自己的法线抬高）
func _ps(x: float, z: float, lift: float = 0.0) -> Vector3:
	var p := Planet.plane_to_surface(x, z)
	return p + Planet.up_at(p) * lift


## 面内 uv → 球面点（沿当地法线抬高）
func _fp(face: int, u: float, v: float, lift: float = 0.0) -> Vector3:
	var d := Planet.dir_of(face, u, v)
	return Planet.surface_pos(d) + d * lift


func _shoot(fname: String, pos: Vector3, target: Vector3) -> void:
	_cam.global_position = pos
	if (target - pos).length_squared() > 0.0001:
		_cam.look_at(target, Planet.up_at(pos))
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("PSHOT: img null ", fname)
		return
	var path := ProjectSettings.globalize_path("res://screenshots/m46/" + fname)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("PSHOT: 已存 ", fname)
