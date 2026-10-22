@tool
extends BTAction
## M20-Bot：bot 直线趋近 + 避障节点（寻路降级方案——场景无导航网格）。
## 从黑板读取目标节点（target_var 指定变量名），每物理帧朝目标移动，
## 到达 arrive_radius 内返回 SUCCESS；超过 timeout_sec 未到达返回 FAILURE。
## 移动用 move_and_slide（复用玩家碰撞），位置变化由 MultiplayerSynchronizer 自动同步。
##
## M20b 地形跟随（关键修复一）：世界高差极大（出生点山脊 y≈64、任务官山谷 y≈2），
## 纯 2D 直线移动会让 bot 悬空飞行、永远差 60m 高度接不上任务。
## 垂直方向每帧朝「地形高度 + HOVER_OFFSET」收敛（与 level.get_spawn_point 同公式），
## bot 于是沿地形表面下降/爬升，到达目标 x/z 时高度自然对齐。
##
## M20b 射线避障（关键修复二）：直线必经之线上有 Arena 200m 南墙等障碍，
## 无避障会永久顶墙。每帧向目标方向发射两条水平射线（高/低各一，兼顾 3m 墙与 1.4m 矮掩体）：
##   - 擦碰：沿碰撞法线切向滑行（move_and_slide 本身也会滑，这里保证转向意图稳定）
##   - 正面顶住：朝目标一侧转 55° 绕行（目标在左则左绕、在右则右绕，避免左右摇摆）
## 凸起障碍（墙/柱/掩体）均可收敛；到达墙端后射线清空，自动回归直线。
##
## 移动/停下时广播 Run/Idle 动画（复用玩家 _request_animation 链路，客户端可见行走姿态）。
##
## 已知边界：无全局寻路，U 形陷阱可能绕圈；超时后上层序列重试，bot 从当前位置继续，不丢进度。

## 黑板变量名：目标 Node
@export var target_var: StringName = &"target_node"
## 到达判定半径（米，2D 水平距离）
@export var arrive_radius: float = 2.5
## 超时（秒），防止卡死时无限 RUNNING。绕墙全程可达 500m+，给 150s 余量
## M39：任务点拉到 1500m 外——单程 1500m/30m/s=50s，加加速/爬升/战斗/返回，
## 150s 必然超时。放宽到 420s。
@export var timeout_sec: float = 420.0

## 地形探针节点（相对 PlayersContainer/<bot_id>）。与 level.gd 的 Environment/TerrainStarter 一致
const TERRAIN_PATH := "../../Environment/TerrainStarter"
## 站在地形表面上的抬升量（与 get_spawn_point 的 +0.5 一致）
const HOVER_OFFSET := 0.5
## 水平移动速度（米/秒），同时作为垂直收敛速度上限
const MOVE_SPEED := 5.0
## 避障射线探测距离（米）：略大于转向响应距离，保证提前量
const PROBE_DIST := 3.5
## 垂直地面探测射线长度（米）：bot 无重力，高空坠物不会自己落地，
## 8m 保证从数米空中也能探到物理地面；更高时走地形数据降级
const PROBE_DOWN := 8.0
## 高空下压速度上限（米/秒）：从 65m 事故高空回落约 3s，不能只给 MOVE_SPEED
const FAST_DESCENT := 20.0
## 两条避障射线的相对高度（米）：低射线抓矮掩体，高射线抓高墙
const PROBE_HEIGHTS := [0.4, 1.3]
## 正面顶墙时的绕行角（度）
const DETOUR_ANGLE := 55.0

