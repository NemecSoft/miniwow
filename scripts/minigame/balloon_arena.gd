class_name BalloonArena
extends Node3D

## 气球夺剑小游戏（M36）：5 个彩色气球用绳吊着一把发光宝剑悬在林间空地上，
## 玩家捡地上石块投掷击破气球，全爆后宝剑坠落成可拾取战利品（balloon_sword），
## 一段时间后重新挂上宝剑循环营业。
##
## 网络架构（遵守 M26/M28 铁律）：
## - 场景本体是 level.tscn 静态实例，两端各自程序化构建（确定性结构，节点一一对应）
## - 气球浮动/绳索连线是纯表现，两端各自跑（同起点 sin，相位微小差异无感）
## - 权威逻辑只在服务器：石块命中检测（权威石块 vs 气球世界坐标距离）、
##   石堆状态、掉落生成（world_drops.spawn_drop 走 ItemContainer spawner 自动双端）
## - 状态变化一律服务器 rpc 广播（any_peer + call_local + sender 校验），
##   客户端只发 rpc_id(1) 请求（见 player.gd 的 request_pick_stone/request_throw_stone）

const ARENA_CENTER := Vector3(0.0, 0.0, -100.0) ## 世界坐标：村庄广场正南 30m（玩家出生面朝南一出村即见；村 rect 内无常规树、环带内缘无大树）
const BALLOON_COUNT := 5
const BALLOON_HEIGHT := 5.5 ## 气球环绕平面离地高度
const BALLOON_RADIUS := 1.0 ## 大气球（WoW 节庆气球手感，30m 外也醒目）
const ORBIT_RADIUS := 3.5 ## 气球环绕剑锚点的半径
const HIT_RADIUS := 1.7 ## 石块命中气球的距离判定（气球半径 1.0 + 浮动 0.28 + 网络抖动）
const STONE_LIFETIME := 5.0
const PILE_RESPAWN_SECONDS := 8.0 ## 石堆被采后重新长出
const SWORD_RESPAWN_SECONDS := 30.0 ## 宝剑坠落后重新挂回（掉落物已被拾取/消失才重置）
const PICKUP_RANGE := 3.0 ## 玩家可取石堆距离
const SWORD_ITEM_ID := "balloon_sword"

## 5 个气球的颜色（WoW 风鲜艳配色，雾灰背景中跳出来）
const BALLOON_COLORS: Array[Color] = [
	Color(0.85, 0.18, 0.16), # 红
	Color(0.95, 0.78, 0.12), # 黄
	Color(0.22, 0.45, 0.90), # 蓝
	Color(0.25, 0.72, 0.32), # 绿
	Color(0.62, 0.32, 0.82), # 紫
]

const BALLOON_STONE_SCENE := preload("res://scenes/minigame/balloon_stone.tscn")
const BALLOON_POP_SCENE := preload("res://scenes/vfx/balloon_pop.tscn")

## 石堆布局（arena 局部坐标，确定性——两端必须一致）
const STONE_PILE_OFFSETS: Array[Vector3] = [
	Vector3(4.5, 0.0, 3.5),
	Vector3(-5.0, 0.0, 4.0),
	Vector3(0.0, 0.0, -5.5),
]
## 每堆内部石块偏移（同一堆共用，保证两端石头形状一致）
const PILE_STONE_OFFSETS: Array[Vector3] = [
	Vector3(0.0, 0.09, 0.0),
	Vector3(0.32, 0.07, 0.18),
	Vector3(-0.26, 0.11, -0.12),
	Vector3(0.08, 0.05, -0.3),
]

var _ground_y: float = 0.0 ## 场地地面高度（射线探测）
var _balloons: Array[Node3D] = [] ## 5 个气球根节点（浮动目标）
var _balloon_meshes: Array[MeshInstance3D] = []
var _balloon_base: Array[Vector3] = [] ## 各气球基准局部位置
var _balloon_popped: Array[bool] = []
var _ropes: Array[MeshInstance3D] = [] ## 与气球一一对应的绳
var _sword_pivot: Node3D
var _sword_light: OmniLight3D
var _stone_piles: Array[Node3D] = []
var _stone_pile_ready: Array[bool] = []
var _stone_pile_timer: Array[float] = []

## 以下仅服务器维护
var _authority_stones: Array[Node3D] = [] ## 服务器权威石块（命中检测对象）
var _sword_dropped: bool = false ## 剑已坠落（等待 reset）
var _sword_respawn_timer: float = 0.0


