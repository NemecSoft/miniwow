extends Node3D

## 世界装饰（M44：莫高雷 / 高山屏障 / 地狱火半岛）
##
## 一、分区天空：莫高雷晴朗蓝天 + 白云；地狱火橙红天 + 灰烬感薄雾。
##     玩家跨越隘口时按 WorldShape.zone_factor() 平滑过渡（不是硬切）。
## 二、分区植被：
##     · 莫高雷：针叶林（冷杉）+ 金黄草浪 + 白色野花 + 灰岩块
##     · 地狱火：枯树 + 骨堆 + 红岩 + 火山碎石
## 三、湖泊水面（莫高雷南部）
## 四、村庄实体（VillageLayout 读取随机布局 JSON）
##
## 【性能】所有重复物件走 MultiMesh（草 3600 / 树 900 / 岩石 620 各 1 个 draw call）。
## 【贴地】一律用 WorldShape.height_at()，与地形网格/碰撞同源，绝不各自采样。

const TREE_COUNT := 900
const GRASS_COUNT := 3600
const FLOWER_COUNT := 1300
const ROCK_COUNT := 620
const DEAD_TREE_COUNT := 240
const BONE_COUNT := 140

## 避让：村内（建筑自己会放，别再种树）
const VILLAGE_AVOID := Rect2(-116.0, -346.0, 232.0, 432.0)
## 道路两侧留空
const ROAD_CLEAR := 5.2

var _sky: Node
## 天空参数从 PlanetProfile 取：a = 温和区 / b = 炽热区（外域不插值，只用 a）
var _sky_a := {}
var _sky_b := {}
var _sky_blend := 0.0
var _tod_stopped := false
var _was_high := false
var _sun_diag_frames := 0
var _sky_ready := false
## 所有地表细节（草/树/岩/蘑菇/骨/水晶/村庄）的统一父节点。
## 高空/太空视角整体关掉——逐个 visibility_range 在本机 MultiMesh 上不生效
## （custom_aabb 覆盖整球，剔除判定失效），直接关容器最可靠。
var _detail_root: Node3D
var _detail_shown := true
## 分区天空的 atm 基准值，太空模式要按比例压薄，回地面要恢复
var _atm_sun_base := 12.5
var _atm_thick_base := 0.7
## 真实太阳模式下的一天进度（秒）。起始值由 --sun-hour 决定（0=午夜 12=正午）
var _sun_clock := 0.0


func _ready() -> void:
	_detail_root = Node3D.new()
	_detail_root.name = "Details"
	add_child(_detail_root)
	_init_sun_clock()
	var prof := Planet.profile()
	_sky_a = prof.sky_a.duplicate()
	_sky_b = prof.sky_b.duplicate()
	_setup_sky()
	await get_tree().process_frame
	_build_world()


func _process(delta: float) -> void:
	_update_sun_local()
	_update_zone_sky(delta)


## M47：两套光照方案，都跑在同一套球面行走/径向重力上，只换"太阳从哪来"。
##
##   Planet.LIGHT_SOLAR （方案 A）真实太阳
##     太阳是世界惯性系里的一个方向，绕星球自转轴转圈（一天 = solar_day_length 秒）。
##     站在背光半球就是黑夜：太阳灯的世界方向照不到你，天空压暗出星星。
##
##   Planet.LIGHT_GLOBAL（方案 B）全球白天
##     太阳永远挂在观察者当地的正午偏南，走到哪个面都是白天。
##
## 关键实现约束（踩过坑）：
##   · Sky3D 内部所有昼夜判定（太阳灯能量、夜间染色、环境色、星星）都读
##     `_sun_transform.origin.y`，而它的球坐标 alt=0 表示**天顶**、y=cos(alt)。
##     所以必须传 alt = acos(当地太阳高度) —— 传地理高度角会让整片天变黑夜。
##   · 但它拼出来的太阳灯**方向**是"把当地天空搬到世界坐标系"的假方向，
##     背面的人照样被照亮。所以设完 alt/az 之后必须再覆盖一次灯的世界方向。
##   · 天空 shader 的 planet_up 也在这里写：天顶 = 观察者当地法线（球面必须）。
func _update_sun_local() -> void:
	if _sky == null or _sky.get("sky") == null:
		return
	var s = _sky.sky
	if s == null:
		return
	# TimeOfDay 每帧按世界坐标重算太阳方位，会覆盖下面的赋值 → 直接停掉
	var tod = _sky.get("tod")
	if tod != null and not _tod_stopped:
		_tod_stopped = true
		tod.set_process(false)
		tod.set_physics_process(false)
		printerr("[World] TimeOfDay 已停用（球面太阳由法线驱动）")
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var up := Planet.up_at(cam.global_position)

	# 天顶 = 当地法线（否则站在 -X 面时整个世界 Y 当地平线，天空算成一片地平线色）
	# 注意 sky_material 挂在 Sky3D 上，SkyDome 没有这个属性（写成 s.sky_material
	# 会拿到 null，静默什么都不做 —— 这就是天空一直纯色的原因之一）
	if _sky.get("sky_material") != null and _sky.sky_material != null:
		_sky.sky_material.set_shader_parameter("planet_up", up)

	var pf := Planet.profile()
	var axis: Vector3

	if Planet.light_mode == Planet.LIGHT_SOLAR:
		# ----- 方案 A：真实太阳（世界惯性系 + 自转）-----
		_sun_clock += get_process_delta_time()
		var hour := fposmod(_sun_clock / Planet.solar_day_length, 1.0) * TAU
		axis = Planet.sun_dir_at(hour)
		_light_mode_apply_solar(s, pf, axis, up)
	else:
		# ----- 方案 B：全球白天（太阳跟着观察者走）-----
		var north := Vector3.UP - up * Vector3.UP.dot(up)
		if north.length_squared() < 0.01:
			north = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
		north = north.normalized()
		var zf: float = pf.sun_zenith
		axis = (up * zf + north * sqrt(maxf(0.0, 1.0 - zf * zf))).normalized()
		_light_mode_apply_global(s, pf, axis, up)

	if _sun_diag_frames < 3:
		_sun_diag_frames += 1
		printerr("[World] 光照=%s 太阳世界方向=%s 当地高度=%+.0f° up=%s" % [
			Planet.light_mode_name(), str(axis.snapped(Vector3.ONE * 0.01)),
			rad_to_deg(asin(clampf(axis.dot(up), -1.0, 1.0))),
			str(up.snapped(Vector3.ONE * 0.01))])


