extends Node

## 战斗数值计算工具（autoload）。
## 所有伤害/暴击判定只在服务器执行，客户端不自行计算战斗结果。

const CRIT_CHANCE := 0.05
const CRIT_MULTIPLIER := 1.5
const DEFENSE_FACTOR := 0.5
const DAMAGE_VARIANCE_MIN := 0.9
const DAMAGE_VARIANCE_MAX := 1.1
const MIN_DAMAGE := 1

## 伤害公式：攻击力 * 技能系数 - 目标防御 * 0.5，再乘 0.9~1.1 随机浮动，下限 1 点
func calculate_damage(atk: float, multiplier: float, target_def: float) -> int:
	var base := atk * multiplier - target_def * DEFENSE_FACTOR
	if base < float(MIN_DAMAGE):
		base = float(MIN_DAMAGE)
	var variance := randf_range(DAMAGE_VARIANCE_MIN, DAMAGE_VARIANCE_MAX)
	return maxi(MIN_DAMAGE, int(floor(base * variance)))


func roll_crit() -> bool:
	return randf() < CRIT_CHANCE


## 统一取节点的属性集合（玩家和木桩都把 AttributeSet 挂在同名子节点下）
static func get_attribute_set(node: Node) -> AttributeSet:
	if node == null:
		return null
	return node.get_node_or_null("AttributeSet") as AttributeSet


## 升级所需累计经验（M2 任务系统启用）
func exp_needed_for_level(level: int) -> int:
	if level <= 1:
		return 0
	match level:
		2:
			return 100
		3:
			return 300
		4:
			return 600
		5:
			return 1000
		_:
			return 1000 + (level - 5) * 800
