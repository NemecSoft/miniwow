extends Node

## M7 自动化测试（独立测试场景运行，保证 autoload 单例可用）：
## 攻击方向修复 + 攻击动画区分 + 动画锁。
## 1. 怪物/玩家转向公式正号化（模型正面 +Z，负号公式是模板遗留 bug）
## 2. 普攻 Attack1 / 重击 Kick 动画配置与播放链路
## 3. 动画锁：攻击动画不被 Idle/Run 秒切；Jump 可打断；播放完毕复位
## 4. 怪物攻击动画不被 0.25s 同步定时器切断
## 运行方式：godot --headless --path . res://tools/test_m7.tscn

var _failures: Array[String] = []


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
	# headless 下模板 start_host 跳过本地(peer 1)玩家，手动补上
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

	await _test_facing()
	await _test_player_facing(player)
	await _test_anim_config()
	await _test_anim_lock(player)
	await _test_monster_attack_anim(player)
	_report()


# ===== 1b. 玩家转向：世界空间换算（父节点带 π 旋转的叠加陷阱） =====

func _test_player_facing(player: CharacterBody3D) -> void:
	var body := player.get_node_or_null("GodotRobot3D") as Node3D
	if body == null:
		_fail("玩家找不到 GodotRobot3D")
		return
	# 前进（向 -Z 跑）：全局 +Z 轴应指向 (0,0,-1)（面朝前进方向）
	for i in range(60):
		body.apply_rotation(Vector3(0, 0, -3))
		await get_tree().physics_frame
	var forward: Vector3 = body.global_transform.basis.z.normalized()
	_check("玩家前进时面朝移动方向（父节点 π 叠加陷阱已修复）",
		forward.dot(Vector3(0, 0, -1)) > 0.9, "实际 forward=%s" % str(forward))
	# 向右移动（向 +X 跑）：全局 +Z 轴应指向 (1,0,0)
	for i in range(60):
		body.apply_rotation(Vector3(3, 0, 0))
		await get_tree().physics_frame
	forward = body.global_transform.basis.z.normalized()
	_check("玩家右移时面朝 +X", forward.dot(Vector3(1, 0, 0)) > 0.9,
		"实际 forward=%s" % str(forward))
	# 向 +Z 跑（后退键）：全局 +Z 轴应指向 (0,0,1)
	for i in range(60):
		body.apply_rotation(Vector3(0, 0, 3))
		await get_tree().physics_frame
	forward = body.global_transform.basis.z.normalized()
	_check("玩家后退时面朝 +Z", forward.dot(Vector3(0, 0, 1)) > 0.9,
		"实际 forward=%s" % str(forward))


# ===== 1. 转向公式：模型正面 +Z =====

func _test_facing() -> void:
	var monster_scene := load("res://scenes/monsters/monster.tscn") as PackedScene
	var monster := monster_scene.instantiate()
	monster.monster_id = "wolf"
	get_tree().root.call_deferred("add_child", monster)
	await get_tree().process_frame
	await get_tree().process_frame
	var body := monster.get_node_or_null("GodotRobot3D") as Node3D
	if body == null:
		_fail("怪物找不到 body 模型")
		return

	# 面向 +Z 方向的目标：模型 +Z 轴应收敛到 (0,0,1)
	# 注意 basis.z 的模长受 scale_factor 影响，必须先归一化再比对方向
	var origin: Vector3 = monster.global_position
	for i in range(60):
		monster._face_toward(origin + Vector3(0, 0, 5))
		await get_tree().physics_frame
	var forward: Vector3 = body.global_transform.basis.z.normalized()
	_check("怪物面向 +Z 目标（修复背对 bug）", forward.dot(Vector3(0, 0, 1)) > 0.9,
		"实际 forward=%s" % str(forward))

	# 面向 +X 方向的目标：模型 +Z 轴应收敛到 (1,0,0)
	for i in range(60):
		monster._face_toward(origin + Vector3(5, 0, 0))
		await get_tree().physics_frame
	forward = body.global_transform.basis.z.normalized()
	_check("怪物面向 +X 目标", forward.dot(Vector3(1, 0, 0)) > 0.9,
		"实际 forward=%s" % str(forward))
	monster.free()


# ===== 2. 动画配置（数据驱动） =====

