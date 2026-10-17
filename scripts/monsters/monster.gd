class_name Monster
extends CharacterBody3D

## MiniWoW 怪物（M2）。
## 服务器权威：AI、移动、伤害全部只在服务器执行；客户端通过 MultiplayerSynchronizer
## 同步位置，通过事件 RPC 同步血量/动画/仇恨状态。死亡后在 home_position 满血重生。
## 威胁（threat）机制：玩家造成/治疗累积仇恨，怪物优先攻击仇恨最高者，脱战回满血。

enum State { IDLE, PATROL, CHASE, ATTACK, DEAD }

@export var monster_id: String = ""
@export var home_position := Vector3.ZERO # 为零时取场景初始位置作为刷新点

const GRAVITY := 9.8
const TURN_LERP := 0.2
const ANIM_SYNC_INTERVAL := 0.25

const PALETTE_PATHS := {
	"red": "res://assets/characters/player/GodotRobotPaletteSwap/GodotRedPalette.png",
	"green": "res://assets/characters/player/GodotRobotPaletteSwap/GodotGreenPalette.png",
	"yellow": "res://assets/characters/player/GodotRobotPaletteSwap/GodotYellowPalette.png",
	"blue": "res://assets/characters/player/GodotRobotPaletteSwap/GodotPalette.png",
	"gray": "res://assets/characters/player/GodotRobotPaletteSwap/GodotGrayPalette.png",
	"brown": "res://assets/characters/player/GodotRobotPaletteSwap/GodotBrownPalette.png",
	"purple": "res://assets/characters/player/GodotRobotPaletteSwap/GodotPurplePalette.png",
	"bone": "res://assets/characters/player/GodotRobotPaletteSwap/GodotBonePalette.png",
}

const HAT_SCENES := {
	"fedora": "res://scenes/items/hats/fedora.tscn",
	"headphones": "res://scenes/items/hats/headphones.tscn",
	"pirate_hat": "res://scenes/items/hats/pirate_hat.tscn",
	"sheriff_hat": "res://scenes/items/hats/sheriff_hat.tscn",
	"sombrero": "res://scenes/items/hats/sombrero.tscn",
	"wizard_hat": "res://scenes/items/hats/wizard_hat.tscn",
}
const WEAPON_SCENES := {
	"sword": "res://scenes/items/weapons/sword.tscn",
	"sword_big": "res://scenes/items/weapons/sword_big.tscn",
	"axe": "res://scenes/items/weapons/axe.tscn",
}

var data: MonsterData = null
var state: Monster.State = Monster.State.IDLE
var threat: Dictionary = {} # peer_id -> 累计伤害（仅服务器）
var current_target_peer := 0

# ===== M18b-2：击退 + 硬直（roguelite KnockbackComponent / EnemyStun 机制移植）=====
# 击退：服务器侧速度脉冲，指数衰减（decay=8 与 roguelite 一致），叠加进 velocity
# 由 move_and_slide 消化，位置经 MultiplayerSynchronizer 自然广播到各客户端。
# 硬直：被击退后短暂定身（不追人不攻击），结束时回 Idle 重新索敌。
const KNOCKBACK_DECAY := 8.0
const KNOCKBACK_MAX := 20.0
const STUN_DURATION_MSEC := 450

var _knockback := Vector3.ZERO
var _stun_until_msec := 0

func is_stunned() -> bool:
	return Time.get_ticks_msec() < _stun_until_msec

func add_knockback(force: Vector3) -> void:
	_knockback = (_knockback + force).limit_length(KNOCKBACK_MAX)
	_stun_until_msec = Time.get_ticks_msec() + STUN_DURATION_MSEC
	# 硬直表现：打断当前攻击前摇，定身待机（怪物库无受击动画，用 Idle 定格）
	_attack_swing_timer = -1.0
	_broadcast_anim(&"Idle")

