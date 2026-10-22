class_name Planet
extends RefCounted

## 星球门面（M45 立方球 / M46 多星球）
##
## 【形制】立方球（cube-sphere）：6 个立方体面投射到球面 = 6 块大陆/区域，
##   面边缘统一沉到海底（外域：沉入虚空）→ 六面天然无缝拼接。
##
## 【多星球】M46 起本类只是**门面**，真正的形制参数在地形函数在 Profile 里：
##   · scripts/world/planet_azeroth.gd  —— 艾泽拉斯（R=2200，有海洋）
##   · scripts/world/planet_outland.gd  —— 外域（R=1500，无海洋，边缘断崖坠虚空）
##   切换：`Planet.use_world("outland")`（必须在任何地形生成之前调用）。
##   之所以做门面而不是把 Planet 改成实例对象：player.gd / monster.gd /
##   level.gd 里有几十处 `Planet.xxx`，门面让这些调用点一行都不用改。
##
## 【坐标体系】全部用**方向向量**，不用平面 x/z：
##   · 星球表面任意点 = dir * (RADIUS + height_at(dir))
##   · "上"= dir，"下"= -dir，重力沿 -dir
##   · 每个角色的 transform.basis 的 Y 轴 = 当地法线，局部 XZ = 切平面
##     这样既有的「局部 XZ 移动 + 局部 Y 跳跃」代码全部无需改动。

const FACE_COUNT := 6

# ===== 当前星球的形制参数（由 use_world 从 Profile 灌入）=====
# 注意：这些是 static var 而不是 const，切星球时会变。

## 星球半径（米）。地平线 d ≈ sqrt(2·R·h)：站着 ≈ 86m（艾泽拉斯）/ 71m（外域）
static var RADIUS := 2200.0
## 海底/虚空底高度（相对 RADIUS）
static var SEA_FLOOR := -46.0
## 水面高度（相对 RADIUS）。外域没有水，这里是虚空的"可见面"
static var SEA_LEVEL := -40.0
## 平面世界坐标 → 面内 uv 的缩放
static var PLANE_SCALE := 1150.0
static var LAND_EDGE := 0.86
static var LAND_SEA := 0.995

static var _profile: PlanetProfile = null
static var _world_id := "azeroth"

# ===== 光照方案（M47）=====
# 两种都跑在同一套球面行走 / 径向重力上，只换"太阳从哪来"：

## 方案 A：真实太阳。太阳是**世界惯性系**里的一个固定方向，随星球自转
## 绕自转轴转圈（一天 = SolarDayLength 秒）。站在背光半球就是黑夜，
## 太阳灯照不到，天空压暗、出星星。这是"真·艾泽拉斯星球"该有的样子。
const LIGHT_SOLAR := 0
## 方案 B：全球白天。太阳永远挂在观察者当地的正午偏南（按当地法线构造），
## 走到哪个面都是白天，适合不想被黑夜打断的探索/联调。
const LIGHT_GLOBAL := 1

## M47：默认改成「全球白天」——用户明确要求"不要有黑天，全球蓝天白云"，
## 测试阶段不能被昼夜循环打断。真实太阳（LIGHT_SOLAR）仍可用 F9 或
## `--light solar` 切回去，只是不再是默认。
static var light_mode := LIGHT_GLOBAL
## 一昼夜时长（秒）。200 秒能在几分钟的试玩里看到日出→正午→日落→星空。
static var solar_day_length := 200.0
## 太阳赤纬（弧度）。0 = 太阳在赤道面（南北极永远地平线上）；
## 14° 让高纬面保留低角度长昼，同时赤道带有明显的昼夜。
static var solar_declination := deg_to_rad(14.0)



