class_name PlanetAzeroth
extends PlanetProfile

## 艾泽拉斯（M45/M46）
##
## 6 块大陆：卡利姆多中部 / 荆棘谷 / 诺森德 / 奥丹姆 / 东部王国 / 大漩涡群岛
## 面 0 直接复用平面世界 WorldShape（莫高雷草原 → 山脉隘口 → 地狱火红土），
## 所以村庄、湖泊、台地、火山、道路全部原样落在球面上。

func _configure() -> void:
	id = "azeroth"
	display_name = "艾泽拉斯"
	radius = 2200.0
	sea_floor = -46.0
	sea_level = -40.0
	plane_scale = 1150.0
	land_edge = 0.86
	land_sea = 0.995
	has_ocean = true
	has_lava = true
	uses_zone_mask = true
	uses_zone_blend = true
	edge_ridge_height = 96.0
	edge_ridge_var = 78.0
	edge_jag = 0.0
	decor_style = "azeroth"

	face_colors = [
		Color(0.30, 0.44, 0.19),   # 0 卡利姆多（草原，实际由遮罩决定）
		Color(0.11, 0.27, 0.13),   # 1 荆棘谷（丛林）
		Color(0.78, 0.87, 0.94),   # 2 诺森德（冰原）
		Color(0.72, 0.58, 0.36),   # 3 奥丹姆（沙漠）
		Color(0.30, 0.44, 0.19),   # 4 东部王国（温带）
		Color(0.20, 0.34, 0.28),   # 5 群岛
	]
	face_var = [0.35, 0.45, 0.20, 0.32, 0.38, 0.40]

	sand_color = Color(0.78, 0.70, 0.50)
	rock_color = Color(0.42, 0.40, 0.37)
	rock_dark = Color(0.26, 0.25, 0.24)
	snow_color = Color(0.93, 0.95, 1.0)
	lava_color = Color(1.0, 0.34, 0.05)
	void_color = Color(0.05, 0.09, 0.14)
	snow_line = 150.0
	rock_line = 44.0
	snow_amount = 0.0
	lava_emission = 1.9

	sky_a = {
		"day_tint": Color(0.60, 0.76, 1.0),
		"horizon": Color(0.94, 0.97, 1.0),
		"sun_intensity": 12.5,
		"mie": 0.16,
		"cumulus": 0.52,
		"fog_density": 0.00042,
		"fog_light": Color(0.74, 0.86, 1.0),
		"ambient": Color(0.52, 0.66, 1.0),
	}
	sky_b = {
		"day_tint": Color(1.0, 0.62, 0.40),
		"horizon": Color(0.98, 0.56, 0.34),
		"sun_intensity": 10.0,
		"mie": 0.46,
		"cumulus": 0.30,
		"fog_density": 0.00105,
		"fog_light": Color(0.96, 0.62, 0.42),
		"ambient": Color(0.86, 0.54, 0.40),
	}
	sun_zenith = 0.74


func face_height(face: int, u: float, v: float, d: Vector3) -> float:
	match face:
		0: return _face_kalimdor(u, v, d)
		1: return _face_jungle(u, v, d)
		2: return _face_ice(u, v, d)
		3: return _face_desert(u, v, d)
		4: return _face_plains(u, v, d)
		_: return _face_isles(u, v, d)


## 面 0：卡利姆多中部 —— 直接复用平面世界（莫高雷 → 隘口 → 地狱火）
func _face_kalimdor(u: float, v: float, _d: Vector3) -> float:
	return WorldShape.height_at(u * plane_scale, v * plane_scale)


## 面 1：荆棘谷 —— 热带丛林，河谷下切，藤蔓高树
func _face_jungle(u: float, v: float, d: Vector3) -> float:
	var base: float = 34.0 + nz(_n3, d, 0.9) * 30.0
	# 河谷：两条正弦状低洼带
	var river: float = absf(sin(u * 3.4 + 0.7)) * 0.5 + absf(sin(v * 2.6 - 1.2)) * 0.5
	base -= _sstep(0.32, 0.06, river) * 40.0
	# 丛林台地
	base += _sstep(0.30, 0.62, nz(_n3c, d, 0.35) * 0.5 + 0.5) * 54.0
	# 中尺度起伏
	base += nz(_n3b, d, 0.55) * 9.0
	return base


## 面 2：诺森德 —— 冰原雪山
func _face_ice(u: float, v: float, d: Vector3) -> float:
	var base: float = 40.0 + nz(_n3, d, 0.8) * 34.0
	# 冰脊：高频尖锐山脊
	var ridged: float = absf(nz(_n3b, d, 1.7))
	base += pow(ridged, 0.7) * 165.0
	# 冰川谷
	base -= _sstep(0.5, 0.1, absf(sin(u * 2.2) * cos(v * 1.8))) * 34.0
	return base


## 面 3：奥丹姆 —— 沙漠沙丘 + 砂岩台地
func _face_desert(u: float, v: float, d: Vector3) -> float:
	var base: float = 26.0 + nz(_n3, d, 1.1) * 22.0
	# 沙丘：长条波纹（用切平面坐标做方向性条纹）
	base += (sin(u * 26.0 + nz(_n3b, d, 1.2) * 3.0) * 0.5 + 0.5) * 11.0
	# 砂岩台地（方山）
	var mesa: float = nz(_n3c, d, 0.30) * 0.5 + 0.5
	base += _sstep(0.62, 0.78, mesa) * 96.0
	return base


## 面 4：东部王国 —— 温带丘陵、森林、农田
func _face_plains(u: float, v: float, d: Vector3) -> float:
	var base: float = 20.0 + nz(_n3, d, 0.85) * 22.0
	base += _sstep(0.45, 0.85, nz(_n3c, d, 0.40) * 0.5 + 0.5) * 46.0
	# 一条大河
	var rv: float = absf(v - sin(u * 2.1) * 0.28)
	base -= _sstep(0.10, 0.02, rv) * 26.0
	base += nz(_n3b, d, 0.6) * 7.0
	return base


## 面 5：大漩涡群岛 —— 破碎群岛、礁石
func _face_isles(u: float, v: float, d: Vector3) -> float:
	var base: float = -14.0 + nz(_n3, d, 1.3) * 26.0
	# 岛屿：低频噪声取正部分
	var isle: float = nz(_n3c, d, 0.50) * 0.5 + 0.5
	base += _sstep(0.55, 0.80, isle) * 64.0
	# 大漩涡中心（面中心下沉）
	var c: float = sqrt(u * u + v * v)
	base -= _sstep(0.34, 0.0, c) * 34.0
	return base
