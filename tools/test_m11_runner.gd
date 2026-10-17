extends Node

## M11 声效系统 + M12 村民 NPC 测试
## 运行：godot --headless --path . res://tools/test_m11.tscn

var _pass_count := 0
var _fail_count := 0


func _ready() -> void:
	print("=== M11+M12 测试开始 ===")
	_test_sfx_library()
	_test_sfx_behaviour()
	_test_hook_buttons()
	_test_skill_sfx_mapping()
	await _test_villager()
	await _test_m13()
	print("=== SUMMARY: PASS=%d FAIL=%d ===" % [_pass_count, _fail_count])
	get_tree().quit(0 if _fail_count == 0 else 1)


func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass_count += 1
		print("PASS | ", name)
	else:
		_fail_count += 1
		print("FAIL | ", name, " -> ", detail)


# ===== 1. 音效库完整性 =====

func _test_sfx_library() -> void:
	var lib: Dictionary = SfxManager._LIBRARY
	# M15：+3 条真脚步声（footstep_0/1/2，Jeheno concrete）
	_check("音效库共 29 个条目", lib.size() == 29, "实际 %d" % lib.size())
	var missing: Array[String] = []
	for key in lib.keys():
		var path := String(lib[key])
		if not FileAccess.file_exists(path):
			missing.append(path)
	_check("所有音效文件存在", missing.is_empty(), "缺失: %s" % str(missing))


# ===== 6. M13：脚步/木桩/玩家受击 =====

func _test_m13() -> void:
	# footstep.wav 波形参数：0.28s 单声道 44.1kHz（make_footstep.py 产物）
	var step := load("res://assets/sfx/movement/footstep.wav") as AudioStreamWAV
	_check("footstep.wav 可加载且为 WAD 格式", step != null)
	if step:
		_check("footstep 时长约 0.28s", absf(step.get_length() - 0.28) < 0.05,
			"实际 %.3fs" % step.get_length())
		_check("footstep 为单声道", step.stereo == false)
	# 木桩受击音：实例化后直接调同步函数验证不崩溃
	var dummy_scene := load("res://scenes/monsters/training_dummy.tscn") as PackedScene
	_check("training_dummy.tscn 可加载", dummy_scene != null)
	if dummy_scene:
		var dummy := dummy_scene.instantiate()
		add_child.call_deferred(dummy)
		await get_tree().physics_frame
		if dummy.is_inside_tree():
			dummy.sync_dummy_hp(90, 100, true) # 各端播音路径（headless 静默）
			_check("木桩 sync_dummy_hp 播音路径不崩溃", true)
		dummy.queue_free()
	# 脚步逻辑存在性（源码断言：本地 2D + 远程 3D 双路径）
	var player_src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_check("player.gd 含脚步系统（本地速度判定 + 远程动画驱动）",
		player_src.contains("_update_footsteps") and player_src.contains("_remote_moving"))
	var sfx_src := FileAccess.get_file_as_string("res://scripts/autoload/sfx_manager.gd")
	_check("SfxManager.play 支持音量参数（脚步压低）", sfx_src.contains("volume_db: float = 0.0"))


# ===== 2. 播放行为 =====

func _test_sfx_behaviour() -> void:
	# headless 下 muted=true，但逻辑路径仍要无崩溃
	SfxManager.play(&"ui_click")
	SfxManager.play(&"不存在的key") # 应警告不崩溃
	_check("play() 未知 key 不崩溃", true)
	SfxManager.play_3d(&"swing", Vector3.ZERO)
	_check("play_3d() headless 下静默不崩溃", true)
	# 冷却：模拟"从未播过"状态（-30s 基准，等同产品代码初始化值）
	SfxManager._hp_alert_last_msec = -SfxManager.HP_ALERT_COOLDOWN_MSEC
	var first := SfxManager.play_hp_alert(&"low_hp")
	var second := SfxManager.play_hp_alert(&"full_heal")
	_check("血量提示首次触发成功", first)
	_check("血量提示冷却期内被拒", not second, "30 秒冷却内第二次应返回 false")
	SfxManager._hp_alert_last_msec = 0


# ===== 3. 按钮挂钩 =====

func _test_hook_buttons() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var btn := Button.new()
	holder.add_child(btn)
	SfxManager.hook_buttons(holder)
	var after_first := btn.pressed.get_connections().size()
	SfxManager.hook_buttons(holder) # 幂等
	var after_second := btn.pressed.get_connections().size()
	_check("hook_buttons 连接点击音", after_first >= 1, "连接数 %d" % after_first)
	_check("hook_buttons 幂等不重复连", after_first == after_second,
		"两次连接数 %d vs %d" % [after_first, after_second])
	SfxManager.hook_hover(holder)
	var hover_count := btn.mouse_entered.get_connections().size()
	_check("hook_hover 连接悬停音", hover_count >= 1)
	holder.queue_free()


# ===== 4. 技能音效映射完整性 =====

func _test_skill_sfx_mapping() -> void:
	var lib: Dictionary = SfxManager._LIBRARY
	var missing: Array[String] = []
	for skill_id in Character.SKILL_SFX.keys():
		var sfx_key: StringName = Character.SKILL_SFX[skill_id]
		if not lib.has(sfx_key):
			missing.append("%s -> %s" % [skill_id, sfx_key])
	_check("SKILL_SFX 全部指向已有音效 key", missing.is_empty(), "缺失: %s" % str(missing))
	_check("SKILL_SFX 不含普攻（动画函数已播）", not Character.SKILL_SFX.has("basic_attack"))


# ===== 5. 村民 NPC =====

func _test_villager() -> void:
	var scene := load("res://scenes/npcs/villager.tscn") as PackedScene
	_check("villager.tscn 可加载", scene != null)
	if scene == null:
		return
	var villager := scene.instantiate() as Villager
	_check("根节点是 Villager 类", villager != null)
	if villager == null:
		return
	add_child(villager)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("村民在 villagers 组", villager.is_in_group("villagers"))
	var anim := villager.get("anim_player") as AnimationPlayer
	_check("动画播放器存在", anim != null)
	if anim:
		_check("有待机聊天动画", anim.has_animation(&"Idle_Talking"))
		_check("有交互挥手动画", anim.has_animation(&"Interact"))
		_check("有舞蹈彩蛋动画", anim.has_animation(&"Dance"))
		_check("待机动画已自动播放", anim.current_animation == &"Idle_Talking",
			"实际 %s" % anim.current_animation)
		# 挥手
		villager.say_hello()
		await get_tree().process_frame
		_check("say_hello 切到 Interact", anim.current_animation == &"Interact",
			"实际 %s" % anim.current_animation)
		villager.dance()
		await get_tree().process_frame
		_check("dance 切到 Dance", anim.current_animation == &"Dance",
			"实际 %s" % anim.current_animation)
	var label := villager.get_node_or_null("NameLabel") as Label3D
	_check("名牌存在且规格统一(0.02)", label != null and is_equal_approx(label.pixel_size, 0.02),
		"pixel_size=%s" % str(label.pixel_size if label else -1.0))
	var prompt := villager.get_node_or_null("InteractPrompt") as Label3D
	_check("交互提示存在且默认隐藏", prompt != null and not prompt.visible)
	_check("碰撞层为 NPC 层(2)", villager.collision_layer == 2,
		"实际 %d" % villager.collision_layer)
	# level.tscn 摆位（读源文件断言）
	var level_src := FileAccess.get_file_as_string("res://scenes/level/level.tscn")
	_check("level.tscn 已放置村民", level_src.contains("22_villager"))
	villager.queue_free()