## M25：长途骑行阈值——目标超过 40m 召唤飞行器骑行，到达自动下客收车。
## 村内移动（NPC 间 15~30m）保持步行，符合"真人玩家"观感（用户决策）。
## M39：目标拉远到 1500m（RIDE_ARRIVE 9→22、垂直差阈值 3.5→12）——
##   新落点在丘陵地形，沙发 autopilot 近端巡航高度是 ground+1.2m，
##   但地形起伏 ±7m，旧 3.5m 垂直差会让 bot 贴着坡面时永不满足到达条件，
##   一路飞到超时才 FAILURE（1500m 单程 30m/s ≈ 50s，叠加悬停等待必然超 150s）。
const RIDE_DISTANCE := 40.0
const RIDE_ARRIVE := 22.0
## 骑行到达的垂直差容差（米）：丘陵起伏 ±7m，且 autopilot 修正 3 让飞行器
## 收敛到 tgt_pos.y+12 → 垂直差稳态约 12m，阈值必须 > 12 才收得住
## （原 12 用严格小于 `<`，稳态卡在边界上不成立 → 420s 超时）。
const RIDE_ARRIVE_DY := 20.0
## M24：跳跃——与玩家同款物理（player.try_jump 的 JUMP_VELOCITY）
const JUMP_VELOCITY := 7.5
## 卡住判定阈值：实际水平位移 < 预期的 35% 视为被挡
const STUCK_RATIO := 0.35
## 卡住持续多久触发跳跃（秒）
const STUCK_JUMP_DELAY := 0.35
## 跳跃最短持续时间（秒）：防止起跳瞬间 is_on_floor 仍为 true 误判落地
const JUMP_MIN_TIME := 0.25

var _elapsed: float = 0.0
var _terrain: Terrain3D = null
## M24：跳跃状态机（bot 与玩家同款跳跃能力——AI 接管玩家的能力基座）
var _jumping := false
var _jump_time := 0.0
var _stuck_time := 0.0
var _last_pos := Vector3.ZERO


func _enter() -> void:
	_elapsed = 0.0
	_jumping = false
	_stuck_time = 0.0
	var bot := agent as Node3D
	_last_pos = bot.global_position if bot != null else Vector3.ZERO


