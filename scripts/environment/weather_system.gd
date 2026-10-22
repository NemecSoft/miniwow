class_name WeatherSystem
extends Node3D

## M43：完整天气系统（晴 / 小雨 / 雷雨 / 降雪 / 暴风雪）。
##
## 前身是 M40 的 StormSystem（只有"雨 + 闪电"一条路，而且从未挂进关卡、
## 找 Environment 的路径也写错了 —— 它找 "WorldEnvironment"，实际节点是
## "Environment/Sky3D"，所以雾增强一直是空转）。本次重写为参数化五档天气：
##
##   · 粒子：雨与雪共用两个 GPUParticles3D，切天气只改 amount/速度/风向，
##     不重建节点（重建会有一帧全空的闪烁）。发射盒始终跟随相机。
##   · 环境：雾密度 / 色调曝光 / 环境光按预设做 0.9s 过渡，硬切会很假。
##   · 声音：雨声/风声是程序化合成的无缝循环（tools/make_weather_sfx.py），
##     走 Ambient 总线，与 BGM 的 Music 总线分开，玩家可以单独调。
##   · 雷雨：相机处 OmniLight 闪白 + 延迟雷声（先见闪电后听雷，符合物理）。
##
## 切换方式：F5 循环五档，F6 直接回晴；也可以代码调 set_weather(Kind.XXX)。

signal weather_changed(kind: int)

enum Kind { CLEAR, RAIN, STORM, SNOW, BLIZZARD }

const NAMES := ["晴朗", "小雨", "雷雨", "降雪", "暴风雪"]

## 各档天气参数
##   rain/snow：粒子强度倍率（0 = 关）
##   wind：横向风速（米/秒），决定雨丝倾角与雪的水平漂移
##   fog：雾密度倍率（基准取关卡初始值）
##   exposure：色调曝光倍率
##   sun/ambient/cloud：太阳直射强度 / 环境光 / 云量倍率
##     —— 阴天必须真的"没有直射阳光"，否则雨点落在阳光广场上非常违和
const PRESET := {
	Kind.CLEAR:    {"rain": 0.0, "snow": 0.0, "wind": 0.0,  "fog": 1.0, "exposure": 1.00,
		"sun": 1.00, "ambient": 1.00, "cloud": 1.0, "sfx": &"",     "db": -60.0},
	Kind.RAIN:     {"rain": 0.60, "snow": 0.0, "wind": 3.0, "fog": 1.7, "exposure": 0.86,
		"sun": 0.50, "ambient": 0.78, "cloud": 0.70, "sfx": &"rain", "db": -11.0},
	Kind.STORM:    {"rain": 1.0, "snow": 0.0, "wind": 7.0,  "fog": 2.8, "exposure": 0.60,
		"sun": 0.22, "ambient": 0.52, "cloud": 0.46, "sfx": &"rain", "db": -3.0},
	Kind.SNOW:     {"rain": 0.0, "snow": 0.8, "wind": 0.8,  "fog": 1.6, "exposure": 0.96,
		"sun": 0.62, "ambient": 0.90, "cloud": 0.85, "sfx": &"wind", "db": -19.0},
	Kind.BLIZZARD: {"rain": 0.0, "snow": 1.7, "wind": 15.0, "fog": 3.4, "exposure": 0.62,
		"sun": 0.32, "ambient": 0.58, "cloud": 0.58, "sfx": &"wind", "db": -5.0},
}

## 天空染色目标（写 SkyDome 属性，直接进 shader）
## 只调 sun_energy / ambient_energy 是**不够**的——天空穹顶的颜色由大气散射 shader 的
## atm_day_tint 决定，太阳光强弱只影响地面受光。实测：只降 sun_energy 的话，
## 暴雨天仍是湛蓝天空 + 白云，违和感极强。必须同时压暗天空底色并拉满云量。
const SKY_TARGET := {
	Kind.CLEAR:    {"tint": Color(0.65, 0.79, 1.00), "atm_sun": 12.0, "disk": 30.0, "cumulus": 0.42, "cirrus": 0.45},
	Kind.RAIN:     {"tint": Color(0.47, 0.52, 0.58), "atm_sun": 3.0,  "disk": 0.0,  "cumulus": 0.80, "cirrus": 0.78},
	Kind.STORM:    {"tint": Color(0.29, 0.32, 0.37), "atm_sun": 0.8,  "disk": 0.0,  "cumulus": 0.92, "cirrus": 0.90},
	Kind.SNOW:     {"tint": Color(0.66, 0.70, 0.76), "atm_sun": 4.5,  "disk": 0.0,  "cumulus": 0.82, "cirrus": 0.80},
	Kind.BLIZZARD: {"tint": Color(0.57, 0.59, 0.63), "atm_sun": 2.0,  "disk": 0.0,  "cumulus": 0.92, "cirrus": 0.90},
}

