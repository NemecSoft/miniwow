#!/usr/bin/env python3
"""M8：给 6 个怪物 .tres 的 loot_table 追加鸡腿掉落条目（世界掉落物）"""
import re
import sys

BASE = "D:/AI/GodotProject/MiniWoW/MiniWoW/resources/monsters"

# 怪物 -> 鸡腿掉落概率（等级越高越慷慨，精英最高）
CHANCES = {
    "wolf.tres": 0.12,
    "boar.tres": 0.15,
    "worgen.tres": 0.18,
    "spider_elite.tres": 0.30,
    "lich.tres": 0.20,
    "golem.tres": 0.25,
}

for fname, chance in CHANCES.items():
    path = f"{BASE}/{fname}"
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()

    if "LootEntry_chicken" in text:
        print(f"SKIP | {fname} 已有鸡腿条目")
        continue

    # 1) loot_table 数组末尾追加 SubResource 引用
    m = re.search(r"loot_table = Array\[LootEntry\]\(\[(.*?)\]\)", text)
    if not m:
        print(f"FAIL | {fname} 找不到 loot_table 行")
        sys.exit(1)
    old_array = m.group(0)
    new_array = old_array[:-2] + f', SubResource("LootEntry_chicken")]'
    assert old_array in text
    text = text.replace(old_array, new_array)

    # 2) 在 [resource] 前插入 SubResource 定义
    block = (
        f'[sub_resource type="Resource" script_class="LootEntry" id="LootEntry_chicken"]\n'
        f'script = ExtResource("2_loot")\n'
        f'item_id = "chicken_leg"\n'
        f'chance = {chance}\n'
        f'quantity = 1\n\n'
    )
    assert "[resource]" in text
    text = text.replace("[resource]", block + "[resource]", 1)

    # 3) load_steps +1
    m2 = re.search(r"load_steps=(\d+)", text)
    assert m2, f"{fname} 无 load_steps"
    text = text.replace(m2.group(0), f"load_steps={int(m2.group(1)) + 1}", 1)

    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"OK   | {fname} 鸡腿 chance={chance}")

print("done")
