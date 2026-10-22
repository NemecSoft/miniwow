extends Node3D

## M15：Plush 伙伴"小跟班"（设计文档 5.10）。
## 纯表现单机实体：不进多人同步（不在 PlayersContainer，各端玩家有自己的伙伴）、
## 不可被打、无碰撞（直接 lerp 位置，不走物理）。
## 跟随规则：距离 <2.5 米待机；2.5~6 米步行；6~12 米奔跑；>15 米瞬移兜底。

const PARTNER_SCENE := "res://scenes/npcs/partner.tscn"
## M16b 修正：glb 内部没有任何材质，COLOR_0 顶点色方案无效（贴出来仍是白的）——
## 原始配色其实靠 Jeheno 包里的贴图。改用官方 ShaderMaterial
## （albedo+normal 贴图，godot_plush.gdshader 带菲涅尔边缘光）覆盖全部 surface。
const PLUSH_MAT := preload("res://assets/characters/partner/plush_mat.tres")
## 跟随距离阈值（米）
const DIST_IDLE := 2.5
const DIST_WALK := 6.0
const DIST_TELEPORT := 15.0
## 移动速度（米/秒），与动画节奏匹配
const WALK_SPEED := 2.6
const RUN_SPEED := 5.5
## 位置/朝向平滑系数
const LERP_POS := 6.0
const LERP_YAW := 8.0
## 交互提示显示距离
const INTERACT_RANGE := 3.0

## 动画名（探针 probe_plush 实测：AnimationPlayer 在根级，小写无前缀）
const ANIM_IDLE := &"idle"
const ANIM_WALK := &"walk"
const ANIM_RUN := &"run"
const ANIM_WAVE := &"wave"

var owner_player: CharacterBody3D
var _is_waving := false

# AnimationPlayer 在 glb 实例内部（Plush/glb 根/AnimationPlayer），非本节点直接子级
@onready var anim_player: AnimationPlayer = $Plush/AnimationPlayer
@onready var interact_prompt: Label3D = $InteractPrompt


func _ready() -> void:
	add_to_group("partners")
	_apply_plush_material()
	if anim_player and anim_player.has_animation(ANIM_IDLE):
		anim_player.play(ANIM_IDLE)
	if anim_player and anim_player.has_animation(ANIM_WAVE):
		anim_player.get_animation(ANIM_WAVE).loop_mode = Animation.LOOP_NONE
	# M19：漂浮伙伴无互动——交互提示永久隐藏
	if interact_prompt:
		interact_prompt.visible = false
	# 模型自带 Y 立方体型，缩放到与机器人协调的高度（约 0.9 米）
	scale = Vector3.ONE * 0.5
	_build_aura()


func _apply_plush_material() -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		# M41：光晕是 MeshInstance3D，不能被 Plush 材质覆盖（否则加法光斑变成实体白块）
		if mi.name == "AuraHalo":
			continue
		for surface in mi.mesh.get_surface_count():
			mi.set_surface_override_material(surface, PLUSH_MAT)


## M19 漂浮模式（原神派蒙式）：小型、悬空跟随、正弦浮动、无交互
const HOVER_HEIGHT := 1.6          # 悬浮高度（玩家脚底起算）
const HOVER_SIDE := 0.9            # 右侧偏移
const HOVER_BACK := 0.8            # 后方偏移
const HOVER_AMPLITUDE := 0.12      # 上下浮动幅度
const HOVER_FREQ := 2.0            # 浮动频率
const FOLLOW_LERP := 5.0           # 位置平滑
var _hover_t := 0.0


func _physics_process(delta: float) -> void:
	if owner_player == null or not is_instance_valid(owner_player):
		return
	_hover_t += delta
	var hover_wave: float = sin(_hover_t * TAU * HOVER_FREQ) * HOVER_AMPLITUDE

	# 目标点：玩家右后上方的漂浮位（随玩家朝向旋转）
	var offset := owner_player.global_transform.basis * Vector3(HOVER_SIDE, 0, HOVER_BACK)
	var target := owner_player.global_position + Vector3(offset.x, HOVER_HEIGHT, offset.z)
	target.y += hover_wave

	# 瞬移兜底（传送/重生后快速归位）
	if global_position.distance_to(target) > 15.0:
		global_position = target
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-FOLLOW_LERP * delta))

	# 面朝主人
	var to_player := owner_player.global_position - global_position
	rotation.y = lerp_angle(rotation.y, atan2(to_player.x, to_player.z), 1.0 - exp(-8.0 * delta))

	# 漂浮时播放待机动画
	_play(ANIM_IDLE)