func _ready() -> void:
	# M34 铁律：Terrain3D data_directory 异步加载，_ready 时地形未就绪，
	# 探测射线会打空。延时到地形就绪再建场地（forest_starter 同款 2.5s 模式）。
	get_tree().create_timer(3.0).timeout.connect(_build_arena)


func _build_arena() -> void:
	# 入树后才能写 global_position（Environment 容器带 y≈2.25 变换，必须世界坐标定位）。
	# 先探测地面高度，arena 根贴地——所有子节点局部坐标即"离地"语义
	# （气球 y=6 离地 6m、石堆 y=0 贴地），丘陵地形上不浮空不埋地。
	_ground_y = _probe_ground_y()
	global_position = ARENA_CENTER + Vector3(0.0, _ground_y, 0.0)
	_build_balloons()
	_build_sword()
	_build_stone_piles()
	printerr("[BalloonArena] 场地已构建 center=", ARENA_CENTER, " ground_y=", _ground_y)


func _probe_ground_y() -> float:
	var query := PhysicsRayQueryParameters3D.new()
	query.from = ARENA_CENTER + Vector3(0.0, 60.0, 0.0)
	query.to = ARENA_CENTER + Vector3(0.0, -10.0, 0.0)
	query.collision_mask = 2
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and is_finite(hit.position.y):
		return hit.position.y
	return 0.0 # 平地 region 兜底


# ===== 构建：气球 + 绳 =====
func _build_balloons() -> void:
	var container := Node3D.new()
	container.name = "Balloons"
	add_child(container)
	var ropes := Node3D.new()
	ropes.name = "Ropes"
	add_child(ropes)
	var pivot_local := Vector3(0.0, BALLOON_HEIGHT + 1.5, 0.0)
	for i in BALLOON_COUNT:
		var angle := TAU * float(i) / float(BALLOON_COUNT)
		var base := Vector3(cos(angle) * ORBIT_RADIUS, BALLOON_HEIGHT, sin(angle) * ORBIT_RADIUS)
		_balloon_base.append(base)
		_balloon_popped.append(false)
		# 气球本体
		var balloon := Node3D.new()
		balloon.name = "Balloon%d" % i
		balloon.position = base
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = BALLOON_RADIUS
		sphere.height = BALLOON_RADIUS * 2.0
		sphere.radial_segments = 16
		sphere.rings = 10
		mesh.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = BALLOON_COLORS[i]
		mat.roughness = 0.55
		mat.emission_enabled = true
		mat.emission = BALLOON_COLORS[i]
		mat.emission_energy_multiplier = 0.25
		mesh.material_override = mat
		balloon.add_child(mesh)
		# 气球嘴（底部小球）
		var knot := MeshInstance3D.new()
		var knot_mesh := SphereMesh.new()
		knot_mesh.radius = 0.09
		knot_mesh.height = 0.18
		knot_mesh.radial_segments = 8
		knot_mesh.rings = 4
		knot.mesh = knot_mesh
		knot.position = Vector3(0.0, -BALLOON_RADIUS - 0.04, 0.0)
		knot.material_override = mat
		balloon.add_child(knot)
		container.add_child(balloon)
		_balloons.append(balloon)
		_balloon_meshes.append(mesh)
		# 绳（细长 BoxMesh，每帧在 _update_ropes 里对齐气球顶→剑锚点）
		var rope := MeshInstance3D.new()
		rope.name = "Rope%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(0.035, 1.0, 0.035)
		rope.mesh = box
		var rope_mat := StandardMaterial3D.new()
		rope_mat.albedo_color = Color(0.25, 0.2, 0.15)
		rope_mat.roughness = 1.0
		rope.material_override = rope_mat
		ropes.add_child(rope)
		_ropes.append(rope)