## 切换星球。必须在任何地形/角色生成之前调用。
## id: "azeroth" | "outland"
static func use_world(id: String) -> void:
	if _profile != null and _profile.id == id:
		return
	match id:
		"outland": _profile = PlanetOutland.new()
		_: _profile = PlanetAzeroth.new()
	_world_id = _profile.id
	RADIUS = _profile.radius
	SEA_FLOOR = _profile.sea_floor
	SEA_LEVEL = _profile.sea_level
	PLANE_SCALE = _profile.plane_scale
	LAND_EDGE = _profile.land_edge
	LAND_SEA = _profile.land_sea
	printerr("[Planet] 载入星球 %s（%s）R=%d 海洋=%s" % [
		_profile.id, _profile.display_name, int(_profile.radius),
		"有" if _profile.has_ocean else "无"])


static func profile() -> PlanetProfile:
	if _profile == null:
		use_world(planet_from_config())
	return _profile


## 星球选择来源（优先级从高到低）：
##   1. 命令行 `-- --world outland`（联调/验收用）
##   2. user://settings.cfg 的 world 键（游戏内 F8 切换后落盘）
##   3. 默认 azeroth
## 必须在任何地形生成之前确定：TerrainStarter/ForestStarter 的 _ready 比
## Level._ready 更早执行，所以这里不等外部调用，自己解析。
static func planet_from_config() -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--world" and i + 1 < args.size():
			var w: String = args[i + 1]
			if w == "outland" or w == "azeroth":
				return w
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		var w2: String = cfg.get_value("world", "active", "azeroth")
		if w2 == "outland" or w2 == "azeroth":
			return w2
	return "azeroth"


## 把星球选择写进存档（供 F8 切换后重启场景生效）
static func save_planet_choice(id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")   # 多管理器共用：load→合并→save
	cfg.set_value("world", "active", id)
	cfg.save("user://settings.cfg")


# ===== 光照方案（M47）=====

## 读光照方案：命令行 `--light solar|global` > 存档 > 默认 solar
static func light_mode_from_config() -> int:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--light" and i + 1 < args.size():
			match args[i + 1]:
				"global", "globalday", "day": return LIGHT_GLOBAL
				"solar", "sun": return LIGHT_SOLAR
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		if String(cfg.get_value("world", "light_mode", "global")) == "global":
			return LIGHT_GLOBAL
	return LIGHT_GLOBAL


static var _light_inited := false
static func init_light_mode() -> void:
	if _light_inited:
		return
	_light_inited = true
	light_mode = light_mode_from_config()


static func toggle_light_mode() -> int:
	light_mode = LIGHT_GLOBAL if light_mode == LIGHT_SOLAR else LIGHT_SOLAR
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("world", "light_mode", "global" if light_mode == LIGHT_GLOBAL else "solar")
	cfg.save("user://settings.cfg")
	return light_mode


static func light_mode_name(m: int = -1) -> String:
	var v := light_mode if m < 0 else m
	return "真实太阳（有昼夜）" if v == LIGHT_SOLAR else "全球白天（无黑夜）"


## 太阳在世界惯性系里的方向（单位向量）。
## hour：本地时角（弧度），0 = 面 0 当地正午，π = 面 0 当地午夜。
## 做法：先取赤道面内、赤纬固定的一个方向，再绕自转轴（世界 +Y）转 hour。
static func sun_dir_at(hour: float) -> Vector3:
	var d := Vector3(cos(solar_declination), sin(solar_declination), 0.0)
	return d.rotated(Vector3.UP, hour).normalized()


## → Sky3D 需要的 (altitude, azimuth)。
## 注意 Sky3D 的球坐标是 alt=0 → 天顶（y=cos(alt)），不是常规的地理高度角。
static func sky_coords(dir: Vector3) -> Vector2:
	var y: float = clampf(dir.y, -1.0, 1.0)
	return Vector2(acos(y), atan2(dir.x, dir.z))


## 清掉静态缓存，让下一次 profile() 重新按存档选择星球。
## static var 的生命周期是整个进程，reload_current_scene 不会重置它，必须手动清。
static func reset_world() -> void:
	_profile = null
	_world_id = "azeroth"
	# 换星球必须清掉上颗星球的渲染网格高度缓存，否则新地形用旧高度贴地
	clear_mesh_cache()


static func world_id() -> String:
	return _world_id


static func display_name() -> String:
	return profile().display_name


static func has_ocean() -> bool:
	return profile().has_ocean


static func _ensure_noise() -> void:
	profile()


static func _sstep(e0: float, e1: float, x: float) -> float:
	if is_equal_approx(e0, e1):
		return 0.0 if x < e0 else 1.0
	var t: float = clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ===== 立方球参数化（与星球无关的纯数学）=====

## 面基：center / right(u 方向) / up(v 方向)
static func _face_basis(face: int) -> Array:
	match face:
		0: return [Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)]   # +X
		1: return [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)]   # -X
		2: return [Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)]   # +Y
		3: return [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)]   # -Y
		4: return [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)]    # +Z
		_: return [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)]  # -Z


