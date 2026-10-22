@tool
extends BTAction
## 探针任务：统计 tick 次数，达到预算后返回 SUCCESS。
## 同时验证 blackboard 与 agent 在任务内可访问。

## tick 多少次后算成功
@export var tick_budget: int = 3

var tick_count: int = 0


func _tick(_delta: float) -> Status:
	tick_count += 1
	# 验证 blackboard 读写（LimboAI 执行时会克隆任务实例，
	# 外部持有的原始实例字段不会更新，故计数经黑板回传）
	blackboard.set_var(&"tick_count", tick_count)
	blackboard.set_var(&"last_tick_time", Time.get_ticks_msec())
	var agent_ok: bool = agent != null
	print("[CounterTask] tick #%d agent_valid=%s" % [tick_count, agent_ok])
	if tick_count >= tick_budget:
		return SUCCESS
	return RUNNING