## 发射盒半径（米）：粒子只在相机周围这个盒子内，超出靠雾遮住
const BOX_RADIUS := 32.0
const BOX_HEIGHT := 40.0
const RAIN_MAX := 6000
const SNOW_MAX := 5200

var _kind: int = Kind.CLEAR
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _rain_pm: ParticleProcessMaterial
var _snow_pm: ParticleProcessMaterial
var _flash: OmniLight3D
var _light_timer: Timer
var _ambient: AudioStreamPlayer
var _env: Environment
var _base_fog := -1.0
var _base_exposure := 1.0
var _storm_active := false
var _sky: Node = null
var _sky_base := {}
## 地形材质缓存：雪天要给 terrain_grass.gdshader 写 snow_amount 做地面积雪。
## 地形网格是运行时建的（terrain_starter 延迟 1.5s + 后台 region 加载），
## 所以不能在 _ready 缓存，改为首次需要时再找 + 找不到就低频重试。
var _ground_mats: Array[ShaderMaterial] = []
var _ground_probe := 0.0
var _warned_missing_sfx := false

const SFX_LIBRARY := {
	&"rain": "res://assets/audio/weather/weather_rain.ogg",
	&"wind": "res://assets/audio/weather/weather_wind.ogg",
}


func _ready() -> void:
	_build_rain()
	_build_snow()
	_build_lightning()
	_build_ambient()
	call_deferred("_cache_environment")
	set_weather(Kind.CLEAR, true)


# ===== 粒子构建 =====

## 雨：细长四边形 + 固定 Y 轴 billboard（永远竖直），暗色半透明才在亮天可见
func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain_pm = ParticleProcessMaterial.new()
	_rain_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_pm.emission_box_extents = Vector3(BOX_RADIUS, BOX_HEIGHT * 0.5, BOX_RADIUS)
	_rain_pm.direction = Vector3(0, -1, 0)
	_rain_pm.spread = 3.0
	_rain_pm.initial_velocity_min = 20.0
	_rain_pm.initial_velocity_max = 28.0
	_rain_pm.gravity = Vector3(0, -9.8, 0)
	_rain.process_material = _rain_pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.48, 0.58, 0.72, 0.52)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_rain.material_override = mat
	var q := QuadMesh.new()
	q.size = Vector2(0.085, 1.15)
	_rain.draw_pass_1 = q
	_rain.amount = RAIN_MAX
	# 铁律：visibility_aabb 默认仅 8 米，大发射盒会被整体剔除不渲染
	_rain.visibility_aabb = AABB(Vector3(-BOX_RADIUS - 4, -BOX_HEIGHT, -BOX_RADIUS - 4),
		Vector3(BOX_RADIUS * 2 + 8, BOX_HEIGHT * 2, BOX_RADIUS * 2 + 8))
	_rain.lifetime = 1.6
	_rain.emitting = false
	add_child(_rain)


