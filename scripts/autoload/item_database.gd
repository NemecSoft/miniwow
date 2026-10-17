extends Node

const FEDORA_ICON: Texture2D = preload("res://assets/items/hats/icons/fedora.png")
const HEADPHONES_ICON: Texture2D = preload("res://assets/items/hats/icons/headphones.png")
const PIRATE_HAT_ICON: Texture2D = preload("res://assets/items/hats/icons/pirate_hat.png")
const SHERIFF_HAT_ICON: Texture2D = preload("res://assets/items/hats/icons/sheriff_hat.png")
const SOMBRERO_ICON: Texture2D = preload("res://assets/items/hats/icons/sombrero.png")
const WIZARD_HAT_ICON: Texture2D = preload("res://assets/items/hats/icons/wizard_hat.png")
const BACKPACK_ICON: Texture2D = preload("res://assets/items/backpacks/icons/backpack.png")
const SWORD_ICON: Texture2D = preload("res://assets/items/weapons/icons/sword.png")
const SWORD_BIG_ICON: Texture2D = preload("res://assets/items/weapons/icons/sword_big.png")
const AXE_ICON: Texture2D = preload("res://assets/items/weapons/icons/axe.png")
const CHICKEN_LEG_ICON: Texture2D = preload("res://assets/items/misc/icons/chicken_leg.png")
const BONE_ICON: Texture2D = preload("res://assets/items/misc/icons/bone.png")
const CHALICE_ICON: Texture2D = preload("res://assets/items/misc/icons/chalice.png")

var items: Dictionary = {}


func _ready():
	_create_sample_items()


func get_item(item_id: String) -> Item:
	return items.get(item_id)


func get_all_items() -> Dictionary:
	return items


func _create_sample_items():
	# ===== 模板原有装备（补 M3 属性词条，保持普通品质可掉落；M6 中文化显示名）=====
	_create_item(
		"fedora",
		"礼帽",
		"经典的软毡礼帽。",
		Item.ItemType.HAT,
		"res://scenes/items/hats/fedora.tscn",
		FEDORA_ICON,
		true,
		25,
		0,
		1
	)
	_create_item(
		"headphones",
		"耳机",
		"舒适的头戴式耳机。",
		Item.ItemType.HAT,
		"res://scenes/items/hats/headphones.tscn",
		HEADPHONES_ICON,
		true,
		25,
		0,
		1
	)
	_create_item(
		"pirate_hat",
		"海盗帽",
		"饱经风霜的海盗帽。",
		Item.ItemType.HAT,
		"res://scenes/items/hats/pirate_hat.tscn",
		PIRATE_HAT_ICON,
		true,
		25,
		0,
		1
	)
	_create_item(
		"sheriff_hat",
		"警长帽",
		"缀着警长徽章的边疆帽。",
		Item.ItemType.HAT,
		"res://scenes/items/hats/sheriff_hat.tscn",
		SHERIFF_HAT_ICON,
		true,
		25,
		0,
		1
	)
	_create_item(
		"sombrero", "宽边帽", "宽大鲜艳的宽边帽。", Item.ItemType.HAT, "res://scenes/items/hats/sombrero.tscn", SOMBRERO_ICON, true, 25, 0, 1
	)
	_create_item(
		"wizard_hat",
		"巫师帽",
		"充满奥术风情的尖顶帽。",
		Item.ItemType.HAT,
		"res://scenes/items/hats/wizard_hat.tscn",
		WIZARD_HAT_ICON,
		true,
		60,
		0,
		2
	)
	_create_item(
		"backpack",
		"背包",
		"结实的背上背包。",
		Item.ItemType.BACKPACK,
		"res://scenes/items/backpacks/backpack.tscn",
		BACKPACK_ICON,
		true,
		60
	)
	_create_item(
		"sword",
		"短剑",
		"均衡的单手短剑。",
		Item.ItemType.WEAPON,
		"res://scenes/items/weapons/sword.tscn",
		SWORD_ICON,
		true,
		80,
		2,
		0
	)
	_create_item(
		"sword_big",
		"大剑",
		"巨大的双手大剑。",
		Item.ItemType.WEAPON,
		"res://scenes/items/weapons/sword_big.tscn",
		SWORD_BIG_ICON,
		true,
		120,
		5,
		0
	)
	_create_item(
		"axe",
		"小斧",
		"钢刃锋利的紧凑小斧。",
		Item.ItemType.WEAPON,
		"res://scenes/items/weapons/axe.tscn",
		AXE_ICON,
		true,
		95,
		3,
		0
	)

	# ===== M3 新增装备：白/绿/蓝三品质，3D 模型复用模板场景 =====
	# 武器
	_create_equipment("sword_iron", "铁剑", "村庄铁匠打造的制式长剑。", Item.ItemType.WEAPON, Item.ItemRarity.COMMON, 2, 0, 40, "res://scenes/items/weapons/sword.tscn", SWORD_ICON)
	_create_equipment("sword_green", "精铁剑", "剑身泛着绿光的精铁长剑。", Item.ItemType.WEAPON, Item.ItemRarity.UNCOMMON, 4, 0, 90, "res://scenes/items/weapons/sword.tscn", SWORD_ICON)
	_create_equipment("sword_blue", "亡灵利刃", "从亡灵将军骸骨旁夺得的蓝色战刃。", Item.ItemType.WEAPON, Item.ItemRarity.RARE, 7, 0, 220, "res://scenes/items/weapons/sword_big.tscn", SWORD_BIG_ICON)
	_create_equipment("axe_iron", "战斧", "沉重但劈砍有力的铁斧。", Item.ItemType.WEAPON, Item.ItemRarity.COMMON, 3, 0, 60, "res://scenes/items/weapons/axe.tscn", AXE_ICON)
	# 帽子（防具部位）
	_create_equipment("cap", "皮帽", "结实的皮制软帽。", Item.ItemType.HAT, Item.ItemRarity.COMMON, 0, 1, 15, "res://scenes/items/hats/fedora.tscn", FEDORA_ICON)
	_create_equipment("helm", "战盔", "带护颈的战盔，哨兵部队制式。", Item.ItemType.HAT, Item.ItemRarity.UNCOMMON, 0, 2, 50, "res://scenes/items/hats/sheriff_hat.tscn", SHERIFF_HAT_ICON)
	_create_equipment("circlet", "秘术环带", "缝着符文布条的环带，微光闪烁。", Item.ItemType.HAT, Item.ItemRarity.RARE, 0, 3, 120, "res://scenes/items/hats/wizard_hat.tscn", WIZARD_HAT_ICON)

	# ===== M3 消耗品：双击使用，回血/回蓝 =====
	_create_consumable("bread", "面包", "香喷喷的烤面包，恢复 30 点生命。", 30, 0, 5, "res://scenes/items/misc/chicken_leg.tscn", CHICKEN_LEG_ICON)
	_create_consumable("water", "清水", "清凉的泉水，恢复 20 点法力。", 0, 20, 5, "res://scenes/items/misc/chalice.tscn", CHALICE_ICON)
	# ===== M8 消耗品：鸡腿（怪物世界掉落专属，商人不出售）=====
	_create_consumable("chicken_leg", "烤鸡腿", "油光发亮的烤鸡腿，恢复 35 点生命。", 35, 0, 8, "res://scenes/items/misc/chicken_leg.tscn", CHICKEN_LEG_ICON)

	# ===== 杂项（模板原有，不可用；M6 中文化）=====
	_create_item(
		"bone",
		"骨头",
		"一根风干的旧骨头。",
		Item.ItemType.MISC,
		"res://scenes/items/misc/bone.tscn",
		BONE_ICON,
		false,
		2
	)
	_create_item(
		"chalice",
		"金杯",
		"华贵的金色酒杯。",
		Item.ItemType.MISC,
		"res://scenes/items/misc/chalice.tscn",
		CHALICE_ICON,
		false,
		35
	)


