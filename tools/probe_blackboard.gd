@tool
extends Node
## M20-Bot 探针：BTPlayer 黑板生命周期 + BlackboardPlan 机制验证。

var _results: Array[String] = []


func _ready() -> void:
	var r := _results
	r.append("== BTPlayer 黑板生命周期 ==")

	# 建一棵最小树
	var seq := BTSequence.new()
	var wait := BTWait.new()
	wait.duration = 0.2
	seq.add_child(wait)
	var tree := BehaviorTree.new()
	tree.root_task = seq

	# BTPlayer 代码创建
	var bp := BTPlayer.new()
	r.append("blackboard 未进树时是否有效: %s" % (bp.blackboard != null))
	bp.behavior_tree = tree
	bp.set_scene_root_hint(self)
	bp.agent_node = NodePath("..")
	add_child(bp)

	# 记录引用（用于检测是否被替换）
	var bb_before: Object = bp.blackboard
	r.append("add_child 后 blackboard: %s" % (bb_before != null))

	# 等几帧让树开始 tick
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var bb_after: Object = bp.blackboard
	r.append("3 帧后 blackboard: %s（与之前同一对象: %s）" % [
		bb_after != null, bb_after == bb_before])

	# set_var / get_var / has_var 行为
	bb_after.set_var(&"test_var", 42)
	r.append("set_var+get_var 有默认参数: %s" % bb_after.get_var(&"test_var", -1))
	r.append("has_var 存在变量: %s" % bb_after.has_var(&"test_var"))
	r.append("has_var 不存在变量: %s" % bb_after.has_var(&"missing_var"))
	var got_default: Variant = bb_after.get_var(&"missing_var", null)
	r.append("get_var 缺失变量+默认值: %s（不崩）" % (got_default == null))

	r.append("")
	r.append("== BlackboardPlan 机制 ==")
	r.append("ClassDB 有 BlackboardPlan: %s" % ClassDB.class_exists("BlackboardPlan"))
	r.append("BehaviorTree 有 blackboard_plan 属性: %s" % _has_prop(tree, "blackboard_plan"))
	r.append("BTPlayer 有 blackboard_plan 属性: %s" % _has_prop(bp, "blackboard_plan"))
	r.append("BlackboardPlan 有 bind_var 方法: %s" % ClassDB.class_has_method("BlackboardPlan", "bind_var", true))

	# 试用 BlackboardPlan
	var plan := BlackboardPlan.new()
	if ClassDB.class_has_method("BlackboardPlan", "bind_var", true):
		plan.bind_var(&"plan_test", 99)
		r.append("bind_var(&plan_test, 99) 调用成功")
		if plan.has_method("get_var_default"):
			r.append("get_var_default: %s" % plan.get_var_default(&"plan_test"))

	for line in r:
		print(line)

	# 全部结束，退出
	print("=== PROBE_BB_DONE ===")
	get_tree().quit(0)


func _has_prop(obj: Object, prop: String) -> bool:
	for p in obj.get_property_list():
		if p.name == prop:
			return true
	return false
