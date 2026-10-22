extends Node

# 探针：LimboAI 端到端运行时验证
# 纯代码构建行为树 → BTPlayer 挂载 → 加入场景树 → 实际 tick 若干物理帧
# 验证：树能跑、任务被 tick、黑板读写、restart 可用

const CounterTask := preload("res://tools/probe_task_counter.gd")

var _counter: BTAction
var _player: BTPlayer


func _ready() -> void:
	var ok := true

	# 1. 纯代码建树：BTSequence [ CounterTask, BTWait ]
	var root := BTSequence.new()
	var counter: BTAction = CounterTask.new()
	counter.tick_budget = 3
	root.add_child(counter)
	root.add_child(BTWait.new())

	var bt := BehaviorTree.new()
	bt.root_task = root

	# 2. BTPlayer 挂树并加入场景树（update_mode 默认 PHYSICS 自动 tick）
	#    代码创建的节点 owner 为空，必须显式给 scene_root_hint / agent_node
	_player = BTPlayer.new()
	_player.behavior_tree = bt
	_player.set_scene_root_hint(self)
	_player.agent_node = NodePath("..")
	add_child(_player)
	_counter = counter

	# 3. 黑板读写
	var bb := _player.blackboard
	if bb == null:
		print("FAIL: BTPlayer.blackboard is null")
		get_tree().quit(1)
		return
	bb.set_var(&"probe_key", 12345)

	_run_assertions()


func _run_assertions() -> void:
	# 等待足够物理帧让树跑完（tick_budget=3 + BTWait 0.1s 默认 = 1 秒）
	await get_tree().create_timer(1.5).timeout

	var ok := true
	var bb := _player.blackboard

	# 任务确实被 tick 了（计数经黑板回传，规避任务克隆）
	var ticks: int = bb.get_var(&"tick_count", 0)
	if ticks < 3:
		print("FAIL: blackboard tick_count=%d (<3)" % ticks)
		ok = false
	else:
		print("PASS: counter ticked %d times" % ticks)

	# 黑板读写
	if not bb.has_var(&"probe_key") or bb.get_var(&"probe_key") != 12345:
		print("FAIL: blackboard set/get_var mismatch")
		ok = false
	else:
		print("PASS: blackboard set_var/get_var = %s" % bb.get_var(&"probe_key"))

	if not bb.has_var(&"last_tick_time"):
		print("FAIL: blackboard 'last_tick_time' missing (任务内写入失败)")
		ok = false
	else:
		print("PASS: blackboard task-internal write ok")

	# restart 可调用
	bb.set_var(&"tick_count", 0)
	_player.restart()
	await get_tree().create_timer(0.5).timeout
	ticks = bb.get_var(&"tick_count", 0)
	if ticks <= 0:
		print("FAIL: restart 后无新 tick")
		ok = false
	else:
		print("PASS: restart() 可用，新 tick 数=%d" % ticks)

	print("=== LimboAI 端到端结果: %s ===" % ["PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)
