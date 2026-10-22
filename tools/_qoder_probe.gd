extends Node

## 临时探针（判定测试失败归因用，验证完即删）
## 运行：godot --headless --path . res://tools/_qoder_probe.tscn


func _ready() -> void:
	_probe_anim_bones()
	await _probe_game()
	get_tree().quit(0)


# ===== A. 骨骼驱动集比对（anim_binding ⑤）=====

func _probe_anim_bones() -> void:
	var scene := load("res://scenes/characters/infantry_mannequin.tscn") as PackedScene
	var inst := scene.instantiate()
	add_child(inst)
	var ap := inst.get_node_or_null("Mannequin/AnimationPlayer") as AnimationPlayer
	if ap == null:
		print("Q| ANIM: 找不到 Mannequin/AnimationPlayer")
		return
	var lib := ap.get_animation_library(&"")
	var names: Array = []
	for n in lib.get_animation_list():
		names.append(String(n))
	print("Q| ANIM: mannequin 库动画=", names)
	var idle := _bones(lib.get_animation(&"Idle"))
	var run := _bones(lib.get_animation(&"Run"))
	var sit: Animation = load("res://assets/animations/retarget/sit_idle_kaykit.tres")
	var sitb := _bones(sit)
	print("Q| ANIM: Idle 骨骼集(", idle.size(), ")=", idle.keys())
	print("Q| ANIM: Run 骨骼集(", run.size(), ")=", run.keys())
	print("Q| ANIM: sit_idle_kaykit 骨骼集(", sitb.size(), ")=", sitb.keys())
	var leak_idle: Array[String] = []
	for b in sitb.keys():
		if not idle.has(b):
			leak_idle.append(b)
	var both := idle.duplicate()
	for b in run.keys():
		both[b] = true
	var leak_both: Array[String] = []
	for b in sitb.keys():
		if not both.has(b):
			leak_both.append(b)
	print("Q| ANIM: 相对 mannequin Idle 残留=", leak_both if false else leak_idle)
	print("Q| ANIM: 相对 mannequin Idle+Run 残留=", leak_both)
	inst.queue_free()


func _bones(anim: Animation) -> Dictionary:
	var out := {}
	if anim == null:
		return out
	for t in anim.get_track_count():
		var sub := String(anim.track_get_path(t).get_subname(0))
		if not sub.is_empty():
			out[sub] = true
	return out


# ===== B. 商店 / 拾取 / 朝向 =====

