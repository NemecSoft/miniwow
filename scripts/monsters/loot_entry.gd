class_name LootEntry
extends Resource

## 怪物掉落表条目（M3）：掉什么、掉多少概率、掉几个。
## 配置在 resources/monsters/*.tres 的 loot_table 数组里，怪物死亡时由服务器 roll。

@export var item_id: String = ""
@export var chance: float = 1.0 ## 0~1，1 = 必掉
@export var quantity: int = 1
