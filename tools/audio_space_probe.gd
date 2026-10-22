extends Node3D

## M43 回归探针：验证 3D 音效的距离剔除 / 近处 2D 兜底 / 非法坐标拦截。
## 跑法：godot --path . res://tools/audio_space_probe.tscn
## 判定：打印每项"是否生成了 AudioStreamPlayer3D 节点"，EXPECT 与 GOT 必须一致。

var _cam: Camera3D


func _ready() -> void:
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.global_position = Vector3(0, 10, 0)
	_cam.look_at(Vector3.ZERO)
	_cam.make_current()
	await get_tree().process_frame
	# headless 下 SfxManager 会自动静音（无音频设备），本探针只验逻辑分支，手动解除
	SfxManager.set("_muted", false)

	await _case("近处 5m（应生成 3D）", Vector3(0, 0, 5), true)
	await _case("中距 30m（应生成 3D）", Vector3(30, 0, 0), true)
	await _case("远距 200m（应剔除）", Vector3(0, 0, 200), false)
	await _case("远距 60m（应剔除）", Vector3(60, 0, 0), false)
	await _case("NaN 坐标（应拦截）", Vector3(NAN, 0, 0), false)
	# 相机在 (0,10,0)，所以"近"要贴着相机放（此处约 1.1 米）
	await _case("贴近相机 1.1m（应走 2D，不生成 3D）", Vector3(0, 9.5, 1.0), false, true)

	printerr("ASP: 结束")
	get_tree().quit(0)


func _case(label: String, pos: Vector3, expect_3d: bool, use_world := false) -> void:
	var before := _count_3d()
	if use_world:
		SfxManager.play_world(&"hit_light", pos, 4.0)
	else:
		SfxManager.play_3d(&"hit_light", pos)
	await get_tree().process_frame
	var got := _count_3d() > before
	var ok := "PASS" if got == expect_3d else "*** FAIL ***"
	printerr("ASP: ", ok, " | ", label, " | 生成3D=", got)


func _count_3d() -> int:
	var n := 0
	for c in get_children():
		if c is AudioStreamPlayer3D:
			n += 1
	return n
