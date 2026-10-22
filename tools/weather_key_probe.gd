extends Node3D

## M43 探针：验证 F5 循环切天气 + 天气环境音真的在播。
func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	var level := scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	level.call("_on_host_pressed", "天气键", "blue")
	await get_tree().create_timer(5.0).timeout
	var w := level.get_node_or_null("Environment/WeatherSystem") as WeatherSystem
	if w == null:
		printerr("WK: 找不到天气节点")
		get_tree().quit(0)
		return
	printerr("WK: 初始=", w.weather_name())
	for i in 5:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F5
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().create_timer(1.2).timeout
		var amb := w.get_node("WeatherAmbient") as AudioStreamPlayer
		printerr("WK: 按F5 -> ", w.weather_name(),
			" | 环境音 playing=", str(amb.playing),
			" db=", snappedf(amb.volume_db, 0.1),
			" 流=", (amb.stream.resource_path.get_file() if amb.stream != null else "无"))
	printerr("WK: 结束（应回到 晴朗）")
	get_tree().quit(0)
