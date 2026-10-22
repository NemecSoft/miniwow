class_name PlanetOutland
extends PlanetProfile

## 外域 / Outland —— 魔兽世界的"火星"（M46）
##
## 【与原版的差别，也是这里的设计原则】
##   魔兽的外域是**德拉诺星球的残骸**：被撕裂后飘在扭曲虚空中，
##   没有完整的大气，边缘直接断掉坠入虚空。所以：
##   · R = 1500（比艾泽拉斯小得多，走一圈只要一半时间）
##   · 没有海洋。sea_floor = -300 是"虚空底"，边缘是 300 米高的断崖
##   · 大陆轮廓用 edge_jag 打碎，不再是规整的方块
##   · 边缘不抬海岸山脉（那是艾泽拉斯的"高山隔开"），而是直接断裂
##   · 天空是橙红/紫罗兰，太阳压得很低（末日感）
##
## 【6 块区域】
##   0 +X 地狱火半岛  红土高原、干裂沟壑、熔岩裂隙、白骨碎丘
##   1 -X 赞加沼泽    低平湿地、巨型蘑菇圆丘
##   2 +Y 纳格兰      翠绿草原、缓丘、峡谷
##   3 -Y 刀锋山      极高石刺、深谷
##   4 +Z 影月谷      紫黑火山灰、邪能绿熔岩
##   5 -Z 虚空风暴    破碎浮岛、大面积沉入虚空

func _configure() -> void:
	id = "outland"
	display_name = "外域"
	radius = 1500.0
	sea_floor = -300.0
	sea_level = -262.0
	plane_scale = 900.0
	land_edge = 0.78
	land_sea = 0.965
	has_ocean = false
	has_lava = true
	uses_zone_mask = false
	uses_zone_blend = false
	# 外域不抬海岸山脉：断崖本身就是分界
	edge_ridge_height = 0.0
	edge_ridge_var = 0.0
	edge_jag = 0.085
	decor_style = "outland"

	face_colors = [
		Color(0.42, 0.17, 0.09),   # 0 地狱火半岛（红土，压深防过曝成米白）
		Color(0.15, 0.33, 0.29),   # 1 赞加沼泽（湿地青绿）
		Color(0.31, 0.50, 0.20),   # 2 纳格兰（翠绿）
		Color(0.40, 0.33, 0.27),   # 3 刀锋山（灰褐石）
		Color(0.34, 0.20, 0.34),   # 4 影月谷（紫黑，提亮以免渲成死黑）
		Color(0.32, 0.19, 0.44),   # 5 虚空风暴（紫）
	]
	face_var = [0.40, 0.45, 0.36, 0.30, 0.42, 0.50]

	sand_color = Color(0.66, 0.56, 0.42)
	rock_color = Color(0.28, 0.22, 0.18)   # 浅灰岩在太空视角会糊成一片白，压深
	rock_dark = Color(0.22, 0.16, 0.16)
	snow_color = Color(0.86, 0.84, 0.90)
	lava_color = Color(1.0, 0.30, 0.04)
	lava_color_b = Color(0.35, 1.0, 0.22)
	void_color = Color(0.07, 0.04, 0.13)
	# 外域没有雪。原来 300 这条线会被刀锋山（尖刺到 285）撞上，从太空看
	# 是整个球顶一圈白毛（用户 2026-10-22 退单的那张 c1 图里的毛刺）。
	snow_line = 4000.0
	rock_line = 215.0
	snow_amount = 0.0
	lava_emission = 2.4

	# 光照标定（M46 实测第二代）：
	#   第一版压得太狠（sun 0.82 / ambient 0.52 / zenith 0.46），直射光总量只有
	#   艾泽拉斯的 40%，暗色材质的面（虚空风暴）直接全黑成剪影。
	#   现在把太阳抬高 + 直射提上来，环境光适度，让明暗梯度回来。
	sun_energy = 0.95
	ambient_energy = 0.45
	tonemap_exposure = 0.86
	sky_exposure = 0.96
	bg_energy = 1.00

	sky_a = {
		"day_tint": Color(0.98, 0.66, 0.52),
		"horizon": Color(0.96, 0.70, 0.52),
		"sun_intensity": 9.5,
		"mie": 0.58,
		"cumulus": 0.26,
		"fog_density": 0.00125,
		"fog_light": Color(0.88, 0.58, 0.50),
		"ambient": Color(0.80, 0.54, 0.48),
	}
	# 外域不分区插值，sky_b 仅作占位
	sky_b = {}
	sun_zenith = 0.64
	noise_seed = 880231


