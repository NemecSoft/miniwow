class_name PlanetProfile
extends RefCounted

## 星球配置基类（M46：一颗星球 = 一份 Profile）
##
## 【为什么要抽这层】
##   M45 的 Planet 是一堆 static const + static func，只够描述一颗艾泽拉斯。
##   要加"外域"这颗完全不同的星球（没有海洋、更小、更破碎），又不能让
##   player.gd / monster.gd / level.gd 里几十处 `Planet.xxx` 全部改写，
##   所以：Planet 降级成**门面**（facade），内部持有一份 Profile。
##   调用点写 `Planet.height_at(d)`，实际执行的是 `_profile.height_at(d)`。
##
## 【子类只需实现】
##   · `face_height()`：6 个面各自的地形函数
##   · `_configure()`：填色调 / 天空 / 海平面 / 植被风格等数据
##   其余（立方球参数化、海岸过渡、大陆遮罩、法线吸附）全部在基类完成。

# ===== 形制参数（由子类在 _configure 里覆盖）=====

var id := "azeroth"
var display_name := "艾泽拉斯"

## 星球半径（米）。地平线距离 d ≈ sqrt(2·R·h)
var radius := 2200.0
## 海底高度（相对 radius）。无海洋星球这里是"虚空底"
var sea_floor := -46.0
## 水面高度（相对 radius）
var sea_level := -40.0
## 平面世界坐标 → 面内 uv 的缩放（世界 ±N 米映射到 uv ±1）
var plane_scale := 1150.0
## 大陆遮罩：edge 超过 land_edge 开始沉海，到 land_sea 全海
var land_edge := 0.86
var land_sea := 0.995

## 有没有海洋。false = 边缘直接坠入虚空（外域是星球残骸）
var has_ocean := true
## 有没有熔岩（熔岩在 shader 里走自发光通道）
var has_lava := true
## 面 0 是否使用平面世界遮罩（道路/草原/红土/熔岩，仅艾泽拉斯的卡利姆多）
var uses_zone_mask := true
## 面 1（uv 0.5~1.0 区间）是否用 zone_factor 做双主题插值
var uses_zone_blend := true

## 海岸山脉：块与块之间先抬成高山再沉海（"高山隔开"）
var edge_ridge_height := 96.0
var edge_ridge_var := 78.0
## 边缘抖动：让大陆轮廓不规则而不是完美方块
var edge_jag := 0.0

# ===== 视觉 =====

## 6 个面的主色
var face_colors: Array[Color] = []
## 6 个面的明度变化幅度（0~1，越大越花）
var face_var: Array[float] = []
var sand_color := Color(0.78, 0.70, 0.50)
var rock_color := Color(0.42, 0.40, 0.37)
var rock_dark := Color(0.26, 0.25, 0.24)
var snow_color := Color(0.93, 0.95, 1.0)
var lava_color := Color(1.0, 0.34, 0.05)
## 第二套熔岩色（外域：影月谷的邪能绿熔岩 vs 地狱火的橙红）
var lava_color_b := Color(0.35, 1.0, 0.22)
var void_color := Color(0.10, 0.06, 0.16)
var snow_line := 150.0
var rock_line := 44.0
var snow_amount := 0.0
var lava_emission := 1.9

## 天空：两套参数（a = 温和区 / b = 炽热区）。uses_zone_blend=false 时只用 a
var sky_a := {}
var sky_b := {}
## 太阳方向权重：axis = up*zenith + north*(1-zenith)
var sun_zenith := 0.74
## 直射光与环境光强度（外域压暗，避免过曝发白）
var sun_energy := 1.18
var ambient_energy := 1.0
var tonemap_exposure := 1.22
var sky_exposure := 1.45
var bg_energy := 1.55

## 植被风格标识（forest_starter 按此分派撒点逻辑）
var decor_style := "azeroth"

## 噪声种子（换一种子 = 换一套地形纹理，避免两颗星球长得像）
var noise_seed := 90210

# ===== 噪声（每颗星球独立种子，避免两张地图长得像）=====

var _n3: FastNoiseLite
var _n3b: FastNoiseLite
var _n3c: FastNoiseLite


func _init() -> void:
	_configure()
	_build_noise()


## 子类覆盖：填参数
func _configure() -> void:
	pass


## 子类覆盖：6 个面各自的地形函数（返回相对 radius 的高度，负值 = 水下/虚空）
func face_height(_face: int, _u: float, _v: float, _d: Vector3) -> float:
	return 0.0