# ===== 构建：悬挂的宝剑 =====
func _build_sword() -> void:
	var pivot := Node3D.new()
	pivot.name = "SwordPivot"
	pivot.position = Vector3(0.0, BALLOON_HEIGHT + 1.5, 0.0)
	add_child(pivot)
	_sword_pivot = pivot
	# 剑身（银，微发光——雾中指引目标）
	var blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.07, 1.1, 0.14)
	blade.mesh = blade_mesh
	blade.position = Vector3(0.0, 0.55, 0.0)
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.78, 0.82, 0.88)
	blade_mat.metallic = 0.65
	blade_mat.roughness = 0.28
	blade_mat.emission_enabled = true
	blade_mat.emission = Color(0.32, 0.5, 0.62)
	blade_mat.emission_energy_multiplier = 0.4
	blade.material_override = blade_mat
	pivot.add_child(blade)
	# 护手（金，镶红宝石）
	var guard := MeshInstance3D.new()
	var guard_mesh := BoxMesh.new()
	guard_mesh.size = Vector3(0.5, 0.07, 0.12)
	guard.mesh = guard_mesh
	var gold_mat := StandardMaterial3D.new()
	gold_mat.albedo_color = Color(0.95, 0.75, 0.22)
	gold_mat.metallic = 0.5
	gold_mat.roughness = 0.35
	guard.material_override = gold_mat
	pivot.add_child(guard)
	var gem := MeshInstance3D.new()
	var gem_mesh := SphereMesh.new()
	gem_mesh.radius = 0.06
	gem_mesh.height = 0.12
	gem_mesh.radial_segments = 8
	gem_mesh.rings = 4
	gem.mesh = gem_mesh
	gem.position = Vector3(0.0, 0.06, 0.0)
	var gem_mat := StandardMaterial3D.new()
	gem_mat.albedo_color = Color(0.9, 0.2, 0.2)
	gem_mat.emission_enabled = true
	gem_mat.emission = Color(0.9, 0.2, 0.2)
	gem_mat.emission_energy_multiplier = 1.5
	gem.material_override = gem_mat
	pivot.add_child(gem)
	# 剑柄（棕）
	var grip := MeshInstance3D.new()
	var grip_mesh := BoxMesh.new()
	grip_mesh.size = Vector3(0.06, 0.28, 0.08)
	grip.mesh = grip_mesh
	grip.position = Vector3(0.0, -0.17, 0.0)
	var grip_mat := StandardMaterial3D.new()
	grip_mat.albedo_color = Color(0.35, 0.22, 0.12)
	grip_mat.roughness = 0.9
	grip.material_override = grip_mat
	pivot.add_child(grip)
	# 金色微光灯（雾中远处可见的目标指引）
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.4)
	light.light_energy = 2.5
	light.omni_range = 5.0
	light.position = Vector3(0.0, 0.55, 0.0)
	pivot.add_child(light)
	_sword_light = light


# ===== 构建：3 个石堆 =====
func _build_stone_piles() -> void:
	var container := Node3D.new()
	container.name = "StonePiles"
	add_child(container)
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.42, 0.41, 0.39)
	stone_mat.roughness = 1.0
	for i in STONE_PILE_OFFSETS.size():
		var pile := Node3D.new()
		pile.name = "StonePile%d" % i
		pile.position = STONE_PILE_OFFSETS[i]
		for offset in PILE_STONE_OFFSETS:
			var stone := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.16
			mesh.height = 0.24
			mesh.radial_segments = 6
			mesh.rings = 4
			stone.mesh = mesh
			# 不规则感：各块不同缩放（确定性，与下标绑定）
			var s := 0.7 + 0.15 * float(PILE_STONE_OFFSETS.find(offset))
			stone.scale = Vector3(s, s * 0.8, s * 1.1)
			stone.position = offset
			stone.material_override = stone_mat
			pile.add_child(stone)
		container.add_child(pile)
		_stone_piles.append(pile)
		_stone_pile_ready.append(true)
		_stone_pile_timer.append(0.0)


# ===== 表现：气球浮动 + 绳索对齐（两端各自跑）=====
func _physics_process(_delta: float) -> void:
	if _balloons.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	var pivot_local := Vector3(0.0, BALLOON_HEIGHT + 1.5, 0.0)
	for i in _balloons.size():
		if _balloon_popped[i]:
			continue
		var base := _balloon_base[i]
		var float_offset := Vector3(
			sin(t * 1.1 + float(i) * 0.9) * 0.12,
			sin(t * 1.5 + float(i) * 1.7) * 0.28,
			cos(t * 0.9 + float(i) * 0.5) * 0.12
		)
		_balloons[i].position = base + float_offset
		# 绳：气球顶 → 剑锚点（局部系 Basis 构造，Y 轴对齐绳方向）
		var rope := _ropes[i]
		if rope == null:
			continue
		var a: Vector3 = _balloons[i].position + Vector3(0.0, BALLOON_RADIUS, 0.0)
		var diff: Vector3 = pivot_local - a
		var length: float = diff.length()
		if length < 0.001:
			continue
		var y_axis: Vector3 = diff / length
		var x_axis: Vector3 = y_axis.cross(Vector3.UP)
		if x_axis.length() < 0.001:
			x_axis = Vector3.RIGHT
		else:
			x_axis = x_axis.normalized()
		var z_axis: Vector3 = x_axis.cross(y_axis)
		rope.transform = Transform3D(
			Basis(x_axis, y_axis, z_axis).scaled(Vector3(1.0, length, 1.0)),
			(a + pivot_local) * 0.5
		)
	if not multiplayer.is_server():
		return
	_server_tick(_delta)