## 起始时刻：--sun-hour <0~24>，0 = 面 0 当地午夜，12 = 正午。
## 默认 10 点（太阳已升起、影子偏长，比正午好看）。
func _init_sun_clock() -> void:
	Planet.init_light_mode()
	var h := 10.0
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--sun-hour" and i + 1 < args.size():
			h = clampf(float(args[i + 1]), 0.0, 24.0)
	_sun_clock = (h - 12.0) / 24.0 * Planet.solar_day_length
	printerr("[World] 光照方案 = %s（起始 %.1f 时，一天 %d 秒）" % [
		Planet.light_mode_name(), h, int(Planet.solar_day_length)])


## 把太阳放进 Sky3D 的坐标系：它只认 alt=acos(当地高度) / az=水平方位
func _push_sun_coords(s, axis: Vector3, up: Vector3) -> void:
	var cos_el: float = clampf(axis.dot(up), -1.0, 1.0)
	s.sun_altitude = acos(cos_el)
	s.sun_azimuth = atan2(axis.x, axis.z)


## 把太阳灯摆到真实的世界方向（-Z 指向星球中心 = 光线朝内）
func _place_sun_light(axis: Vector3) -> void:
	var sl = _sky.get("sun")
	if not (sl is DirectionalLight3D):
		return
	var node := sl as DirectionalLight3D
	var t := Transform3D(Basis(), axis.normalized() * 1000.0)
	node.global_transform = t.looking_at(Vector3.ZERO, Vector3.UP)


## 方案 A：真实太阳。昼夜全部由 dot(太阳, 当地法线) 决定。
func _light_mode_apply_solar(s, pf: PlanetProfile, axis: Vector3, up: Vector3) -> void:
	var cos_el: float = clampf(axis.dot(up), -1.0, 1.0)
	_push_sun_coords(s, axis, up)

	# 昼夜过渡：-0.10（天完全黑）→ +0.18（太阳已升起）
	var day: float = smoothstep(-0.10, 0.18, cos_el)
	# 低角度时偏橙（日出日落），正午偏白
	var warm: float = clampf(1.0 - cos_el * 2.2, 0.0, 1.0)
	var sun_col: Color = Color(1.0, 0.60, 0.34).lerp(Color(1.0, 0.96, 0.90), 1.0 - warm)

	# 先写 SkyDome 的属性（它的 setter 会重算并覆盖灯能量），再写灯本身
	_sky.sun_energy = pf.sun_energy
	_place_sun_light(axis)
	var sl = _sky.get("sun")
	if sl is DirectionalLight3D:
		var node := sl as DirectionalLight3D
		# 自己算能量曲线：Sky3D 内置的过渡只有 ±1°，日落是一瞬间切黑
		node.light_energy = pf.sun_energy * day
		node.light_color = sun_col

	var env: Environment = _sky.environment if _sky.get("environment") != null else null
	if env != null:
		if day > 0.5:
			# 白天：环境光取自天空（和 M46 一致，天空是什么色地上就什么色）
			env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			env.ambient_light_energy = pf.ambient_energy + 0.15
			env.background_energy_multiplier = pf.bg_energy
		else:
			# 夜间：环境光必须切到固定色。
			# 天空一黑，"从天空取环境光"就等于没有任何环境光 —— 实测整屏纯黑，
			# 玩家连脚下都看不见（真实过了头，没法玩）。这里给一层冷色夜光。
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			# 颜色/强度按"能看清轮廓"标定：地面 albedo 本身只有 0.2 左右，
			# 深蓝 0.1×0.62 的入射光下反出来的亮度不到 1%，实测整屏死黑。
			env.ambient_light_color = Color(0.18, 0.23, 0.40)
			env.ambient_light_energy = lerpf(1.05, 0.0, clampf(day * 2.0, 0.0, 1.0))
			env.background_energy_multiplier = lerpf(pf.bg_energy * 0.20, pf.bg_energy, day * 2.0)


## 方案 B：全球白天。太阳永远在当地正午偏南，任何面都不会入夜。
func _light_mode_apply_global(s, pf: PlanetProfile, axis: Vector3, up: Vector3) -> void:
	_push_sun_coords(s, axis, up)
	_sky.sun_energy = pf.sun_energy
	_sky.ambient_energy = pf.ambient_energy
	# 灯方向必须跟着 axis（当地构造），否则照不亮眼前的角色
	_place_sun_light(axis)
	var sl = _sky.get("sun")
	if sl is DirectionalLight3D:
		var node := sl as DirectionalLight3D
		node.light_energy = pf.sun_energy * 0.97
		node.light_color = Color(1.0, 0.97, 0.92)

	if _sky.get("environment") != null:
		var env: Environment = _sky.environment
		env.ambient_light_energy = pf.ambient_energy + 0.15
		env.background_energy_multiplier = pf.bg_energy


# ===== 一、天空 =====

func _setup_sky() -> void:
	_sky = get_node_or_null("../Sky3D")
	if _sky == null:
		printerr("[World] 未找到 Sky3D，跳过天空")
		return
	_apply_sky_params(0.0)
	var env: Environment = _sky.environment
	if env != null:
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_sun_scatter = 0.18
		env.fog_depth_begin = 320.0
		env.fog_depth_end = 2600.0
		env.fog_depth_curve = 1.0
		# 关键：原生 depth fog 不染天空（否则整片天空变橙红，M38 事故根因）
		env.fog_sky_affect = 0.0
		env.fog_aerial_perspective = 0.0
		# 球面世界天空整体偏暗，抬高背景与环境光能量（外域不能抬，会过曝）
		env.background_energy_multiplier = Planet.profile().bg_energy
		env.ambient_light_energy = Planet.profile().ambient_energy + 0.15
	var prof := Planet.profile()
	_sky.cloud_intensity = 1.12
	_sky.sun_energy = prof.sun_energy
	_sky.ambient_energy = prof.ambient_energy
	# 球面世界天空偏暗（天顶深蓝近黑）：提曝光 + 大气日间色调
	if _sky.get("exposure") != null:
		_sky.exposure = prof.sky_exposure
	if env != null:
		env.tonemap_exposure = prof.tonemap_exposure
	call_deferred("_lock_noon")
	_sky_ready = true
	printerr("[World] 天空已初始化（%s）" % prof.display_name)


