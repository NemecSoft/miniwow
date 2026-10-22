extends "res://scripts/vehicles/hover_couch.gd"

## M31c 完整复刻 tsl《特斯拉能飞！》驾驶系统（main.js It 状态机逐条对照）：
##   地面：姿态自动回正(9/s)、速度积分(accel 12/max 42)、转向阻尼(0.3/(1+(v/22)²))、
##         油门/刹车/倒车(9)/滑行(exp(-0.36w))、boost 推进(+21, 超 42 回落 -0.9)、
##         爬坡采样、落差>0.45 自动起飞、喷气升空(velocity+up*2)
##   空中：姿态控制(俯仰 1.7 / 偏航 1.05 / 翻滚 2.2 rad/s, lerp 7)、重力 18、
##         升空喷气沿车身上方向 +30、boost 沿车头 +21、空气阻尼 exp(-0.025w)、
##         落地判定(车身 up.y>0.7)→着陆冲击 landingImpact，未摆正→crashed
##   坠车：贴地滑移 + 手动 Q/E 翻滚 ↑↓ 俯仰摆正，摆正后恢复地面
##   燃料：lift 耗 1.0/s、boost 耗 0.48/s、地面静止回充 1.6/s、上限 8s（tsl 原值）
##   高度上限：城区 max.y-2 = 248（tsl 原值），到达后上升喷气暂停
##   HUD：速度 km/h + 俯仰/翻滚角度 + 离地高度 + 推进剂%（tsl roadster-hud 同构）
##   特效：4 个车底喷口向下喷焰（lifting）+ 2 个车尾喷口向后喷焰（boosting），
##         喷口位置 = roadster2.glb jet_lift_*/jet_boost_* 节点原值
##   车轮：wheel_* 按 wheelRoll 转动（tsl: speed/0.344），前轮 steer_* 随转向偏转
## 网络：驾驶端本地模拟，position/rotation 由 MultiplayerSynchronizer 广播；
##       boosting_sync / lifting_sync 广播喷焰与音效到远程端。
## 键位：W油门 S刹车/倒车 A/D转向 Shift喷气加速 空格喷气升空 ↑↓俯仰 Q/E翻滚 R复位

# ---- tsl 原值（main.js Z6 + It 状态机，单位 m/s、m/s²）----
const CAR_GRAVITY := 18.0
const CAR_MAX_SPEED := 42.0
const CAR_BOOST_SPEED := 64.0
const CAR_ACCELERATION := 12.0
const CAR_BRAKING := 25.0
const CAR_LIFT_ACCELERATION := 30.0   # 升空喷气（沿车身上方向）
const CAR_BOOST_ACCELERATION := 21.0
const CAR_FUEL_SECONDS := 8.0
const CAR_REFILL_RATE := 1.6
# ---- It 状态机手感原值 ----
const TSL_REVERSE_MAX := 9.0          # 倒车极速（max(-9, speed-9w)）
const TSL_BRAKE_DAMP := 5.0           # 刹车 damp 系数
const TSL_COAST_DAMP := 0.36          # 滑行 exp(-0.36w)
const TSL_BOOST_DECAY := 0.9          # 无 boost 超 42 回落
const TSL_WHEELBASE := 2.82           # 转向半径分母（yaw += speed/2.82*tan(steer)*w）
const TSL_STEER_BASE := 0.3           # 转向角基数 0.3/(1+(v/22)²)
const TSL_ALIGN_RATE := 9.0           # 地面姿态回正 slerp(1-exp(-9w))
const TSL_PITCH_RATE := 1.7           # 空中俯仰角速度 rad/s
const TSL_YAW_RATE := 1.05            # 空中偏航角速度 rad/s
const TSL_ROLL_RATE := 2.2            # 空中翻滚角速度 rad/s
const TSL_ANG_LERP := 7.0             # 角速度 lerp(1-exp(-7w))
const TSL_AIR_DAMP := 0.025           # 空气阻尼 exp(-0.025w)
const TSL_TAKEOFF_DROP := 0.45        # 落差>0.45 起飞
const TSL_LIFT_POP := 2.0             # 升空瞬间 velocity+up*2
const TSL_LIFT_POP_Y := 0.07          # 升空瞬间 y+0.07
const TSL_WHEEL_RADIUS := 0.344       # 轮滚分母
const TSL_MAX_HEIGHT := 248.0         # 城区 max.y(250)-2
const TSL_LAND_OK_UP_Y := 0.7         # 落地摆正判定 up.y>0.7
const TSL_LAND_OK_FWD_Y := 0.65       # 落地摆正判定 |fwd.y|<0.65
# ---- MiniWoW 侧适配（tsl 未提取到，标注为适配层）----
const CAR_RIDE_HEIGHT := 0.02         # 贴地高度（真模型轮底 y=0 接地）
const CAR_LOOP_MIN_SPEED := 18.0
const CAR_IMPACT_SPEED := 15.0

