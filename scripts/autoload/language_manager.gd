extends Node

## MiniWoW 多语言管理（默认中文）。
## 架构：Godot TranslationServer + 运行时注册的 Translation 资源（不依赖 CSV 导入管线）。
## 键 = 中文原文（默认语言下 tr() 直接回键，界面零改动）；en_US 提供英文翻译。
## 切换：LanguageManager.set_language() / toggle_language()，偏好持久化到 user://settings.cfg。
## 静态 UI 文本：各 UI 场景根节点挂 auto_translate_mode = 1， locale 变化时自动刷新。
## 动态文本：脚本里统一 tr("中文键") % 参数；资源显示名（物品/技能/任务/怪物/职业）
## 在 .tres 里保持中文键，显示点包 tr()。

signal language_changed(locale: String)

const DEFAULT_LOCALE := "zh_CN"
const SUPPORTED_LOCALES: Array[String] = ["zh_CN", "en_US"]
const LOCALE_DISPLAY_NAMES := {"zh_CN": "中文", "en_US": "English"}
const SETTINGS_PATH := "user://settings.cfg"

var current_locale := DEFAULT_LOCALE

## 英文翻译表：键 = 中文原文（与界面/资源数据严格一致）
const EN_MESSAGES := {
	# ===== 主菜单 =====
	"MiniWoW · 迷你魔兽世界": "MiniWoW",
	"昵称：": "Nickname: ",
	"你的昵称": "YourNick",
	"角色外观：": "Player Skin: ",
	"服务器 IP：": "IP Address: ",
	"创建主机": "Create Host",
	"加入游戏": "Join Game",
	"退出游戏": "Quit Game",
	"蓝色": "Blue",
	"黄色": "Yellow",
	"绿色": "Green",
	"红色": "Red",
	# ===== 暂停菜单 / 语言 =====
	"已暂停": "Paused",
	"继续游戏": "Resume",
	"返回主菜单": "Main Menu",
	"语言：%s": "Language: %s",
	# ===== 玩家列表 =====
	"在线玩家": "Online Players",
	"%d 人在线": "%d online",
	"（你）": "(you)",
	# ===== 聊天 =====
	"对所有人说...": "Say to all...",
	"系统": "System",
	"任务": "Quest",
	"地上掉了：": "Dropped on the ground: ",
	"背包已满，无法拾取 %s": "Inventory full, cannot pick up %s",
	"拾取了 ": "Picked up ",
	# ===== 背包 / 物品 =====
	"装备栏": "Equipment",
	"帽子": "Hat",
	"武器": "Weapon",
	"背包": "Backpack",
	"物品栏": "Inventory",
	"关闭背包": "Close inventory",
	"丢弃": "Drop",
	"装备": "Equip",
	"卸下": "Unequip",
	"使用": "Use",
	"普通": "Common",
	"精良": "Uncommon",
	"稀有": "Rare",
	"史诗": "Epic",
	"传说": "Legendary",
	"消耗品": "Consumable",
	"工具": "Tool",
	"杂物": "Miscellaneous",
	"+%d 攻击力": "+%d Attack",
	"+%d 防御": "+%d Defense",
	"恢复 %d 点生命": "Restores %d HP",
	"恢复 %d 点法力": "Restores %d MP",
	"类型:": "Type: ",
	"售价:": "Price: ",
	"最大堆叠:": "Max Stack: ",
	"%d 金币": "%d gold",
	# ===== HUD =====
	"金币: %d": "Gold: %d",
	"攻 %d · 防 %d": "ATK %d · DEF %d",
	"经验 %d/%d": "XP %d/%d",
	"已满级": "Max Level",
	"（可交付）": "(Ready)",
	"冒险者": "Adventurer",
	"左键": "LMB",
	"普攻": "Attack",
	"技能2": "Skill 2",
	"技能3": "Skill 3",
	"准星对准目标按左键选中并攻击 | 按住左键连续攻击 | Q 选择最近目标 | 1/2/3 释放职业技能":
		"Aim at a target and left-click to attack | Hold left-click for auto-attack | Q target nearest | 1/2/3 cast class skills",
	"你死了": "You Died",
	"别灰心，回村满血再来": "Don't give up - return to the village and revive",
	"释放灵魂（回村复活）": "Release Spirit (revive at the village)",
	# ===== 商店 =====
	"商人 · 格鲁克": "Merchant - Gluk",
	"关闭": "Close",
	"出售商品（点击购买）": "Goods (click to buy)",
	"我的背包（点击出售，半价）": "Your Bag (click to sell at half price)",
	"背包里没有可出售的物品": "No sellable items in your bag",
	"按 E 与商人交易": "Press E to trade",
	# ===== 任务面板 =====
	"任务 · 卫兵队长 卡尔": "Quests - Captain Karl",
	"暂时没有任务": "No quests right now",
	"按 E 与卫兵队长交谈": "Press E to talk",
	"【%s】 —— 尚未开放": "[%s] - Not yet unlocked",
	"%s —— 已完成": "%s - Completed",
	"%s %d/%d（可交付）": "%s %d/%d (Ready)",
	"奖励：%s": "Reward: %s",
	"接取": "Accept",
	"交付": "Turn In",
	# ===== 职业选择 =====
	"选择你的职业": "Choose Your Class",
	"再想想": "Think Again",
	"按 E 交谈（选择职业）": "Press E to talk (choose class)",
	"生命 %d · 法力 %d\n攻击 %d · 防御 %d": "HP %d - MP %d\nATK %d - DEF %d",
	"成为%s": "Become %s",
	# ===== NPC / 场景标牌 =====
	"卫兵队长 · 卡尔": "Captain - Karl",
	"职业训练师 · 薇拉": "Class Trainer - Vera",
	"新月村 · 复活点": "Newmoon Village - Respawn Point",
	"森林 · 小心野狼！": "Forest - Beware of Wolves!",
	# ===== 战斗实体 =====
	"训练木桩": "Training Dummy",
	"怪物": "Monster",
	"（精英）": "(Elite)",
	# ===== 播报（player.gd / monster.gd）=====
	"%s 升到了 Lv.%d！": "%s reached Lv.%d!",
	"%s 选择了职业：%s！": "%s has chosen the class: %s!",
	"【%s】目标完成：%s %d/%d —— 回城找卫兵队长·卡尔交付！":
		"[%s] Objective complete: %s %d/%d - return to Captain Karl in the village!",
	"已接受任务【%s】：%s 0/%d": "Quest accepted [%s]: %s 0/%d",
	"完成任务【%s】！获得 %s": "Quest complete [%s]! Rewards: %s",
	"击杀了 %s，获得 %d 金币": "Defeated %s, gained %d gold",
	# ===== 任务奖励摘要 =====
	"%d 经验": "%d XP",
	"、": ", ",
	# ===== 职业 =====
	"战士": "Warrior",
	"法师": "Mage",
	"牧师": "Priest",
	"步兵": "Infantry",
	"钢铁之壁。生命与防御全职业之最，用盾击和反击风暴控场，铁壁与背水一战立于不败。":
		"Wall of steel. Highest HP and defense of all classes; control the field with shield bash and retaliation, and stand unbroken with Iron Wall and Last Stand.",
	"步兵的看家本领：用盾牌狠狠砸向目标，造成攻击力 130% 的伤害。冷却 6 秒，消耗 8 点法力。":
		"The infantry's bread and butter: smash the target with a shield for 130% attack damage. 6s cooldown, costs 8 mana.",
	"扎稳马步举盾迎敌，10 秒内防御提升 12 点。冷却 25 秒，消耗 15 点法力。":
		"Plant your feet and raise the shield: +12 defense for 10 seconds. 25s cooldown, costs 15 mana.",
	"被围攻时的答案：持盾旋转横扫周身敌人，造成攻击力 120% 的范围伤害。冷却 10 秒，消耗 12 点法力。":
		"The answer to being swarmed: spin with shield extended, dealing 120% attack damage around you. 10s cooldown, costs 12 mana.",
	"步兵的脊梁：立即恢复自身 35% 生命并获得 8 点防御，持续 12 秒。冷却 60 秒，消耗 20 点法力。":
		"Backbone of the infantry: instantly restore 35% of your health and gain 8 defense for 12 seconds. 60s cooldown, costs 20 mana.",
	"盾击": "Shield Bash",
	"反击风暴": "Retaliation Storm",
	"铁壁": "Iron Wall",
	"背水一战": "Last Stand",
	"坚实的前排。生命与防御最高，贴近敌人用重击和斩杀开路，旋风扫清围攻。":
		"Stalwart frontliner. Highest HP and defense; carve a path with heavy strikes and executes, and clear the swarm with whirlwind.",
	"脆弱的炮台。法力充沛，火球与冰箭在 12 米外取敌首级，被近身就用魔爆术突围。":
		"Fragile artillery. Abundant mana; fireball and frostbolt strike from 12 meters away; Arcane Blast to break free when closed in.",
	"团队的后盾。惩击压制、快速治疗与恢复让队伍走得更高更远，神圣新星攻守兼备。":
		"The team's backbone. Smite to pressure, Flash Heal and Renew to carry the party further; Holy Nova covers both offense and healing.",
	# ===== 技能 =====
	"普通攻击": "Auto Attack",
	"手持武器的一次普通挥砍，命中即造成攻击力 100% 的物理伤害。":
		"A basic swing with your weapon, dealing 100% of attack power as physical damage.",
	"重击": "Heavy Strike",
	"蓄力猛击，造成攻击力 200% 的伤害。冷却 3 秒，消耗 10 点法力。":
		"A charged blow dealing 200% attack power. 3s cooldown, 10 mana.",
	"斩杀": "Execute",
	"处决技：目标生命低于 35% 时造成攻击力 320% 的伤害。冷却 8 秒，消耗 15 点法力。":
		"Finisher: deals 320% attack power when the target is below 35% HP. 8s cooldown, 15 mana.",
	"盾墙": "Shield Wall",
	"举盾防御，8 秒内防御提升 10 点。冷却 20 秒，消耗 12 点法力。":
		"Raise your shield: +10 defense for 8 seconds. 20s cooldown, 12 mana.",
	"旋风斩": "Whirlwind",
	"挥舞武器卷起旋风，对身边 4.5 米内所有敌人造成攻击力 150% 的伤害。冷却 6 秒，消耗 15 点法力。":
		"Spin your weapon in a whirlwind, dealing 150% attack power to all enemies within 4.5m. 6s cooldown, 15 mana.",
	"火球术": "Fireball",
	"召唤火球飞向敌人（12 米），造成攻击力 135% 的伤害。冷却 2.5 秒，消耗 10 点法力。":
		"Hurl a fireball at the enemy (12m), dealing 135% attack power. 2.5s cooldown, 10 mana.",
	"冰箭": "Frostbolt",
	"发射冰箭（14 米），造成攻击力 100% 的伤害，并使目标移速降低 55%，持续 4 秒。冷却 5 秒，消耗 12 点法力。":
		"Fire a frostbolt (14m) dealing 100% attack power and slowing the target by 55% for 4s. 5s cooldown, 12 mana.",
	"魔爆术": "Arcane Blast",
	"奥术能量以自身为中心爆发，对 4 米内所有敌人造成攻击力 125% 的伤害。冷却 8 秒，消耗 16 点法力。":
		"Arcane energy erupts around you, dealing 125% attack power to all enemies within 4m. 8s cooldown, 16 mana.",
	"奥术强化": "Arcane Power",
	"灌注奥术之力，10 秒内攻击力提升 8 点。冷却 30 秒，消耗 20 点法力。":
		"Channel arcane power: +8 attack for 10 seconds. 30s cooldown, 20 mana.",
	"惩击": "Smite",
	"呼唤圣光击中敌人（10 米），造成攻击力 115% 的伤害。冷却 2 秒，消耗 8 点法力。":
		"Call down holy light on the enemy (10m), dealing 115% attack power. 2s cooldown, 8 mana.",
	"快速治疗": "Flash Heal",
	"圣光闪过，立即恢复目标 30% 最大生命（对准队友释放则治疗队友，否则治疗自己）。冷却 6 秒，消耗 18 点法力。":
		"Holy light flashes: instantly restore 30% of max HP (an ally target heals that ally, otherwise yourself). 6s cooldown, 18 mana.",
	"恢复": "Renew",
	"在目标身上种下持续 5 秒的治疗，每秒恢复 4% 最大生命（对准队友释放则祝福队友，否则祝福自己）。冷却 10 秒，消耗 16 点法力。":
		"Seed a 5-second heal on the target, restoring 4% max HP per second (an ally target blesses that ally, otherwise yourself). 10s cooldown, 16 mana.",
	"神圣新星": "Holy Nova",
	"圣光爆发：对身边 5 米内所有敌人造成攻击力 110% 的伤害，同时治疗所有队友 12% 最大生命。冷却 12 秒，消耗 22 点法力。":
		"A burst of holy light: 110% attack power to all enemies within 5m, and heals all allies for 12% max HP. 12s cooldown, 22 mana.",
	# ===== 怪物 =====
	"野狼": "Wolf",
	"掠夺者": "Raider",
	"野猪": "Boar",
	"狼人": "Worgen",
	"毒蜘蛛": "Venom Spider",
	"亡灵法师": "Lich",
	"石元素": "Stone Golem",
	# ===== 任务 =====
	"林缘试炼": "Trial at the Forest Edge",
	"卫兵队长卡尔：村子东边的林缘最近游荡着一群野狼，夜里犬吠个不停。去收拾 3 只，让村民们睡个安稳觉。":
		"Captain Karl: A pack of wolves has been prowling the forest edge east of the village, barking all night. Take down 3 of them so the villagers can sleep.",
	"野猪之患": "Boar Menace",
	"卫兵队长卡尔：野猪拱翻了村东的菜地。猎人们都在山里，这事就交给你了——4 只野猪，动静小点。":
		"Captain Karl: Boars have ravaged the vegetable fields east of the village. The hunters are all in the mountains, so this falls to you - 4 boars, and keep it quiet.",
	"狼人的威胁": "Worgen Threat",
	"卫兵队长卡尔：林地深处有狼人出没，已经有两个伐木工被咬伤。它们比野兽难缠，带上伤药——不，带上武器。3 只狼人。":
		"Captain Karl: Worgen stalk the deep woods; two lumberjacks have already been bitten. They are tougher than beasts - bring medicine... no, bring a weapon. 3 worgen.",
	"清除毒蛛": "Clear the Venom Spider",
	"卫兵队长卡尔：林地中央盘着一只毒蜘蛛精英，蛛网封住了猎人的小路。杀了它，林地才能通行。当心它的毒。":
		"Captain Karl: A venom spider elite lurks at the heart of the woods, its webs blocking the hunters' path. Kill it so the woods are passable. Beware its venom.",
	"亡灵的侵扰": "Undead Disturbance",
	"卫兵队长卡尔：森林深处飘起了骨白色的光——亡灵法师在拿尸骨练邪术。趁它们还没成气候，烧掉 4 个。":
		"Captain Karl: Bone-white lights drift in the deep forest - liches are practicing dark arts on corpses. Burn 4 of them before they grow powerful.",
	"石元素的心核": "Heart of the Golem",
	"卫兵队长卡尔：最深处的石元素醒了，大地在震。击碎 2 个石元素，拿到它们的心核——这是你出师前最后的试炼。这顶秘术环带，办完这事就是你的了。":
		"Captain Karl: The stone golems of the deepest wood have awakened, and the earth shakes. Shatter 2 of them and take their cores - this is your final trial before graduation. That arcanist circlet will be yours once it is done.",
	"击杀野狼": "Slay Wolves",
	"击杀野猪": "Slay Boars",
	"击杀狼人": "Slay Worgen",
	"击杀毒蜘蛛（精英）": "Slay the Venom Spider (Elite)",
	"击杀亡灵法师": "Slay Liches",
	"击杀石元素": "Shatter Stone Golems",
	# ===== 模板原有物品（中文化）=====
	"礼帽": "Fedora",
	"经典的软毡礼帽。": "A timeless felt fedora.",
	"耳机": "Headphones",
	"舒适的头戴式耳机。": "Comfortable over-ear headphones.",
	"海盗帽": "Pirate Hat",
	"饱经风霜的海盗帽。": "A weathered hat for a daring pirate.",
	"警长帽": "Sheriff Hat",
	"缀着警长徽章的边疆帽。": "A frontier hat with a sheriff badge.",
	"宽边帽": "Sombrero",
	"宽大鲜艳的宽边帽。": "A broad and colorful sombrero.",
	"巫师帽": "Wizard Hat",
	"充满奥术风情的尖顶帽。": "A pointed hat filled with arcane style.",
	"结实的背上背包。": "A sturdy backpack worn on the back.",
	"短剑": "Sword",
	"均衡的单手短剑。": "A balanced hand sword.",
	"大剑": "Big Sword",
	"巨大的双手大剑。": "A large two-handed sword.",
	"小斧": "Small Axe",
	"钢刃锋利的紧凑小斧。": "A compact axe with a sharp steel head.",
	# ===== M3 新增物品 =====
	"铁剑": "Iron Sword",
	"村庄铁匠打造的制式长剑。": "A standard long sword forged by the village blacksmith.",
	"精铁剑": "Refined Iron Sword",
	"剑身泛着绿光的精铁长剑。": "A refined iron long sword glowing faintly green.",
	"亡灵利刃": "Deathblade",
	"从亡灵将军骸骨旁夺得的蓝色战刃。": "A blue war blade taken from beside a death knight's bones.",
	"战斧": "War Axe",
	"沉重但劈砍有力的铁斧。": "A heavy iron axe that chops with force.",
	"皮帽": "Leather Cap",
	"结实的皮制软帽。": "A sturdy leather cap.",
	"战盔": "War Helm",
	"带护颈的战盔，哨兵部队制式。": "A war helm with neck guard, standard issue of the sentinels.",
	"秘术环带": "Arcanist Circlet",
	"缝着符文布条的环带，微光闪烁。": "A circlet sewn with rune cloth, faintly shimmering.",
	"面包": "Bread",
	"香喷喷的烤面包，恢复 30 点生命。": "A freshly baked loaf, restores 30 HP.",
	"烤鸡腿": "Roasted Chicken Leg",
	"油光发亮的烤鸡腿，恢复 35 点生命。": "A glistening roasted chicken leg, restores 35 HP.",
	"清水": "Spring Water",
	"清凉的泉水，恢复 20 点法力。": "Cool spring water, restores 20 MP.",
	"骨头": "Bone",
	"一根风干的旧骨头。": "A weathered bone.",
	"金杯": "Chalice",
	"华贵的金色酒杯。": "A decorative golden chalice.",
}


