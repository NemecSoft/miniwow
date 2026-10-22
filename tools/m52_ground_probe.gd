extends Node3D

## M52 地面判定抖动取证（可 headless 跑，不需要出图）。
##
## 假设：广场上走路时 _grounded 在相邻帧之间反复翻转 → _was_airborne 每帧被置位再清掉
## → 每帧 spawn 一次 land_particles.tscn → 身后拖出一条橙色烟雾带（用户说的"重影"）。
##
## 只量三样真东西：gap（脚底到地面，米）、is_on_floor()（物理权威）、
## 以及场景里存活多少个 LandParticles 节点。

const FRAMES := 120

var _level: Node3D
var _me: Node3D


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	_level.call("_on_host_pressed", "抖动", "blue")
	await get_tree().create_timer(4.0).timeout
	_me = _find_player()
	if _me == null:
		printerr("F52: !! 没有玩家")
		get_tree().quit(0)
		return

	printerr("F52: 起点 " + str(_me.global_position))
	_probe_ray()

	# ---- 第一段：静止 40 帧（对照）----
	var idle_flips := 0
	var idle_floor_false := 0
	var idle_prev: bool = _me.get("_grounded")
	for i in 40:
		await get_tree().physics_frame
		var g0: bool = _me.get("_grounded")
		if g0 != idle_prev:
			idle_flips += 1
			idle_prev = g0
		if not _me.is_on_floor():
			idle_floor_false += 1
	printerr("F52: 【静止 40 帧】_grounded 翻转 %d 次 | is_on_floor() 假 %d 次" % [
		idle_flips, idle_floor_false])

	var flips := 0
	var prev_grounded: bool = _me.get("_grounded")
	var min_gap := 1e9
	var max_gap := -1e9
	var floor_true := 0
	var airborne_frames := 0
	var land_count_before := _count_land_fx()

	Input.action_press("move_forward")
	for i in FRAMES:
		await get_tree().physics_frame
		var p: Vector3 = _me.global_position
		var up: Vector3 = Planet.up_at(p)
		var terrain_r: float = Planet.RADIUS + Planet.mesh_height(up)
		var game_r: float = _me.call("_ground_radius_at", p, up)
		var gap: float = p.length() - game_r
		min_gap = minf(min_gap, gap)
		max_gap = maxf(max_gap, gap)
		if _me.is_on_floor():
			floor_true += 1
		var g: bool = _me.get("_grounded")
		if g != prev_grounded:
			flips += 1
			prev_grounded = g
		if not g:
			airborne_frames += 1
		if i < 20:
			printerr("F52[%02d]: gap=%+.3f (地形差%+.3f) on_floor=%s grounded=%s vr=%+.2f" % [
				i, gap, p.length() - terrain_r, str(_me.is_on_floor()), str(g),
				(_me.velocity as Vector3).dot(up)])
	Input.action_release("move_forward")
	await get_tree().physics_frame

	var land_after := _count_land_fx()
	printerr("F52: === 结果（%d 帧走路）===" % FRAMES)
	printerr("F52: _grounded 翻转 %d 次 | 非接地帧 %d/%d | is_on_floor() 真 %d/%d" % [
		flips, airborne_frames, FRAMES, floor_true, FRAMES])
	printerr("F52: gap 范围 %.3f ~ %.3f 米" % [min_gap, max_gap])
	printerr("F52: LandParticles 存活 %d → %d" % [land_count_before, land_after])
	get_tree().quit(0)


func _find_player() -> Node3D:
	var pc := _level.get_node_or_null("PlayersContainer")
	return pc.get_node_or_null("1") as Node3D if pc != null else null


## 复刻 _ground_radius_at 的射线，把"到底踩在谁身上"打出来。
func _probe_ray() -> void:
	var p: Vector3 = _me.global_position
	var up: Vector3 = Planet.up_at(p)
	var space := _me.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + up * 1.0, p - up * 3.0)
	q.collision_mask = 2
	q.collide_with_areas = false
	q.hit_from_inside = false
	q.exclude = [_me.get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	# 再用全掩码打一遍：如果全掩码命中了别的东西（layer 不是 2），说明地图上
	# 有一层"能站人但 _ground_radius_at 看不见"的碰撞面 —— 角色就会站在它上面，
	# 而 gap 永远算成"离地形的高度"，_grounded 只能靠抖动的 is_on_floor()。
	var qa := PhysicsRayQueryParameters3D.create(p + up * 1.0, p - up * 3.0)
	qa.collision_mask = 0xFFFFFFFF
	qa.collide_with_areas = false
	qa.hit_from_inside = false
	qa.exclude = [_me.get_rid()]
	var hit_all: Dictionary = space.intersect_ray(qa)
	var terrain_r: float = Planet.RADIUS + Planet.mesh_height(up)
	printerr("F52[射线]: 地形半径=%.3f 玩家原点半径=%.3f 差=%.3f" % [
		terrain_r, p.length(), p.length() - terrain_r])
	if hit.is_empty():
		printerr("F52[射线]: 打空（mask=2 什么都没命中）")
	else:
		var hp: Vector3 = hit["position"]
		var col = hit["collider"]
		printerr("F52[射线]: 命中 %s | 点半径=%.3f | 比地形高 %.3f" % [
			str(col.get_path()) if col is Node else str(col), hp.length(), hp.length() - terrain_r])
	if hit_all.is_empty():
		printerr("F52[全掩码]: 也打空")
	else:
		var hp2: Vector3 = hit_all["position"]
		var col2 = hit_all["collider"]
		printerr("F52[全掩码]: 命中 %s | 点半径=%.3f | 比地形高 %.3f" % [
			str(col2.get_path()) if col2 is Node else str(col2), hp2.length(), hp2.length() - terrain_r])
	# 胶囊尺寸，用来把"原点高度"换算成"脚底高度"
	var cs := _me.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null and cs.shape is CapsuleShape3D:
		var cap := cs.shape as CapsuleShape3D
		printerr("F52[胶囊]: radius=%.3f height=%.3f shape_y=%.3f → 脚底在原点 %+.3f 处" % [
			cap.radius, cap.height, cs.position.y, cs.position.y - cap.height * 0.5])


func _count_land_fx() -> int:
	return get_tree().root.find_children("*LandParticles*", "GPUParticles3D", true, false).size()