## M19 模型替换接口：传入新模型场景替换默认 Plush（保留漂浮/跟随行为）
func set_model(model_scene: PackedScene) -> void:
	var old := $Plush
	if old:
		old.queue_free()
	var inst := model_scene.instantiate()
	inst.name = "Plush"
	add_child(inst)
	_apply_plush_material()


func _update_interact_prompt(distance: float) -> void:
	if interact_prompt:
		interact_prompt.visible = distance <= INTERACT_RANGE


## 玩家按 E 打招呼：挥手一次后回待机（与 villager.say_hello 同模式）
func say_hello() -> void:
	if _is_waving:
		return
	# AnimationPlayer 缺失时直接放弃，避免 _is_waving 卡死导致跟随停摆
	if anim_player == null or not anim_player.has_animation(ANIM_WAVE):
		return
	_is_waving = true
	anim_player.play(ANIM_WAVE)
	if not anim_player.animation_finished.is_connected(_on_wave_finished):
		anim_player.animation_finished.connect(_on_wave_finished)


func _on_wave_finished(anim_name: StringName) -> void:
	if anim_name == ANIM_WAVE:
		_is_waving = false
		_play(ANIM_IDLE)


func _play(state: StringName) -> void:
	if anim_player and anim_player.has_animation(state) and anim_player.current_animation != String(state):
		anim_player.play(state)


## M41：小精灵星尘/火焰光环（原神派蒙式细密晶晶亮）
## 迭代史（三版都栽在不同地方，写下来防复发）：
##   v1 QuadMesh 没有 alpha 贴图 → 渲染成硬边方块（用户原话"橙色马赛克"）；
##   v2 换成径向柔光点 → 够柔了，但太稀太小（本节点 _ready 里 scale=0.5，粒子尺寸被连带减半）；
##   v3 程序化四角星贴图（"晶晶亮"的关键是星芒不是圆点）+ 光晕，但尺寸/亮度调过头 → 过曝成白团；
##   v4（当前）收敛尺寸与 energy，回到"细密晶亮"。
## 注意：本节点 _ready 里 scale=0.5，下面所有 QuadMesh.size / 发射半径都是局部值，
##       世界尺寸 = 局部值 × 0.5（例如 dq.size=0.12 → 世界 6cm）。
var _aura_color: Color = Color(0.72, 0.86, 1.0)   # 默认白蓝星尘（火焰主题可切换）
var _aura_particles: Array[GPUParticles3D] = []
var _aura_light: OmniLight3D = null
var _aura_halo: MeshInstance3D = null
var _soft_dot: GradientTexture2D = null
var _star_tex: ImageTexture = null


## 径向渐变柔光点：中心实、边缘透明。用于火星与光晕（圆润不刺眼）。
func _make_soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.30, 0.68, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.66),
		Color(1, 1, 1, 0.16),
		Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


## 程序化四角星贴图：实心亮核 + 四道十字光刺 + 四道弱斜刺。
## 这是"晶晶亮"和"糊成一团光斑"的分水岭——圆点永远出不来星芒感。
func _make_star_texture(size: int) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size) * 0.5
	for y in size:
		for x in size:
			var dx := (float(x) + 0.5 - c) / c
			var dy := (float(y) + 0.5 - c) / c
			var r := sqrt(dx * dx + dy * dy)
			# 亮核：高斯衰减
			var a: float = exp(-r * r * 16.0)
			var falloff: float = maxf(0.0, 1.0 - r)
			# 十字光刺（主）
			a += falloff * maxf(0.0, 1.0 - absf(dy) * 12.0) * 0.9
			a += falloff * maxf(0.0, 1.0 - absf(dx) * 12.0) * 0.9
			# 45° 斜刺（弱，避免看起来像加号）
			var u := (dx + dy) * 0.70710678
			var v := (dx - dy) * 0.70710678
			a += falloff * maxf(0.0, 1.0 - absf(v) * 20.0) * 0.34
			a += falloff * maxf(0.0, 1.0 - absf(u) * 20.0) * 0.34
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## 生命周期 alpha 曲线：出生淡入 → 中段最亮 → 消亡淡出（配合加法混合 = 晶晶亮）
func _make_alpha_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.70, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.85),
		Color(1, 1, 1, 0.0),
	])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