func _apply_knockback(delta: float) -> void:
	# 指数衰减（与 roguelite 相同公式：lerp 零，帧率无关）
	_knockback = _knockback.lerp(Vector3.ZERO, 1.0 - exp(-KNOCKBACK_DECAY * delta))
	if _knockback.length() < 0.5:
		_knockback = Vector3.ZERO
	velocity.x = _knockback.x
	velocity.z = _knockback.z

var attribute_set: AttributeSet
var _state_timer := 0.0
var _patrol_point := Vector3.ZERO
var _attack_swing_timer := -1.0
var _respawn_countdown := -1.0
var _aggro_broadcasted := false
var _anim_sync_timer := 0.0
var _current_anim := &""
var _last_attacker_peer := 0

@onready var body_model: Node3D = $GodotRobot3D
@onready var anim_player: AnimationPlayer = $GodotRobot3D/AnimationPlayer
## M18b-5：KayKit 视觉实例引用（仅 model_variant == "kaykit" 时非空，
## 用于区分怪物音效：KayKit 怪用 roguelite 受击闷响）
var _kaykit_visual: Node3D = null
@onready var name_label: Label3D = $NameLabel
## M18b-6：roguelite 头顶血条（怪物挂载点 y=2.6，红色）
@onready var _health_bar: RogueHealthBar = $HealthBar
@onready var selection_ring: MeshInstance3D = $SelectionRing


func _ready() -> void:
	data = MonsterDatabase.get_monster(monster_id)
	if data == null:
		push_error("Monster: 未找到怪物数据 '%s'" % monster_id)
		return
	if home_position == Vector3.ZERO:
		home_position = global_position
	attribute_set = $AttributeSet
	attribute_set.configure(data.max_hp, 0, data.atk, data.def)
	attribute_set.died.connect(_on_died)
	_apply_skin()
	_apply_equipment()
	_apply_body_variant() # M18b-4：kaykit 变体——换模型与动画播放器
	body_model.scale = Vector3.ONE * data.scale_factor
	selection_ring.scale = Vector3.ONE * data.scale_factor
	var title := tr(data.display_name) + (tr("（精英）") if data.is_elite else "")
	name_label.text = "%s Lv.%d" % [title, data.level]
	name_label.modulate = _name_color(false)
	add_to_group("monsters")
	_play_anim(&"Idle")
	_state_timer = randf_range(0.5, 2.0)


# ===== 外观 =====

## M18b-4：模型变体——data.model_variant == "kaykit" 时隐藏 GodotRobot 骨架，
## 实例化 roguelite 敌人视觉（GamedevTV 黑圆头小人 + 橙剑），动画播放器切换到
## KayKit 的 AnimationPlayer（库键名 = MiniWoW 怪物状态名，零映射）。
## 后续 _play_anim/_broadcast_anim/_sync_locomotion_anim 全部自动走新播放器。
const KAYKIT_VISUAL := preload("res://scenes/monsters/kaykit_enemy_visual.tscn")

func _apply_body_variant() -> void:
	if data == null or data.model_variant != "kaykit":
		return
	var armature := body_model.get_node_or_null("RobotArmature") as Node3D
	if armature:
		armature.visible = false
	var visual := KAYKIT_VISUAL.instantiate() as Node3D
	body_model.add_child(visual)
	_kaykit_visual = visual
	var kaykit_ap := visual.get_node_or_null("Enemy_Medium/AnimationPlayer") as AnimationPlayer
	if kaykit_ap:
		anim_player = kaykit_ap
	else:
		push_error("KaykitEnemyVisual: AnimationPlayer 未找到，%s 回退机器人动画" % monster_id)

func _apply_skin() -> void:
	var texture := load(PALETTE_PATHS.get(data.palette, PALETTE_PATHS["blue"])) as Texture2D
	if texture == null:
		return
	var skeleton := body_model.get_node_or_null("RobotArmature/Skeleton3D")
	if skeleton == null:
		return
	for mesh_name in ["Bottom", "Chest", "Face", "LimbsAndHead"]:
		var mesh := skeleton.get_node_or_null(mesh_name) as MeshInstance3D
		if mesh:
			var material := StandardMaterial3D.new()
			material.albedo_texture = texture
			mesh.set_surface_override_material(0, material)