## 飞车座位：单主驾，坐进座舱（真模型座舱 y≈0.45~0.96，玻璃烟熏色可透视）
const CAR_SEAT_OFFSETS := [Vector3(0, 0.28, 0.2)]

# ---- tsl 驾驶状态（驾驶端本地）----
var _car_speed := 0.0                 # 沿车头方向标量速度（负 = 倒车）
var _car_fuel := CAR_FUEL_SECONDS
var _car_mode := "ground"             # ground / air / crashed（tsl s.mode）
var _vel := Vector3.ZERO              # 空中速度矢量
var _ang_vel := Vector3.ZERO          # 空中角速度矢量
var _steer := 0.0                     # 前轮转向角（damp 平滑）
var _wheel_roll := 0.0                # 轮滚累计（视觉）
var _air_time := 0.0                  # 滞空计时（tsl airTime）
var _landing_impact := 0.0            # 落地冲击（衰减 12/s）
var _ceiling_latch := false           # 高度上限闩（下降 3.5 后解除）
var _boosting := false
var _lifting := false
# ---- 回环状态（保留 M31 结构）----
var _loop_center := Vector3.ZERO
var _loop_axis := Vector3.RIGHT
var _loop_radius := 0.0
var _loop_angle := 0.0
var _loop_progress := 0.0
var _loop_dir := 1.0
var _in_loop := false

@onready var _engine_sound: AudioStreamPlayer3D = $EngineSound
@onready var _jet_sound: AudioStreamPlayer3D = $JetSound
@onready var _speed_label: Label3D = $SpeedLabel
@onready var _attitude_label: Label3D = $AttitudeLabel
# 真模型喷口/车轮节点（特效挂点；wheel 在 steer 父节点下，用 find_child 全递归找）
@onready var _wheel_nodes := {
	"fl": find_child("wheel_front_left", true, false),
	"fr": find_child("wheel_front_right", true, false),
	"rl": find_child("wheel_rear_left", true, false),
	"rr": find_child("wheel_rear_right", true, false),
}
@onready var _steer_nodes := {
	"fl": find_child("steer_front_left", true, false),
	"fr": find_child("steer_front_right", true, false),
}
@onready var _lift_fx: Array[Node3D] = [$LiftFX_FL, $LiftFX_FR, $LiftFX_RL, $LiftFX_RR]
@onready var _boost_fx: Array[Node3D] = [$BoostFX_L, $BoostFX_R]

## 同步属性：喷焰/音效广播到远程端（SceneReplicationConfig）
@export var boosting_sync := false
@export var lifting_sync := false