## (face, u, v) → 单位方向
static func dir_of(face: int, u: float, v: float) -> Vector3:
	var b := _face_basis(face)
	var c: Vector3 = b[0]
	var r: Vector3 = b[1]
	var up: Vector3 = b[2]
	return (c + r * u + up * v).normalized()


## 单位方向 → [face, u, v]（uv ∈ [-1,1]，面内线性）
static func face_uv(dir: Vector3) -> Array:
	var d := dir.normalized()
	var ax := absf(d.x)
	var ay := absf(d.y)
	var az := absf(d.z)
	if ax >= ay and ax >= az:
		var u: float = (d.z / ax) * (-1.0 if d.x > 0.0 else 1.0)
		return [0 if d.x > 0.0 else 1, u, d.y / ax]
	if ay >= ax and ay >= az:
		var u2: float = d.x / ay
		var v2: float = (d.z / ay) * (-1.0 if d.y > 0.0 else 1.0)
		return [2 if d.y > 0.0 else 3, u2, v2]
	var u3: float = (d.x / az) * (1.0 if d.z > 0.0 else -1.0)
	return [4 if d.z > 0.0 else 5, u3, d.y / az]


## 世界平面坐标 (x,z) → 球面方向（面 0，即起始大陆）
static func dir_from_plane(x: float, z: float) -> Vector3:
	return dir_of(0, x / PLANE_SCALE, z / PLANE_SCALE)


## 球面方向 → 面 0 的平面坐标 (x,z)；非面 0 时返回最接近的近似
static func plane_of(dir: Vector3) -> Vector2:
	var fu := face_uv(dir)
	return Vector2(fu[1] * PLANE_SCALE, fu[2] * PLANE_SCALE)


# ===== 高度（转发给 Profile）=====

## 某方向的相对高度（米，相对 RADIUS）。负值 = 海底 / 虚空。
## 注意：这是**解析高度**，地形网格生成时在顶点处采样它；顶点之间网格是
## 平面三角形，所以角色行走 / 物件贴地必须用 mesh_height()，不能用这个。
static func height_at(dir: Vector3) -> float:
	return profile().height_at(dir)


## 地形网格每面的分段数。必须与 TerrainStarter.SEG 一致（单点定义，改这里）。
const MESH_SEG := 180


## 【M47 事故修复 · 必读】与地形网格**逐三角形一致**的表面高度。
##
## 为什么必须有这个函数：地形是每面 180×180 个四边形拼的，四边形内部是两个
## 平面三角形。角色/怪物/建筑如果直接拿解析高度落位，在起伏剧烈的地方会和
## 网格差好几米 —— 实测就是"角色悬空站在山腰"（用户 2026-10-22 退单）。
##
## 这里按 TerrainStarter 的绕序 `(i0,i2,i1) + (i1,i2,i3)` 复刻同一套插值，
## 对角线是 i1-i2（即局部 tx + ty = 1 这条线）。
## 【M47】渲染网格的高度缓存：6 个面，每面 (MESH_SEG+1)² 个顶点高度。
## TerrainStarter 建完网格后灌进来，之后 mesh_height 直接按**真实顶点**做三角插值。
##
## 为什么不能用 height_at 重算：实测（tools/mesh_ground_probe.gd）玩家比
## 屏幕上渲染出来的地面高 **0.30m** —— 因为渲染网格顶点是 height_at 在
## 180 段网格上采样的**离散**值，而重算走的是"同一函数但不同取整/插值路径"，
## 两者在起伏处对不上。用真实顶点缓存后，贴地与渲染逐点一致。
static var _mesh_cache: Array = []