## 雪：柔光圆点 + 慢速下落 + 湍流飘摆，朝相机的 billboard
func _build_snow() -> void:
	_snow = GPUParticles3D.new()
	_snow.name = "Snow"
	_snow_pm = ParticleProcessMaterial.new()
	_snow_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_snow_pm.emission_box_extents = Vector3(BOX_RADIUS, BOX_HEIGHT * 0.5, BOX_RADIUS)
	_snow_pm.direction = Vector3(0, -1, 0)
	_snow_pm.spread = 12.0
	_snow_pm.initial_velocity_min = 1.1
	_snow_pm.initial_velocity_max = 2.4
	_snow_pm.gravity = Vector3(0, -0.55, 0)
	# 湍流是"雪不是直线掉"的关键：小幅随机扰动
	_snow_pm.turbulence_enabled = true
	_snow_pm.turbulence_noise_strength = 1.4
	_snow_pm.turbulence_noise_scale = 6.0
	_snow_pm.turbulence_influence_min = 0.05
	_snow_pm.turbulence_influence_max = 0.22
	_snow.process_material = _snow_pm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _make_snow_texture(48)
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.92)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.vertex_color_use_as_albedo = false
	# 阴天下白色雪片与灰天空对比度极低（实测几乎看不见），给一点自发光把雪"提亮"
	mat.emission_enabled = true
	mat.emission = Color(0.92, 0.95, 1.0)
	mat.emission_energy_multiplier = 0.45
	_snow.material_override = mat
	var q := QuadMesh.new()
	q.size = Vector2(0.34, 0.34)
	_snow.draw_pass_1 = q
	_snow.amount = SNOW_MAX
	_snow.visibility_aabb = _rain.visibility_aabb
	_snow.lifetime = 9.0
	_snow.emitting = false
	add_child(_snow)