func face_height(face: int, u: float, v: float, d: Vector3) -> float:
	match face:
		0: return _face_hellfire(u, v, d)
		1: return _face_zangar(u, v, d)
		2: return _face_nagrand(u, v, d)
		3: return _face_blade(u, v, d)
		4: return _face_shadowmoon(u, v, d)
		_: return _face_netherstorm(u, v, d)


## 面 0：地狱火半岛 —— 红土高原 + 干裂沟壑 + 熔岩裂隙
func _face_hellfire(u: float, v: float, d: Vector3) -> float:
	var base: float = 30.0 + nz(_n3, d, 0.85) * 28.0
	# 高原台地（大幅抬升，形成方山/台地群）
	var plat: float = nz(_n3c, d, 0.32) * 0.5 + 0.5
	base += _sstep(0.42, 0.64, plat) * 96.0
	# 熔岩裂谷：蜿蜒下切
	var crev: float = absf(sin(u * 5.4 + nz(_n3b, d, 1.1) * 2.6))
	base -= _sstep(0.17, 0.0, crev) * 62.0
	# 骨白碎丘
	var bone: float = nz(_n3b, d, 1.8) * 0.5 + 0.5
	base += _sstep(0.68, 0.88, bone) * 18.0
	return base


## 面 1：赞加沼泽 —— 低平湿地 + 巨型蘑菇圆丘
func _face_zangar(u: float, v: float, d: Vector3) -> float:
	var base: float = 4.0 + nz(_n3, d, 0.8) * 13.0
	# 蘑菇林圆丘（低频噪声抬成圆顶）
	var dome: float = nz(_n3c, d, 0.42) * 0.5 + 0.5
	base += _sstep(0.54, 0.78, dome) * 74.0
	# 积水洼地
	var pool: float = nz(_n3b, d, 0.9) * 0.5 + 0.5
	base -= _sstep(0.44, 0.16, pool) * 22.0
	return base


## 面 2：纳格兰 —— 翠绿草原 + 缓丘 + 峡谷
func _face_nagrand(u: float, v: float, d: Vector3) -> float:
	var base: float = 30.0 + nz(_n3, d, 0.75) * 26.0
	base += _sstep(0.44, 0.86, nz(_n3c, d, 0.38) * 0.5 + 0.5) * 58.0
	# 一条大峡谷（浮空岛就悬在它上方）
	var cny: float = absf(v - sin(u * 1.7 + 0.4) * 0.34)
	base -= _sstep(0.13, 0.02, cny) * 54.0
	return base


## 面 3：刀锋山 —— 极高石刺 + 深谷
func _face_blade(u: float, v: float, d: Vector3) -> float:
	var base: float = 22.0 + nz(_n3, d, 0.9) * 20.0
	# 石刺：绝对值噪声开方 → 高频尖峰
	var ridged: float = absf(nz(_n3b, d, 2.0))
	base += pow(ridged, 0.42) * 285.0
	# 深谷
	var gully: float = absf(sin(u * 3.2) * sin(v * 2.8))
	base -= _sstep(0.30, 0.04, gully) * 62.0
	return base


## 面 4：影月谷 —— 紫黑火山灰 + 邪能裂隙 + 火山锥
func _face_shadowmoon(u: float, v: float, d: Vector3) -> float:
	var base: float = 22.0 + nz(_n3, d, 0.9) * 24.0
	# 邪能裂隙
	var crev: float = absf(sin(u * 4.6 + v * 1.8 + nz(_n3b, d, 1.0) * 1.8))
	base -= _sstep(0.13, 0.0, crev) * 48.0
	# 火山锥
	var vol: float = nz(_n3c, d, 0.34) * 0.5 + 0.5
	base += _sstep(0.58, 0.84, vol) * 118.0
	return base


## 面 5：虚空风暴 —— 破碎浮岛，大面积沉入虚空
func _face_netherstorm(u: float, v: float, d: Vector3) -> float:
	var base: float = -70.0 + nz(_n3, d, 1.1) * 34.0
	# 岛块：低频噪声高点
	var isle: float = nz(_n3c, d, 0.45) * 0.5 + 0.5
	base += _sstep(0.58, 0.82, isle) * 124.0
	# 岛上的碎裂台阶（离散化高度）
	var step_n: float = nz(_n3b, d, 1.4) * 0.5 + 0.5
	base += floorf(step_n * 5.0) * 6.5
	return base