func _lock_noon() -> void:
	if _sky == null:
		return
	var tod = _sky.get("tod")
	if tod == null:
		return
	tod.current_time = 12.0
	tod.game_time_enabled = false
	tod.editor_time_enabled = false


func _apply_sky_params(f: float) -> void:
	if _sky == null:
		return
	var p := Planet.profile().sky_at(f)
	var day_tint: Color = p.get("day_tint", Color(0.6, 0.76, 1.0))
	var horizon: Color = p.get("horizon", Color(0.94, 0.97, 1.0))
	var sun_i: float = float(p.get("sun_intensity", 12.5))
	var mie: float = float(p.get("mie", 0.16))
	var cov: float = float(p.get("cumulus", 0.5))
	var fog_d: float = float(p.get("fog_density", 0.00042))
	var fog_l: Color = p.get("fog_light", Color(0.74, 0.86, 1.0))
	var amb: Color = p.get("ambient", Color(0.52, 0.66, 1.0))
	_atm_sun_base = sun_i
	if _sky.get("sky") != null and _sky.sky != null:
		var s = _sky.sky
		s.atm_day_tint = day_tint
		s.atm_horizon_light_tint = horizon
		s.atm_sun_intensity = sun_i
		s.atm_sun_mie_intensity = mie
		s.cumulus_visible = true
		s.cumulus_coverage = cov
		s.cirrus_visible = true
		s.cirrus_coverage = cov * 1.05
		s.fog_density = fog_d
	if _sky.environment != null:
		_sky.environment.fog_light_color = fog_l
		_sky.environment.fog_depth_begin = lerpf(320.0, 180.0, f)
		_sky.environment.ambient_light_color = amb
	# 【M47】地平线以下"行星地面"色必须跟随当前天色。
	# 默认是中立灰 (0.3,0.3,0.3)，在 shader 里再乘散射色 → 外域变成一条暗红硬边，
	# 与上方橙红天空撞色（用户截图里地平线那条横带）。取地平线色的 55%，
	# 既保留"远处地面压暗"的空气透视感，又不会有色相突变。
	if _sky.get("ground_color") != null:
		_sky.set("ground_color", Color(horizon.r * 0.55, horizon.g * 0.55,
			horizon.b * 0.58, 1.0))


func _update_zone_sky(delta: float) -> void:
	if not _sky_ready:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	# M45：离地 320m 以上（空中/太空视角）关掉距离雾——否则 6000m 外看星球
	# 整颗被雾糊成白蛋，看不到大陆轮廓。
	# M46：只在跨越阈值时改一次，避免每帧写 material（顺带修了"飞回地面雾不恢复"）。
	var alt: float = p.length() - Planet.RADIUS

	# 【M47】太空视角三重清理（用户 2026-10-22 退单那张"长霉橘子"图）：
	#   1) 关掉整层地表细节 —— 4600m 外 3720 块岩石/900 根蘑菇只有亚像素大小，
	#      在球面上糊成一片黑点噪斑
	#   2) 压薄大气 —— 不压的话整屏被外域的橙红大气糊住，看不到黑色太空
	#   3) 分区天色插值保持不动
	var space_t: float = clampf((alt - 400.0) / 800.0, 0.0, 1.0)
	var want_detail := space_t < 0.55
	if want_detail != _detail_shown:
		_detail_shown = want_detail
		if _detail_root != null:
			_detail_root.visible = want_detail
	if _sky.get("sky") != null and _sky.sky != null:
		_sky.sky.atm_thickness = lerpf(_atm_thick_base, 0.10, space_t)
		_sky.sky.atm_sun_intensity = lerpf(_atm_sun_base, _atm_sun_base * 0.10, space_t)

	var high := alt >= 320.0
	if high != _was_high:
		_was_high = high
		_apply_sky_params(_sky_blend)
		if _sky != null and _sky.environment != null:
			_sky.environment.fog_enabled = not high
		# Sky3D 自带的大气雾也必须一起关：它挂在天空材质上，不受 Environment.fog 影响
		if _sky.get("sky") != null and _sky.sky != null:
			_sky.sky.fog_density = 0.0 if high else float(_sky_a.get("fog_density", 0.00042))
	# 分区天色：只有支持双主题的星球（艾泽拉斯）才按 zone_factor 插值
	if not Planet.profile().uses_zone_blend:
		return
	var pl := Planet.plane_of(p)
	var target: float = WorldShape.zone_factor(pl.x, pl.y)
	if absf(target - _sky_blend) < 0.004:
		return
	_sky_blend = move_toward(_sky_blend, target, delta * 0.55)
	_apply_sky_params(_sky_blend)


# ===== 二/三/四、世界物件 =====

func _build_world() -> void:
	var t0 := Time.get_ticks_msec()
	var prof := Planet.profile()
	if prof.decor_style == "outland":
		_build_outland()
	else:
		_setup_water()
		_setup_grass()
		_setup_flowers()
		_setup_trees()
		_setup_rocks()
		_setup_hellfire_props()
		_build_village()
	printerr("[World] 装饰完成 %dms · 风格=%s" % [Time.get_ticks_msec() - t0, prof.decor_style])


func _build_village() -> void:
	var v := VillageLayout.new()
	v.name = "VillageLayout"
	_detail_root.add_child(v)
	v.build()


## 地表是否适合放物件（避开村庄、道路、水面、陡坡）
func _placeable(x: float, z: float, min_h: float, max_h: float) -> bool:
	if VILLAGE_AVOID.has_point(Vector2(x, z)):
		return false
	if WorldShape.road_distance(x, z) < ROAD_CLEAR:
		return false
	var h := WorldShape.height_at(x, z)
	if h < min_h or h > max_h:
		return false
	# 湖面以下不放（水里长草/长树都怪）
	if Vector2(x, z).distance_to(WorldShape.LAKE_CENTER) < WorldShape.LAKE_RADIUS * 0.92:
		if h < WorldShape.LAKE_WATER + 0.4:
			return false
	return true



