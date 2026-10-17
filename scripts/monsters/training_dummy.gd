class_name TrainingDummy
extends CharacterBody3D

## 训练木桩（M1 战斗靶子）。
## 服务器权威：只有服务器执行掉血与刷新计时；客户端通过 sync_dummy_hp 同步血量。
## 死亡后 scale.y 压扁表示"塌了"，respawn_time 秒后满血弹回（M2 怪物刷新机制的预演）。

@export var display_name := "训练木桩"
@export var level := 1
@export var max_hp := 1000
@export var respawn_time := 3.0

@onready var attribute_set: AttributeSet = $AttributeSet
@onready var name_label: Label3D = $NameLabel
@onready var selection_ring: MeshInstance3D = $SelectionRing

var _respawn_countdown := -1.0


func _ready() -> void:
	attribute_set.max_hp = max_hp
	attribute_set.max_mp = 0
	attribute_set.base_atk = 0
	attribute_set.base_def = 0
	attribute_set.hp = max_hp
	attribute_set.mp = 0
	attribute_set.died.connect(_on_died)
	if name_label:
		name_label.text = "%s Lv.%d" % [tr(display_name), level]
	add_to_group("monsters")


## 被玩家选为目标时显示脚下金环（本地表现，不走网络）
func set_selected(selected: bool) -> void:
	if selection_ring:
		selection_ring.visible = selected and attribute_set.is_alive()


## 服务器调用：由攻击者的 request_attack 结算后触发
func apply_combat_damage(amount: int, _source_peer_id: int, is_crit: bool) -> void:
	if not multiplayer.is_server():
		return
	if not attribute_set.is_alive():
		return
	var applied := attribute_set.apply_damage(amount)
	if applied <= 0:
		return
	sync_dummy_hp.rpc(attribute_set.hp, attribute_set.max_hp, attribute_set.is_alive())
	sync_combat_damage.rpc(str(get_tree().get_root().get_path()) + "/" + str(get_tree().get_root().get_path_to(self)), applied, is_crit)


@rpc("authority", "call_local", "reliable")
func sync_dummy_hp(hp: int, max_hp_value: int, alive: bool) -> void:
	attribute_set.max_hp = max_hp_value
	attribute_set.set_hp_from_authority(hp)
	_update_alive_visual(alive)
	# M13：木桩受击木头声（纯表现，各端独立触发；与怪物血肉声区分材质）
	SfxManager.play_3d(&"dummy_hit", global_position)


@rpc("authority", "call_local", "reliable")
func sync_combat_damage(target_path: String, amount: int, is_crit: bool) -> void:
	var target := get_node_or_null(target_path) as Node3D
	if target == null:
		return
	DamageNumber.spawn(_effects_root(), target.global_position + Vector3.UP * 1.7, amount, is_crit)
	DamageNumber.shake(target)


func _effects_root() -> Node:
	return get_node_or_null("/root/Level/Environment/Effects")


func _on_died() -> void:
	_update_alive_visual(false)
	if multiplayer.is_server():
		_respawn_countdown = respawn_time


func _update_alive_visual(alive: bool) -> void:
	if name_label:
		name_label.visible = alive
	if alive:
		scale = Vector3.ONE
	else:
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector3(1.0, 0.12, 1.0), 0.25)


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server() or _respawn_countdown < 0.0:
		return
	_respawn_countdown -= delta
	if _respawn_countdown > 0.0:
		return
	_respawn_countdown = -1.0
	attribute_set.full_restore()
	sync_dummy_hp.rpc(attribute_set.hp, attribute_set.max_hp, true)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC)