func _tick(delta: float) -> Status:
	# M20c 死亡中断：LimboAI selector 记忆 current_child，RUNNING 中的长任务不中断，
	# 会让根 Selector 永远卡在当前分支、永不回退 tick 死亡处理分支
	# （实测事故：bot 被野猪围殴致死后 138 秒不复活）。死亡 → FAILURE 强制 selector 重头 tick。
	if _is_bot_dead():
		return FAILURE
	# 防御：get_var 对缺失变量会 ERR_FAIL 刷屏（实测 LimboAI 1.8 行为），先 has_var 拦一道
	if not blackboard.has_var(target_var):
		return FAILURE
	var target: Node3D = blackboard.get_var(target_var, null)
	if not is_instance_valid(target):
		return FAILURE

	_elapsed += delta
	if _elapsed > timeout_sec:
		_play_animation(&"Idle")
		return FAILURE

	var bot: CharacterBody3D = agent as CharacterBody3D
	if bot == null:
		return FAILURE

	# M20d：到达判定必须用 3D 距离。原 2D 判定（to_target.y=0）导致 bot 被弹到
	# 65m 高空后水平距任务官仅 2.4m ≤ arrive_radius，每帧判 SUCCESS 停止驱动，
	# 而 QuestAction 用 3D 距离 62.9m > interact_radius 每帧 FAILURE——
	# BT 在分支间空转死循环，bot 永久冻结高空（full9 实测）。
	# 移动方向仍取水平投影（flat）：爬墙/贴脸时不做垂直窜升，垂直只由地形跟随收敛。
	var to_target: Vector3 = target.global_position - bot.global_position
	var flat: Vector3 = to_target
	flat.y = 0.0
	var distance: float = to_target.length()
	# M37：flat NaN 闸——bot 或 target 位置非有限时 length() 比较恒 false，
	# 会一路漏到 flat.normalized() 每帧刷屏（M33 体系漏网点，实测复现：
	# boar 死亡瞬间一批 30 条）。停步 + 打印来源，定位后摘除诊断。
	if not (is_finite(flat.x) and is_finite(flat.z)):
		printerr("MOVE-NAN: %s bot_pos=%s target=%s tgt_pos=%s" % [
			(agent as Node).name, bot.global_position, target.name, target.global_position])
		bot.velocity.x = 0.0
		bot.velocity.z = 0.0
		return RUNNING
	# M24 诊断：仅异常时打印（正常移动每秒 4bot×1 条会刷屏；dy>20 或高空悬停才值得看）
	if int(_elapsed) != int(_elapsed - delta) and (absf(to_target.y) > 20.0 or bot.global_position.y > target.global_position.y + 20.0):
		printerr("MT_DIAG: %s->%s 3D=%.1f flat=%.1f dy=%.1f bot_y=%.1f tgt_y=%.1f" % [
			(agent as Node).name, target.name, distance, flat.length(),
			to_target.y, bot.global_position.y, target.global_position.y])
	if distance <= arrive_radius:
		bot.velocity.x = 0.0
		bot.velocity.z = 0.0
		_play_animation(&"Idle")
		return SUCCESS

	# M33 防御 A：水平已到达（目标在正下方/头顶，flat≈0）时 flat.normalized()
	# 会每帧刷 "Vector3 cannot be normalized" 且 dir fallback (0,0,0)。
	# 停水平驱动、只做垂直收敛，等 3D 距离进 arrive_radius 或超时 FAILURE。
	# M37：上面的 NaN 闸已拦下非有限值，此处 length() 比较安全。
	if flat.length() < 0.01:
		bot.velocity.x = 0.0
		bot.velocity.z = 0.0
		if _jumping:
			_update_jump(bot, delta)
		else:
			_apply_terrain_follow(bot, target)
			_update_stuck_jump(bot, delta)
		bot.move_and_slide()
		if not _jumping:
			_play_animation(&"Run")
		return RUNNING

	# ===== M25：长途骑行——目标超过 RIDE_DISTANCE 才召唤飞行器，到达自动收回 =====
	if bot.get("mounted_vehicle") != null:
		var couch: Node3D = bot.mounted_vehicle
		if not is_instance_valid(couch):
			bot.set("mounted_vehicle", null)
			return RUNNING
		# 骑行中：把目标交给沙发自动驾驶；接近地面到达半径即下客收车
		if couch.has_method("set_autopilot"):
			couch.set_autopilot(target)
		# 死亡守卫：骑乘分支会跳过死亡冻结逻辑，尸体必须强制下客，
		# 否则复活回村后每帧被钉回沙发位置，bot 永久卡死
		var attrs: Node = bot.get("attribute_set")
		if attrs != null and not attrs.is_alive():
			couch.server_dismount_peer(bot.get_multiplayer_authority())
			couch.server_recall()
			return RUNNING
		# M39：到达判定改成**水平距离 + 垂直差分开判**。
		# 原判据用 3D 距离 `distance <= RIDE_ARRIVE` —— 飞行器巡航稳态在
		# tgt_pos.y+12，3D 距离恒 ≥ 12m，与 RIDE_ARRIVE(22) 抢边界，
		# 丘陵起伏 ±7m 时更收不住（实测 bot 到 1424m 后卡在 569m 高空、
		# 420s 超时）。分开判后：水平够近且高度差在容差内即下客。
		var flat_d: float = Vector2(
			bot.global_position.x - target.global_position.x,
			bot.global_position.z - target.global_position.z).length()
		var dy: float = absf(bot.global_position.y - target.global_position.y)
		if flat_d <= RIDE_ARRIVE and dy <= RIDE_ARRIVE_DY:
			couch.server_dismount_peer(bot.get_multiplayer_authority())
			couch.server_recall()
			_stuck_time = 0.0
		return RUNNING  # 骑行中本体由座位跟随驱动，不走步行/动画
	if distance > RIDE_DISTANCE and bot.has_method("bot_summon_and_mount"):
		bot.bot_summon_and_mount()
		if bot.get("mounted_vehicle") != null:
			return RUNNING  # 上座成功，下一帧进入自动驾驶分支
		# 召唤失败（极端情况）：本轮继续步行

	var dir: Vector3 = flat.normalized()
	dir = _steer_around_obstacles(bot, dir, flat.normalized())
	bot.velocity.x = dir.x * MOVE_SPEED
	bot.velocity.z = dir.z * MOVE_SPEED
	if _jumping:
		# M24：空中——玩家同款重力抛物线（不调地形跟随，否则贴面收敛会掐死跳跃）
		_update_jump(bot, delta)
	else:
		_apply_terrain_follow(bot, target)
		_update_stuck_jump(bot, delta)
	bot.move_and_slide()
	_face_velocity(bot, bot.velocity)
	if not _jumping:
		_play_animation(&"Run")
	return RUNNING