func _ready() -> void:
	super()
	add_to_group("tsl_car")
	_car_fuel = CAR_FUEL_SECONDS
	# M31：tsl 原版音效（electric-drive 引擎循环 + jet-loop 喷气循环）
	for s: AudioStreamPlayer3D in [_engine_sound, _jet_sound]:
		if s.stream is AudioStreamWAV:
			(s.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			(s.stream as AudioStreamWAV).loop_end = (s.stream as AudioStreamWAV).data.size() / 2
	_engine_sound.play()


func is_remote_driving() -> bool:
	return seats.get(_local_peer_id()) != 0


## M30：座位表覆盖——单主驾
func _get_seat_offsets() -> Array:
	return CAR_SEAT_OFFSETS


func _physics_process(delta: float) -> void:
	super(delta)
	# 非驾驶端（远程）：由同步属性驱动远程喷焰/音效（驾驶端在 _drive_tick 里跑 tsl 状态机）
	if seats.get(_local_peer_id()) != 0:
		_update_remote_fx()


## M30 虚函数覆盖：tsl 完整驾驶状态机（基类沙发飞行被本覆盖替换）
func _drive_tick(delta: float) -> void:
	if seats.get(_local_peer_id()) != 0:
		return
	_tsl_tick(delta)


## ===== tsl It 状态机（驾驶端）=====
func _tsl_tick(delta: float) -> void:
	# 回环贴附中（保留 M31 通道；tsl：track 模式 lifting → 脱离）
	if _in_loop:
		if _lifting:
			_in_loop = false
			_car_mode = "air"
			_vel = -global_transform.basis.z * _car_speed
			_vel += global_transform.basis.y * TSL_LIFT_POP
			_air_time = 0.0
		else:
			_loop_tick(delta)
			_update_fx_hud()
		return
	var throttle := Input.get_axis("move_backward", "move_forward")   # +1 前进
	var steer_in := Input.get_axis("move_left", "move_right")         # +1 右转
	var brake := throttle < 0.0
	var want_boost := Input.is_action_pressed("shift")
	var want_lift := Input.is_action_pressed("jump")
	var pitch_in := Input.get_axis("pitch_up", "pitch_down")          # +1 = 机头向下（↑ 键抬头）
	var roll_in := Input.get_axis("roll_left", "roll_right")          # +1 = 右滚
	if Input.is_action_just_pressed("car_reset"):
		_tsl_reset()

	# ---- boost/lift 判定（tsl：燃料>0、crashed 时仅 up.y>0.35 可再起飞、高度上限闩）----
	var up := global_transform.basis.y
	var fwd := -global_transform.basis.z
	if global_position.y >= TSL_MAX_HEIGHT - 0.03 and _vel.y >= 0.0:
		_ceiling_latch = true
	if global_position.y < TSL_MAX_HEIGHT - 3.5:
		_ceiling_latch = false
	var has_fuel := _car_fuel > 0.001
	_boosting = has_fuel and _car_mode != "crashed" and want_boost and not brake and not (_ceiling_latch and fwd.y > 0.0)
	_lifting = has_fuel and want_lift and (_car_mode != "crashed" or up.y > 0.35) and not (_ceiling_latch and up.y > 0.0)

	# ---- 燃料（tsl 原值：lift 1.0/s、boost 0.48/s、地面无喷气回充 1.6/s）----
	var burn := (1.0 if _lifting else 0.0) + (0.48 if _boosting else 0.0)
	_car_fuel = clampf(_car_fuel - burn * delta, 0.0, CAR_FUEL_SECONDS)
	if not want_boost and not want_lift and _car_mode != "air":
		_car_fuel = minf(CAR_FUEL_SECONDS, _car_fuel + CAR_REFILL_RATE * delta)
	_landing_impact = maxf(0.0, _landing_impact - delta * 12.0)

	match _car_mode:
		"crashed":
			_tsl_crashed_tick(delta, pitch_in, steer_in, roll_in)
		"air":
			_tsl_air_tick(delta, pitch_in, steer_in, roll_in)
		"ground":
			_tsl_ground_tick(delta, throttle, brake, steer_in)

	_update_fx_hud()


## ===== 地面模式（tsl ground 分支）=====
func _tsl_ground_tick(delta: float, throttle: float, brake: bool, steer_in: float) -> void:
	var up := global_transform.basis.y
	var fwd := -global_transform.basis.z

	# 姿态自动回正（yaw-only，slerp 1-exp(-9w)）；tsl 地面不允许手动翻滚
	var yaw_only := atan2(-fwd.x, -fwd.z)
	var target_q := Quaternion(Vector3.UP, yaw_only)
	quaternion = quaternion.slerp(target_q, 1.0 - exp(-delta * TSL_ALIGN_RATE)).normalized()
	fwd = -global_transform.basis.z
	up = global_transform.basis.y

	# ---- 速度积分（tsl X() 原值）----
	if brake:
		if throttle == 0.0 and _car_speed <= 0.05:
			_car_speed = maxf(-TSL_REVERSE_MAX, _car_speed - 9.0 * delta)
		else:
			_car_speed = _dampf(_car_speed, 0.0, TSL_BRAKE_DAMP, delta)
	elif throttle > 0.0:
		if _car_speed < CAR_MAX_SPEED:
			_car_speed += CAR_ACCELERATION * throttle * delta
		if _car_speed < 0.0:
			_car_speed = minf(0.0, _car_speed + 20.0 * delta)
	else:
		_car_speed *= exp(-TSL_COAST_DAMP * delta)
	if _boosting and not brake:
		_car_speed += CAR_BOOST_ACCELERATION * delta
	if not _boosting and _car_speed > CAR_MAX_SPEED:
		_car_speed = maxf(CAR_MAX_SPEED, _car_speed - TSL_BOOST_DECAY * delta)
	_car_speed = clampf(_car_speed, -TSL_REVERSE_MAX, CAR_BOOST_SPEED)

	# ---- 转向（tsl：O=0.3/(1+(v/22)²)，damp 系数归零 12 / 打舵 6）----
	var steer_scale := TSL_STEER_BASE / (1.0 + pow(absf(_car_speed) / 22.0, 2.0))
	_steer = _dampf(_steer, -steer_in * steer_scale, 12.0 if absf(steer_in) < 0.001 else 6.0, delta)
	var yaw_q := Quaternion(Vector3.UP, _car_speed / TSL_WHEELBASE * tan(_steer) * delta)
	quaternion = (yaw_q * quaternion).normalized()

	# ---- 位移 + 爬坡采样 ----
	var fwd2 := -global_transform.basis.z
	var step := _car_speed * delta
	var dest := global_position + fwd2 * step
	var h0 := _physics_ground_height(global_position, _ground_exclude_rids())
	var h1 := _physics_ground_height(dest, _ground_exclude_rids())
	if h0 > -90.0 and h1 > -90.0 and h0 - h1 > TSL_TAKEOFF_DROP:
		# 冲出坡顶/悬崖 → 起飞（速度矢量继承，tsl k()）
		_enter_air(fwd2 * _car_speed)
		return
	# 水平滑墙（撞楼/撞树；撞击够快触发建筑破坏）
	var move := _resolve_horizontal_move(global_position, fwd2 * step, 1.0)
	var new_pos := global_position + move
	if h1 > -90.0:
		new_pos.y = h1 + CAR_RIDE_HEIGHT
	global_position = new_pos
	_check_loop_enter(fwd2)

	# ---- 喷气升空（tsl：k() + y+=0.07 + velocity+up*2）----
	if _lifting:
		_enter_air(fwd2 * _car_speed)
		_vel += up * TSL_LIFT_POP
		global_position.y += TSL_LIFT_POP_Y
		return

	_report_impact()


## ===== 空中模式（tsl air 分支原值）=====
func _tsl_air_tick(delta: float, pitch_in: float, steer_in: float, roll_in: float) -> void:
	_air_time += delta
	var up := global_transform.basis.y
	var fwd := -global_transform.basis.z

	# 姿态控制：目标角速度 (pitch*1.7, -steer*1.05, -roll*2.2)，lerp 1-exp(-7w)
	var target_ang := Vector3(pitch_in * TSL_PITCH_RATE, -steer_in * TSL_YAW_RATE, -roll_in * TSL_ROLL_RATE)
	_ang_vel = _ang_vel.lerp(target_ang, 1.0 - exp(-delta * TSL_ANG_LERP))
	if _ang_vel.length() > 0.0001:
		var spin := _ang_vel.normalized() * _ang_vel.length() * delta
		quaternion = (quaternion * Quaternion(spin.normalized(), spin.length())).normalized()
	up = global_transform.basis.y
	fwd = -global_transform.basis.z

	# 力：重力 18 / 升空 +30 沿车身上方 / boost +21 沿车头 / 阻尼 exp(-0.025w)
	_vel.y -= CAR_GRAVITY * delta
	if _lifting:
		_vel += up * CAR_LIFT_ACCELERATION * delta
	if _boosting:
		_vel += fwd * CAR_BOOST_ACCELERATION * delta
	_vel *= exp(-TSL_AIR_DAMP * delta)

	# 低空减速伞（tsl assist：t0<10 && vy<-5.5 → vy 提到 -5.5，+65w 缓冲）
	var ground := _physics_ground_height(global_position, _ground_exclude_rids())
	if ground > -90.0:
		var to_ground := ground + CAR_RIDE_HEIGHT - global_position.y
		if to_ground < 10.0 and to_ground > 0.01 and _vel.y < -5.5:
			_vel.y = minf(-5.5, _vel.y + 65.0 * delta)

	# 位移（全 3D 扫掠防穿）
	var move := _vel * delta
	var swept := _sweep_3d(global_position, move)
	global_position += swept
	if swept.length_squared() < move.length_squared() - 0.000001:
		# 撞击：消去法向速度分量（tsl：vel.addScaledVector(normal, -dot)）
		var hit_n := (move - swept)
		if hit_n.length_squared() > 0.000001:
			var n := hit_n.normalized()
			var vn := _vel.dot(n)
			if vn < 0.0:
				_vel += n * (-vn)

	# 落地判定（tsl：up.y>0.7、接近地面、vy<0 → 着陆）
	if ground > -90.0:
		var ride := ground + CAR_RIDE_HEIGHT
		if up.y > TSL_LAND_OK_UP_Y and global_position.y <= ride and _vel.y < 0.0:
			global_position.y = ride
			_landing_impact = absf(_vel.y)
			if up.y > TSL_LAND_OK_UP_Y and absf(fwd.y) < TSL_LAND_OK_FWD_Y:
				_car_mode = "ground"
				_car_speed = _vel.dot(fwd)
				_vel = Vector3.ZERO
				_ang_vel = Vector3.ZERO
			else:
				_car_mode = "crashed"
				_car_speed = 0.0
				_vel = Vector3.ZERO
				_ang_vel = Vector3.ZERO
			return

	# 高度上限钳制（tsl：y>max.y-2 → 停在该高度）
	if global_position.y > TSL_MAX_HEIGHT:
		global_position.y = TSL_MAX_HEIGHT
		_vel.y = minf(0.0, _vel.y)

	_car_speed = _vel.dot(fwd)
	_report_impact()


## ===== 坠车模式（tsl crashed：贴地滑移 + 手动摆正）=====
func _tsl_crashed_tick(delta: float, pitch_in: float, steer_in: float, roll_in: float) -> void:
	var fwd := -global_transform.basis.z
	var up := global_transform.basis.y
	# 贴地钳制
	var ground := _physics_ground_height(global_position, _ground_exclude_rids())
	if ground > -90.0:
		global_position.y = ground + CAR_RIDE_HEIGHT
	# 手动姿态（tsl：pitch 1.7 / steer 1.05 / roll 2.2）
	var rot := Vector3(pitch_in * TSL_PITCH_RATE, -steer_in * TSL_YAW_RATE, -roll_in * TSL_ROLL_RATE)
	if rot.length() > 0.0001:
		quaternion = (quaternion * Quaternion(rot.normalized(), rot.length() * delta)).normalized()
	# 摆正判定（tsl S()：up.y>0.7 && |fwd.y|<0.65）
	if up.y > TSL_LAND_OK_UP_Y and absf(fwd.y) < TSL_LAND_OK_FWD_Y:
		_car_mode = "ground"
		_car_speed = 0.0
	elif _lifting and up.y > 0.35:
		# 喷气再起飞（tsl：k() + velocity+up*2）
		_car_mode = "air"
		_vel = Vector3.ZERO
		_vel += up * TSL_LIFT_POP
		_air_time = 0.0


## 本版本 Godot 无 dampf 全局函数——帧率无关阻尼插值（lerp 指数形式）
func _dampf(a: float, b: float, damping: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-damping * dt))


