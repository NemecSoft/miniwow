extends Node3D

## M43 天气验证探针：依次切五种天气，各拍一张真实视角截图。
## 用法：godot --path <项目> res://tools/weather_shot.tscn
## 注意：必须窗口模式（headless 是 dummy 渲染后端，出不了图）。

const OUT := "res://screenshots/m43/weather/"

var _level: Node3D
var _weather: WeatherSystem


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "天气", "blue")
	await get_tree().create_timer(5.0).timeout
	for cl in _level.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for c in _level.find_children("*", "Control", true, false):
		(c as Control).visible = false

	_weather = _level.get_node_or_null("Environment/WeatherSystem") as WeatherSystem
	printerr("WS: weather=", str(_weather))
	if _weather == null:
		get_tree().quit(0)
		return

	var shots := [
		[WeatherSystem.Kind.CLEAR, "w0_clear.png"],
		[WeatherSystem.Kind.RAIN, "w1_rain.png"],
		[WeatherSystem.Kind.STORM, "w2_storm.png"],
		[WeatherSystem.Kind.SNOW, "w3_snow.png"],
		[WeatherSystem.Kind.BLIZZARD, "w4_blizzard.png"],
	]
	for item in shots:
		var kind: int = item[0]
		_weather.set_weather(kind, true)
		var sky = _weather.get("_sky")
		var eb = ""
		if sky != null:
			eb = " sky.sun=" + str(snappedf(float(sky.get("sun_energy")), 0.01)) \
				+ " cloud=" + str(snappedf(float(sky.get("cloud_intensity")), 0.01)) \
				+ " amb=" + str(snappedf(float(sky.get("ambient_energy")), 0.01))
		printerr("WS: 切到 ", _weather.weather_name(), " 雨=", str(_weather.get_node("Rain").emitting),
			" 雪=", str(_weather.get_node("Snow").emitting), " sky=", str(sky != null), eb)
		# 粒子需要时间铺满（雪寿命 9 秒，等 4 秒够看出形态）
		await get_tree().create_timer(4.0).timeout
		await _save(item[1])

	# 额外：暴风雪下再切到雷雨，验证从"雪"切"雨"不会残留
	_weather.set_weather(WeatherSystem.Kind.STORM, true)
	await get_tree().create_timer(2.0).timeout
	await _save("w5_storm_after_snow.png")
	printerr("WS: 结束")
	get_tree().quit(0)


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("WS: img null ", fname)
		return
	var path := ProjectSettings.globalize_path(OUT + fname)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	printerr("WS: 已存 ", fname)
