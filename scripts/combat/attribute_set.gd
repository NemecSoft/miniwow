class_name AttributeSet
extends Node

## 属性集合：挂在玩家或怪物节点下的 AttributeSet 子节点上。
## 一切 HP/MP 的权威值只存在于服务器；客户端通过 RPC 广播同步（见 player.gd / training_dummy.gd）。
## M3 装备加成（bonus_atk/bonus_def）；M5 职业基础属性 + 临时增益 + 减速 + 持续治疗。

signal hp_changed(current: int, maximum: int)
signal mp_changed(current: int, maximum: int)
signal died()
signal stats_changed(atk: int, def_value: int) ## M5：攻防变化（装备/增益）时广播

@export var max_hp: int = 120
@export var max_mp: int = 50
@export var base_atk: int = 12
@export var base_def: int = 3

var hp: int
var mp: int
var atk: int
var def: int
var bonus_atk: int = 0 ## M3：装备提供的攻击加成（随穿脱变化）
var bonus_def: int = 0 ## M3：装备提供的防御加成
var _dead := false

# ===== M5：职业基础与等级成长（未选职业时用默认值，行为与 M4 一致）=====
var _class_base_hp := 120
var _class_base_mp := 50
var _class_base_atk := 12
var _class_base_def := 3
var _growth_hp := 0
var _growth_mp := 0
var _growth_atk := 0
var _growth_def := 0

# ===== M5：持续效果（仅服务器 tick；条目为 Dictionary，见各 add_* 方法）=====
var _effects: Array[Dictionary] = []
var _slow_factor := 1.0 ## 当前减速系数（1 = 正常）
var _slow_remaining := 0.0


func _ready() -> void:
	atk = base_atk
	def = base_def
	hp = max_hp
	mp = max_mp


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server() or _effects.is_empty():
		return
	var stats_dirty := false
	var i := _effects.size() - 1
	while i >= 0:
		var effect: Dictionary = _effects[i]
		effect["remaining"] = float(effect["remaining"]) - delta
		if String(effect["kind"]) == "dot":
			effect["tick_timer"] = float(effect["tick_timer"]) - delta
			while float(effect["tick_timer"]) <= 0.0 and int(effect["ticks_left"]) > 0:
				effect["ticks_left"] = int(effect["ticks_left"]) - 1
				effect["tick_timer"] = float(effect["tick_timer"]) + float(effect["interval"])
				apply_damage(int(effect["amount"])) # 服务器权威掉血（死亡信号自动链式同步）
		elif String(effect["kind"]) == "hot":
			effect["tick_timer"] = float(effect["tick_timer"]) - delta
			while float(effect["tick_timer"]) <= 0.0 and int(effect["ticks_left"]) > 0:
				effect["ticks_left"] = int(effect["ticks_left"]) - 1
				effect["tick_timer"] = float(effect["tick_timer"]) + float(effect["interval"])
				heal(int(effect["amount"]))
		if float(effect["remaining"]) <= 0.0 or int(effect.get("ticks_left", 1)) <= 0:
			_effects.remove_at(i)
			if String(effect["kind"]) == "buff":
				stats_dirty = true
		i -= 1
	if _slow_remaining > 0.0:
		_slow_remaining = maxf(0.0, _slow_remaining - delta)
		if _slow_remaining <= 0.0:
			_slow_factor = 1.0
	if stats_dirty:
		_recalc_stats()


## 供怪物在 _ready 时调用：按 MonsterData 一次性配置并满状态出生
## （怪物节点 _ready 晚于子节点 AttributeSet._ready，改 export 值已来不及，必须走这里）
func configure(new_max_hp: int, new_max_mp: int, new_atk: int, new_def: int) -> void:
	max_hp = new_max_hp
	max_mp = new_max_mp
	base_atk = new_atk
	base_def = new_def
	atk = new_atk
	def = new_def
	full_restore()


## M5：选择职业后调用（服务器与客户端各自本地设置，再叠加等级成长）
func set_class_base(new_hp: int, new_mp: int, new_atk: int, new_def: int) -> void:
	_class_base_hp = new_hp
	_class_base_mp = new_mp
	_class_base_atk = new_atk
	_class_base_def = new_def
	_recalc_base_stats()


## M4：升级成长。按 LevelData 提升基础属性并回满血蓝（升级奖励）。
## 服务器与客户端都会在收到 sync_experience 后各调一次，保持数值一致。
func apply_level_growth(level: int) -> void:
	var growth := LevelData.get_growth(level)
	_growth_hp = int(growth.hp)
	_growth_mp = int(growth.mp)
	_growth_atk = int(growth.atk)
	_growth_def = int(growth.def)
	_recalc_base_stats()
	full_restore()


## 职业基础 + 等级成长 → max/base 属性 → 重算攻防 → 回满
func _recalc_base_stats() -> void:
	max_hp = _class_base_hp + _growth_hp
	max_mp = _class_base_mp + _growth_mp
	base_atk = _class_base_atk + _growth_atk
	base_def = _class_base_def + _growth_def
	_recalc_stats()