## M24：卡住检测 → 自动跳跃。bot 无重力贴面移动，遇矮障碍顶住时
## 实际位移远低于预期；持续卡住则触发玩家同款跳跃（物理 + Jump 动画）。
func _update_stuck_jump(bot: CharacterBody3D, delta: float) -> void:
	var moved := bot.global_position - _last_pos
	moved.y = 0.0
	var expected := MOVE_SPEED * delta
	if expected > 0.0 and moved.length() < expected * STUCK_RATIO:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	_last_pos = bot.global_position
	if _stuck_time >= STUCK_JUMP_DELAY and bot.is_on_floor():
		_stuck_time = 0.0
		_jumping = true
		_jump_time = 0.0
		bot.velocity.y = JUMP_VELOCITY
		_play_animation(&"Jump", true)


## M24：跳跃空中阶段——重力积累 + 落地判定（与玩家 _apply_gravity 同公式）
func _update_jump(bot: CharacterBody3D, delta: float) -> void:
	_jump_time += delta
	bot.velocity.y -= 9.8 * delta
	if _jump_time > JUMP_MIN_TIME and bot.is_on_floor():
		_jumping = false


## M20c：bot 死亡检查（所有长任务 _tick 首行调用）。
## agent 无效也按死亡处理——节点被销毁时同样必须中断 RUNNING。
func _is_bot_dead() -> bool:
	var bot: Node = agent
	if bot == null or not is_instance_valid(bot):
		return true
	var attr_set: Node = bot.get("attribute_set")
	return attr_set != null and not attr_set.is_alive()


## 避障转向：返回修正后的水平移动方向（单位向量）。
## to_target_h 已归一化的目标水平方向，仅用于顶墙时选择朝目标一侧绕行。
func _steer_around_obstacles(bot: CharacterBody3D, dir: Vector3, to_target_h: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
	for h in PROBE_HEIGHTS:
		var origin: Vector3 = bot.global_position + Vector3(0, h, 0)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * PROBE_DIST)
		query.exclude = [bot.get_rid()] # 排除自身碰撞体
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.get("normal", Vector3.ZERO)
		normal.y = 0.0
		# M33：NaN 闸——命中位置异常的碰撞体时法线可能非有限，
		# length()<0.1 对 NaN 恒 false 会漏到 normalized() 刷屏
		if not (is_finite(normal.x) and is_finite(normal.z)):
			continue
		if normal.length() < 0.1:
			continue # 竖直面/异常法线，忽略
		normal = normal.normalized()
		# 擦碰：去掉撞墙分量，沿墙面切向滑行
		var slide: Vector3 = dir - normal * dir.dot(normal)
		if slide.length() < 0.25:
			# 正面顶住：朝目标一侧转 DETOUR_ANGLE 绕行（一致性优先，不左右摇摆）
			var opt_a: Vector3 = dir.rotated(Vector3.UP, deg_to_rad(DETOUR_ANGLE))
			var opt_b: Vector3 = dir.rotated(Vector3.UP, deg_to_rad(-DETOUR_ANGLE))
			slide = opt_a if opt_a.dot(to_target_h) >= opt_b.dot(to_target_h) else opt_b
		return slide.normalized()
	return dir


