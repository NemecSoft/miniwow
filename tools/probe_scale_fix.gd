extends Node
## M25e 验证：受击抖动幂等性 + 死亡压扁/复活弹回 + 看门狗不误报
## 用法：headless 跑 tools/probe_scale_fix.tscn

const SHAKE_ROUNDS := 10

var _wolf: Node3D = null
var _elapsed := 0.0
var _phase := 0
var _shake_count := 0
var _max_scale := 1.0
var _final_scale := Vector3.ONE
var _log_lines: Array[String] = []

func _ready() -> void:
	var packed := load("res://scenes/monsters/monster.tscn") as PackedScene
	_wolf = packed.instantiate()
	_wolf.set("monster_id", "wolf")
	add_child(_wolf)
	printerr("SCALETEST: 阶段1 连续 %d 次受击抖动" % SHAKE_ROUNDS)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	var s := _wolf.scale
	var smax: float = maxf(maxf(s.x, s.y), s.z)
	if smax > _max_scale:
		_max_scale = smax
	if _phase == 0:
		# 每 0.03 秒抖一次（比 tween 周期 0.13s 快，模拟 bot 围殴连击）
		if _shake_count < SHAKE_ROUNDS:
			DamageNumber.shake(_wolf)
			_shake_count += 1
		elif _shake_count == SHAKE_ROUNDS:
			_shake_count += 1
			_log_lines.append("阶段1: 10 连击后 max_scale=%.4f（旧实现会指数叠到 >1.5）" % _max_scale)
		# 等 tween 全部结束（0.13s）+ 余量
		if _shake_count > SHAKE_ROUNDS and _elapsed > 1.0:
			_final_scale = _wolf.scale
			_log_lines.append("阶段1: 静止后 scale=%s（应≈1）" % str(_final_scale))
			_phase = 1
			_elapsed = 0.0
			# 阶段2：死亡压扁
			_wolf.call("_update_alive_visual", false)
			_wolf.set("state", 4) # Monster.State.DEAD
			printerr("SCALETEST: 阶段2 死亡压扁")
	elif _phase == 1:
		if _elapsed > 0.5:
			var dead_scale := _wolf.scale
			_log_lines.append("阶段2: 死亡压扁中 scale=%s（应≈(1,0.1,1)，看门狗此时应豁免）" % str(dead_scale))
			_phase = 2
			_elapsed = 0.0
			# 阶段3：复活弹回
			_wolf.call("_update_alive_visual", true)
			_wolf.set("state", 0)
			# 连续两次 alive 同步（旧 bug：并发 tween 叠加）
			_wolf.call("_update_alive_visual", true)
			printerr("SCALETEST: 阶段3 复活弹回（含重复同步）")
	elif _phase == 2:
		if _elapsed > 1.5:
			_final_scale = _wolf.scale
			_log_lines.append("阶段3: 复活弹回后 scale=%s（应≈1）" % str(_final_scale))
			_report()
			get_tree().quit(0)

func _report() -> void:
	var ok_max := _max_scale < 1.16
	var ok_final := _final_scale.is_equal_approx(Vector3.ONE)
	for line in _log_lines:
		printerr("SCALETEST: " + line)
	if ok_max and ok_final:
		printerr("SCALETEST_DONE: PASS (max=%.4f final≈1)" % _max_scale)
	else:
		printerr("SCALETEST_DONE: FAIL (max=%.4f final=%s)" % [_max_scale, str(_final_scale)])
