class_name WorldShape
extends RefCounted

## 世界形状真值（World Shape）—— 全地图唯一的高度/分区/道路数据源。
##
## 【需求】参考《魔兽世界》：多张地图，高山隔开，道路连接。
##   · 莫高雷 Mulgore：绿色草原 + 金色草甸 + 针叶林 + 红岩台地 + 湖泊（村庄所在）
##   · 高山屏障：东西向山脉带，海拔 180~240m，唯一缺口是"隘口"
##   · 地狱火半岛 Hellfire：红土高原 + 火山锥 + 熔岩裂隙 + 枯树骨堆
##
## 【坐标】X 东为正，Z 南为正（Godot 惯例）；村心 (0, -130)，出生点 (0, 2.8, -130)。
##   莫高雷在南（z > -250），山脉带 z ∈ [-430, -250]，地狱火在北（z < -430）。
##
## 【为什么所有东西都从这里取】地形网格、Terrain3D 碰撞高度、遮罩贴图、
##   植被撒点、道路压平、NPC/怪的位置，全部调用同一组函数，避免"视觉地形和
##   碰撞地形对不上"的老坑（M34/M39 反复踩过）。

# ===== 世界范围 =====
## 显示网格半宽（米）。±800 覆盖莫高雷全境 + 山脉带 + 地狱火 370m 纵深。
const WORLD_HALF := 800.0
## 自建渲染网格每边格数（±800m / 360 = 4.44m 一格，约 26 万三角面）
const CUSTOM_CELLS := 360
## Terrain3D 数据区：region_size 1024，2x2 个 region 覆盖 ±1024m（碰撞外延）
const DATA_HALF := 1024.0

# ===== 区域分界（沿 Z 轴）=====
## 莫高雷草原北界 = 山脚线
const Z_MULGORE_EDGE := -250.0
## 山脉带北界 = 地狱火门户
const Z_HELLFIRE_EDGE := -430.0
## 两个区域的基础海拔（隘口在这两个值之间平滑爬升）
const MULGORE_BASE := 3.0
const HELL_BASE := 46.0

# ===== 村庄平台（KayKit Arena 地砖所在，必须接近 0m）=====
const VILLAGE_RECT := Rect2(-112.0, -342.0, 224.0, 424.0)
const VILLAGE_BLEND := 64.0

# ===== 湖泊（莫高雷南部）=====
const LAKE_CENTER := Vector2(-330.0, 205.0)
const LAKE_RADIUS := 118.0
const LAKE_FLOOR := 1.0
const LAKE_WATER := 5.6

# ===== 红岩台地（莫高雷地标，参考图背景的石柱山）=====
## [中心x, 中心z, 半径, 高度]
const MESAS := [
	[-520.0, -60.0, 96.0, 78.0],
	[-430.0, 120.0, 68.0, 56.0],
	[300.0, 190.0, 82.0, 64.0],
	[520.0, -40.0, 110.0, 92.0],
]
## 台地平台顶/壁陡度：0.78~1.0 之间速降
const MESA_PLATEAU := 0.74

# ===== 地狱火半岛：火山锥 =====
## [中心x, 中心z, 半径, 高度]
const VOLCANOES := [
	[-330.0, -640.0, 132.0, 74.0],
	[250.0, -700.0, 108.0, 58.0],
	[40.0, -780.0, 150.0, 88.0],
]

# ===== 熔岩裂隙（地狱火，折线；shader 里发光，地形下切）=====
const CREVICES := [
	[Vector2(-620, -520), Vector2(-380, -600), Vector2(-160, -690), Vector2(60, -720)],
	[Vector2(-60, -760), Vector2(160, -820), Vector2(420, -790), Vector2(660, -700)],
	[Vector2(-500, -760), Vector2(-320, -840), Vector2(-90, -880)],
]
const CREVICE_WIDTH := 16.0
const CREVICE_DEPTH := 11.0