func _build_noise() -> void:
	## 【M46 事故修复 · 噪声标定】
	## 采样坐标必须是「方向 × 星球半径（米）」，频率必须是「1/波长（米）」。
	## 旧写法用「方向 × 105~620」这种魔法倍数配 frequency 0.0009~0.0032，
	## 换算下来整个球面只覆盖 0.2 个噪声周期 → 除了复用平面世界的面 0，
	## 其余 5 个面全是一块缓慢起伏的饼（实测截图为证）。
	_n3 = FastNoiseLite.new()    # 主地形：波长 ≈ 180m
	_n3.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n3.frequency = 0.0055
	_n3.fractal_octaves = 4
	_n3.fractal_gain = 0.5
	_n3.seed = noise_seed

	_n3b = FastNoiseLite.new()   # 细节/山脊/裂谷：波长 ≈ 45m
	_n3b.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n3b.frequency = 0.022
	_n3b.fractal_octaves = 3
	_n3b.seed = noise_seed + 1207

	_n3c = FastNoiseLite.new()   # 大尺度分区：波长 ≈ 620m
	_n3c.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n3c.frequency = 0.0016
	_n3c.fractal_octaves = 2
	_n3c.seed = noise_seed + 4409


## 球面噪声采样：坐标 = 方向 × 半径（米），配合上面按「每米」标定的频率，
## 于是 noise 的波长就是真实的地面米数。scale 用于按面微调粗细。
func nz(n: FastNoiseLite, d: Vector3, scale: float = 1.0) -> float:
	var k: float = radius * scale
	return n.get_noise_3d(d.x * k, d.y * k, d.z * k)


func _sstep(e0: float, e1: float, x: float) -> float:
	if is_equal_approx(e0, e1):
		return 0.0 if x < e0 else 1.0
	var t: float = clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ===== 高度 =====

## 某方向的相对高度（米，相对 radius）。负值 = 海底 / 虚空。
func height_at(dir: Vector3) -> float:
	var d := dir.normalized()
	var fu := Planet.face_uv(d)
	var face: int = int(fu[0])
	var u: float = fu[1]
	var v: float = fu[2]
	var edge: float = maxf(absf(u), absf(v))

	# 边缘抖动：让大陆边界不是笔直的方框
	if edge_jag > 0.0:
		var j: float = _n3b.get_noise_3d(d.x * 26.0, d.y * 26.0, d.z * 26.0)
		edge += j * edge_jag

	var h: float = face_height(face, u, v, d)

	# 海岸山脉（艾泽拉斯：块与块之间高山隔开）
	if edge_ridge_height > 0.0:
		var ridge: float = _sstep(0.50, 0.64, edge) * (1.0 - _sstep(0.66, 0.78, edge))
		var rn: float = _n3b.get_noise_3d(d.x * 42.0, d.y * 42.0, d.z * 42.0) * 0.5 + 0.5
		h += ridge * (edge_ridge_height + edge_ridge_var * rn)

	# 大陆遮罩：边缘沉下去 → 6 面接缝处都是低地，天然无缝
	var land: float = 1.0 - _sstep(land_edge, land_sea, edge)
	h = lerpf(sea_floor, h, land)

	if not is_finite(h):
		return 0.0
	return h


# ===== shader 参数打包 =====

func shader_params() -> Dictionary:
	var cols := PackedVector3Array()
	var vars := PackedFloat32Array()
	for i in 6:
		var c: Color = face_colors[i] if i < face_colors.size() else Color(0.4, 0.5, 0.3)
		cols.append(Vector3(c.r, c.g, c.b))
		vars.append(face_var[i] if i < face_var.size() else 0.35)
	return {
		"planet_radius": radius,
		"sea_level": sea_level,
		"has_ocean": 1.0 if has_ocean else 0.0,
		"has_lava": 1.0 if has_lava else 0.0,
		"uses_zone_mask": 1.0 if uses_zone_mask else 0.0,
		"face_col": cols,
		"face_var": vars,
		"sand_color": Vector3(sand_color.r, sand_color.g, sand_color.b),
		"rock_color": Vector3(rock_color.r, rock_color.g, rock_color.b),
		"rock_dark": Vector3(rock_dark.r, rock_dark.g, rock_dark.b),
		"snow_color": Vector3(snow_color.r, snow_color.g, snow_color.b),
		"lava_color": Vector3(lava_color.r, lava_color.g, lava_color.b),
		"void_color": Vector3(void_color.r, void_color.g, void_color.b),
		"snow_line": snow_line,
		"rock_line": rock_line,
		"snow_amount": snow_amount,
		"lava_emission": lava_emission,
	}


## 天空参数按 t（0 = a 套 / 1 = b 套）插值
func sky_at(t: float) -> Dictionary:
	if not uses_zone_blend or sky_b.is_empty():
		return sky_a.duplicate()
	var out := {}
	for k in sky_a:
		var va: Variant = sky_a[k]
		var vb: Variant = sky_b.get(k, va)
		if va is Color:
			out[k] = (va as Color).lerp(vb as Color, t)
		elif va is float or va is int:
			out[k] = lerpf(float(va), float(vb), t)
		else:
			out[k] = va
	return out