func _test_anim_config() -> void:
	var heavy := SkillDatabase.get_skill("heavy_strike")
	_check("重击配置 Kick 动画（与普攻区分）", heavy != null and heavy.animation == &"Kick",
		"实际=%s" % (str(heavy.animation) if heavy else "null"))
	var basic := SkillDatabase.get_skill("basic_attack")
	_check("普攻配置 Attack1 动画", basic != null and basic.animation == &"Attack1",
		"实际=%s" % (str(basic.animation) if basic else "null"))
	# 攻击类技能复用 Attack1，非攻击类用 Emote2
	for skill_id in ["m_fireball", "m_frostbolt", "w_whirlwind", "p_smite"]:
		var skill := SkillDatabase.get_skill(skill_id)
		_check("%s 复用 Attack1" % skill_id, skill != null and skill.animation == &"Attack1",
			"实际=%s" % (str(skill.animation) if skill else "null"))
	for skill_id in ["w_shield_wall", "p_flash_heal", "m_arcane_power"]:
		var skill := SkillDatabase.get_skill(skill_id)
		_check("%s 用 Emote2（无攻击动作）" % skill_id, skill != null and skill.animation == &"Emote2",
			"实际=%s" % (str(skill.animation) if skill else "null"))


# ===== 3. 玩家动画锁 =====

func _test_anim_lock(player: CharacterBody3D) -> void:
	var anim := player.get_node_or_null("GodotRobot3D/AnimationPlayer") as AnimationPlayer
	if anim == null:
		_fail("玩家找不到 AnimationPlayer")
		return
	# 普攻动画 + 锁
	player._request_animation(&"Attack1", true)
	_check("播放 Attack1 后 is_attacking=true", player.is_attacking)
	_check("当前动画 = Attack1", anim.current_animation == "Attack1",
		"实际=%s" % anim.current_animation)
	# 模拟下一帧移动动画请求：不允许覆盖
	player._request_animation(&"Idle")
	_check("攻击动画未被 Idle 秒切", anim.current_animation == "Attack1",
		"实际=%s" % anim.current_animation)
	player._request_animation(&"Run")
	_check("攻击动画未被 Run 秒切", anim.current_animation == "Attack1",
		"实际=%s" % anim.current_animation)
	# Kick 可播放（重击）
	player._request_animation(&"Kick", true)
	_check("Kick 通过白名单播放", anim.current_animation == "Kick",
		"实际=%s" % anim.current_animation)
	_check("Kick 播放期间同样上锁", player.is_attacking)
	# Jump 允许打断（WoW 手感：打人可以跳）
	player._request_animation(&"Jump", true)
	_check("Jump 可打断攻击动画", anim.current_animation == "Jump",
		"实际=%s" % anim.current_animation)
	_check("打断后 is_attacking=false", not player.is_attacking)
	# 播放完毕复位
	player._request_animation(&"Kick", true)
	player._on_animation_finished(&"Kick")
	_check("Kick 播完 is_attacking 复位", not player.is_attacking)
	player._request_animation(&"Idle")


# ===== 4. 怪物攻击动画不被同步定时器切断 =====

func _test_monster_attack_anim(player: CharacterBody3D) -> void:
	var monster_scene := load("res://scenes/monsters/monster.tscn") as PackedScene
	var monster := monster_scene.instantiate()
	monster.monster_id = "wolf"
	monster.current_target_peer = 1
	get_tree().root.call_deferred("add_child", monster)
	await get_tree().process_frame
	await get_tree().process_frame
	# 放到玩家身边：否则 42 米外会触发脱战（leash）回满血走回家，动画被切是预期行为
	monster.global_position = (player.global_position as Vector3) + Vector3(1.5, 0, 0)
	var anim := monster.get_node_or_null("GodotRobot3D/AnimationPlayer") as AnimationPlayer
	if anim == null:
		_fail("怪物找不到 AnimationPlayer")
		return
	# 进入攻击状态并发动一次攻击（_deal_attack 广播 Attack1）
	monster._enter_attack()
	monster._deal_attack(player)
	_check("怪物攻击播放 Attack1", anim.current_animation == "Attack1",
		"实际=%s" % anim.current_animation)
	# 跑 1 秒物理帧：ATTACK 状态下 0.25s 同步定时器不得切回 Idle/Run
	for i in range(60):
		await get_tree().physics_frame
	_check("怪物攻击动画 1 秒内不被定时器切断", anim.current_animation == "Attack1",
		"实际=%s" % anim.current_animation)
	monster.free()


# ===== 工具 =====

func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS | %s" % name)
	else:
		var msg := "FAIL | %s%s" % [name, (" -> " + detail) if not detail.is_empty() else ""]
		print(msg)
		_failures.append(msg)


func _fail(msg: String) -> void:
	print("FAIL | %s" % msg)
	_failures.append(msg)


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("=== M7 测试全部通过 ===")
	else:
		print("=== M7 测试失败 %d 项 ===" % _failures.size())
		for f in _failures:
			print("  " + f)
	get_tree().quit(1 if not _failures.is_empty() else 0)