## 地形网格一致高度：统一走 Planet.mesh_height（单点实现，别在这里再抄一份）
func _mesh_height(dir: Vector3) -> float:
	return Planet.mesh_height(dir)


## M45：平面 (x,z) + yaw + 缩放 → 星球表面变换（Y 轴对齐当地法线）
## 撒点仍按平面坐标做（村庄周边的疏密关系不变），落点再投到球面。
func _sphere_xf(x: float, z: float, yaw: float, s: Vector3, lift: float = 0.0) -> Transform3D:
	var d := Planet.dir_from_plane(x, z)
	var pos: Vector3 = d * (Planet.RADIUS + _mesh_height(d) + lift)
	var b := Planet.align_basis(d, Basis(Vector3.UP, yaw) * Vector3.FORWARD)
	return Transform3D(b.scaled(s), pos)


## 【M46 事故修复 · 必读】
## 旧写法是「MultiMesh.instance_count = 上限 → 逐个写 transform → 最后改小到实际数量」。
## 窗口模式实测（tools/mm_probe.gd）：
##   count=100 写满 50 个，get_aabb() 正常 → 再 instance_count = 50 → get_aabb() 变成 (0,0,0)，
##   实例数据被整块清零。
## 后果：只要"实际数量 < 上限"，这批物件就完全不可见——岩石/芦苇/骸骨/浮空岛
## 从 M44 起一直没渲染出来，因为草和花恰好是满额所以没人发现。
## 正确做法：先收集到数组，再一次性把 count 从 0 设为实际数量，然后写入。
func _new_multimesh(mesh: Mesh, _count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	# 故意不设 instance_count（保持 0）——见上面的坑
	return mm


## 把收集好的变换（+可选实例色）一次性灌进 MultiMesh 并挂成节点。
## colors 非空时自动开 use_colors；use_colors 必须在 instance_count 之前设，
## 否则同样会重建缓冲清零数据。
func _finalize_mm(mm: MultiMesh, xforms: Array, colors: Array = [],
		node_name: String = "", mat: Material = null) -> void:
	if not colors.is_empty():
		mm.use_colors = true
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i] as Transform3D)
		if not colors.is_empty():
			mm.set_instance_color(i, colors[i] as Color)
	if node_name != "":
		_add_mmi_planet(mm, node_name, mat)


## 【M46 事故修复 · 必读】
## 材质必须走 material_override，不能设在 PrimitiveMesh.material 上：
##   PrimitiveMesh（SphereMesh/CylinderMesh）的 surface 在第一次生成后，
##   再改 .material 不会重建，材质被静默丢弃 → 渲染成纯黑（太空视角看是
##   球面上一片黑点）。艾泽拉斯的岩石从 M44 起就是这个状态。
## 【M47 太空视角修复】地表细节必须在远处消失。
## 4600m 外看星球时，2~7 米的岩石/蘑菇/骨刺只有亚像素大小，3720 块石头会在
## 球面上糊成一片"霉斑黑点"（用户 2026-10-22 直接退单的那张 c1 图）。
## 而且玩家在地面时根本看不到 900m 外的东西（R=2200 时地平线只有 86m），
## 所以这个裁剪对第一人称体验零影响，只对高空/太空视角生效。
const DETAIL_RANGE := 900.0

func _mark_detail(n: GeometryInstance3D) -> void:
	n.visibility_range_end = DETAIL_RANGE
	n.visibility_range_end_margin = 140.0
	n.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _add_mmi(mm: MultiMesh, node_name: String, mat: Material = null) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = node_name
	if mat != null:
		mmi.material_override = mat
	# 全图范围的 AABB，避免"离开初始视锥后整片消失"的剔除事故
	mmi.custom_aabb = AABB(Vector3(-820, -120, -820), Vector3(1640, 560, 1640))
	_mark_detail(mmi)
	_detail_root.add_child(mmi)


# ===== M46：外域装饰（全 6 面撒点，不再用平面坐标）=====

## 按「面 + 面内 uv」撒点：Y 轴对齐当地法线。外域没有平面世界，只能这样撒。
func _face_xf(face: int, u: float, v: float, yaw: float, s: Vector3, lift: float = 0.0) -> Transform3D:
	var d := Planet.dir_of(face, u, v)
	var b := Planet.align_basis(d, Basis(Vector3.UP, yaw) * Vector3.FORWARD)
	return Transform3D(b.scaled(s), d * (Planet.RADIUS + _mesh_height(d) + lift))


## 在面上随机找一个高度落在 [min_h, max_h] 的点，返回 [u, v]，失败返回空数组
func _pick_face_point(face: int, rng: RandomNumberGenerator, min_h: float, max_h: float) -> Array:
	for _i in 16:
		var u := rng.randf_range(-0.82, 0.82)
		var v := rng.randf_range(-0.82, 0.82)
		var d := Planet.dir_of(face, u, v)
		var h := Planet.height_at(d)
		if h < min_h or h > max_h:
			continue
		return [u, v]
	return []


func _add_mmi_planet(mm: MultiMesh, node_name: String, mat: Material = null) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = node_name
	if mat != null:
		mmi.material_override = mat
	# 整颗星球的 AABB（含悬空岛）
	var r := Planet.RADIUS + 400.0
	mmi.custom_aabb = AABB(Vector3(-r, -r, -r), Vector3(r * 2.0, r * 2.0, r * 2.0))
	_mark_detail(mmi)
	_detail_root.add_child(mmi)


func _build_outland() -> void:
	_out_rocks()
	_out_mushrooms()
	_out_crystals()
	_out_bones()
	_out_floating_isles()
	printerr("[World] 外域装饰：岩石/蘑菇/水晶/骸骨/浮空岛")