## 程序化雪片贴图：高斯柔光核，边缘完全透明（硬边方块会像"纸屑"）
func _make_snow_texture(size: int) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	var sigma := half * 0.42
	for y in size:
		for x in size:
			var dx := float(x) + 0.5 - half
			var dy := float(y) + 0.5 - half
			var d2 := dx * dx + dy * dy
			var a := exp(-d2 / (2.0 * sigma * sigma))
			# 中心压平一点点，避免像发光球
			a = clampf(a * 1.06, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


func _build_lightning() -> void:
	_flash = OmniLight3D.new()
	_flash.name = "LightningFlash"
	_flash.light_energy = 0.0
	_flash.omni_range = 90.0
	_flash.light_color = Color(0.86, 0.90, 1.0)
	add_child(_flash)
	_light_timer = Timer.new()
	_light_timer.one_shot = true
	_light_timer.timeout.connect(_on_lightning)
	add_child(_light_timer)


func _build_ambient() -> void:
	_ambient = AudioStreamPlayer.new()
	_ambient.name = "WeatherAmbient"
	_ambient.bus = &"Ambient"
	_ambient.volume_db = -60.0
	add_child(_ambient)


func _cache_environment() -> void:
	_sky = _find_sky()
	_env = _find_env()
	if _env != null:
		_base_fog = _env.fog_density
		var e = _env.get("tonemap_exposure")
		_base_exposure = float(e) if e != null else 1.0
		if _base_fog <= 0.0:
			_base_fog = 0.0004
	# Sky3D（addon）的太阳/环境光/云量都是 setter 转发到 SkyDome，
	# 记录初值后按倍率缩放，天气切换才能真正"阴下来"
	if _sky != null:
		_sky_base = {
			"sun": float(_sky.get("sun_energy")) if _sky.get("sun_energy") != null else 1.0,
			"ambient": float(_sky.get("ambient_energy")) if _sky.get("ambient_energy") != null else 1.0,
			"cloud": float(_sky.get("cloud_intensity")) if _sky.get("cloud_intensity") != null else 0.6,
		}


## 关键修正两处：
## ① 老代码找 "WorldEnvironment" 绝对路径，而实际节点名是 "Environment/Sky3D"；
## ② 不能只查 current_scene —— 探针/联机场景里关卡常是手动 add_child 的，
##    不是 current_scene，那样会找不到天空，天气永远只改粒子不改环境。
## 现在从自身祖先链起找（天气节点就挂在 Environment 下，兄弟即 Sky3D），再全局兜底。
func _find_sky() -> Node:
	var n: Node = self
	while n != null:
		if n is WorldEnvironment:
			return n
		for c in n.get_children():
			if c is WorldEnvironment:
				return c
		n = n.get_parent()
	var root := get_tree().root
	if root == null:
		return null
	for n2 in root.find_children("*", "WorldEnvironment", true, false):
		return n2
	return null


func _find_env() -> Environment:
	var sky := _sky if _sky != null else _find_sky()
	if sky is WorldEnvironment:
		return (sky as WorldEnvironment).environment
	return null


# ===== 切换天气 =====

func set_weather(kind: int, instant := false) -> void:
	kind = clampi(kind, Kind.CLEAR, Kind.BLIZZARD)
	_kind = kind
	var p: Dictionary = PRESET[kind]
	_apply_particles(p)
	_apply_sky(kind)
	_apply_environment(p, instant)
	_apply_ground_snow(kind)
	_apply_ambient_sfx(p, instant)
	_storm_active = kind == Kind.STORM
	if _storm_active:
		_start_next_lightning()
	else:
		if _light_timer != null:
			_light_timer.stop()
		if _flash != null:
			_flash.light_energy = 0.0
	weather_changed.emit(kind)


func cycle_weather() -> int:
	set_weather((_kind + 1) % NAMES.size())
	return _kind


func get_weather() -> int:
	return _kind


func weather_name() -> String:
	return NAMES[_kind]


func _apply_particles(p: Dictionary) -> void:
	var rain_ratio: float = p["rain"]
	var snow_ratio: float = p["snow"]
	var wind: float = p["wind"]

	if rain_ratio > 0.0:
		_rain.amount = maxi(120, int(RAIN_MAX * rain_ratio))
		_rain_pm.emission_box_extents = Vector3(BOX_RADIUS, BOX_HEIGHT * 0.5, BOX_RADIUS)
		# 斜雨：风向给一个水平初速，视觉上雨丝会倾斜（billboard 固定 Y 但整体位移可见）
		_rain_pm.direction = Vector3(-wind * 0.11, -1.0, 0.0).normalized()
		_rain_pm.initial_velocity_min = 20.0 + wind * 0.6
		_rain_pm.initial_velocity_max = 28.0 + wind * 0.9
		_rain.emitting = true
	else:
		_rain.emitting = false

	if snow_ratio > 0.0:
		_snow.amount = maxi(120, int(SNOW_MAX * snow_ratio))
		_snow_pm.emission_box_extents = Vector3(BOX_RADIUS, BOX_HEIGHT * 0.5, BOX_RADIUS)
		# 暴风雪：水平风压过下落速度 → 雪几乎横着飞
		_snow_pm.initial_velocity_min = 1.1 + wind * 0.15
		_snow_pm.initial_velocity_max = 2.4 + wind * 0.35
		_snow_pm.gravity = Vector3(-wind * 0.85, -0.55, wind * 0.18)
		_snow_pm.turbulence_noise_strength = 1.4 if wind < 5.0 else 4.5
		_snow.emitting = true
	else:
		_snow.emitting = false


## 天空染色：晴/雨/雪各自的底色、太阳散射、云量。
## 直接写 SkyDome 的 @export 属性（setter 会同步到 sky_material 的 shader 参数）。
func _apply_sky(kind: int) -> void:
	if _sky == null:
		return
	var dome = _sky.get("sky")
	if dome == null:
		return
	var t: Dictionary = SKY_TARGET[kind]
	dome.set("atm_day_tint", t["tint"])
	dome.set("atm_sun_intensity", t["atm_sun"])
	dome.set("sun_disk_intensity", t["disk"])
	dome.set("cumulus_coverage", t["cumulus"])
	dome.set("cirrus_coverage", t["cirrus"])


## 地面积雪：只作用于自建地形网格（terrain_grass.gdshader）。
## 广场地台本来就是浅色地砖，不需要也不该盖雪。
func _cache_ground_materials() -> void:
	_ground_mats.clear()
	var root := get_tree().root
	if root == null:
		return
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var m := (n as MeshInstance3D).material_override
		if m is ShaderMaterial:
			var sm := m as ShaderMaterial
			if sm.shader != null and sm.shader.resource_path.get_file() == "terrain_grass.gdshader":
				_ground_mats.append(sm)


func _push_ground_snow() -> void:
	var amount := 0.0
	if _kind == Kind.SNOW:
		amount = 0.58
	elif _kind == Kind.BLIZZARD:
		amount = 0.90
	for sm in _ground_mats:
		if is_instance_valid(sm):
			sm.set_shader_parameter("snow_amount", amount)


func _apply_ground_snow(kind: int) -> void:
	if _ground_mats.is_empty() and (kind == Kind.SNOW or kind == Kind.BLIZZARD):
		_cache_ground_materials()
	_push_ground_snow()


func _apply_environment(p: Dictionary, instant: bool) -> void:
	if _env == null:
		_cache_environment()
	if _env == null:
		return
	if _base_fog <= 0.0:
		_base_fog = 0.0004
	var target_fog: float = _base_fog * float(p["fog"])
	var target_exp: float = _base_exposure * float(p["exposure"])
	# 天空：直射太阳、环境光、云量（无过渡——Sky3D 每帧会按时间重算这些值，
	# tween 会被它覆盖，直接设反而稳定）
	if _sky != null and not _sky_base.is_empty():
		_sky.set("sun_energy", float(_sky_base["sun"]) * float(p["sun"]))
		_sky.set("ambient_energy", float(_sky_base["ambient"]) * float(p["ambient"]))
		_sky.set("cloud_intensity", float(_sky_base["cloud"]) * float(p["cloud"]))
	if instant:
		_env.fog_density = target_fog
		_env.set("tonemap_exposure", target_exp)
		return
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_env, "fog_density", target_fog, 0.9)
	t.tween_property(_env, "tonemap_exposure", target_exp, 0.9)