# ===== 官道（莫高雷 ↔ 隘口 ↔ 地狱火，贯穿两区）=====
## 主路：从村庄北门出发，穿过隘口，平原直下地狱火火口
const HIGHWAY := [
	Vector2(-26, 96), Vector2(-20, 20), Vector2(-8, -70), Vector2(-14, -150),
	Vector2(4, -222), Vector2(28, -286), Vector2(44, -352), Vector2(48, -430),
	Vector2(30, -512), Vector2(4, -596), Vector2(-26, -684), Vector2(-70, -790),
]
const HIGHWAY_WIDTH := 8.0
## 支路：村庄 → 湖泊（莫高雷南部景观道）
const SIDE_ROADS := [
	[Vector2(-26, 96), Vector2(-110, 130), Vector2(-205, 152), Vector2(-282, 186)],
	[Vector2(-8, -70), Vector2(-140, -96), Vector2(-268, -74), Vector2(-360, -18)],
	[Vector2(48, -430), Vector2(180, -470), Vector2(300, -560), Vector2(390, -660)],
]
const SIDE_ROAD_WIDTH := 5.0

# ===== 噪声（懒初始化静态实例）=====
static var _n_macro: FastNoiseLite
static var _n_mid: FastNoiseLite
static var _n_ridge: FastNoiseLite
static var _n_hell: FastNoiseLite
static var _village_roads: Array = []   # 由 village_layout 注入的村内道路折线


static func _ensure_noise() -> void:
	if _n_macro != null:
		return
	_n_macro = FastNoiseLite.new()
	_n_macro.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_macro.frequency = 0.0016
	_n_macro.fractal_octaves = 3
	_n_macro.fractal_gain = 0.48
	_n_macro.seed = 20261022

	_n_mid = FastNoiseLite.new()
	_n_mid.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_mid.frequency = 0.0072
	_n_mid.fractal_octaves = 2
	_n_mid.fractal_gain = 0.45
	_n_mid.seed = 7712

	_n_ridge = FastNoiseLite.new()
	_n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n_ridge.frequency = 0.0034
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_ridge.fractal_octaves = 3
	_n_ridge.seed = 424242

	_n_hell = FastNoiseLite.new()
	_n_hell.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n_hell.frequency = 0.0042
	_n_hell.fractal_octaves = 3
	_n_hell.fractal_gain = 0.5
	_n_hell.seed = 66613


# ===== 基础数学工具 =====