## 服务器权威逻辑：权威石块命中检测 + 石堆重生 + 宝剑 reset
func _server_tick(delta: float) -> void:
	# 1) 权威石块积分与命中检测
	for i in range(_authority_stones.size() - 1, -1, -1):
		var stone := _authority_stones[i]
		if not is_instance_valid(stone):
			_authority_stones.remove_at(i)
			continue
		var stone_pos: Vector3 = stone.global_position
		var hit_idx := -1
		for b in BALLOON_COUNT:
			if _balloon_popped[b]:
				continue
			if stone_pos.distance_to(_balloons[b].global_position) <= HIT_RADIUS:
				hit_idx = b
				break
		if hit_idx >= 0:
			_authority_stones.remove_at(i)
			# 广播各端移除对应表现份（name 与服务器权威份一致），再销毁权威份
			despawn_stone_visual.rpc(stone.name)
			stone.queue_free()
			pop_balloon.rpc(hit_idx)
			continue
		if stone_pos.y < _ground_y - 1.0:
			_authority_stones.remove_at(i)
			stone.queue_free()
	# 2) 石堆重生计时
	for i in _stone_pile_ready.size():
		if _stone_pile_ready[i]:
			continue
		_stone_pile_timer[i] -= delta
		if _stone_pile_timer[i] <= 0.0:
			_stone_pile_ready[i] = true
			set_pile_visible.rpc(i, true)
	# 3) 宝剑 reset：坠落后且掉落物已不在世上（被拾取或超时消失）才重新挂剑
	if _sword_dropped:
		if not _sword_drop_still_exists():
			_sword_respawn_timer -= delta
			if _sword_respawn_timer <= 0.0:
				_sword_dropped = false
				reset_arena.rpc()


func _sword_drop_still_exists() -> bool:
	var container := get_node_or_null("/root/Level/Environment/ItemContainer")
	if container == null:
		return false
	for child in container.get_children():
		if child is ItemRigidBody3D and (child as ItemRigidBody3D).item_id == SWORD_ITEM_ID:
			return true
	return false


# ===== 玩家交互接口（player.gd 调用；距离检测两端本地跑，状态变更只服务器）=====

## 返回 3m 内已长出的石堆下标，无则 -1
func get_nearest_stone_pile(player_world_pos: Vector3) -> int:
	for i in _stone_piles.size():
		if not _stone_pile_ready[i]:
			continue
		if player_world_pos.distance_to(_stone_piles[i].global_position) <= PICKUP_RANGE:
			return i
	return -1


## 服务器：玩家采走一个石堆（隐藏 + 重生计时 + 广播）
func take_stone_pile(idx: int) -> void:
	if not multiplayer.is_server():
		return
	if idx < 0 or idx >= _stone_pile_ready.size() or not _stone_pile_ready[idx]:
		return
	_stone_pile_ready[idx] = false
	_stone_pile_timer[idx] = PILE_RESPAWN_SECONDS
	set_pile_visible.rpc(idx, false)


## 服务器：生成一块权威石块（手动积分，arena 服务器循环做命中检测）
## stone_name 与广播给各端的表现份同名——命中后按名广播移除
func spawn_authority_stone(stone_name: String, origin: Vector3, direction: Vector3, speed: float) -> void:
	if not multiplayer.is_server():
		return
	# M33 NaN 铁律：入参逐分量检查，非有限直接拒绝
	if not (is_finite(origin.x) and is_finite(origin.y) and is_finite(origin.z)):
		return
	if not (is_finite(direction.x) and is_finite(direction.y) and is_finite(direction.z)):
		return
	var stone := BALLOON_STONE_SCENE.instantiate() as BalloonStone
	if stone == null:
		return
	stone.name = stone_name
	add_child(stone)
	stone.global_position = origin
	stone.is_authority = true
	stone.setup(direction.normalized() * speed, _ground_y, STONE_LIFETIME)
	_authority_stones.append(stone)