static func set_mesh_cache(face: int, heights: PackedFloat32Array) -> void:
	if _mesh_cache.size() < 6:
		_mesh_cache.resize(6)
	_mesh_cache[face] = heights


static func clear_mesh_cache() -> void:
	_mesh_cache.clear()


## 某方向的**渲染网格**高度（角色/物件贴地一律用这个，不要用 height_at）
static func mesh_height(dir: Vector3) -> float:
	var fu := face_uv(dir)
	var face: int = int(fu[0])
	# --- 优先：真实渲染顶点缓存 ---
	if face < _mesh_cache.size():
		var arr = _mesh_cache[face]
		if arr is PackedFloat32Array and (arr as PackedFloat32Array).size() > 0:
			var cache: PackedFloat32Array = arr
			var n: int = int(round(sqrt(float(cache.size()))))   # = MESH_SEG + 1
			if n >= 2:
				var step_c := 2.0 / float(n - 1)
				var gx_c: float = (float(fu[1]) + 1.0) / step_c
				var gy_c: float = (float(fu[2]) + 1.0) / step_c
				var ix_c: int = clampi(int(floor(gx_c)), 0, n - 2)
				var iy_c: int = clampi(int(floor(gy_c)), 0, n - 2)
				var tx_c: float = clampf(gx_c - float(ix_c), 0.0, 1.0)
				var ty_c: float = clampf(gy_c - float(iy_c), 0.0, 1.0)
				var a00: float = cache[iy_c * n + ix_c]
				var a10: float = cache[iy_c * n + ix_c + 1]
				var a01: float = cache[(iy_c + 1) * n + ix_c]
				var a11: float = cache[(iy_c + 1) * n + ix_c + 1]
				if tx_c + ty_c <= 1.0:
					return a00 + (a10 - a00) * tx_c + (a01 - a00) * ty_c
				return a11 + (a01 - a11) * (1.0 - tx_c) + (a10 - a11) * (1.0 - ty_c)
	# --- 回退：缓存还没建好（关卡早期）时走解析式 ---
	var step := 2.0 / float(MESH_SEG)
	var gx: float = (float(fu[1]) + 1.0) / step
	var gy: float = (float(fu[2]) + 1.0) / step
	var ix: int = clampi(int(floor(gx)), 0, MESH_SEG - 1)
	var iy: int = clampi(int(floor(gy)), 0, MESH_SEG - 1)
	var tx: float = clampf(gx - float(ix), 0.0, 1.0)
	var ty: float = clampf(gy - float(iy), 0.0, 1.0)
	var u0: float = -1.0 + step * float(ix)
	var v0: float = -1.0 + step * float(iy)
	var u1: float = u0 + step
	var v1: float = v0 + step
	var h00: float = height_at(dir_of(face, u0, v0))
	var h10: float = height_at(dir_of(face, u1, v0))
	var h01: float = height_at(dir_of(face, u0, v1))
	var h11: float = height_at(dir_of(face, u1, v1))
	if tx + ty <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * ty
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - ty)


## 某方向的地表位置（用网格高度，角色/物件都该落在这上面）
static func ground_pos(dir: Vector3) -> Vector3:
	var d := dir.normalized()
	return d * (RADIUS + mesh_height(d))


# ===== 表面位置 =====

