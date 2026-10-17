class_name QuestData
extends Resource

## MiniWoW 任务数据资源（.tres）。新增任务 = 在 resources/quests/ 丢一个 .tres，不改代码。
## M4 只做"击杀类"目标；HAVE_ITEM（收集类）预留未启用。

enum ObjectiveType { KILL_MONSTER, HAVE_ITEM }

@export var id: String = ""
@export var name: String = ""
@export var description: String = "" # 任务剧情文本（任务面板展示）
@export var objective_text: String = "" # 目标简述，如"击杀野狼"

@export_category("目标")
@export var objective_type: ObjectiveType = ObjectiveType.KILL_MONSTER
@export var target_monster_id: String = "" # KILL_MONSTER：对应 MonsterData.id
@export var target_item_id: String = "" # HAVE_ITEM：对应 Item id
@export var required_count: int = 1
@export var min_level: int = 1

@export_category("奖励")
@export var reward_exp: int = 0
@export var reward_gold: int = 0
@export var reward_item_id: String = "" # 可选，交付时入包
@export var reward_item_quantity: int = 1
@export var prerequisite_quest_id: String = "" # 前置任务（任务链），空 = 无前置


## 奖励预览文本（任务面板/交付播报用）
func get_reward_summary() -> String:
	var parts: Array[String] = []
	if reward_exp > 0:
		parts.append(tr("%d 经验") % reward_exp)
	if reward_gold > 0:
		parts.append(tr("%d 金币") % reward_gold)
	if not reward_item_id.is_empty():
		var item := ItemDatabase.get_item(reward_item_id)
		if item:
			parts.append("[%s]%s x%d" % [tr(item.get_rarity_name()), tr(item.name), reward_item_quantity])
		else:
			parts.append("%s x%d" % [reward_item_id, reward_item_quantity])
	return tr("、").join(parts)
