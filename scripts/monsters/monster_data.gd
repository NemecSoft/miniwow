class_name MonsterData
extends Resource

## 怪物数据资源（.tres）。新增怪物 = 在 resources/monsters/ 丢一个 .tres，不改代码。

@export var id: String = ""
@export var display_name: String = ""
@export var level: int = 1

@export_category("属性")
@export var max_hp: int = 100
@export var atk: int = 8
@export var def: int = 1
@export var move_speed: float = 3.0

@export_category("战斗")
@export var attack_range: float = 2.0
@export var attack_interval: float = 1.6
@export var attack_windup: float = 0.35

@export_category("AI")
@export var aggro_radius: float = 10.0
@export var leash_radius: float = 18.0
@export var respawn_time: float = 12.0

@export_category("奖励")
@export var is_elite: bool = false
@export var gold_min: int = 0
@export var gold_max: int = 0
## M4：击杀经验（只发给最后一下的玩家，组队各自结算）
@export var exp_reward: int = 0
## M3 掉落表：死亡时逐条 roll chance，命中直接入杀手背包
@export var loot_table: Array[LootEntry] = []

@export_category("外观")
@export var palette: String = "red" # red/green/yellow/blue/gray/brown/purple/bone
@export var scale_factor: float = 1.0
## M18b-4：模型变体——robot=GodotRobot 骨架（默认）；kaykit=roguelite 敌人模型
## （GamedevTV 黑圆头小人 + 橙剑，见 scenes/monsters/kaykit_enemy_visual.tscn）
@export var model_variant: String = "robot"
@export var hat_id: String = "" # fedora/headphones/pirate_hat/sheriff_hat/sombrero/wizard_hat
@export var weapon_id: String = "" # sword/sword_big/axe
