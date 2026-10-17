extends Node

## M14+M15 自动化测试（独立测试场景运行，保证 autoload 可用）：
## M14：拾取服务器验证修复（Pickup 拾取型设时间戳/打击型不设）、开局默认战士、
##       技能失败提示限流、打击特效场景（hit_spark/swing_dust）
## M15：真脚步声三连、跳跃/落地粒子、Plush 伙伴（跟随/挥手/交互组）
## 运行方式：godot --headless --path . res://tools/test_m14.tscn

var _pass_count := 0
var _failures: Array[String] = []


func _ready() -> void:
	var level_scene := load("res://scenes/level/level.tscn") as PackedScene
	var level := level_scene.instantiate()
	get_tree().root.call_deferred("add_child", level)
	await get_tree().process_frame
	var players_container := level.get_node_or_null("PlayersContainer") as Node3D
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

	await _test_pickup_validation(player)
	_test_default_class(player)
	_test_skill_notify(player)
	_test_vfx_scenes()
	_test_footsteps()
	await _test_partner(player)
	_report()


# ===== 1. 拾取服务器验证（M14 核心 bug）=====

func _test_pickup_validation(player: CharacterBody3D) -> void:
	# 前置：玩家脚下放一个掉落物（服务器验证要求"面前有可拾取物"才授权）
	var world_drops := get_tree().root.get_node_or_null("Level/Environment/ItemContainer") as WorldDrops
	if world_drops:
		world_drops.spawn_drop("chicken_leg", 1, player.global_position + Vector3(1.0, 0.5, 0.0))
		# 等玩家落地 + 掉落物稳定
		for i in range(20):
			await get_tree().physics_frame
	# 拾取型 Pickup（1.0x）→ 时间戳必须被设置（M14 修复点：旧代码只认 Emote2）
	player.set("_server_pickup_animation_started_msec", -1)
	player.request_animation_state(&"Pickup", 1.0)
	await get_tree().process_frame
	var ts: int = player.get("_server_pickup_animation_started_msec")
	_check("拾取型 Pickup 设置服务器时间戳（E 键可捡）", ts >= 0, "实际 %d" % ts)

	# 打击型 Pickup（2.5x）→ 时间戳被清（不属于拾取）
	player.request_animation_state(&"Pickup", 2.5)
	await get_tree().process_frame
	_check("打击型 Pickup 不触发拾取授权", int(player.get("_server_pickup_animation_started_msec")) < 0)

	# 旧动画名 Emote2 不再触发拾取授权（M9 起拾取已改名）
	player.set("_server_pickup_animation_started_msec", -1)
	player.request_animation_state(&"Emote2", 1.0)
	await get_tree().process_frame
	_check("Emote2 不再触发拾取授权（M9 改名一致性）",
		int(player.get("_server_pickup_animation_started_msec")) < 0)


# ===== 2. 开局默认职业（M14）=====

func _test_default_class(player: CharacterBody3D) -> void:
	# _enter_combat_ready 已在玩家 _ready 阶段执行，headless 本地即服务器
	_check("开局默认战士（未选职业时）", player.player_class == "warrior",
		"实际 '%s'" % player.player_class)
	var class_data := ClassDatabase.get_class_data(player.player_class)
	_check("默认职业数据有效（4 个技能槽）",
		class_data != null and class_data.skill_ids.size() == 4)
	# 属性已按职业重配（战士血量应高于默认 100）
	_check("职业基础属性已应用", player.attribute_set.max_hp > 100,
		"max_hp=%d" % player.attribute_set.max_hp)


# ===== 3. 技能失败提示（M14）=====

func _test_skill_notify(player: CharacterBody3D) -> void:
	# 限流：同技能 800ms 内第二次提示不生效（无崩溃即可，行为为静默）
	player._notify_skill("test_skill", "第一次")
	player._notify_skill("test_skill", "第二次（应被限流）")
	_check("技能提示限流不崩溃", true)
	# _notify_local 本地提示不崩溃（headless 下 current_scene 无 show_chat_message 也不炸）
	player._notify_local("测试提示")
	_check("本地提示不崩溃", true)