## 光点材质：软贴图 + 加法混合 + unshaded + 顶点色（让 color_ramp 的 alpha 生效）
func _make_point_material(tex: Texture2D, tint: Color, energy: float, through_walls: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(1, 1, 1, 1)
	m.emission_enabled = true
	m.emission = tint
	m.emission_energy_multiplier = energy
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = through_walls
	return m


## 量模型包围盒 → 光环中心与半径（本节点局部空间）。
## 硬编码 y 偏移踩过坑：模型原点不在几何中心，光效会堆在脚下。一律按包围盒算。
func _measure_model() -> Vector2:
	var aabb := AABB()
	var first := true
	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.name == "AuraHalo":
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		if first:
			aabb = box
			first = false
		else:
			aabb = aabb.merge(box)
	if first:
		return Vector2(0.35, 0.5)
	var inv := global_transform.affine_inverse()
	var c_local: Vector3 = inv * aabb.get_center()
	# 半径取包围盒半对角线，再收一点（完全贴边太散）
	var r_local: float = inv.basis.get_scale().x * (aabb.size.length() * 0.5)
	return Vector2(c_local.y, clampf(r_local * 0.62, 0.25, 3.0))


func _build_aura() -> void:
	_soft_dot = _make_soft_dot()
	_star_tex = _make_star_texture(64)
	_aura_particles.clear()
	var mm := _measure_model()
	var cy: float = mm.x
	var rad: float = mm.y
	printerr("[aura] center_y=", str(cy), " radius=", str(rad))

	# ① 星尘：细密小光点，缓慢漂浮、包裹身体（量足但不能糊模型 → 走小星芒）
	var dust := GPUParticles3D.new()
	dust.name = "Stardust"
	var dpm := ParticleProcessMaterial.new()
	dpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	dpm.emission_sphere_radius = rad
	dpm.direction = Vector3(0, 1, 0)
	dpm.spread = 180.0
	dpm.initial_velocity_min = 0.02
	dpm.initial_velocity_max = 0.16
	dpm.gravity = Vector3(0, 0, 0)
	dpm.scale_min = 0.45
	dpm.scale_max = 1.10
	dpm.color_ramp = _make_alpha_ramp()
	dpm.angular_velocity_min = -30.0
	dpm.angular_velocity_max = 30.0
	var dq := QuadMesh.new()
	dq.size = Vector2(0.19, 0.19)
	dust.draw_pass_1 = dq
	dust.material_override = _make_point_material(_star_tex, _aura_color, 1.05, false)
	dust.process_material = dpm
	dust.amount = 130
	dust.lifetime = 3.2
	dust.position = Vector3(0, cy, 0)
	dust.visibility_aabb = AABB(Vector3(-2.4, -2.4, -2.4), Vector3(4.8, 4.8, 4.8))
	add_child(dust)
	_aura_particles.append(dust)

	# ② 亮星：少量更大更亮的高光星芒，短寿命快闪（点睛）
	var spark := GPUParticles3D.new()
	spark.name = "Sparkle"
	var spm := ParticleProcessMaterial.new()
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spm.emission_sphere_radius = rad * 0.9
	spm.direction = Vector3(0, 1, 0)
	spm.spread = 180.0
	spm.initial_velocity_min = 0.05
	spm.initial_velocity_max = 0.32
	spm.gravity = Vector3(0, 0, 0)
	spm.scale_min = 0.55
	spm.scale_max = 1.05
	spm.color_ramp = _make_alpha_ramp()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.32, 0.32)
	spark.draw_pass_1 = sq
	spark.material_override = _make_point_material(_star_tex, _aura_color.lightened(0.45), 1.90, true)
	spark.process_material = spm
	spark.amount = 24
	spark.lifetime = 2.1
	spark.position = Vector3(0, cy, 0)
	spark.visibility_aabb = AABB(Vector3(-2.4, -2.4, -2.4), Vector3(4.8, 4.8, 4.8))
	add_child(spark)
	_aura_particles.append(spark)

	# ③ 火星拖尾：身体下方升起的小火星（火焰主题时数量拉高）
	var ember := GPUParticles3D.new()
	ember.name = "EmberTrail"
	var epm := ParticleProcessMaterial.new()
	epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	epm.emission_sphere_radius = rad * 0.6
	epm.direction = Vector3(0, 1, 0)
	epm.spread = 24.0
	epm.initial_velocity_min = 0.40
	epm.initial_velocity_max = 1.10
	epm.gravity = Vector3(0, 0.95, 0)
	epm.scale_min = 0.35
	epm.scale_max = 1.05
	epm.damping_min = 0.2
	epm.damping_max = 0.6
	epm.color_ramp = _make_alpha_ramp()
	var eq := QuadMesh.new()
	eq.size = Vector2(0.22, 0.22)
	ember.draw_pass_1 = eq
	ember.material_override = _make_point_material(_soft_dot, _aura_color, 1.45, false)
	ember.process_material = epm
	ember.amount = 14
	ember.lifetime = 1.6
	ember.position = Vector3(0, cy - rad * 0.55, 0)
	ember.visibility_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))
	add_child(ember)
	_aura_particles.append(ember)

	# ④ 背面柔光光晕：一大片极淡的加法光斑，制造"在发光"的体积感
	_aura_halo = MeshInstance3D.new()
	_aura_halo.name = "AuraHalo"
	var hq := QuadMesh.new()
	hq.size = Vector2(rad * 2.6, rad * 2.6)
	_aura_halo.mesh = hq
	var hm := StandardMaterial3D.new()
	hm.albedo_texture = _soft_dot
	hm.albedo_color = Color(_aura_color.r, _aura_color.g, _aura_color.b, 0.14)
	hm.emission_enabled = true
	hm.emission = _aura_color
	hm.emission_energy_multiplier = 0.25
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.no_depth_test = true
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_aura_halo.material_override = hm
	_aura_halo.position = Vector3(0, cy, 0)
	_aura_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aura_halo)

	# ⑤ 柔和点光源：让角色真把地面/周围照亮一点点（"发光"的物理证据）
	_aura_light = OmniLight3D.new()
	_aura_light.name = "AuraLight"
	_aura_light.light_color = _aura_color
	_aura_light.light_energy = 0.55
	_aura_light.omni_range = 3.2
	_aura_light.shadow_enabled = false
	_aura_light.position = Vector3(0, cy, 0)
	add_child(_aura_light)


