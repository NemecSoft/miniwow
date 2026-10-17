extends Node

## M9 自动化测试（独立测试场景运行，保证 autoload 单例可用）：
## 基础打击与空手武器——空手普攻改播 Pickup 加速版（2.5x，手向下快挥 = 劈打）、
## 武器栏为空时左手自动挂鸡腿外观（fallback）、ChickenLeg visible 全服同步。
## 运行方式：godot --headless --path . res://tools/test_m9.tscn

var _failures: Array[String] = []

const HAND_PATH := "GodotRobot3D/RobotArmature/Skeleton3D/LeftHandAttach"


func _ready() -> void:
	var level_scene := load("res://scenes/level/level.tscn") as PackedScene
	if level_scene == null:
		_fail("无法加载 level.tscn")
		_report()
		return
	var level := level_scene.instantiate()
	get_tree().root.call_deferred("add_child", level)
	await get_tree().process_frame
	var players_container := level.get_node_or_null("PlayersContainer") as Node3D
	if players_container == null:
		_fail("找不到 PlayersContainer")
		_report()
		return
	var player_scene := load("res://scenes/level/player.tscn") as PackedScene
	var player_instance := player_scene.instantiate() as CharacterBody3D
	player_instance.name = "1"
	players_container.add_child(player_instance, true)
	for i in range(30):
		await get_tree().process_frame
	var player := players_container.get_node_or_null("1") as CharacterBody3D
	if player == null:
		_fail("玩家未生成")
		_report()
		return

	await _test_visual_node(player)
	_test_syncer_config(player)
	await _test_unarmed_flag(player)
	await _test_strike_animation(player)
	await _test_strike_lock(player)
	await _test_chicken_fallback(player)
	_report()


# ===== 1. 外观节点与同步配置 =====

func _test_visual_node(player: CharacterBody3D) -> void:
	var chicken := player.get_node_or_null(HAND_PATH + "/ChickenLeg") as Node3D
	_check("LeftHandAttach 下存在 ChickenLeg 外观节点", chicken != null)
	if chicken:
		_check("ChickenLeg 默认隐藏", not chicken.visible)
		_check("ChickenLeg 挂在骨骼挂点（BoneAttachment3D）", \
			player.get_node_or_null(HAND_PATH) is BoneAttachment3D)
	# 外观场景应为纯 Node3D（无物理体，避免挂骨骼后乱跳）
	var visual_scene := load("res://scenes/items/misc/chicken_leg_visual.tscn") as PackedScene
	_check("鸡腿外观场景可加载", visual_scene != null)
	if visual_scene:
		var inst := visual_scene.instantiate() as Node3D
		_check("鸡腿外观为纯 Node3D（非刚体）", inst != null and not inst is RigidBody3D)
		if inst:
			inst.free()


func _test_syncer_config(player: CharacterBody3D) -> void:
	# SceneReplicationConfig 无公开遍历 API，直接读场景源文件断言（与 tscn 内容一致）
	var f := FileAccess.open("res://scenes/level/player.tscn", FileAccess.READ)
	_check("player.tscn 可读", f != null)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	_check("同步配置包含 ChickenLeg:visible（全服同步）",
		text.contains("LeftHandAttach/ChickenLeg:visible"))


# ===== 2. 空手判定 =====

func _test_unarmed_flag(player: CharacterBody3D) -> void:
	var inv = player.get("player_inventory")
	_check("服务器背包已生成", inv != null)
	if inv == null:
		return
	# 开局自动穿 sword_iron → 有武器
	var has_weapon_at_start: bool = not inv.equipped_weapon.item_id.is_empty()
	_check("开局已装备铁剑（有武器）", has_weapon_at_start)
	_check("开局非空手（_is_unarmed=false）", not player._is_unarmed())
	# 卸下武器 → 空手（备份装备对象，测完恢复——覆盖丢弃会让物品凭空消失）
	var saved_weapon = inv.equipped_weapon
	var unequipped: bool = inv.unequip_to_slot(Item.ItemType.WEAPON, -1)
	if not unequipped or not inv.equipped_weapon.item_id.is_empty():
		inv.equipped_weapon = InventorySlot.new()
	_check("卸下武器后为空手（_is_unarmed=true）", player._is_unarmed(),
		"weapon='%s'" % inv.equipped_weapon.item_id)
	inv.equipped_weapon = saved_weapon


# ===== 3. 打击动画映射 =====