# ===== RPC：服务器下发广播（any_peer + call_local + sender 校验）=====

## 气球被击破：各端隐藏气球 + 爆裂特效 + 音效 + 播报
@rpc("any_peer", "call_local", "reliable")
func pop_balloon(idx: int) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	if idx < 0 or idx >= _balloons.size():
		return
	_balloon_popped[idx] = true
	_balloons[idx].visible = false
	var world_pos: Vector3 = _balloons[idx].global_position
	SfxManager.spawn_effect(BALLOON_POP_SCENE.resource_path, world_pos)
	SfxManager.play_3d(&"hit_light", world_pos)
	if multiplayer.is_server():
		var remaining := 0
		for b in _balloon_popped:
			if not b:
				remaining += 1
		if remaining > 0:
			show_balloon_message.rpc("击中气球！还剩 %d 个" % remaining)
		else:
			_drop_sword()


## 服务器：全爆 → 宝剑坠落成掉落物 + 各端隐藏悬挂的剑
func _drop_sword() -> void:
	var container := get_node_or_null("/root/Level/Environment/ItemContainer") as WorldDrops
	if container != null:
		# 掉落起点 = arena 根上方 1.5m（arena 根已贴地，无论丘陵/平地都从地面上方落下）
		container.spawn_drop(SWORD_ITEM_ID, 1, global_position + Vector3(0.0, 1.5, 0.0))
	_sword_dropped = true
	_sword_respawn_timer = SWORD_RESPAWN_SECONDS
	hide_sword.rpc()
	show_balloon_message.rpc("绳索断裂！宝剑坠落在场中，快去拾取！")
	SfxManager.play(&"quest_success")


## 系统播报（走 level 的聊天频道，同 _server_pickup 模式）
@rpc("any_peer", "call_local", "reliable")
func show_balloon_message(msg: String) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	var level_scene := get_tree().current_scene
	if level_scene and level_scene.has_method("show_chat_message"):
		level_scene.show_chat_message.rpc(tr("系统"), msg)


## 石堆显隐（服务器广播）
@rpc("any_peer", "call_local", "reliable")
func set_pile_visible(idx: int, visible: bool) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	if idx < 0 or idx >= _stone_piles.size():
		return
	_stone_piles[idx].visible = visible


## 投掷石块表现份生成（服务器下发；服务器本地跳过——已有权威份兼视觉）
@rpc("any_peer", "call_local", "reliable")
func spawn_stone_visual(stone_name: String, origin: Vector3, direction: Vector3, speed: float) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	if multiplayer.is_server():
		return
	if not (is_finite(origin.x) and is_finite(direction.x)):
		return
	var stone := BALLOON_STONE_SCENE.instantiate() as BalloonStone
	if stone == null:
		return
	stone.name = stone_name
	add_child(stone)
	stone.global_position = origin
	stone.setup(direction.normalized() * speed, _ground_y, STONE_LIFETIME)


## 移除投掷石块表现份（命中气球后各端清理）
@rpc("any_peer", "call_local", "reliable")
func despawn_stone_visual(stone_name: String) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	var stone := get_node_or_null(stone_name)
	if stone:
		stone.queue_free()


## 全爆后各端隐藏悬挂的剑与绳
@rpc("any_peer", "call_local", "reliable")
func hide_sword() -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	if _sword_pivot != null:
		_sword_pivot.visible = false
	for rope in _ropes:
		if rope != null:
			rope.visible = false


## 重置场地：气球复活 + 剑绳恢复（宝剑掉落物已消失后服务器广播）
@rpc("any_peer", "call_local", "reliable")
func reset_arena() -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	for i in _balloon_popped.size():
		_balloon_popped[i] = false
		_balloons[i].visible = true
	if _sword_pivot != null:
		_sword_pivot.visible = true
	for rope in _ropes:
		if rope != null:
			rope.visible = true
	# 播报本地直接显示（本 rpc 本身就是全端广播，不再嵌套转发）
	var level_scene := get_tree().current_scene
	if level_scene and level_scene.has_method("show_chat_message"):
		level_scene.show_chat_message(tr("系统"), tr("又一只彩色气球挂上了新剑，继续投掷吧！"))
