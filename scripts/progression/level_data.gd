extends Node

## MiniWoW 等级与经验数据（M4）：1~10 级经验表 + 每级成长。
## 以 autoload 单例（LevelData）方式注册；配平只改这一张表。
## EXP_TABLE[i] = 从 Lv(i+1) 升到 Lv(i+2) 所需经验。
## 设计目标：6 条任务链（约 30 只怪 + 任务奖励）把玩家送到 Lv7~8，剩余靠刷怪。

const MAX_LEVEL := 10

## 每级升级所需经验（索引 0 = Lv1→Lv2）
## 配平目标：6 条任务链全清 ≈ Lv7~8，剩余 2 级靠刷怪补足
const EXP_TABLE: Array[int] = [80, 160, 280, 420, 600, 820, 1100, 1450, 1900]

## 每升一级的属性成长（AttributeSet 在 Lv1 基础值上叠加）
const HP_PER_LEVEL := 25
const MP_PER_LEVEL := 10
const ATK_PER_LEVEL := 3
const DEF_PER_LEVEL := 1

## 怪物经验参考（用于配平，实际值在各 MonsterData.exp_reward）：
## 狼 12 / 野猪 15 / 狼人 30 / 精英毒蜘蛛 120 / 亡灵法师 60 / 石元素 90


## 当前等级升到下一级所需经验；满级返回 0
func exp_to_next(level: int) -> int:
	if level >= MAX_LEVEL:
		return 0
	return EXP_TABLE[clampi(level - 1, 0, EXP_TABLE.size() - 1)]


## 到达 level 级时的累计成长（相对 Lv1）
func get_growth(level: int) -> Dictionary:
	var steps := clampi(level - 1, 0, MAX_LEVEL - 1)
	return {
		"hp": steps * HP_PER_LEVEL,
		"mp": steps * MP_PER_LEVEL,
		"atk": steps * ATK_PER_LEVEL,
		"def": steps * DEF_PER_LEVEL,
	}