func _test_strike_animation(player: CharacterBody3D) -> void:
	var body = player.get("body") if player.get("body") != null else player.get_node_or_null("GodotRobot3D")
	if body == null:
		_fail("找不到 Body（GodotRobot3D）")
		return
	var anim_player := body.animation_player as AnimationPlayer
	_check("动画播放器可用", anim_player != null)
	if anim_player == null:
		return
	# M16d：空手普攻（basic_attack=SwordSlash）→ 空手自动映射 Strike 直拳
	player._play_attack_animation(&"SwordSlash")
	await get_tree().process_frame
	_check("空手普攻播 Strike（M16 重定向）", body._current_state == &"Strike",
		"实际=%s" % body._current_state)
	_check("Strike 动画已注入机器人动画库", anim_player.has_animation(&"Strike"))
	_check("空手打击进入攻击锁（is_attacking）", player.get("is_attacking") == true)
	# 复位
	player._on_animation_finished(&"Strike")
	_check("Strike 播完复位 is_attacking", player.get("is_attacking") == false)
	# 换回武器 → 普攻（basic_attack 现指向 SwordSlash）播挥剑 @ 1.5x
	# M16d：Attack1 旋风斩归还给 w_whirlwind 等技能，普攻用重定向 SwordSlash
	var inv = player.get("player_inventory")
	inv.equip_from_slot(inv.get_slot_index_of("sword_iron"), Item.ItemType.WEAPON)
	player._play_attack_animation(&"SwordSlash")
	await get_tree().process_frame
	_check("有武器普攻播 SwordSlash（M16b 替换旋风斩）", body._current_state == &"SwordSlash",
		"实际=%s" % body._current_state)
	# M14：打击感保底——挥剑统一提速 1.5x
	_check("SwordSlash 播放速度 1.5x（M14 提速）", absf(anim_player.get_playing_speed() - 1.5) < 0.01,
		"实际=%.2f" % anim_player.get_playing_speed())
	player._on_animation_finished(&"SwordSlash")


# ===== 4. 攻击锁（防移动动画秒切） =====

func _test_strike_lock(player: CharacterBody3D) -> void:
	var inv = player.get("player_inventory")
	# 先卸下武器，确保走"空手打击 = Pickup@2.5x"路径（备份恢复，物品不丢）
	var saved_weapon = inv.equipped_weapon
	inv.equipped_weapon = InventorySlot.new()
	var body = player.get_node_or_null("GodotRobot3D")
	# M16d：空手打击走 Strike（普攻 SwordSlash 空手映射），移动动画请求应被攻击锁拦截
	player._play_attack_animation(&"SwordSlash")
	await get_tree().process_frame
	player._request_animation(&"Run")
	await get_tree().process_frame
	_check("打击期间移动动画被锁拦截", body._current_state == &"Strike",
		"实际=%s" % body._current_state)
	player._on_animation_finished(&"Strike")
	# 拾取型 Pickup（speed 1.0）不应触发攻击锁
	player._request_animation(&"Pickup")
	await get_tree().process_frame
	_check("拾取型 Pickup 不上攻击锁", player.get("is_attacking") == false)
	# 远程同步：headless 无 peer 时本地即 authority，sync_animation_state 会提前 return；
	# 临时把 authority 让给假想远端（peer 2），模拟"远程玩家收到打击广播"再恢复。
	player.set_multiplayer_authority(2)
	player.sync_animation_state(&"Pickup", 9999, 2.5)
	_check("远程打击型 Pickup 上攻击锁", player.get("is_attacking") == true)
	player._on_animation_finished(&"Pickup")
	player.set_multiplayer_authority(1)
	# 清场：恢复装备对象（铁剑）
	inv.equipped_weapon = saved_weapon


# ===== 5. 鸡腿 fallback 外观 =====

func _test_chicken_fallback(player: CharacterBody3D) -> void:
	var chicken := player.get_node_or_null(HAND_PATH + "/ChickenLeg") as Node3D
	if chicken == null:
		_fail("ChickenLeg 节点丢失，fallback 无法验证")
		return
	var inv = player.get("player_inventory")
	# 当前有武器（上一节重新装备了铁剑）→ 鸡腿隐藏
	player._set_equipment_visibility(inv.equipped_weapon.item_id, "cap", "")
	_check("有武器时鸡腿隐藏", not chicken.visible)
	# 武器栏为空 → 鸡腿显示
	player._set_equipment_visibility("", "cap", "")
	_check("武器栏为空时鸡腿显示（fallback）", chicken.visible)
	# 清场：恢复铁剑装备与对应外观
	inv.equip_from_slot(inv.get_slot_index_of("sword_iron"), Item.ItemType.WEAPON)
	player._set_equipment_visibility(inv.equipped_weapon.item_id, "cap", "")
	_check("恢复装备后鸡腿隐藏", not chicken.visible)


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS | %s" % name)
	else:
		var msg := "FAIL | %s%s" % [name, (" -> " + detail) if not detail.is_empty() else ""]
		print(msg)
		_failures.append(msg)


func _fail(name: String) -> void:
	print("FAIL | %s" % name)
	_failures.append("FAIL | " + name)


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("=== M9 测试全部通过 ===")
	else:
		print("=== M9 测试失败 %d 项 ===" % _failures.size())
		for f in _failures:
			print("  " + f)
	get_tree().quit(1 if not _failures.is_empty() else 0)
