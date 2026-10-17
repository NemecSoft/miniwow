class_name SkillData
extends Resource

## 技能数据资源（.tres）。M5 起支持完整效果组：
## 单体伤害 / 治疗 / 弹道 / 自身 AoE / 减速 / DOT / HOT / 攻击防御增益。
## 新增技能 = 丢一个 .tres 到 resources/skills/ 并在 SkillDatabase 注册。

enum TargetType { ENEMY, SELF, ALLY, AOE_SELF }

@export var id: String = ""
@export var skill_name: String = ""
@export var description: String = ""
@export var icon: Texture2D

@export var cooldown: float = 1.0
@export var mp_cost: int = 0
@export var damage_multiplier: float = 1.0
@export var range: float = 3.2
@export var animation: StringName = &"Attack1"

# ===== M5 效果组 =====
@export var target_type: TargetType = TargetType.ENEMY ## 目标类型：敌人/自己/友方/自身周围AoE
@export var aoe_radius: float = 0.0 ## AoE 半径（AOE_SELF 生效）

## 弹道（法师火球/冰箭）：is_projectile=true 时飞行到命中才结算
@export var is_projectile: bool = false
@export var projectile_speed: float = 18.0
@export var projectile_color: Color = Color(1.0, 0.55, 0.15)

## 治疗（ALLY/SELF：heal_percent 按目标最大生命比例，优先于 heal_amount）
@export var heal_amount: int = 0
@export var heal_percent: float = 0.0

## 减速（命中后目标移动速度系数与持续时间）
@export var slow_factor: float = 1.0
@export var slow_duration: float = 0.0

## 持续伤害（DOT）
@export var dot_amount: int = 0
@export var dot_ticks: int = 0
@export var dot_interval: float = 1.0

## 持续治疗（HOT）
@export var hot_amount: int = 0
@export var hot_ticks: int = 0
@export var hot_interval: float = 1.0

## 增益（SELF 技能给自己加临时攻防）
@export var buff_atk: int = 0
@export var buff_def: int = 0
@export var buff_duration: float = 0.0

## 斩杀条件：目标生命低于该比例才可释放（0 = 不限制）
@export var requires_target_hp_below: float = 0.0

## M18b-2：击退力度（米/秒，0 = 不击退）。命中时沿攻击者→目标方向
## 施加瞬时速度脉冲，怪物侧指数衰减（roguelite KnockbackComponent 机制移植）
@export var knockback_force: float = 0.0


## 是否有治疗效果（供 UI/服务器分支判断）
func has_heal_effect() -> bool:
	return heal_amount > 0 or heal_percent > 0.0 or hot_ticks > 0