func _apply_equipment() -> void:
	var skeleton := body_model.get_node_or_null("RobotArmature/Skeleton3D")
	if skeleton == null:
		return
	_spawn_equipment(skeleton.get_node_or_null("HeadAttach"), HAT_SCENES, data.hat_id)
	_spawn_equipment(skeleton.get_node_or_null("LeftHandAttach"), WEAPON_SCENES, data.weapon_id)


func _spawn_equipment(attach: Node, scenes: Dictionary, item_id: String) -> void:
	if attach == null or item_id.is_empty():
		return
	var scene_path: String = scenes.get(item_id, "")
	if scene_path.is_empty():
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	attach.add_child(packed.instantiate())


func _name_color(aggroed: bool) -> Color:
	if aggroed:
		return Color(1.0, 0.45, 0.2)
	if data.is_elite:
		return Color(1.0, 0.82, 0.25)
	return Color(0.9, 0.9, 0.9)


func set_selected(selected: bool) -> void:
	if selection_ring:
		selection_ring.visible = selected and attribute_set.is_alive()


# ===== 战斗入口（玩家 request_attack 通过 duck-typing 调用）=====

func apply_combat_damage(amount: int, source_peer_id: int, is_crit: bool) -> void:
	if not multiplayer.is_server() or not attribute_set.is_alive():
		return
	if source_peer_id > 0:
		threat[source_peer_id] = int(threat.get(source_peer_id, 0)) + amount
		_last_attacker_peer = source_peer_id
	var applied := attribute_set.apply_damage(amount)
	if applied <= 0:
		return
	sync_monster_hp.rpc(attribute_set.hp, attribute_set.max_hp, attribute_set.is_alive())
	sync_combat_damage.rpc(str(get_tree().get_root().get_path()) + "/" + str(get_tree().get_root().get_path_to(self)), applied, is_crit)


@rpc("authority", "call_local", "reliable")
func sync_monster_hp(hp: int, max_hp_value: int, alive: bool) -> void:
	attribute_set.max_hp = max_hp_value
	var was_alive := attribute_set.is_alive()
	attribute_set.set_hp_from_authority(hp)
	_update_alive_visual(alive)
	# M18b-6：roguelite 头顶血条（双层掉血残影），各端血量同步处驱动
	if _health_bar:
		_health_bar.set_health(hp, max_hp_value)
	# M11：受击/死亡音效（纯表现，各端独立触发）。
	# call_local 使服务器也执行，各端都在自己的世界里就近发声。
	# 死亡 = 活着 → 死；受击 = 活着 → 活着（复活/重置是死 → 活，不发声）
	if was_alive and not alive:
		SfxManager.play_3d(&"monster_die", global_position)
	elif was_alive and alive:
		# M18b-5：KayKit 怪（如掠夺者）用 roguelite 受击闷响；
		# 其余机器人怪保持原味（痛叫与血肉声二选一随机）
		if _kaykit_visual != null:
			SfxManager.play_3d(&"hit_light", global_position)
		else:
			SfxManager.play_3d(&"monster_pain" if randf() < 0.5 else &"hit_flesh", global_position)
		# M14：命中火花（纯表现，与音效同接收端触发）
		SfxManager.spawn_effect("res://scenes/vfx/hit_spark.tscn", global_position + Vector3.UP * 1.0)


@rpc("authority", "call_local", "reliable")
func sync_combat_damage(target_path: String, amount: int, is_crit: bool) -> void:
	var target := get_node_or_null(target_path) as Node3D
	if target == null:
		return
	var height := 1.7 * (data.scale_factor if data else 1.0)
	DamageNumber.spawn(_effects_root(), target.global_position + Vector3.UP * height, amount, is_crit)
	DamageNumber.shake(target)


