#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""M6 i18n：批量给 tscn 加 auto_translate_mode = 1，并把模板英文文本换成中文键。
每处替换都断言旧文本存在，失败即报错退出。
"""
import io, sys, os

ROOT = r"D:/AI/GodotProject/MiniWoW/MiniWoW/scenes"

# (文件, 根节点声明行前缀, [(old, new), ...])
JOBS = [
    ("ui/main_menu_ui.tscn", '[node name="MainMenuUI"', [
        ('text = "3D Multiplayer Template"', 'text = "MiniWoW · 迷你魔兽世界"'),
        ('text = "Nickname : "', 'text = "昵称："'),
        ('placeholder_text = "YourNick"', 'placeholder_text = "你的昵称"'),
        ('text = "Player Skin : "', 'text = "角色外观："'),
        ('text = "IP Address : "', 'text = "服务器 IP："'),
        ('text = "HOST"', 'text = "创建主机"'),
        ('text = "JOIN"', 'text = "加入游戏"'),
        ('text = "QUIT"', 'text = "退出游戏"'),
    ]),
    ("ui/pause_menu_ui.tscn", '[node name="PauseMenuUI"', [
        ('text = "PAUSED"', 'text = "已暂停"'),
        ('text = "RESUME"', 'text = "继续游戏"'),
        ('text = "MAIN MENU"', 'text = "返回主菜单"'),
        ('text = "QUIT"', 'text = "退出游戏"'),
    ]),
    ("ui/hud.tscn", '[node name="HUD"', []),
    ("ui/inventory_ui.tscn", '[node name="InventoryUI"', [
        ('text = "Equipment"', 'text = "装备栏"'),
        ('text = "Hat"', 'text = "帽子"'),
        ('text = "Weapon"', 'text = "武器"'),
        ('text = "Backpack"', 'text = "背包"'),
        ('text = "Inventory"', 'text = "物品栏"'),
        ('tooltip_text = "Close inventory"', 'tooltip_text = "关闭背包"'),
    ]),
    ("ui/shop_ui.tscn", '[node name="ShopUI"', []),
    ("ui/quest_ui.tscn", '[node name="QuestUI"', []),
    ("ui/class_select_ui.tscn", '[node name="ClassSelectUI"', []),
    ("ui/player_list_ui.tscn", '[node name="PlayerListUI"', [
        ('text = "ONLINE PLAYERS"', 'text = "在线玩家"'),
        ('text = "0 online"', 'text = "0 人在线"'),
    ]),
    ("ui/multiplayer_chat_ui.tscn", '[node name="MultiplayerChatUI"', [
        ('placeholder_text = "Say to all..."', 'placeholder_text = "对所有人说..."'),
    ]),
    ("npcs/merchant.tscn", '[node name="Merchant"', []),
    ("npcs/quest_giver.tscn", '[node name="QuestGiver"', []),
    ("npcs/class_trainer.tscn", '[node name="ClassTrainer"', []),
    ("environment/forest.tscn", '[node name="Forest"', []),
    ("level/level.tscn", '[node name="Level"', []),
]

failures = []
for rel, root_prefix, pairs in JOBS:
    path = os.path.join(ROOT, rel)
    with io.open(path, "r", encoding="utf-8") as f:
        text = f.read()
    # 1) 根节点后插入 auto_translate_mode = 1
    lines = text.split("\n")
    out = []
    inserted = False
    for line in lines:
        out.append(line)
        if not inserted and line.startswith(root_prefix):
            out.append("auto_translate_mode = 1")
            inserted = True
    if not inserted:
        failures.append("%s: 找不到根节点 %s" % (rel, root_prefix))
        continue
    text = "\n".join(out)
    # 2) 文本替换
    for old, new in pairs:
        if old not in text:
            failures.append("%s: 找不到待替换文本 %s" % (rel, old))
            continue
        if text.count(old) != 1:
            failures.append("%s: 文本出现多次 %s" % (rel, old))
            continue
        text = text.replace(old, new)
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("OK  %s" % rel)

if failures:
    print("\n".join(failures))
    sys.exit(1)
print("全部完成")