# ===== 4. 特效场景（M14/M15）=====

func _test_vfx_scenes() -> void:
	for path in [
		"res://scenes/vfx/hit_spark.tscn",
		"res://scenes/vfx/swing_dust.tscn",
		"res://scenes/vfx/jump_particles.tscn",
		"res://scenes/vfx/land_particles.tscn",
	]:
		var scene := load(path) as PackedScene
		_check("特效场景可加载 %s" % path.get_file(), scene != null)
		if scene:
			var inst := scene.instantiate()
			_check("特效根节点为 GPUParticles3D %s" % path.get_file(), inst is GPUParticles3D)
			_check("特效挂自毁脚本 %s" % path.get_file(),
				inst.get_script() != null and String(inst.get_script().resource_path).ends_with("self_destroy_particles.gd"))
			inst.free()
	# spawn_effect headless 静默跳过不崩溃
	SfxManager.spawn_effect("res://scenes/vfx/hit_spark.tscn", Vector3.ZERO)
	_check("spawn_effect headless 跳过不崩溃", true)


# ===== 5. 真脚步声（M15）=====

func _test_footsteps() -> void:
	var keys: Array[StringName] = SfxManager.FOOTSTEP_KEYS
	_check("脚步声随机组共 3 条", keys.size() == 3, "实际 %d" % keys.size())
	for key in keys:
		var path: String = SfxManager._LIBRARY.get(key, "")
		_check("脚步音效文件存在 %s" % key, path != "" and FileAccess.file_exists(path), path)
	# 随机播放接口存在且不崩溃
	SfxManager.play_random(keys, -8.0)
	SfxManager.play_3d_random(keys, Vector3.ZERO, 8.0)
	_check("随机轮播接口不崩溃", true)


# ===== 6. Plush 伙伴（M15）=====

func _test_partner(player: CharacterBody3D) -> void:
	var partner := get_tree().root.get_node_or_null("Level/Partner") as Node3D
	_check("本地玩家已生成伙伴（Level/Partner）", partner != null)
	if partner == null:
		return
	_check("伙伴在 partners 组", partner.is_in_group("partners"))
	_check("伙伴已绑定主人", partner.get("owner_player") == player)
	var anim := partner.get_node_or_null("Plush/AnimationPlayer") as AnimationPlayer
	_check("伙伴动画播放器存在", anim != null)
	if anim:
		for required in [&"idle", &"walk", &"run", &"wave"]:
			_check("伙伴动画 %s 存在" % required, anim.has_animation(required))
	# 挥手状态机
	partner.say_hello()
	_check("say_hello 后处于挥手状态", partner.get("_is_waving") == true)
	if anim and anim.has_animation(&"wave"):
		_check("挥手动画循环已关闭（播完自动回待机）",
			anim.get_animation(&"wave").loop_mode == Animation.LOOP_NONE)
	partner.set("_is_waving", false)
	# 跟随逻辑：把伙伴放到 10 米外，跑若干物理帧后应向玩家靠近（run 速度 5.5m/s）
	partner.global_position = player.global_position + Vector3(10, 0.5, 0)
	var start_dist: float = partner.global_position.distance_to(player.global_position)
	for i in range(5):
		await get_tree().physics_frame
	var after_dist: float = partner.global_position.distance_to(player.global_position)
	_check("伙伴向玩家跟随移动", after_dist < start_dist - 0.1,
		"起始 %.2f 米 → 现在 %.2f 米" % [start_dist, after_dist])


# ===== 工具 =====

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass_count += 1
		print("PASS | ", name)
	else:
		_failures.append(name)
		var suffix := (" | " + detail) if detail != "" else ""
		print("FAIL | ", name, suffix)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("FAIL | ", msg)


func _report() -> void:
	print("=== M14+M15 测试结果 ===")
	for f in _failures:
		print("失败项：", f)
	print("SUMMARY: PASS=%d FAIL=%d" % [_pass_count, _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)
