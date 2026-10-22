class_name WorldDrops
extends Node3D

## 世界掉落物管理（M8）。挂在 level 的 Environment/ItemContainer 节点上：
## spawn_drop 生成的掉落物作为 ItemContainer 子节点，由 ItemMultiplayerSpawner
## 自动同步到所有客户端；位姿同步靠掉落物自带的 MultiplayerSynchronizer。
## 3 分钟无人拾取自动消失（服务器定时，despawn RPC 广播各端移除）。

const DESPAWN_SECONDS := 180.0 ## 无人拾取存在时限

var _drop_expiry: Dictionary = {} # Node -> 剩余秒数（仅服务器记录）


## 服务器：在指定世界位置生成一个掉落物（带上抛初速度的落地弹跳手感）
func spawn_drop(item_id: String, quantity: int, world_position: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var item := ItemDatabase.get_item(item_id)
	if item == null or item.scene_path.is_empty():
		push_warning("WorldDrops: 物品 '%s' 无场景路径，无法掉落" % item_id)
		return
	var scene := load(item.scene_path) as PackedScene
	if scene == null:
		push_warning("WorldDrops: 无法加载掉落场景 '%s'" % item.scene_path)
		return
	var drop := scene.instantiate()
	if drop is ItemRigidBody3D:
		(drop as ItemRigidBody3D).item_id = item_id
		(drop as ItemRigidBody3D).quantity = maxi(1, quantity)
	# M21：必须传 force_readable_name=true——ItemMultiplayerSpawner 自动同步
	# 要求节点有合法名字，直接 add_child(drop) 会生成 "@RigidBody3D@261" 这类
	# 保留名，spawner 拒绝同步（窗口实测：bot 打死怪后战利品全军覆没，
	# 报 "Unable to auto-spawn node with reserved name"）。
	add_child(drop, true)
	# 容器（Environment）带 y≈2.25 变换，必须用 global_position 定位（M5 弹道同款坑）
	var drop_node := drop as Node3D
	drop_node.global_position = world_position + Vector3(0, 0.6, 0)
	if drop_node is RigidBody3D:
		var rb := drop_node as RigidBody3D
		rb.linear_velocity = Vector3(randf_range(-1.5, 1.5), 3.2, randf_range(-1.5, 1.5))
		rb.angular_velocity = Vector3(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0), randf_range(-5.0, 5.0))
	_drop_expiry[drop_node] = DESPAWN_SECONDS


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server() or _drop_expiry.is_empty():
		return
	for drop in _drop_expiry.keys():
		if not is_instance_valid(drop):
			_drop_expiry.erase(drop)
			continue
		var remaining: float = _drop_expiry[drop] - delta
		if remaining <= 0.0:
			_drop_expiry.erase(drop)
			despawn_drop.rpc(get_path_to(drop))
		else:
			_drop_expiry[drop] = remaining


## 各端移除掉落物（服务器权威调用；path 为相对 ItemContainer 的节点路径）
@rpc("authority", "call_local", "reliable")
func despawn_drop(path: String) -> void:
	var node := get_node_or_null(path)
	if node:
		node.queue_free()


## 供玩家拾取链路调用：移除指定掉落物（本地路径换算 + 广播）
func remove_drop(drop: Node) -> void:
	if not is_instance_valid(drop):
		return
	if multiplayer.is_server():
		despawn_drop.rpc(get_path_to(drop))
	else:
		despawn_drop.rpc_id(1, get_path_to(drop))
