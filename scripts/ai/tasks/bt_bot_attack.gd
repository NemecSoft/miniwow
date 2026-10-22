@tool
extends BTAction
## M20-Bot：bot 攻击节点。
## 对黑板 target_node 周期调用 request_attack（服务器权威，自带 CD/距离/MP 校验）。
## 目标死亡或消失 → SUCCESS（交给上层重新 FindTarget）。
## 攻击节奏由 attack_interval 控制（与 basic_attack 的 1.0s CD 匹配，留余量）。

## 使用的技能 id
@export var skill_id: String = "basic_attack"
## 攻击间隔（秒）
@export var attack_interval: float = 1.1
## 超时（秒），防止追着一个打不到的目标无限 RUNNING
@export var timeout_sec: float = 30.0

var _elapsed: float = 0.0
var _since_attack: float = 0.0


func _enter() -> void:
	_elapsed = 0.0
	_since_attack = attack_interval
	printerr("BT_DIAG: %s 进入攻击分支 target=%s" % [
		agent.name if agent != null else "?",
		blackboard.get_var(&"target_node", null)])


func _tick(delta: float) -> Status:
	# M20c 死亡中断：见 bt_bot_move_to.gd _is_bot_dead 注释（selector 卡分支事故）
	if _is_bot_dead():
		return FAILURE
	# 同 MoveTo：get_var 对缺失变量 ERR_FAIL 刷屏，先 has_var 拦一道
	if not blackboard.has_var(&"target_node"):
		return FAILURE
	var target: Node3D = blackboard.get_var(&"target_node", null)
	if not is_instance_valid(target):
		return SUCCESS # 目标没了 = 这一个打完了

	var target_attrs: Node = target.get("attribute_set")
	if target_attrs == null or not target_attrs.is_alive():
		return SUCCESS

	# M24：目标走出技能射程 → FAILURE 交还上层重新 MoveTo 追击。
	# 原实现站桩空挥到 30s 超时（狼 patrol 走开就全程 miss）。
	var skill := SkillDatabase.get_skill(skill_id)
	var bot3d := agent as Node3D
	if skill != null and skill.range > 0.0 and bot3d != null:
		if bot3d.global_position.distance_to(target.global_position) > skill.range + 0.5:
			return FAILURE

	_elapsed += delta
	_since_attack += delta
	if _elapsed > timeout_sec:
		return FAILURE

	if _since_attack >= attack_interval:
		_since_attack = 0.0
		var bot: Node = agent
		if bot != null:
			# M21c：攻击前面向目标（模型转身，见 bt_bot_move_to._face_velocity）
			_face_target(bot, target)
			# get_path_to 生成相对 bot 的路径，request_attack 用 get_node_or_null 解析
			bot.request_attack(str(bot.get_path_to(target)), skill_id)
	return RUNNING


## M21c：面向目标——复用 _body.apply_rotation 的模型转身链路（水平方向）
func _face_target(bot: Node, target: Node3D) -> void:
	if bot == null or not is_instance_valid(target):
		return
	var to_target: Vector3 = target.global_position - (bot as Node3D).global_position
	to_target.y = 0.0
	# M33：NaN 闸——任一端点位置非有限时 length() 比较恒 false、normalized() 必刷屏
	if not (is_finite(to_target.x) and is_finite(to_target.z)):
		return
	if to_target.length() < 0.1:
		return
	var body: Node = bot.get("_body")
	if body != null and body.has_method("apply_rotation"):
		body.apply_rotation(to_target.normalized())


func _generate_name() -> String:
	return "BotAttack(%s)" % skill_id


## M20c：bot 死亡检查（所有长任务 _tick 首行调用），详见 bt_bot_move_to.gd
func _is_bot_dead() -> bool:
	var bot: Node = agent
	if bot == null or not is_instance_valid(bot):
		return true
	var attr_set: Node = bot.get("attribute_set")
	return attr_set != null and not attr_set.is_alive()