static func _sstep(edge0: float, edge1: float, x: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 0.0 if x < edge0 else 1.0
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.000001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _dist_to_polyline(p: Vector2, pts: Array) -> float:
	var best := 1.0e20
	for i in range(pts.size() - 1):
		var d := _dist_to_segment(p, pts[i], pts[i + 1])
		if d < best:
			best = d
	return best


## 在折线上做"按弧长 0..1 取点"（生成装饰/路面石板用）
static func point_on_polyline(pts: Array, t: float) -> Vector2:
	if pts.size() < 2:
		return pts[0] if pts.size() == 1 else Vector2.ZERO
	var total := 0.0
	var segs: Array[float] = []
	for i in range(pts.size() - 1):
		var l: float = pts[i].distance_to(pts[i + 1])
		segs.append(l)
		total += l
	if total <= 0.0001:
		return pts[0]
	var target: float = clampf(t, 0.0, 1.0) * total
	var acc := 0.0
	for i in segs.size():
		if acc + segs[i] >= target:
			var f: float = (target - acc) / maxf(segs[i], 0.0001)
			return pts[i].lerp(pts[i + 1], f)
		acc += segs[i]
	return pts[pts.size() - 1]


# ===== 隘口 =====

## 隘口中心线：随 z 平滑弯曲（-250 → -430 由 -10 弯到 +46）
static func pass_center_x(z: float) -> float:
	var u: float = clampf((z - Z_MULGORE_EDGE) / (Z_HELLFIRE_EDGE - Z_MULGORE_EDGE), 0.0, 1.0)
	return -12.0 + 58.0 * sin(u * PI * 0.92)


## 隘口开口度：1 = 在两壁之间的通道，0 = 实心山体
static func pass_openness(x: float, z: float) -> float:
	if z > Z_MULGORE_EDGE + 40.0 or z < Z_HELLFIRE_EDGE - 40.0:
		return 0.0
	var d: float = absf(x - pass_center_x(z))
	return 1.0 - _sstep(34.0, 92.0, d)


# ===== 分区基础高度 =====

static func mulgore_height(x: float, z: float) -> float:
	_ensure_noise()
	var macro: float = _n_macro.get_noise_2d(x, z)
	var mid: float = _n_mid.get_noise_2d(x, z)
	# 缓丘：低频 0~9m + 中频 0~3m，整体平缓（WOW 莫高雷是"柔软的草浪"）
	var h: float = MULGORE_BASE + macro * 5.6 + mid * 2.4
	# 红岩台地：顶部平台 + 陡壁
	for m in MESAS:
		var c := Vector2(m[0], m[1])
		var d: float = Vector2(x, z).distance_to(c)
		var r: float = m[2]
		if d > r * 1.55:
			continue
		var top: float = m[3]
		# 1 = 台地内部平台，0 = 台地外
		var inside: float = 1.0 - _sstep(r * MESA_PLATEAU, r, d)
		# 台地边缘外再做一圈缓坡裙边，避免"凭空冒出的方块"
		var skirt: float = (1.0 - _sstep(r * 0.98, r * 1.5, d)) * (1.0 - inside) * 0.28
		h += top * inside + top * skirt
	# 湖泊洼地
	var ld: float = Vector2(x, z).distance_to(LAKE_CENTER)
	if ld < LAKE_RADIUS * 1.6:
		var w: float = 1.0 - _sstep(LAKE_RADIUS * 0.55, LAKE_RADIUS * 1.6, ld)
		h = lerpf(h, LAKE_FLOOR + (macro + 1.0) * 0.8, w)
	return h


static func hellfire_height(x: float, z: float) -> float:
	_ensure_noise()
	var n: float = _n_hell.get_noise_2d(x, z)
	var mid: float = _n_mid.get_noise_2d(x, z)
	# 红土高原：整体平坦但被干裂沟壑切开
	var h: float = HELL_BASE + n * 6.8 + mid * 1.8
	# 火山锥（顶部有火山口凹陷）
	for v in VOLCANOES:
		var c := Vector2(v[0], v[1])
		var d: float = Vector2(x, z).distance_to(c)
		var r: float = v[2]
		if d > r:
			continue
		var t: float = 1.0 - d / r
		# 锥形：pow 让腰部外扩、顶部收窄
		var cone: float = pow(t, 1.5) * v[3]
		# 火口：中心 20% 半径下凹 22%
		var crater: float = (1.0 - _sstep(0.0, r * 0.22, d)) * v[3] * 0.22
		h += cone - crater
	# 熔岩裂隙：沿折线下切
	var cd := crevice_distance(x, z)
	if cd < CREVICE_WIDTH * 2.2:
		h -= CREVICE_DEPTH * (1.0 - _sstep(CREVICE_WIDTH * 0.35, CREVICE_WIDTH * 2.2, cd))
	return h


## 到最近熔岩裂隙中心的距离
static func crevice_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 1.0e20
	for line in CREVICES:
		var d := _dist_to_polyline(p, line)
		if d < best:
			best = d
	return best


# ===== 主高度函数 =====

## 世界高度（米）。所有地形网格/碰撞/撒点都必须只调用这个函数。
static func height_at(x: float, z: float) -> float:
	_ensure_noise()
	# 1) 两区基底按 Z 平滑过渡（山脉带内从莫高雷基准爬到地狱火基准）
	## t: 0 = 莫高雷（z 大），1 = 地狱火（z 小，更北）
	var t: float = _sstep(Z_MULGORE_EDGE, Z_HELLFIRE_EDGE, z)
	var h_grass: float = mulgore_height(x, z)
	var h_hell: float = hellfire_height(x, z)
	var h: float = lerpf(h_grass, h_hell, t)

	# 2) 山脉带：中部隆起，隘口处压低
	var band: float = sin(clampf(t, 0.0, 1.0) * PI)
	band = pow(band, 1.05)
	var ridge: float = 0.60 + 0.40 * (_n_ridge.get_noise_2d(x, z) * 0.5 + 0.5)
	var mountain: float = 205.0 * band * ridge
	# 山脊细节（碎石棱线）
	mountain += band * 16.0 * _n_mid.get_noise_2d(x * 0.6, z * 0.6)
	mountain *= 1.0 - pass_openness(x, z) * 0.965

	h += mountain

	# 3) 村庄平台压平（KayKit 地砖必须在 ~0m，否则角色踩空/穿模）
	var vf: float = _rect_falloff(Vector2(x, z), VILLAGE_RECT, VILLAGE_BLEND)
	if vf > 0.0:
		h = lerpf(h, 0.0, vf)

	# 4) NaN 防护（任何异常都回落 0，绝不把 NaN 传进网格）
	if not is_finite(h):
		return 0.0
	return h


## 区域遮罩：0 = 莫高雷草原，1 = 地狱火红土（山脉带内按高度再混）
static func zone_factor(x: float, z: float) -> float:
	## 0 = 莫高雷草原，1 = 地狱火红土
	return _sstep(Z_MULGORE_EDGE, Z_HELLFIRE_EDGE, z)


## 到最近道路（官道/支路/村内路）的距离，用于遮罩与植被避让
static func road_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := _dist_to_polyline(p, HIGHWAY)
	for line in SIDE_ROADS:
		var d := _dist_to_polyline(p, line)
		if d < best:
			best = d
	for line in _village_roads:
		var d2 := _dist_to_polyline(p, line)
		if d2 < best:
			best = d2
	return best


static func register_village_roads(lines: Array) -> void:
	_village_roads = lines


# ===== 遮罩贴图烘焙 =====

## 生成 RGBA 遮罩：
##   R = 道路强度（1 = 路心）
##   G = 草原权重（莫高雷草/金黄草甸）
##   B = 红土权重（地狱火）
##   A = 熔岩发光（裂隙中心）
## size 建议 512（覆盖 1600m → 3.1m/像素，路宽 8m ≈ 2.5 像素）
static func build_mask_image(size: int) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var span: float = WORLD_HALF * 2.0
	var step: float = span / float(size)
	for py in size:
		var wz: float = -WORLD_HALF + (float(py) + 0.5) * step
		for px in size:
			var wx: float = -WORLD_HALF + (float(px) + 0.5) * step
			var rd_hw: float = _dist_to_polyline(Vector2(wx, wz), HIGHWAY)
			var road: float = 1.0 - _sstep(HIGHWAY_WIDTH * 0.34, HIGHWAY_WIDTH * 0.66, rd_hw)
			var rd_side: float = road_distance(wx, wz)
			var side: float = 1.0 - _sstep(SIDE_ROAD_WIDTH * 0.26, SIDE_ROAD_WIDTH * 0.72, rd_side)
			road = maxf(road, side * 0.92)
			var zf: float = zone_factor(wx, wz)
			# 草原权重：越过山脊后自然消失（山上是岩石）
			var grass: float = 1.0 - zf
			var hell: float = zf
			# 熔岩：只在裂隙中心发光
			var lava := 0.0
			if wz < Z_HELLFIRE_EDGE:
				var cd: float = crevice_distance(wx, wz)
				lava = 1.0 - _sstep(0.0, CREVICE_WIDTH * 0.55, cd)
			# 湖泊区域不发光不画路（水下）
			var ld: float = Vector2(wx, wz).distance_to(LAKE_CENTER)
			if ld < LAKE_RADIUS:
				road *= _sstep(LAKE_RADIUS * 0.35, LAKE_RADIUS, ld)
			img.set_pixel(px, py, Color(road, grass, hell, lava))
	return img


static func _rect_falloff(p: Vector2, rect: Rect2, blend: float) -> float:
	# 矩形内 = 1，矩形外 blend 米内线性衰减到 0
	var dx: float = maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0)
	var dz: float = maxf(maxf(rect.position.y - p.y, p.y - rect.end.y), 0.0)
	var d: float = sqrt(dx * dx + dz * dz)
	if d <= 0.0:
		return 1.0
	return 1.0 - _sstep(0.0, blend, d)