## 每面的岩石基色（外域各地质区差异很大）
## 注意：不能用 MultiMesh 的 instance color —— 本机实测被渲染成纯黑
## （vertex_color_use_as_albedo 吃不到 use_colors 的实例色），
## 所以改成"每面一个材质 + 一个 MultiMesh"，代价是 6 个 draw call。
func _out_rock_albedo(face: int) -> Color:
	match face:
		0: return Color(0.28, 0.14, 0.10)   # 地狱火：深红褐岩柱（比红土深，但不到黑）
		1: return Color(0.26, 0.34, 0.30)   # 赞加：湿岩
		2: return Color(0.34, 0.30, 0.22)   # 纳格兰：暖灰
		3: return Color(0.33, 0.28, 0.23)   # 刀锋山：褐灰
		4: return Color(0.28, 0.18, 0.28)   # 影月谷：紫黑
		_: return Color(0.30, 0.20, 0.40)   # 虚空风暴：紫


# ----- 岩石（6 面铺满，每面一套材质）-----

func _out_rocks() -> void:
	var rk := SphereMesh.new()
	rk.radius = 1.0
	rk.height = 1.0
	rk.radial_segments = 6
	rk.rings = 3

	var per_face := 620
	var rng := RandomNumberGenerator.new()
	rng.seed = 771003
	var total := 0
	for face in 6:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _out_rock_albedo(face)
		mat.roughness = 0.96
		var m := rk.duplicate() as SphereMesh
		m.material = mat
		var mm := _new_multimesh(m, 0)
		var xs: Array[Transform3D] = []
		for _i in per_face * 5:
			if xs.size() >= per_face:
				break
			var pt := _pick_face_point(face, rng, 2.0, 340.0)
			if pt.is_empty():
				continue
			var s := rng.randf_range(2.0, 6.5)
			# 岩刺：Y 方向随机拉长，XZ 收窄 → 尖石而不是圆石
			var sy := rng.randf_range(0.6, 2.2)
			xs.append(_face_xf(face, pt[0], pt[1], rng.randf_range(0.0, TAU),
				Vector3(s, s * sy, s * rng.randf_range(0.7, 1.3)), -s * 0.28))
		_finalize_mm(mm, xs, [], "OutRocks%d" % face, mat)
		total += xs.size()
	printerr("[World] 外域岩石 ", total)


# ----- 巨型蘑菇（赞加沼泽标志）-----

func _out_mushrooms() -> void:
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.62, 0.66, 0.52)
	stem_mat.roughness = 0.9
	var stem := CylinderMesh.new()
	stem.top_radius = 0.55
	stem.bottom_radius = 0.85
	stem.height = 5.0
	stem.radial_segments = 8
	stem.material = stem_mat

	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.30, 0.62, 0.66)
	cap_mat.roughness = 0.55
	cap_mat.emission_enabled = true
	cap_mat.emission = Color(0.18, 0.58, 0.52)
	cap_mat.emission_energy_multiplier = 0.35
	var cap := SphereMesh.new()
	cap.radius = 2.6
	cap.height = 1.5
	cap.radial_segments = 12
	cap.rings = 5
	cap.material = cap_mat

	# 杆 + 盖两套 MultiMesh 共用同一批放置点（MultiMesh 只吃一个 mesh）
	var mm_stem := _new_multimesh(stem, 0)
	var mm_cap := _new_multimesh(cap, 0)
	var xs_stem: Array[Transform3D] = []
	var xs_cap: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 66017
	# 面 1（赞加沼泽）密，其余面稀疏
	for face in 6:
		var target_n: int = 900 if face == 1 else (120 if face == 2 else 0)
		if target_n == 0:
			continue
		var n := 0
		for _i in target_n * 8:
			if n >= target_n:
				break
			var pt := _pick_face_point(face, rng, 1.0, 90.0)
			if pt.is_empty():
				continue
			var s := rng.randf_range(0.9, 2.8)
			var yaw := rng.randf_range(0.0, TAU)
			var lean := rng.randf_range(-0.10, 0.10)
			var sy := rng.randf_range(0.9, 1.4)
			# 【坑】translated_local 的偏移会被 basis 的缩放再乘一次，
			# 所以这里必须传 mesh 的**本地**坐标（CylinderMesh 半高 2.5、全高 5.0），
			# 不能传"已经算上 scale 的米数"——那样杆会飞出天际、伞盖跟杆脱节。
			var xf := _face_xf(face, pt[0], pt[1], yaw, Vector3(s, s * sy, s), -0.4)
			# 杆：底部贴地（mesh 原点在中心 → 上移半个本地高度）
			xs_stem.append(xf.translated_local(Vector3(0, 2.5, 0)))
			# 盖：坐在杆顶（沿法线抬到杆高，用 lift 而不是 translated_local）
			var stem_h: float = 5.0 * s * sy
			var cap_xf := _face_xf(face, pt[0], pt[1], yaw, Vector3(s, s * 0.62, s),
				stem_h - 0.55 * s)
			xs_cap.append(cap_xf.rotated_local(Vector3.RIGHT, lean))
			n += 1
	_finalize_mm(mm_stem, xs_stem, [], "OutMushroomStems", stem_mat)
	_finalize_mm(mm_cap, xs_cap, [], "OutMushroomCaps", cap_mat)
	printerr("[World] 外域蘑菇 ", xs_stem.size())


# ----- 邪能水晶（影月谷 / 虚空风暴）-----

func _out_crystals() -> void:
	# 八面体：少段数的球拉高 = 尖晶
	var cry := SphereMesh.new()
	cry.radius = 0.7
	cry.height = 1.0
	cry.radial_segments = 4
	cry.rings = 2

	var rng := RandomNumberGenerator.new()
	rng.seed = 314159
	var total := 0
	for face in 6:
		var target_n: int = 0
		match face:
			0: target_n = 110
			4: target_n = 260
			5: target_n = 230
			_: target_n = 40
		# 面 5 虚空风暴偏紫，其余偏邪能绿
		var mat := StandardMaterial3D.new()
		var tint := Color(0.62, 0.34, 1.0) if face == 5 else Color(0.34, 1.0, 0.42)
		mat.albedo_color = tint * 0.55
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = 1.9
		mat.roughness = 0.22
		mat.metallic = 0.35
		var m := cry.duplicate() as SphereMesh
		m.material = mat
		var mm := _new_multimesh(m, 0)
		var xs: Array[Transform3D] = []
		for _i in target_n * 8:
			if xs.size() >= target_n:
				break
			var pt := _pick_face_point(face, rng, 2.0, 280.0)
			if pt.is_empty():
				continue
			var s := rng.randf_range(2.2, 5.5)
			var tall := rng.randf_range(2.6, 6.5)
			var tilt := Vector3(rng.randf_range(-0.22, 0.22), 0.0, rng.randf_range(-0.22, 0.22))
			var xf := _face_xf(face, pt[0], pt[1], rng.randf_range(0.0, TAU),
				Vector3(s, s * tall, s), -0.2)
			if tilt.length_squared() > 0.0001:
				xf = xf.rotated_local(Vector3.RIGHT, tilt.x).rotated_local(Vector3.BACK, tilt.z)
			xs.append(xf)
		_finalize_mm(mm, xs, [], "OutCrystals%d" % face, mat)
		total += xs.size()
	printerr("[World] 邪能水晶 ", total)