## R 复位（MiniWoW 适配：姿态回正+速度清零+落回地面；tsl 原版 R=回回环入口）
func _tsl_reset() -> void:
	var fwd := -global_transform.basis.z
	var yaw_only := atan2(-fwd.x, -fwd.z)
	quaternion = Quaternion(Vector3.UP, yaw_only)
	_vel = Vector3.ZERO
	_ang_vel = Vector3.ZERO
	_car_speed = 0.0
	_steer = 0.0
	_car_mode = "ground"
	_ceiling_latch = false
	var ground := _physics_ground_height(global_position, _ground_exclude_rids())
	if ground > -90.0:
		global_position.y = ground + CAR_RIDE_HEIGHT


## 起飞（tsl k()：mode=air，速度矢量 = 车头方向 * speed）
func _enter_air(initial_vel: Vector3) -> void:
	_car_mode = "air"
	_vel = initial_vel
	_air_time = 0.0


## ===== 特效 / HUD（驾驶端真实状态；远程端读同步属性）=====
func _update_fx_hud() -> void:
	_apply_fx(_boosting, _lifting)
	boosting_sync = _boosting
	lifting_sync = _lifting
	# 引擎音随速变调 + 喷气音
	var kmh := absf(_car_speed) * 3.6
	_engine_sound.pitch_scale = 0.8 + clampf(kmh / 230.0, 0.0, 1.0) * 0.9
	if (_boosting or _lifting) and not _jet_sound.playing:
		_jet_sound.play()
	elif not _boosting and not _lifting and _jet_sound.playing:
		_jet_sound.stop()
	# HUD：速度表 + 姿态（tsl roadster-hud 同构）
	if _speed_label != null:
		_speed_label.text = str(int(kmh)) + " km/h"
		_speed_label.modulate = Color(1, 1, 1) if not _boosting else Color(1, 0.75, 0.4)
	if _attitude_label != null:
		var b := global_transform.basis
		var pitch_deg := int(rad_to_deg(asin(clampf(b.z.y, -1.0, 1.0))))
		var roll_deg := int(rad_to_deg(asin(clampf(b.x.y, -1.0, 1.0))))
		var ground := _physics_ground_height(global_position, _ground_exclude_rids())
		var height_txt := "离地 " + str(snappedf(maxf(global_position.y - ground - CAR_RIDE_HEIGHT, 0.0), 0.1)) + " m" if ground > -90.0 else "离地 --- m"
		var fuel_pct := int(_car_fuel / CAR_FUEL_SECONDS * 100.0)
		_attitude_label.text = "俯仰 " + str(pitch_deg) + "° · 翻滚 " + str(roll_deg) + "°\n" \
			+ height_txt + " · 推进剂 " + str(fuel_pct) + "%"
		if _air_time > 0.5 and _car_mode == "air":
			_attitude_label.text += " · 滞空 " + str(snappedf(_air_time, 0.1)) + "s"