func _ready() -> void:
	_register_translations()
	current_locale = _load_saved_locale()
	if not (current_locale in SUPPORTED_LOCALES):
		current_locale = DEFAULT_LOCALE
	TranslationServer.set_locale(current_locale)


## 运行时注册翻译（无 CSV 导入依赖，启动即生效）。
## 注意：必须同时注册 zh_CN 恒等翻译——否则 Godot 在 locale 无精确匹配时会
## 回退到任意已注册翻译（实测 zh_CN 下会错误显示英文）。
func _register_translations() -> void:
	var zh := Translation.new()
	zh.locale = "zh_CN"
	for key in EN_MESSAGES:
		zh.add_message(key, key)
	TranslationServer.add_translation(zh)

	var en := Translation.new()
	en.locale = "en_US"
	for key in EN_MESSAGES:
		en.add_message(key, str(EN_MESSAGES[key]))
	TranslationServer.add_translation(en)


func set_language(locale: String) -> void:
	if not (locale in SUPPORTED_LOCALES):
		push_warning("LanguageManager: 不支持的语言 '%s'" % locale)
		return
	if locale == current_locale and TranslationServer.get_locale() == locale:
		return
	current_locale = locale
	TranslationServer.set_locale(locale)
	_save_locale(locale)
	language_changed.emit(locale)


## 中文 <-> 英文 互切（当前仅两种语言时的快捷入口）
func toggle_language() -> void:
	set_language("en_US" if current_locale == "zh_CN" else "zh_CN")


## 语言切换按钮的显示文本（如 "语言：中文" / "Language: English"）
func language_button_text() -> String:
	var name: String = LOCALE_DISPLAY_NAMES.get(current_locale, current_locale)
	return tr("语言：%s") % [name]


func _load_saved_locale() -> String:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error != OK:
		return DEFAULT_LOCALE
	return str(config.get_value("language", "locale", DEFAULT_LOCALE))


func _save_locale(locale: String) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH) # 保留其他潜在配置段
	config.set_value("language", "locale", locale)
	config.save(SETTINGS_PATH)
