extends Node3D

## M47 真实观感验收：完全用玩家自己的相机，不调机位、不隐藏场景。
##
## 存在的意义：之前一直用自由相机（planet_shot.gd）验收，拍出来的全是
## "上帝视角的漂亮构图"，而玩家实际看到的是角色浮在半空、地面糊成一片。
## 用户 2026-10-22 直接退单，所以验收必须从玩家眼睛出发。
##
## 用法：
##   godot --path . res://tools/player_view_shot.tscn -- --world outland
## 产出：
##   screenshots/m47/p01_spawn.png   出生点原地
##   screenshots/m47/p02_third.png   拉远看角色全身（检查脚有没有踩实）
##   screenshots/m47/p03_look_down.png 低头看脚下地面
##   screenshots/m47/p04_walk.png    走两步之后
##   + 终端打印角色径向离地高度（mesh 高度 vs 解析高度两套，各自差多少）

const BASE_DIR := "res://screenshots/m47/"

var _tag := ""

var _level: Node3D
var _player: Node3D


func _ready() -> void:
	# --tag <名字>：给输出文件加前缀，方便一次跑多种光照/时刻方案
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--tag" and i + 1 < args.size():
			_tag = args[i + 1] + "_"
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("PV: headless 出不了图，必须窗口模式")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "观感", "blue")
	await get_tree().create_timer(6.0).timeout

	# 隐藏 HUD（只留 3D 世界，看场景本身）
	for cl in _level.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for c in _level.find_children("*", "Control", true, false):
		(c as Control).visible = false

	_player = _find_player()
	_report_ground()
	await get_tree().create_timer(0.8).timeout
	await _save("p01_spawn.png")

	var p := _player
	if p == null:
		printerr("PV: 找不到玩家节点")
		get_tree().quit(0)
		return

	# 相机拉远到 6m 看角色全身：脚有没有踩在地形上
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var up := Planet.up_at(p.global_position)
		var fwd: Vector3 = -p.global_transform.basis.z
		cam.global_position = p.global_position + up * 1.6 - fwd * 5.5
		cam.look_at(p.global_position + up * 0.9, up)
	await get_tree().create_timer(0.5).timeout
	await _save("p02_third.png")

	# 低头看脚下：地面有没有裂缝/黑边/穿模
	if cam != null:
		var up2 := Planet.up_at(p.global_position)
		var fwd2: Vector3 = -p.global_transform.basis.z
		cam.global_position = p.global_position + up2 * 3.2 - fwd2 * 0.9
		cam.look_at(p.global_position, up2)
	await get_tree().create_timer(0.5).timeout
	await _save("p03_look_down.png")

	# 走两步，再拍一次（检查移动中是否持续贴地）
	for i in 60:
		p.global_position += -p.global_transform.basis.z * 0.12
		await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
	_report_ground()
	await _save("p04_walk.png")

	# 骑乘验收：按 X 的等价调用（服务器权威侧直接召唤），然后拍第三人称
	p.call("_summon_mount", true, p.get_multiplayer_authority(), Vector3(), INF, "couch")
	await get_tree().create_timer(1.6).timeout
	var mv = p.get("mounted_vehicle")
	printerr("PV: 骑乘状态 mounted=%s" % str(mv))
	if mv != null and cam != null:
		var mup := Planet.up_at(p.global_position)
		var mfwd: Vector3 = -p.global_transform.basis.z
		cam.global_position = p.global_position + mup * 2.4 - mfwd * 6.0
		cam.look_at(p.global_position + mup * 0.8, mup)
	await get_tree().create_timer(0.6).timeout
	await _save("p05_mounted.png")

	printerr("PV: 结束")
	get_tree().quit(0)


## 量化：角色原点低于/高于地形网格多少米
func _report_ground() -> void:
	if _player == null:
		return
	var pos: Vector3 = _player.global_position
	if pos.length_squared() < 1.0:
		printerr("PV: 玩家位置异常 %s" % str(pos))
		return
	var dir: Vector3 = pos.normalized()
	var r: float = pos.length()
	var h_mesh: float = Planet.mesh_height(dir)
	var h_analytic: float = Planet.height_at(dir)
	printerr("PV: 玩家 r=%.2f | 网格表面 r=%.2f (差 %+.2f m) | 解析表面 r=%.2f (差 %+.2f m) | dir=%s" % [
		r,
		Planet.RADIUS + h_mesh, r - (Planet.RADIUS + h_mesh),
		Planet.RADIUS + h_analytic, r - (Planet.RADIUS + h_analytic),
		str(dir.snapped(Vector3.ONE * 0.01))])


func _find_player() -> Node3D:
	var pc := _level.get_node_or_null("PlayersContainer")
	if pc == null:
		printerr("PV: 没有 PlayersContainer")
		return null
	printerr("PV: PlayersContainer xf.origin=%s 子节点数=%d" % [
		str(pc.global_transform.origin.snapped(Vector3.ONE * 0.1)), pc.get_child_count()])
	for c in pc.get_children():
		var n3 := c as Node3D
		printerr("PV:   child %s pos=%s r=%.1f" % [
			c.name, str(n3.global_position.snapped(Vector3.ONE * 0.1)) if n3 else "?",
			n3.global_position.length() if n3 else -1.0])
	var want: Vector3 = _level.call("get_spawn_point", 1)
	printerr("PV: get_spawn_point(1) = %s r=%.1f" % [str(want.snapped(Vector3.ONE * 0.1)), want.length()])
	for c in pc.get_children():
		if c is Node3D:
			return c as Node3D
	return null


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("PV: img null ", fname)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE_DIR))
	var path := ProjectSettings.globalize_path(BASE_DIR + _tag + fname)
	var err := img.save_png(path)
	printerr("PV: 已存 %s (err=%d)" % [fname, err])