func _update_remote_fx() -> void:
	_apply_fx(boosting_sync, lifting_sync)
	if (boosting_sync or lifting_sync) and not _jet_sound.playing:
		_jet_sound.play()
	elif not boosting_sync and not lifting_sync and _jet_sound.playing:
		_jet_sound.stop()


## 喷焰开关 + 抖动（每帧随机缩放，模拟喷气湍流）
func _apply_fx(boost_on: bool, lift_on: bool) -> void:
	for fx: Node3D in _lift_fx:
		if fx == null:
			continue
		fx.visible = lift_on
		if lift_on:
			var s := randf_range(0.8, 1.25)
			fx.scale = Vector3(s, randf_range(0.85, 1.3), s)
	for fx: Node3D in _boost_fx:
		if fx == null:
			continue
		fx.visible = boost_on
		if boost_on:
			var s := randf_range(0.8, 1.25)
			fx.scale = Vector3(s, randf_range(0.85, 1.35), s)


## 车轮滚动 + 前轮转向（tsl wheelRoll -= t0/0.344；steer 前轮偏转）
func _process(delta: float) -> void:
	# 轮滚由驾驶端/同步 rotation 驱动（远程端跟随位置变化近似——仅驾驶端转轮）
	if seats.get(_local_peer_id()) != 0:
		return
	_wheel_roll -= _car_speed * delta / TSL_WHEEL_RADIUS
	var spin := Quaternion(Vector3.LEFT, _wheel_roll)
	for k: String in _wheel_nodes:
		var w: Node3D = _wheel_nodes[k]
		if w != null:
			w.quaternion = spin
	for k: String in _steer_nodes:
		var s: Node3D = _steer_nodes[k]
		if s != null:
			s.rotation.y = _steer * 0.5