## 方向 → 星球表面位置
static func surface_pos(dir: Vector3) -> Vector3:
	var d := dir.normalized()
	return d * (RADIUS + mesh_height(d))


## 世界坐标 → 可靠的地面/地表位置（径向吸附）
static func snap_to_surface(pos: Vector3) -> Vector3:
	if pos.length_squared() < 0.0001:
		return Vector3(RADIUS, 0, 0)
	return surface_pos(pos.normalized())


static func up_at(pos: Vector3) -> Vector3:
	if pos.length_squared() < 0.0001:
		return Vector3.UP
	return pos.normalized()


## 平面 (x,z) → 星球表面位置（面 0）
static func plane_to_surface(x: float, z: float) -> Vector3:
	return surface_pos(dir_from_plane(x, z))


## 该位置是否已坠入虚空/深海（外域悬崖外）。用于掉落兜底。
static func is_in_void(pos: Vector3) -> bool:
	return pos.length() < RADIUS + SEA_LEVEL + 2.0


## 构造"Y = 当地法线"的正交基，保持前方向尽量连续（平行传输）
static func align_basis(up: Vector3, forward: Vector3) -> Basis:
	var y := up.normalized()
	var f := forward - y * forward.dot(y)
	if f.length_squared() < 0.000001:
		# 退化：任取一个与 y 不平行的参考向量
		var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		f = ref - y * ref.dot(y)
		if f.length_squared() < 0.000001:
			f = Vector3.RIGHT - y * y.x
	f = f.normalized()
	var x := f.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## ==== 切平面朝向编解码（C0 零凑数：球面上的"朝向角"只有一个定义）====
##
## 为什么必须成套出现：球面上"上"是当地法线，世界 XZ 平面不是水平面。
## 用 `atan2(dir.x, dir.z)` 当朝向角，在 up 接近 ±X 的位置会把 90° 的朝向
## 读成 0°（实测差 85.5°）。而网络同步/存盘只能传一个 float，所以角度本身
## 必须相对**当地切平面**表达，且编码与解码共用同一参考轴。
##
## 三个纯函数（无状态、无缓存）：
##   tangent_ref(up)     参考轴：所有角度以它为 0
##   yaw_of(up, dir)     方向 → 绕当地法线的角
##   dir_of_yaw(up, yaw) 角 → 当地水平方向（与 yaw_of 严格互逆）
##   basis_from_yaw(...) = align_basis(up, dir_of_yaw(...))，即 -Z 指向该方向

## 切平面参考轴。取世界 -Z 投影到切平面；在极点附近（up ∥ ±Z）换 -X。
## 注意：换参考轴会让 yaw 数值突变，但**解码端用同一个 up 算同一个参考轴**，
## 还原出的方向仍然连续 —— 这只影响传输数值，不影响朝向。
static func tangent_ref(up: Vector3) -> Vector3:
	var y := up.normalized()
	var ref := Vector3.FORWARD
	if absf(y.dot(ref)) > 0.9:
		ref = Vector3.LEFT
	var f := ref - y * ref.dot(y)
	if f.length_squared() < 0.000001:
		f = Vector3.RIGHT - y * y.x
	return f.normalized()


## 世界方向 → 绕当地法线的角度（弧度）。方向会自动投影到切平面。
## 退化（方向与法线平行）返回 NAN，由调用方决定保留旧值。
static func yaw_of(up: Vector3, dir: Vector3) -> float:
	var y := up.normalized()
	var t := dir - y * dir.dot(y)
	if t.length_squared() < 0.0000001:
		return NAN
	t = t.normalized()
	var ang := tangent_ref(y).signed_angle_to(t, y)
	return ang if is_finite(ang) else NAN


## 绕当地法线的角度 → 当地水平方向。与 yaw_of 互逆。
static func dir_of_yaw(up: Vector3, yaw: float) -> Vector3:
	if not is_finite(yaw):
		return Vector3.ZERO
	var y := up.normalized()
	return tangent_ref(y).rotated(y, yaw)