## M41：切换小精灵主题（星尘=白蓝、火焰=暖橙、奥术=紫、自然=绿）
## 各层基础亮度（切主题时按此系数还原，避免反复调参把数值改飞）
const _BASE_ENERGY := {"Stardust": 1.05, "Sparkle": 1.90, "EmberTrail": 1.45}


func set_aura_theme(color: Color) -> void:
	_aura_color = color
	var warm: bool = color.r > color.b
	for p in _aura_particles:
		if not is_instance_valid(p):
			continue
		var m := p.material_override as StandardMaterial3D
		if m == null:
			continue
		# 亮日光下加法混合会把橙色冲成白色（同 M40 雨丝那坑）——暖色改走 alpha 混合保色
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if warm else BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(color.r, color.g, color.b, 1.0) if warm else Color(1, 1, 1, 1)
		m.emission = color.lightened(0.45) if p.name == "Sparkle" else color
		var base: float = float(_BASE_ENERGY.get(String(p.name), 1.0))
		m.emission_energy_multiplier = base * (0.30 if warm else 1.0)
	if _aura_halo != null and _aura_halo.material_override is StandardMaterial3D:
		var hm := _aura_halo.material_override as StandardMaterial3D
		hm.albedo_color = Color(color.r, color.g, color.b, 0.10 if warm else 0.14)
		hm.emission = color
		hm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if warm else BaseMaterial3D.BLEND_MODE_ADD
	if _aura_light != null:
		_aura_light.light_color = color
		_aura_light.light_energy = 0.85 if warm else 0.55
	var ember := get_node_or_null("EmberTrail") as GPUParticles3D
	if ember != null:
		ember.amount = 30 if warm else 14
		var epm := ember.process_material as ParticleProcessMaterial
		if epm != null:
			epm.initial_velocity_min = 0.28 if warm else 0.40
			epm.initial_velocity_max = 0.80 if warm else 1.10
			epm.gravity = Vector3(0, 0.45, 0) if warm else Vector3(0, 0.95, 0)
			epm.spread = 42.0 if warm else 24.0
	var dust := get_node_or_null("Stardust") as GPUParticles3D
	if dust != null:
		dust.amount = 130 if not warm else 100
