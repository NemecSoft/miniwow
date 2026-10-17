class_name ClassData
extends Resource

## 职业数据资源（.tres）。M5 三职业铁三角：战士/法师/牧师。
## 新增职业 = 丢一个 .tres 到 resources/classes/ 并在 ClassDatabase 注册，无需改代码。

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var base_max_hp: int = 120
@export var base_max_mp: int = 50
@export var base_atk: int = 12
@export var base_def: int = 3
@export var skill_ids: Array[String] = [] ## 该职业的 4 个技能（对应 HUD 技能栏 1~4 键）