## 垂直速度对齐物理地面：优先用向下射线探测真实碰撞面（GridMap/Arena 地板，
## 与真实玩家同款站立面——bot 无重力，不能靠坠落站稳，必须主动探测）。
## 探测不到（高空/悬崖边）时降级到地形数据公式，仍不行再对齐目标高度。
## M20c 事故：原先直接用 Terrain3D 数据高度（盆地 0 → y=2.754），但保护区
## 物理地面是 GridMap 碰撞体（高度更高），bot 被地形跟随向下压、被 GridMap
## 每帧向上弹出，穿透修正速度累积到 89m/s 直飞高空、错失交互距离。
func _apply_terrain_follow(bot: CharacterBody3D, target: Node3D) -> void:
	var space: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
	var from: Vector3 = bot.global_position + Vector3(0, 0.6, 0)
	var to: Vector3 = bot.global_position + Vector3(0, -PROBE_DOWN, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [bot.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		# M33：NaN 闸——射线命中位置异常的目标（坠出世界的怪物等）时 hit.position.y
		# 可能非有限，NaN 传给 clampf 会原样返回 → velocity.y=NaN → 位置 NaN 扩散
		if not is_finite(hit.position.y):
			bot.velocity.y = clampf(
				target.global_position.y - bot.global_position.y, -FAST_DESCENT, MOVE_SPEED)
			return
		# 命中物理地面：贴面悬停（真实玩家站立面）
		var ground_y: float = hit.position.y + HOVER_OFFSET
		bot.velocity.y = clampf(ground_y - bot.global_position.y, -FAST_DESCENT, MOVE_SPEED)
		return
	if _terrain == null:
		var starter := bot.get_node_or_null(TERRAIN_PATH)
		if starter != null and starter.terrain != null and starter.terrain.data != null:
			_terrain = starter.terrain
	if _terrain == null:
		bot.velocity.y = clampf(
			target.global_position.y - bot.global_position.y, -FAST_DESCENT, MOVE_SPEED)
		return
	var ground_y: float = _terrain.global_position.y \
			+ _terrain.data.get_height(bot.global_position) + HOVER_OFFSET
	# M33 防御 B：Terrain3D 数据区外 get_height 返回 NaN（clipmap 环外无数据），
	# NaN 传给 velocity.y 会让位置变 NaN、normalize 全线刷屏。
	# 探不到就降级对齐目标高度（有限值，clamp 保底）。
	if not is_finite(ground_y):
		bot.velocity.y = clampf(
			target.global_position.y - bot.global_position.y, -FAST_DESCENT, MOVE_SPEED)
		return
	bot.velocity.y = clampf(ground_y - bot.global_position.y, -FAST_DESCENT, MOVE_SPEED)


## 复用玩家动画链路（服务器本地播放 + request_animation_state 广播给客户端）。
## _request_animation 内部有 last-state 去重，不会每帧重复发。
## M24：restart 参数透传——Jump 这类 one-shot 动画需要重播触发。
func _play_animation(state: StringName, restart: bool = false) -> void:
	var bot: Node = agent
	if bot != null and bot.has_method("_request_animation"):
		bot._request_animation(state, restart)


## M21c 模型朝向：真人玩家移动靠 _body.apply_rotation(velocity) 让视觉模型转身
## （模型正面 +Z，内部已处理父节点 π 旋转差）；bot 的 BT 只驱动根节点 velocity，
## 从不调它 → 模型永远保持出生朝向，看起来全程反着跑（用户实测报告）。
## 移动/攻击任务每帧调用一次即可对齐。
func _face_velocity(bot: Node, vel: Vector3) -> void:
	if bot == null:
		return
	# M37：NaN 闸——vel 非有限时不能传给 apply_rotation：内部 atan2(NaN)
	# 会把 NaN 写进模型 rotation.y，模型变换随即损坏，下游 basis 归一化
	# 全部刷 "Vector3 cannot be normalized"（bot 出生即刷 12 条的根因）。
	if not (is_finite(vel.x) and is_finite(vel.y) and is_finite(vel.z)):
		return
	var body: Node = bot.get("_body")
	if body != null and body.has_method("apply_rotation"):
		body.apply_rotation(vel)
	# M48：bot 的 _physics_process 因"非 authority"在开头早退（authority=900x），
	# 朝向不会走玩家的自动分发链路 → 客户端看到的 bot 永远定在出生角度。
	# 这里代它跑一次节流发送（内部 10Hz 节流 + 无远端短路 + NaN 闸）。
	if bot.has_method("_net_tick_body_yaw"):
		bot._net_tick_body_yaw()


func _generate_name() -> String:
	return "BotMoveTo %s" % [LimboUtility.decorate_var(target_var)]
