class_name Item
extends Resource

enum ItemType { WEAPON, CONSUMABLE, TOOL, MISC, HAT, BACKPACK }

enum ItemRarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

enum ContextOptions {
	DROP,
	EQUIP,
	UNEQUIP,
	USE,
}

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var icon: Texture2D

@export var stackable: bool = true
@export var max_stack: int = 99

@export var item_type: ItemType = ItemType.MISC
@export var rarity: ItemRarity = ItemRarity.COMMON
@export var value: int = 0
@export var context_options: Array[Item.ContextOptions] = []

## M3 装备词条：穿在身上时叠加到 AttributeSet（武器加攻、防具加防）
@export var bonus_atk: int = 0
@export var bonus_def: int = 0
## M3 消耗品效果：双击使用时恢复的血量/蓝量
@export var heal_amount: int = 0
@export var restore_mp: int = 0

@export var scene_path: String = ""


## 品质对应的名字颜色（tooltip / 聊天播报 / 商店列表共用）
func get_rarity_color() -> Color:
	match rarity:
		ItemRarity.UNCOMMON:
			return Color(0.29, 0.87, 0.51) # 绿
		ItemRarity.RARE:
			return Color(0.38, 0.71, 0.98) # 蓝
		ItemRarity.EPIC:
			return Color(0.75, 0.52, 0.97) # 紫
		ItemRarity.LEGENDARY:
			return Color(0.98, 0.75, 0.14) # 橙
		_:
			return Color(0.83, 0.83, 0.83) # 白


## 品质对应的中文名（避免界面上出现英文术语）
func get_rarity_name() -> String:
	match rarity:
		ItemRarity.UNCOMMON:
			return "精良"
		ItemRarity.RARE:
			return "稀有"
		ItemRarity.EPIC:
			return "史诗"
		ItemRarity.LEGENDARY:
			return "传说"
		_:
			return "普通"


## 是否可装备（三个可见部位）
func is_equipment() -> bool:
	return item_type == ItemType.WEAPON or item_type == ItemType.HAT or item_type == ItemType.BACKPACK


## 是否为恢复类消耗品
func is_consumable() -> bool:
	return item_type == ItemType.CONSUMABLE and (heal_amount > 0 or restore_mp > 0)


## 商人收购价（物品价值的一半，至少 1 金币；买入价=价值本身，卖出打折）
func get_sell_price() -> int:
	return maxi(1, int(ceil(float(value) * 0.5)))