# ----- 巨兽骸骨（地狱火半岛）-----

func _out_bones() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.83, 0.74)
	mat.roughness = 0.82
	var rib := CylinderMesh.new()
	rib.top_radius = 0.10
	rib.bottom_radius = 0.26
	rib.height = 11.0
	rib.radial_segments = 5
	rib.material = mat

	var mm := _new_multimesh(rib, 0)
	var xs: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 202020
	for face in 6:
		var target_n: int = 220 if face == 0 else 45
		var n := 0
		for _i in target_n * 8:
			if n >= target_n:
				break
			var pt := _pick_face_point(face, rng, 2.0, 140.0)
			if pt.is_empty():
				continue
			var s := rng.randf_range(1.0, 2.6)
			# 肋骨斜插进地里
			var xf := _face_xf(face, pt[0], pt[1], rng.randf_range(0.0, TAU),
				Vector3(s, s * rng.randf_range(0.7, 1.5), s), 1.4 * s)
			xs.append(xf.rotated_local(Vector3.RIGHT, rng.randf_range(0.18, 0.55)))
			n += 1
	_finalize_mm(mm, xs, [], "OutBones", mat)
	printerr("[World] 骸骨 ", xs.size())


# ----- 纳格兰浮空岛 / 虚空风暴碎岛 -----

func _out_floating_isles() -> void:
	# 岛体：倒锥台（上大下尖）= 典型浮空岛剪影
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.34, 0.28, 0.24)
	rock_mat.roughness = 0.95
	var body := CylinderMesh.new()
	body.top_radius = 1.0
	body.bottom_radius = 0.06
	body.height = 1.0
	body.radial_segments = 9
	body.material = rock_mat

	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_color = Color(0.30, 0.48, 0.22)
	top_mat.roughness = 0.92
	var top_disc := CylinderMesh.new()
	top_disc.top_radius = 1.0
	top_disc.bottom_radius = 1.0
	top_disc.height = 0.12
	top_disc.radial_segments = 9
	top_disc.material = top_mat

	var mm_body := _new_multimesh(body, 0)
	var mm_top := _new_multimesh(top_disc, 0)
	var xs_body: Array[Transform3D] = []
	var xs_top: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 919191
	for face in 6:
		var target_n: int = 0
		match face:
			2: target_n = 30
			5: target_n = 26
			4: target_n = 12
			_: target_n = 4
		if target_n == 0:
			continue
		var n := 0
		for _i in target_n * 10:
			if n >= target_n:
				break
			var pt := _pick_face_point(face, rng, 4.0, 200.0)
			if pt.is_empty():
				continue
			var r := rng.randf_range(14.0, 46.0)
			var depth := rng.randf_range(1.4, 3.2)
			var lift := rng.randf_range(42.0, 150.0)
			var d := Planet.dir_of(face, pt[0], pt[1])
			var h := Planet.height_at(d)
			var base := d * (Planet.RADIUS + h + lift)
			var b := Planet.align_basis(d, Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Vector3.FORWARD)
			# 岛体：原点在中心，向下偏移让顶面正好在 base
			xs_body.append(Transform3D(b.scaled(Vector3(r, r * depth, r)),
				base - d * (r * depth * 0.5)))
			xs_top.append(Transform3D(b.scaled(Vector3(r, 1.0, r)), base))
			n += 1
	_finalize_mm(mm_body, xs_body, [], "OutFloatingBodies", rock_mat)
	_finalize_mm(mm_top, xs_top, [], "OutFloatingTops", top_mat)
	printerr("[World] 浮空岛 ", xs_body.size())


# ----- 湖泊 -----

func _setup_water() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.36, 0.40, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.06
	mat.metallic = 0.42
	mat.metallic_specular = 0.75
	mat.rim_enabled = true
	mat.rim = 0.35
	var disc := CylinderMesh.new()
	disc.top_radius = WorldShape.LAKE_RADIUS * 0.99
	disc.bottom_radius = WorldShape.LAKE_RADIUS * 0.99
	disc.height = 0.3
	disc.radial_segments = 48
	disc.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "LakeSurface"
	mi.mesh = disc
	add_child(mi)
	# M45：湖面贴到球面（圆盘局部仍平，118m 半径在 R=2200 上弦高约 1.6m，被岸线遮住）
	var ld := Planet.dir_from_plane(WorldShape.LAKE_CENTER.x, WorldShape.LAKE_CENTER.y)
	mi.global_transform = Transform3D(Planet.align_basis(ld, Vector3.FORWARD),
		ld * (Planet.RADIUS + WorldShape.LAKE_WATER))
	# 湖岸芦苇（细长锥，成圈）
	var reed_mat := StandardMaterial3D.new()
	reed_mat.albedo_color = Color(0.42, 0.44, 0.22)
	reed_mat.roughness = 0.95
	var reed := CylinderMesh.new()
	reed.top_radius = 0.02
	reed.bottom_radius = 0.09
	reed.height = 1.5
	reed.radial_segments = 4
	reed.material = reed_mat
	var mm := _new_multimesh(reed, 900)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8811
	var xs: Array[Transform3D] = []
	for i in 900:
		var a := rng.randf_range(0.0, TAU)
		var r := WorldShape.LAKE_RADIUS * rng.randf_range(0.86, 1.16)
		var x: float = WorldShape.LAKE_CENTER.x + cos(a) * r
		var z: float = WorldShape.LAKE_CENTER.y + sin(a) * r
		var h := WorldShape.height_at(x, z)
		if h < WorldShape.LAKE_WATER - 0.3:
			continue
		var s := rng.randf_range(0.7, 1.5)
		xs.append(_sphere_xf(x, z, rng.randf_range(0.0, TAU), Vector3(s, s, s)))
	_finalize_mm(mm, xs)
	_add_mmi(mm, "LakeReeds", reed_mat)
	printerr("[World] 湖面 + 芦苇 ", xs.size())