## 由绕当地法线的角度构造正交基：Y = 法线，-Z = 该方向。
static func basis_from_yaw(up: Vector3, yaw: float) -> Basis:
	var d := dir_of_yaw(up, yaw)
	if d.length_squared() < 0.0000001:
		return align_basis(up, Vector3.FORWARD)
	return align_basis(up, d)


## 把平面世界的一个刚体（村庄/竞技场/建筑）整体搬到球面：
##   pos   = 平面坐标（面 0）
##   yaw   = 原 rotation.y
## 返回 Transform3D（Y = 法线，前方向 = 原 -Z 旋转 yaw）
static func plane_transform(x: float, z: float, yaw: float) -> Transform3D:
	var dir := dir_from_plane(x, z)
	var up := dir
	var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	# 把平面前方向投影到球面切平面
	fwd = (fwd - up * fwd.dot(up))
	if fwd.length_squared() < 0.000001:
		fwd = Vector3.FORWARD
	var b := align_basis(up, fwd)
	return Transform3D(b, surface_pos(dir))


# ===== L1 落位层：一切"贴到表面"只走这里 =====
# 【C0 零凑数约定】见 docs/conventions-relative-computation.md §4.2
# 禁止在业务代码里写 `position.y = 1.15` 之类的绝对抬升；
# 抬多少必须由「模型自身几何底边」与「该点地表」的差值算出来。

## 模型在世界上占据的最低点，沿 up 方向的投影值。
## 真值源 = 各 MeshInstance3D 的顶点（不是手填数，不是 AABB 近似之外的猜测）。
static func model_lowest_projection(node: Node3D, up: Vector3) -> float:
	if node == null:
		return NAN
	var lo := INF
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		# 真值源必须是"实际显示的那套模型"：玩家/Bot/怪物都可能同时挂着两套视觉
		# （GodotRobot + KayKit 步兵），隐藏那套的顶点会算出一个肉眼看不见的最低点，
		# fit_ground 就会按"隐形模型"落地 → 看得见的人悬空。
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			if arr.is_empty():
				continue
			var verts = arr[Mesh.ARRAY_VERTEX]
			if verts == null:
				continue
			for v in (verts as PackedVector3Array):
				lo = minf(lo, (xf * v).dot(up))
	return lo if is_finite(lo) else NAN


## 让模型的最低点正好落在它脚下的地表上（相对值计算，零手填常数）。
##   lift: 沿当地法线的额外抬升，**0 就是贴地**。只有"悬空道具/飞行物"才给正值。
## 换模型、换星球、换坡度都自动正确 —— 这就是它和 `+= 1.15` 的本质区别。
static func fit_ground(node: Node3D, lift: float = 0.0) -> void:
	if node == null:
		return
	var pos := node.global_position
	if pos.length_squared() < 0.0001:
		return
	var up := up_at(pos)
	var ground_proj: float = ground_pos(pos.normalized()).dot(up)
	var lowest := model_lowest_projection(node, up)
	if is_nan(lowest):
		return
	node.global_position += up * (ground_proj - lowest + lift)


## 把一个节点放到 dir 方向的表面上（Y = 当地法线）。
##   dir  : 世界方向，决定落在球面哪个位置
##   yaw  : 绕当地法线的方位角；NAN = 用 align_basis 的基准朝向
##   face : 是否顺手做 fit_ground（让几何底边贴住表面）
static func place_on_surface(node: Node3D, dir: Vector3, yaw: float = NAN, face: bool = true) -> void:
	if node == null:
		return
	var d := dir.normalized()
	if d.length_squared() < 0.0001:
		return
	var b := align_basis(d, Vector3.FORWARD)
	if not is_nan(yaw):
		b = Basis(d, yaw) * b
	node.global_transform = Transform3D(b, surface_pos(d))
	if face:
		fit_ground(node, 0.0)