func _probe_game() -> void:
	var level := (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	get_tree().root.call_deferred("add_child", level)
	await get_tree().process_frame
	var pc := level.get_node_or_null("PlayersContainer") as Node3D
	var player := (load("res://scenes/level/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	pc.add_child(player, true)
	for i in range(40):
		await get_tree().process_frame
	print("Q| NET: peer=", multiplayer.multiplayer_peer, " is_server=", multiplayer.is_server())
	print("Q| POS: player=", player.global_position)

	# --- B1. 商店：默认位置 vs 商人旁 ---
	var merchants := get_tree().get_nodes_in_group("merchants")
	print("Q| SHOP: merchants 数量=", merchants.size())
	for m in merchants:
		if m is Node3D:
			print("Q| SHOP:   merchant ", m.name, " pos=", (m as Node3D).global_position,
				" dist=", player.global_position.distance_to((m as Node3D).global_position))
	var item_db := get_node("/root/ItemDatabase")
	print("Q| SHOP: sword_green 在货架=", item_db.MERCHANT_STOCK.has("sword_green"),
		" value=", item_db.get_item("sword_green").value,
		" bone value=", item_db.get_item("bone").value)
	print("Q| SHOP: 默认位置 _is_near_any_merchant=", player.call("_is_near_any_merchant"))
	# 原地买（复刻测试前置：不在商人旁）
	player.add_gold(500)
	player.request_buy_item("sword_green")
	await get_tree().process_frame
	var inv := player.call("get_inventory")
	print("Q| SHOP: 原地买后 gold=", player.gold, " 包内有精铁剑=", inv.call("get_slot_index_of", "sword_green") >= 0)
	# 传送到商人旁再买
	if not merchants.is_empty():
		var m0 = merchants[0]
		for k in range(6):
			player.global_position = (m0 as Node3D).global_position
			await get_tree().physics_frame
		print("Q| SHOP: 传送商人旁 pos=", player.global_position,
			" near=", player.call("_is_near_any_merchant"))
		player.request_buy_item("sword_green")
		await get_tree().process_frame
		print("Q| SHOP: 商人旁买后 gold=", player.gold,
			" 包内有精铁剑=", inv.call("get_slot_index_of", "sword_green") >= 0)
		# 金币不足
		player.spend_gold(200)
		print("Q| SHOP: spend200 后 gold=", player.gold)
		player.request_buy_item("sword_blue")
		await get_tree().process_frame
		print("Q| SHOP: 买220蓝剑后 gold=", player.gold,
			" 包内有蓝剑=", inv.call("get_slot_index_of", "sword_blue") >= 0)
		# 卖骨头
		var bone_slot: int = inv.call("get_slot_index_of", "bone")
		print("Q| SHOP: 骨头条目 slot=", bone_slot)
		player.request_sell_item(bone_slot)
		await get_tree().process_frame
		print("Q| SHOP: 卖骨头后 gold=", player.gold,
			" 骨头 slot=", inv.call("get_slot_index_of", "bone"))
		# 穿精铁剑
		var green_slot: int = inv.call("get_slot_index_of", "sword_green")
		player.request_equip_item(green_slot, 0) # ItemType.WEAPON = 0
		await get_tree().process_frame
		print("Q| SHOP: 穿精铁剑后 atk=", player.attribute_set.atk, " green_slot=", green_slot)

	# --- B2. 拾取三道闸（M14）---
	var drops := get_tree().root.get_node_or_null("Level/Environment/ItemContainer")
	print("Q| PICK: ItemContainer=", drops)
	if drops != null:
		drops.call("spawn_drop", "chicken_leg", 1, player.global_position + Vector3(1.0, 0.5, 0.0))
		for i in range(20):
			await get_tree().physics_frame
		var kids := drops.get_children()
		print("Q| PICK: ItemContainer 子节点数=", kids.size())
		for c in kids:
			if c is Node3D:
				print("Q| PICK:   ", c.name, " id=", c.get("item_id"), " pos=", (c as Node3D).global_position,
					" dist=", player.global_position.distance_to((c as Node3D).global_position))
	player.set("_server_pickup_animation_started_msec", -1)
	print("Q| PICK: is_server=", multiplayer.is_server(),
		" owner_req=", player.call("_is_owner_request"),
		" tokens=", player.get("_server_animation_request_tokens"),
		" grounded=", player.call("_is_grounded_on_server"),
		" has_item=", player.call("_has_collectible_item_in_front"))
	# 射线细节：mask2 vs 玩家自身 mask
	var space := player.get_world_3d().direct_space_state
	for mask in [2, 1, 3, player.collision_mask]:
		var q := PhysicsRayQueryParameters3D.new()
		q.from = player.global_position + Vector3.UP * 0.15
		q.to = player.global_position + Vector3.DOWN * 0.3
		q.collision_mask = mask
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		print("Q| PICK: ray mask=", mask, " hit=", not hit.is_empty(), " collider=", hit.get("collider"))
	# 更长的向下射线，看地面到底在哪
	for dist in [0.3, 1.0, 3.0]:
		var q2 := PhysicsRayQueryParameters3D.new()
		q2.from = player.global_position + Vector3.UP * 0.15
		q2.to = player.global_position - Vector3.UP * dist
		q2.collision_mask = 2
		q2.exclude = [player.get_rid()]
		print("Q| PICK: 长射线 down=", dist, " hit=", not space.intersect_ray(q2).is_empty())
	print("Q| PICK: is_on_floor=", player.is_on_floor(), " _grounded=", player.get("_grounded"))
	player.call("request_animation_state", &"Pickup", 1.0)
	await get_tree().process_frame
	print("Q| PICK: 调 Pickup 后 ts=", player.get("_server_pickup_animation_started_msec"))

	# --- B3. 玩家真实移动朝向（m7 第 2 项）---
	var body: Node3D = player.get("_body")
	print("Q| FACE: 起始 body global z=", body.global_transform.basis.z.normalized(),
		" 根 z=", player.global_transform.basis.z.normalized())
	Input.action_press("move_right")
	for i in range(40):
		await get_tree().physics_frame
	var v: Vector3 = player.get("velocity")
	var fwd: Vector3 = body.global_transform.basis.z.normalized()
	var up: Vector3 = player.get("_up")
	var vflat := v - up * v.dot(up)
	print("Q| FACE: 按 move_right 后 velocity=", v, " body z(全局)=", fwd,
		" body z 水平归一=", (fwd - up * fwd.dot(up)).normalized(),
		" dot(与速度)=", (fwd - up * fwd.dot(up)).normalized().dot(vflat.normalized()) if vflat.length_squared() > 0.01 else 0.0)
	print("Q| FACE: body 局部 rotation=", body.rotation, " (期望只有 y 非 0)")
	Input.action_release("move_right")
	for i in range(20):
		await get_tree().physics_frame
	Input.action_press("move_forward")
	for i in range(40):
		await get_tree().physics_frame
	v = player.get("velocity")
	fwd = body.global_transform.basis.z.normalized()
	vflat = v - up * v.dot(up)
	print("Q| FACE: 按 move_forward 后 dot(body z, 速度)=",
		(fwd - up * fwd.dot(up)).normalized().dot(vflat.normalized()) if vflat.length_squared() > 0.01 else 0.0)
	Input.action_release("move_forward")