# ----- 草浪（莫高雷的地表质感主力）-----

func _setup_grass() -> void:
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.62, 0.60, 0.26)
	gmat.roughness = 0.95
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var blade := CylinderMesh.new()
	blade.top_radius = 0.0
	blade.bottom_radius = 0.30
	blade.height = 1.05
	blade.radial_segments = 3
	blade.material = gmat
	var mm := _new_multimesh(blade, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 440011
	var xs: Array[Transform3D] = []
	var tries := 0
	while xs.size() < GRASS_COUNT and tries < GRASS_COUNT * 12:
		tries += 1
		var x := rng.randf_range(-780.0, 780.0)
		var z := rng.randf_range(-780.0, 780.0)
		# 只在草原（zone_factor 小）+ 低海拔
		if WorldShape.zone_factor(x, z) > 0.34:
			continue
		if not _placeable(x, z, 0.5, 70.0):
			continue
		var s := rng.randf_range(0.8, 1.9)
		xs.append(_sphere_xf(x, z, rng.randf_range(0.0, TAU),
			Vector3(s, s * rng.randf_range(0.8, 1.4), s), -0.08))
	_finalize_mm(mm, xs)
	_add_mmi(mm, "GrassBlades", gmat)
	printerr("[World] 草浪 ", xs.size())


# ----- 野花 -----

func _setup_flowers() -> void:
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.94, 0.94, 0.90)
	fmat.roughness = 0.8
	fmat.emission_enabled = true
	fmat.emission = Color(0.55, 0.55, 0.5)
	fmat.emission_energy_multiplier = 0.12
	var petal := SphereMesh.new()
	petal.radius = 0.10
	petal.height = 0.20
	petal.radial_segments = 5
	petal.rings = 2
	petal.material = fmat
	var mm := _new_multimesh(petal, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909090
	var xs: Array[Transform3D] = []
	var tries := 0
	while xs.size() < FLOWER_COUNT and tries < FLOWER_COUNT * 10:
		tries += 1
		var x := rng.randf_range(-420.0, 420.0)
		var z := rng.randf_range(-360.0, 420.0)
		if WorldShape.zone_factor(x, z) > 0.25:
			continue
		if not _placeable(x, z, 0.5, 60.0):
			continue
		var s := rng.randf_range(0.6, 1.3)
		xs.append(_sphere_xf(x, z, 0.0, Vector3(s, s, s), 0.35))
	_finalize_mm(mm, xs)
	_add_mmi(mm, "Flowers", fmat)
	printerr("[World] 野花 ", xs.size())


# ----- 针叶林（莫高雷）-----

func _tree_meshes() -> Array:
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.22, 0.16, 0.11)
	trunk_mat.roughness = 1.0
	# 冷杉：深绿三层锥冠（参考图里那种高瘦针叶树）
	var leaf_a := StandardMaterial3D.new()
	leaf_a.albedo_color = Color(0.055, 0.125, 0.075)
	leaf_a.roughness = 0.95
	var leaf_b := StandardMaterial3D.new()
	leaf_b.albedo_color = Color(0.075, 0.165, 0.090)
	leaf_b.roughness = 0.95

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.42
	trunk.height = 7.0
	trunk.radial_segments = 5
	trunk.material = trunk_mat

	var specs := [
		[3.1, 5.0], [2.4, 4.6], [1.5, 4.0],
	]
	var meshes: Array = [trunk]
	var i := 0
	for sp in specs:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = sp[0]
		c.height = sp[1]
		c.radial_segments = 7
		c.material = leaf_a if i % 2 == 0 else leaf_b
		meshes.append(c)
		i += 1
	# 相对树根的偏移
	var offsets := [Vector3(0, 3.5, 0), Vector3(0, 6.0, 0), Vector3(0, 9.2, 0), Vector3(0, 12.0, 0)]
	return [meshes, offsets]


func _setup_trees() -> void:
	var pack := _tree_meshes()
	var meshes: Array = pack[0]
	var offsets: Array = pack[1]
	var mms: Array = []
	for m in meshes:
		mms.append(_new_multimesh(m, TREE_COUNT))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	var occupied := {}
	var cell := 13.0
	var tree_xfs: Array[Transform3D] = []
	var tries := 0
	# 先种近景大树（村周环带，参考图"村口两排巨杉"的感觉）
	while tree_xfs.size() < 120 and tries < 6000:
		tries += 1
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(126.0, 230.0)
		var x: float = cos(a) * r
		var z: float = -130.0 + sin(a) * r
		if not _placeable(x, z, 0.4, 46.0):
			continue
		var c2 := Vector2i(int(floor(x / cell)), int(floor(z / cell)))
		if occupied.has(c2):
			continue
		occupied[c2] = true
		tree_xfs.append(_tree_xf(x, z, rng.randf_range(1.35, 2.05), rng))
	# 再撒全图针叶林（用正弦场聚簇，形成林间空地而不是均匀铺满）
	tries = 0
	while tree_xfs.size() < TREE_COUNT and tries < TREE_COUNT * 30:
		tries += 1
		var x := rng.randf_range(-780.0, 780.0)
		var z := rng.randf_range(-780.0, 780.0)
		if WorldShape.zone_factor(x, z) > 0.30:
			continue
		if not _placeable(x, z, 0.4, 52.0):
			continue
		var clump := sin(x * 0.0125 + 1.7) * cos(z * 0.0102 - 0.6) + sin((x + z) * 0.0031)
		if clump < 0.05 and rng.randf() > 0.18:
			continue
		var c3 := Vector2i(int(floor(x / cell)), int(floor(z / cell)))
		if occupied.has(c3):
			continue
		var too_close := false
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if occupied.has(Vector2i(c3.x + dx, c3.y + dz)):
					too_close = true
					break
			if too_close:
				break
		if too_close and rng.randf() > 0.12:
			continue
		occupied[c3] = true
		tree_xfs.append(_tree_xf(x, z, rng.randf_range(0.75, 1.55), rng))
	# 三套 mesh（树干 + 两层锥冠）共用同一批落点，各自按 offsets 平移
	for i in mms.size():
		var xs: Array[Transform3D] = []
		for xf in tree_xfs:
			xs.append(xf * Transform3D(Basis(), offsets[i]))
		_finalize_mm(mms[i], xs)
		_add_mmi(mms[i], "ConiferTrees%d" % i,
			(meshes[i] as Mesh).surface_get_material(0))
	printerr("[World] 针叶林 ", tree_xfs.size(), " 棵")