## 空中 3D 扫掠（球半径 1.0；截断到障碍前 + 返回滑行位移）
func _sweep_3d(from_pos: Vector3, move: Vector3) -> Vector3:
	if move.length_squared() < 0.0000001:
		return move
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, from_pos)
	params.motion = move
	params.collision_mask = 0xFFFFFFFF
	params.exclude = _ground_exclude_rids()
	var res := space.cast_motion(params)
	if res.is_empty():
		return move
	var safe: float = res[0]
	if safe >= 1.0:
		return move
	if safe <= 0.0:
		return Vector3.ZERO
	return move * safe


## ===== 撞楼检测（保留 M30/M31：驾驶端检测，服务器裁决破坏）=====
func _report_impact() -> void:
	if absf(_car_speed) < CAR_IMPACT_SPEED and _vel.length() < CAR_IMPACT_SPEED:
		return
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + (-global_transform.basis.z) * 2.2)
	query.collision_mask = 0xFFFFFFFF
	query.exclude = _ground_exclude_rids()
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider != null and collider is Node and (collider as Node).is_in_group("building"):
		var now := Time.get_ticks_msec()
		if now - _last_impact_ms > 500:
			_last_impact_ms = now
			var zone := get_node_or_null("../../../CityZone")
			if zone != null and zone.has_method("request_destroy_building"):
				zone.request_destroy_building.rpc_id(1, str((collider as Node).name), hit.get("position"))