func _apply_ambient_sfx(p: Dictionary, instant: bool) -> void:
	var key: StringName = p["sfx"]
	var target_db: float = p["db"]
	if key == &"" or not SFX_LIBRARY.has(key):
		_fade_ambient(-60.0, 0.6 if not instant else 0.01, true)
		return
	var path: String = SFX_LIBRARY[key]
	var stream := load(path) as AudioStream
	if stream == null:
		# 音频还没生成时不应该打断天气本身——只警告一次
		if not _warned_missing_sfx:
			_warned_missing_sfx = true
			push_warning("WeatherSystem: 环境音缺失 " + path)
		return
	if stream is AudioStreamOggVorbis:
		var ogg := (stream as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		ogg.loop = true
		stream = ogg
	if _ambient.stream != stream:
		_ambient.stream = stream
		_ambient.play()
	_fade_ambient(target_db, 0.9 if not instant else 0.01, false)


func _fade_ambient(target_db: float, duration: float, stop_after: bool) -> void:
	if _ambient == null:
		return
	var t := create_tween()
	t.tween_property(_ambient, "volume_db", target_db, maxf(duration, 0.01))
	if stop_after:
		t.tween_callback(_ambient.stop)


# ===== 闪电 =====

func _start_next_lightning() -> void:
	if not _storm_active:
		return
	_light_timer.wait_time = randf_range(3.5, 11.0)
	_light_timer.start()


func _on_lightning() -> void:
	if not _storm_active:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_flash.global_position = cam.global_position
	var t := create_tween()
	# 双闪更像真实闪电（先强后弱两次）
	t.tween_property(_flash, "light_energy", 7.0, 0.04)
	t.tween_property(_flash, "light_energy", 1.2, 0.10)
	t.tween_property(_flash, "light_energy", 5.0, 0.05)
	t.tween_property(_flash, "light_energy", 0.0, 0.55)
	# 先见闪电后听雷：延迟 0.4~1.6 秒
	var delay := randf_range(0.4, 1.6)
	await get_tree().create_timer(delay).timeout
	if cam != null and is_instance_valid(cam):
		SfxManager.play_3d(&"thunder", cam.global_position, 60.0)
	_start_next_lightning()


# ===== 每帧：粒子盒跟随相机 =====

func _process(delta: float) -> void:
	# 地形材质迟到的兜底：雪天时每 2 秒摸一次，找到为止
	if _ground_mats.is_empty() and (_kind == Kind.SNOW or _kind == Kind.BLIZZARD):
		_ground_probe += delta
		if _ground_probe >= 2.0:
			_ground_probe = 0.0
			_cache_ground_materials()
			_push_ground_snow()
	if not _storm_active and _kind == Kind.CLEAR:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var base := cam.global_position + Vector3(0, BOX_HEIGHT * 0.34, 0)
	if _rain != null and _rain.emitting:
		_rain.global_position = base + Vector3(0, 6.0, 0)
	if _snow != null and _snow.emitting:
		_snow.global_position = base + Vector3(-float(PRESET[_kind]["wind"]) * 1.2, 0, 0)


# ===== 输入：F5 循环切换 / F6 回晴 =====

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).physical_keycode
	if key == KEY_F5:
		cycle_weather()
		get_viewport().set_input_as_handled()
	elif key == KEY_F6:
		set_weather(Kind.CLEAR)
		get_viewport().set_input_as_handled()