func _tree_xf(x: float, z: float, s: float, rng: RandomNumberGenerator) -> Transform3D:
	return _sphere_xf(x, z, rng.randf_range(0.0, TAU), Vector3(s, s, s))


# ----- 岩石（莫高雷灰岩 / 地狱火红岩）-----

func _setup_rocks() -> void:
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.44, 0.43, 0.41)
	grey.roughness = 0.95
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.46, 0.21, 0.13)
	red.roughness = 0.95
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 1.4
	rock.radial_segments = 6
	rock.rings = 3
	rock.material = grey

	var mm_g := _new_multimesh(rock, 0)
	var rock_r := rock.duplicate() as SphereMesh
	rock_r.material = red
	var mm_r := _new_multimesh(rock_r, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var xs_g: Array[Transform3D] = []
	var xs_r: Array[Transform3D] = []
	var tries := 0
	while xs_g.size() + xs_r.size() < ROCK_COUNT and tries < ROCK_COUNT * 25:
		tries += 1
		var x := rng.randf_range(-790.0, 790.0)
		var z := rng.randf_range(-790.0, 790.0)
		var h := WorldShape.height_at(x, z)
		if VILLAGE_AVOID.has_point(Vector2(x, z)):
			continue
		if WorldShape.road_distance(x, z) < 4.0:
			continue
		# 低处只留少量（草原以草为主），高处成片
		if h < 30.0 and rng.randf() > 0.28:
			continue
		var hell := WorldShape.zone_factor(x, z) > 0.5
		var s := rng.randf_range(0.8, 3.6) * (1.6 if h > 70.0 else 1.0)
		var xf := _sphere_xf(x, z, rng.randf_range(0.0, TAU),
			Vector3(s * rng.randf_range(0.8, 1.5), s * rng.randf_range(0.5, 1.1), s * rng.randf_range(0.8, 1.5)),
			-s * 0.25)
		if hell and xs_r.size() < ROCK_COUNT:
			xs_r.append(xf)
		elif xs_g.size() < ROCK_COUNT:
			xs_g.append(xf)
	_finalize_mm(mm_g, xs_g)
	_finalize_mm(mm_r, xs_r)
	_add_mmi(mm_g, "RocksGrey", grey)
	_add_mmi(mm_r, "RocksRed", red)
	printerr("[World] 岩石 灰", xs_g.size(), " 红", xs_r.size())


# ----- 地狱火：枯树 + 骨堆 -----

func _setup_hellfire_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 66601

	# 枯树：细黑树干
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.16, 0.12, 0.10)
	bark.roughness = 1.0
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.06
	trunk.bottom_radius = 0.30
	trunk.height = 5.2
	trunk.radial_segments = 5
	trunk.material = bark
	var mm_t := _new_multimesh(trunk, 0)
	var xs_t: Array[Transform3D] = []
	var tries := 0
	while xs_t.size() < DEAD_TREE_COUNT and tries < DEAD_TREE_COUNT * 25:
		tries += 1
		var x := rng.randf_range(-780.0, 780.0)
		var z := rng.randf_range(-800.0, -400.0)
		if WorldShape.zone_factor(x, z) < 0.55:
			continue
		if WorldShape.road_distance(x, z) < 6.0:
			continue
		var h := WorldShape.height_at(x, z)
		if h < 22.0 or h > 90.0:
			continue
		var sc := rng.randf_range(0.7, 1.6)
		xs_t.append(_sphere_xf(x, z, rng.randf_range(0.0, TAU),
			Vector3(sc, sc * rng.randf_range(0.8, 1.5), sc), 2.5 * sc))
	_finalize_mm(mm_t, xs_t)
	_add_mmi(mm_t, "DeadTrees", bark)

	# 骨堆：骨白色肋骨插在地上
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.80, 0.76, 0.64)
	bone.roughness = 0.85
	var rib := CylinderMesh.new()
	rib.top_radius = 0.10
	rib.bottom_radius = 0.14
	rib.height = 2.2
	rib.radial_segments = 5
	rib.material = bone
	var mm_b := _new_multimesh(rib, 0)
	var xs_b: Array[Transform3D] = []
	tries = 0
	while xs_b.size() < BONE_COUNT and tries < BONE_COUNT * 25:
		tries += 1
		var x := rng.randf_range(-700.0, 700.0)
		var z := rng.randf_range(-800.0, -450.0)
		if WorldShape.zone_factor(x, z) < 0.6:
			continue
		if WorldShape.road_distance(x, z) < 4.0:
			continue
		var h := WorldShape.height_at(x, z)
		if h < 24.0 or h > 80.0:
			continue
		var n := rng.randi_range(3, 5)
		for k in n:
			if xs_b.size() >= BONE_COUNT:
				break
			var ang := rng.randf_range(0.0, TAU)
			var tilt := rng.randf_range(0.9, 1.45)
			var base := _sphere_xf(x, z, 0.0, Vector3.ONE)
			var local := Transform3D(Basis(Vector3.RIGHT, tilt).rotated(Vector3.UP, ang),
				Vector3(cos(ang) * 0.9, 0.15, sin(ang) * 0.9))
			xs_b.append(base * local)
	_finalize_mm(mm_b, xs_b)
	_add_mmi(mm_b, "BonePiles", bone)
	printerr("[World] 地狱火：枯树 ", xs_t.size(), " / 骨堆 ", xs_b.size(), " 根")