var _last_impact_ms := 0


## ===== 垂直回环（保留 M31 结构；贴附走 quaternion 姿态）=====
func register_loop(center: Vector3, radius: float, axis: Vector3) -> void:
	_loop_center = center
	_loop_radius = radius
	_loop_axis = axis.normalized()


func _check_loop_enter(fwd: Vector3) -> void:
	if _in_loop or _car_mode != "ground":
		return
	var zone := get_node_or_null("../../../CityZone")
	if zone == null or not zone.has_method("get_loop_entry"):
		return
	var entry: Dictionary = zone.get_loop_entry(global_position, CAR_LOOP_MIN_SPEED)
	if entry.is_empty():
		return
	_in_loop = true
	_loop_center = entry["center"]
	_loop_radius = entry["radius"]
	_loop_axis = entry["axis"]
	var rel := global_position - _loop_center
	var u := Vector3.UP
	var v := _loop_axis.cross(u).normalized()
	_loop_angle = atan2(rel.dot(v), rel.dot(u))
	var tangent_here := u * -sin(_loop_angle) + v * cos(_loop_angle)
	_loop_dir = 1.0 if fwd.dot(tangent_here) >= 0.0 else -1.0
	_loop_progress = 0.0


func _loop_tick(delta: float) -> void:
	if _boosting:
		_car_speed = minf(_car_speed + CAR_BOOST_ACCELERATION * delta, CAR_BOOST_SPEED)
	else:
		_car_speed *= exp(-TSL_COAST_DAMP * delta)
	var need := sqrt(CAR_LIFT_ACCELERATION * _loop_radius)
	if _car_speed < need:
		_in_loop = false
		_car_mode = "air"
		_vel = -global_transform.basis.z * _car_speed
		return
	var ang_vel := _car_speed / _loop_radius
	var d_angle := ang_vel * delta * _loop_dir
	_loop_angle += d_angle
	_loop_progress += absf(d_angle)
	var u := Vector3.UP
	var v := _loop_axis.cross(u).normalized()
	var dir_on_ring := u * cos(_loop_angle) + v * sin(_loop_angle)
	var inner_r: float = _loop_radius - 0.6
	var pos := _loop_center + dir_on_ring * inner_r
	pos += _loop_axis * clampf((global_position - _loop_center).dot(_loop_axis), -2.0, 2.0)
	global_position = pos
	var tangent := (u * -sin(_loop_angle) + v * cos(_loop_angle)) * _loop_dir * (1.0 if _car_speed >= 0.0 else -1.0)
	var inward := -dir_on_ring.normalized()  # 内壁行驶：车身顶朝圆心
	var basis := Basis()
	basis.z = -tangent
	basis.y = inward
	basis.x = basis.y.cross(basis.z).normalized()
	quaternion = Quaternion(basis).normalized()
	_wheel_roll -= _car_speed * delta / TSL_WHEEL_RADIUS
	if _loop_progress >= TAU:
		_in_loop = false
		var exit_pos := global_position + tangent * 6.0
		var ground := _physics_ground_height(exit_pos, _ground_exclude_rids())
		if ground > -90.0:
			exit_pos.y = ground + CAR_RIDE_HEIGHT
		global_position = exit_pos
		_car_mode = "air"
		_vel = tangent * _car_speed * 0.5