func _create_item(
	item_id: String,
	item_name: String,
	item_description: String,
	item_type: Item.ItemType,
	scene_path: String,
	item_icon: Texture2D,
	equipable: bool,
	item_value: int,
	bonus_atk: int = 0,
	bonus_def: int = 0
) -> void:
	var item := Item.new()
	item.id = item_id
	item.name = item_name
	item.description = item_description
	item.item_type = item_type
	item.rarity = Item.ItemRarity.COMMON
	item.stackable = not equipable
	item.max_stack = 99 if item.stackable else 1
	item.value = item_value
	item.icon = item_icon
	item.scene_path = scene_path
	item.bonus_atk = bonus_atk
	item.bonus_def = bonus_def
	if equipable:
		item.context_options.append(Item.ContextOptions.EQUIP)
	item.context_options.append(Item.ContextOptions.DROP)
	items[item.id] = item


## 带品质和词条的装备（M3）
func _create_equipment(
	item_id: String,
	item_name: String,
	item_description: String,
	item_type: Item.ItemType,
	rarity: Item.ItemRarity,
	bonus_atk: int,
	bonus_def: int,
	item_value: int,
	scene_path: String,
	item_icon: Texture2D
) -> void:
	var item := Item.new()
	item.id = item_id
	item.name = item_name
	item.description = item_description
	item.item_type = item_type
	item.rarity = rarity
	item.stackable = false
	item.max_stack = 1
	item.value = item_value
	item.icon = item_icon
	item.scene_path = scene_path
	item.bonus_atk = bonus_atk
	item.bonus_def = bonus_def
	item.context_options.append(Item.ContextOptions.EQUIP)
	item.context_options.append(Item.ContextOptions.DROP)
	items[item.id] = item


## 恢复类消耗品（M3）
func _create_consumable(
	item_id: String,
	item_name: String,
	item_description: String,
	heal_amount: int,
	restore_mp: int,
	item_value: int,
	scene_path: String,
	item_icon: Texture2D
) -> void:
	var item := Item.new()
	item.id = item_id
	item.name = item_name
	item.description = item_description
	item.item_type = Item.ItemType.CONSUMABLE
	item.rarity = Item.ItemRarity.COMMON
	item.stackable = true
	item.max_stack = 20
	item.value = item_value
	item.icon = item_icon
	item.scene_path = scene_path
	item.heal_amount = heal_amount
	item.restore_mp = restore_mp
	item.context_options.append(Item.ContextOptions.USE)
	item.context_options.append(Item.ContextOptions.DROP)
	items[item.id] = item