func _effects_root() -> Node:
	return get_node_or_null("/root/Level/Environment/Effects")


func _on_died() -> void:
	if not multiplayer.is_server():
		return
	state = State.DEAD
	_set_aggro_broadcast(false)
	_broadcast_anim(&"Fall")
	_respawn_countdown = data.respawn_time
	threat.clear()
	current_target_peer = 0
	_reward_killer()


func _reward_killer() -> void:
	if _last_attacker_peer <= 0:
		return
	var killer := _get_player_nodes().get(_last_attacker_peer) as Character
	if killer == null or not killer.attribute_set.is_alive():
		return
	var gold := randi_range(data.gold_min, data.gold_max)
	killer.add_gold(gold)
	# M4：击杀经验 + 任务击杀进度（仅发给最后一下的玩家）
	if data.exp_reward > 0:
		killer.add_experience(data.exp_reward)
	killer.add_quest_kill_progress(data.id)
	# M8：按掉落表 roll 装备/材料，掉到地上变成世界掉落物（玩家按 E 拾取）
	var loot_names: Array[String] = []
	var world_drops := _get_world_drops()
	for entry in data.loot_table:
		if entry == null or entry.item_id.is_empty() or entry.quantity <= 0:
			continue
		if randf() > entry.chance:
			continue
		var item := ItemDatabase.get_item(entry.item_id)
		if item == null:
			push_warning("Monster: 掉落表引用了不存在的物品 '%s'" % entry.item_id)
			continue
		if world_drops:
			world_drops.spawn_drop(entry.item_id, entry.quantity, global_position)
		else:
			# 兜底：没有世界掉落容器时直入杀手背包（测试/异常场景）
			killer.request_add_item(entry.item_id, entry.quantity)
		loot_names.append("[%s]%s" % [tr(item.get_rarity_name()), tr(item.name)])
	var message := tr("击杀了 %s，获得 %d 金币") % [tr(data.display_name), gold]
	if not loot_names.is_empty():
		message += "，" + tr("地上掉了：") + tr("、").join(loot_names)
	message += "！"
	var level_scene := get_tree().current_scene
	if level_scene and level_scene.has_method("show_chat_message"):
		level_scene.show_chat_message.rpc(killer.nickname.text, message)


## M8：世界掉落物容器（level 场景 Environment/ItemContainer）
func _get_world_drops() -> WorldDrops:
	var container := get_node_or_null("/root/Level/Environment/ItemContainer")
	return container as WorldDrops


# ===== AI 状态机（仅服务器）=====

func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server() or data == null:
		return
	if not attribute_set.is_alive():
		_process_respawn(delta)
		return
	_apply_gravity(delta)
	# M18b-2：硬直期间锁 AI（不索敌不攻击），只吃击退位移；
	# 击退速度每帧衰减叠加，播完自然恢复原状态机。
	if is_stunned() or _knockback != Vector3.ZERO:
		_apply_knockback(delta)
		if is_stunned():
			move_and_slide()
			_sync_locomotion_anim(delta)
			return
	match state:
		State.IDLE:
			_process_idle(delta)
		State.PATROL:
			_process_patrol(delta)
		State.CHASE:
			_process_chase(delta)
		State.ATTACK:
			_process_attack(delta)
	move_and_slide()
	_sync_locomotion_anim(delta)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	velocity.y -= GRAVITY * delta


func _process_respawn(delta: float) -> void:
	_respawn_countdown -= delta
	if _respawn_countdown > 0.0:
		return
	_respawn_countdown = -1.0
	global_position = home_position
	velocity = Vector3.ZERO
	attribute_set.full_restore()
	sync_monster_hp.rpc(attribute_set.hp, attribute_set.max_hp, true)
	_broadcast_anim(&"Idle")
	state = State.IDLE
	_state_timer = 0.5