func is_alive() -> bool:
	return not _dead


## M3：玩家穿/脱装备后调用，重算攻击防御（服务器与客户端各自本地计算）
func apply_equipment_bonus(new_bonus_atk: int, new_bonus_def: int) -> void:
	bonus_atk = new_bonus_atk
	bonus_def = new_bonus_def
	_recalc_stats()


## M5：攻防 = 基础 + 装备 + 临时增益；变化时广播（HUD 与伤害同源）
func _recalc_stats() -> void:
	var buff_atk_total := 0
	var buff_def_total := 0
	for effect in _effects:
		if String(effect["kind"]) != "buff":
			continue
		buff_atk_total += int(effect["atk"])
		buff_def_total += int(effect["def"])
	atk = base_atk + bonus_atk + buff_atk_total
	def = base_def + bonus_def + buff_def_total
	stats_changed.emit(atk, def)


# ===== M5：持续效果（服务器调用）=====

## 临时增益：持续时间内攻防提升（同类多次释放可叠加）
func apply_buff(new_bonus_atk: int, new_bonus_def: int, duration: float) -> void:
	if duration <= 0.0 or (new_bonus_atk == 0 and new_bonus_def == 0):
		return
	_effects.append({
		"kind": "buff",
		"atk": new_bonus_atk,
		"def": new_bonus_def,
		"remaining": duration,
	})
	_recalc_stats()


## 减速：取更强的一个（冰箭 55% 减速），到期自动恢复
func apply_slow(factor: float, duration: float) -> void:
	if duration <= 0.0 or factor >= 1.0:
		return
	if factor < _slow_factor or _slow_remaining <= 0.0:
		_slow_factor = factor
	_slow_remaining = maxf(_slow_remaining, duration)


## 怪物/玩家当前移动速度系数（1 = 不被减速）
func current_speed_multiplier() -> float:
	return _slow_factor if _slow_remaining > 0.0 else 1.0


## 持续伤害：每 interval 秒掉 amount 血，共 ticks 次
func add_dot(amount: int, ticks: int, interval: float, _source_peer: int = 0) -> void:
	if amount <= 0 or ticks <= 0:
		return
	_effects.append({
		"kind": "dot",
		"amount": amount,
		"ticks": ticks,
		"ticks_left": ticks,
		"interval": maxf(interval, 0.1),
		"tick_timer": maxf(interval, 0.1),
		"remaining": maxf(interval, 0.1) * float(ticks),
	})


## 持续治疗：每 interval 秒回 amount 血，共 ticks 次
func add_hot(amount: int, ticks: int, interval: float) -> void:
	if amount <= 0 or ticks <= 0:
		return
	_effects.append({
		"kind": "hot",
		"amount": amount,
		"ticks": ticks,
		"ticks_left": ticks,
		"interval": maxf(interval, 0.1),
		"tick_timer": maxf(interval, 0.1),
		"remaining": maxf(interval, 0.1) * float(ticks),
	})


## 清空所有持续效果（死亡/复活时调用）
func clear_effects() -> void:
	if _effects.is_empty() and _slow_remaining <= 0.0:
		return
	_effects.clear()
	_slow_factor = 1.0
	_slow_remaining = 0.0
	_recalc_stats()


# ===== 服务器调用：施加伤害，返回实际扣除的血量 =====
func apply_damage(amount: int) -> int:
	if _dead or amount <= 0:
		return 0
	var applied := mini(amount, hp)
	hp = maxi(0, hp - applied)
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		_dead = true
		clear_effects() # 死亡清掉所有 dot/hot/减速/增益
		died.emit()
	return applied


func heal(amount: int) -> int:
	if _dead or amount <= 0:
		return 0
	var applied := mini(amount, max_hp - hp)
	hp += applied
	hp_changed.emit(hp, max_hp)
	return applied


func spend_mp(amount: int) -> bool:
	if amount <= 0:
		return true
	if mp < amount:
		return false
	mp -= amount
	mp_changed.emit(mp, max_mp)
	return true


func restore_mp(amount: int) -> void:
	if amount <= 0 or _dead:
		return
	mp = mini(max_mp, mp + amount)
	mp_changed.emit(mp, max_mp)


func full_restore() -> void:
	_dead = false
	hp = max_hp
	mp = max_mp
	clear_effects()
	hp_changed.emit(hp, max_hp)
	mp_changed.emit(mp, max_mp)


## 客户端调用：用服务器广播的权威值覆盖本地值（不发重复死亡信号，除首次死亡）
func set_hp_from_authority(value: int) -> void:
	hp = clampi(value, 0, max_hp)
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		if not _dead:
			_dead = true
			died.emit()
	else:
		_dead = false


func set_mp_from_authority(value: int) -> void:
	mp = clampi(value, 0, max_mp)
	mp_changed.emit(mp, max_mp)