func _enter_idle() -> void:
	state = State.IDLE
	velocity.x = 0
	velocity.z = 0
	_state_timer = randf_range(1.0, 3.0)
	_set_aggro_broadcast(false)


func _process_idle(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	var target_id := _find_aggro_player()
	if target_id > 0:
		_enter_chase(target_id)
		return
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_patrol()


func _enter_patrol() -> void:
	state = State.PATROL
	var angle := randf() * TAU
	var radius := randf_range(2.0, data.leash_radius * 0.5)
	_patrol_point = home_position + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
	_state_timer = randf_range(4.0, 8.0)


func _process_patrol(delta: float) -> void:
	var target_id := _find_aggro_player()
	if target_id > 0:
		_enter_chase(target_id)
		return
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_idle()
		return
	_move_toward(_patrol_point, data.move_speed * 0.4)


func _enter_chase(target_id: int) -> void:
	state = State.CHASE
	current_target_peer = target_id
	_set_aggro_broadcast(true)


func _process_chase(delta: float) -> void:
	var target_node := _resolve_target()
	if target_node == null:
		_leash_reset()
		return
	var distance := global_position.distance_to(target_node.global_position)
	if distance > data.leash_radius:
		_leash_reset()
		return
	if distance <= data.attack_range:
		_enter_attack()
		return
	# 仇恨易手：新打者仇恨超过当前目标 110% 才转火
	var new_target := _find_aggro_player()
	if new_target > 0 and new_target != current_target_peer:
		if int(threat.get(new_target, 0)) > int(threat.get(current_target_peer, 0)) * 1.1:
			current_target_peer = new_target
			target_node = _resolve_target()
			if target_node == null:
				_leash_reset()
				return
	# M5：冰箭减速——追击速度乘以当前减速系数（被减速时追不上玩家）
	_move_toward(target_node.global_position, data.move_speed * attribute_set.current_speed_multiplier())


func _enter_attack() -> void:
	state = State.ATTACK
	_attack_swing_timer = data.attack_windup


func _process_attack(delta: float) -> void:
	var target_node := _resolve_target()
	if target_node == null:
		_leash_reset()
		return
	var distance := global_position.distance_to(target_node.global_position)
	if distance > data.attack_range * 1.3:
		_leash_reset()
		return
	velocity.x = 0
	velocity.z = 0
	_face_toward(target_node.global_position)
	_attack_swing_timer -= delta
	if _attack_swing_timer <= 0.0:
		_attack_swing_timer = data.attack_interval
		_deal_attack(target_node)


func _deal_attack(target_node: Node3D) -> void:
	var attrs := CombatMath.get_attribute_set(target_node)
	if attrs == null or not attrs.is_alive():
		return
	_broadcast_anim(&"Attack1")
	var is_crit := CombatMath.roll_crit()
	var damage := CombatMath.calculate_damage(data.atk, 1.0, attrs.def)
	if is_crit:
		damage = int(round(float(damage) * CombatMath.CRIT_MULTIPLIER))
	# M18b-2：盾墙格挡——步兵玩家按住右键（服务器权威 is_blocking）受伤 -70%
	var blocked := false
	if target_node is Character:
		var defender := target_node as Character
		if defender.is_blocking and defender.player_class == "infantry":
			blocked = true
			damage = maxi(1, int(ceil(float(damage) * 0.3)))
	if target_node is Character:
		(target_node as Character).apply_combat_damage(damage, 0, is_crit)


func _leash_reset() -> void:
	threat.clear()
	current_target_peer = 0
	if attribute_set.hp < attribute_set.max_hp:
		attribute_set.full_restore()
		sync_monster_hp.rpc(attribute_set.hp, attribute_set.max_hp, true)
	_enter_idle()


# ===== 目标与工具 =====

func _resolve_target() -> Node3D:
	if current_target_peer <= 0:
		return null
	var player_node := _get_player_nodes().get(current_target_peer) as Node3D
	if player_node == null or not _is_player_alive(player_node):
		return null
	return player_node


## 仇恨优先（累积伤害最高者），否则感应范围内最近者
func _find_aggro_player() -> int:
	var players := _get_player_nodes()
	var top_id := 0
	var top_threat := 0
	for peer_id in threat:
		var player_node: Node3D = players.get(peer_id)
		if player_node == null or not _is_player_alive(player_node):
			continue
		if int(threat[peer_id]) > top_threat:
			top_threat = int(threat[peer_id])
			top_id = peer_id
	if top_id > 0:
		return top_id
	var nearest_id := 0
	var nearest_distance := data.aggro_radius
	for peer_id in players:
		var player_node: Node3D = players[peer_id]
		if not _is_player_alive(player_node):
			continue
		var distance := global_position.distance_to(player_node.global_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest_id = peer_id
	return nearest_id


func _get_player_nodes() -> Dictionary:
	var result := {}
	var container := get_node_or_null("/root/Level/PlayersContainer")
	if container == null:
		return result
	for child in container.get_children():
		var peer_id := str(child.name).to_int()
		if peer_id > 0:
			result[peer_id] = child
	return result


func _is_player_alive(player_node: Node) -> bool:
	var attrs := CombatMath.get_attribute_set(player_node)
	return attrs != null and attrs.is_alive()


func _move_toward(target_position: Vector3, speed: float) -> void:
	var direction := target_position - global_position
	direction.y = 0
	if direction.length() < 0.15:
		velocity.x = 0
		velocity.z = 0
		return
	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	_face_toward(target_position)


func _face_toward(target_position: Vector3) -> void:
	var direction := target_position - global_position
	direction.y = 0
	if direction.length() < 0.01:
		return
	# 模型正面为 +Z：正号公式（负号公式 atan2(-dx,-dz) 是模板遗留 bug，会背对目标）
	var target_yaw := atan2(direction.x, direction.z)
	body_model.rotation.y = lerp_angle(body_model.rotation.y, target_yaw, TURN_LERP)


# ===== 动画同步 =====

func _play_anim(state: StringName, restart := false) -> void:
	if anim_player == null or not anim_player.has_animation(state):
		return
	if not restart and _current_anim == state and anim_player.is_playing():
		return
	_current_anim = state
	anim_player.play(state)


func _broadcast_anim(state: StringName) -> void:
	if not multiplayer.is_server():
		return
	_play_anim(state, true)
	sync_monster_anim.rpc(state)


@rpc("authority", "call_local", "reliable")
func sync_monster_anim(state: StringName) -> void:
	_play_anim(state, true)


func _sync_locomotion_anim(delta: float) -> void:
	_anim_sync_timer -= delta
	if _anim_sync_timer > 0.0:
		return
	_anim_sync_timer = ANIM_SYNC_INTERVAL
	if state == State.ATTACK:
		return # 攻击动画由 _deal_attack 驱动
	var desired := &"Idle" if velocity.length() <= 0.5 else &"Run"
	if desired != _current_anim:
		_broadcast_anim(desired)


@rpc("authority", "call_local", "reliable")
func sync_monster_aggro(aggroed: bool) -> void:
	if name_label:
		name_label.modulate = _name_color(aggroed)


func _set_aggro_broadcast(aggroed: bool) -> void:
	if aggroed == _aggro_broadcasted:
		return
	_aggro_broadcasted = aggroed
	sync_monster_aggro.rpc(aggroed)


# ===== 死亡/刷新视觉（各客户端本地表现）=====

func _update_alive_visual(alive: bool) -> void:
	if name_label:
		name_label.visible = alive
	# M18b-6：roguelite 头顶血条随存活显隐（死亡淡出，复活恢复）
	if _health_bar:
		if alive:
			_health_bar.visible = true
			_health_bar.sprite_3d.transparency = 0.0
		else:
			_health_bar.fade_out()
	if not alive:
		selection_ring.visible = false
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector3(1.0, 0.1, 1.0), 0.3)
	else:
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC)
