extends Node

## M18b-2 自动化校验（以独立测试场景方式运行，保证 autoload 单例可用）：
## 步兵动作战斗层——三连斩连招 / 冲刺 / 格挡 / 击退硬直 / 震屏 的静态断言。
## 运行方式：godot --headless --path . res://tools/test_m18b2.tscn

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _ready() -> void:
	_check_project_inputs()
	_check_player_combo()
	_check_player_dash_block()
	_check_shake_camera()
	_check_monster_knockback()
	_check_skill_knockback()
	_report()


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS | ", label)
	else:
		_fail += 1
		_failures.append(label)
		print("FAIL | ", label)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _check_project_inputs() -> void:
	var proj := _read("res://project.godot")
	_assert("dash={" in proj, "project.godot 已注册 dash 输入")
	_assert("block={" in proj, "project.godot 已注册 block 输入")
	_assert("button_index\":2" in proj.replace(" ", "").replace("\":", "\":")
		or "button_index\": 2" in proj, "block 绑定鼠标右键（button_index 2）")


func _check_player_combo() -> void:
	var src := _read("res://scripts/player/player.gd")
	_assert("INFANTRY_COMBO_ANIMS" in src, "player.gd 定义三连斩动画表")
	_assert("INFANTRY_COMBO_MULT" in src, "player.gd 定义三连斩倍率表")
	_assert("COMBO_WINDOW_MSEC" in src, "player.gd 定义连招窗口")
	_assert("func _advance_combo(" in src, "player.gd 实现连招推进（客户端/服务器共用规则）")
	# 三段动画必须都在动画库（烘焙重定向产物），否则运行时静默不播
	var anims := src.substr(src.find("INFANTRY_COMBO_ANIMS"))
	for anim in [&"SwordSlash", &"Kick", &"Attack1"]:
		_assert(String(anim) in anims.substr(0, 200), "连招表含段动画 %s" % anim)
	# 服务器权威计段：request_attack 内推进 _server_combo_index 并传倍率
	_assert("_server_combo_index" in src, "player.gd 服务器权威连招计数")
	_assert("INFANTRY_COMBO_MULT[_server_combo_index]" in src, "服务器结算使用连段倍率")
	# 空挥不走连招推进（保持客户端/服务器段数一致）
	var start_attack := src.substr(src.find("func _start_attack"))
	start_attack = start_attack.substr(0, start_attack.find("func _on_animation_finished"))
	_assert("_advance_combo" not in start_attack, "空挥路径不推进连招（防段数错位）")


func _check_player_dash_block() -> void:
	var src := _read("res://scripts/player/player.gd")
	_assert("DASH_SPEED" in src and "DASH_COOLDOWN_MSEC" in src, "player.gd 定义冲刺常量")
	_assert("is_action_just_pressed(\"dash\")" in src, "player.gd 检测冲刺输入")
	_assert("is_attacking = false # dash_cancel" in src, "冲刺打断攻击（dash_cancel）")
	_assert("Input.is_action_pressed(\"block\")" in src, "player.gd 检测格挡输入")
	_assert("BLOCK_DAMAGE_FACTOR" in src, "player.gd 定义格挡减伤常量")
	_assert("func set_blocking(" in src, "player.gd 格挡状态 RPC 上报")
	_assert("_current_speed *= BLOCK_SPEED_FACTOR" in src, "格挡移速减半")


func _check_shake_camera() -> void:
	var src := _read("res://scripts/player/shake_camera_3d.gd")
	_assert(src.length() > 0, "shake_camera_3d.gd 存在")
	_assert("func quick_shake(" in src, "震屏实现 quick_shake")
	_assert("h_offset" in src and "v_offset" in src, "震屏写入相机偏移")
	var player := _read("res://scripts/player/player.gd")
	_assert("ShakeCamera3D.new()" in player, "本地玩家挂载震屏节点")
	_assert("_trigger_shake(SHAKE_ATTACK_MAGNITUDE)" in player, "第三段转圈斩出手震屏")
	_assert("SHAKE_HURT_MAGNITUDE" in player, "被击震屏")


func _check_monster_knockback() -> void:
	var src := _read("res://scripts/monsters/monster.gd")
	_assert("func add_knockback(" in src, "monster.gd 实现击退入口")
	_assert("func is_stunned(" in src, "monster.gd 实现硬直判定")
	_assert("KNOCKBACK_DECAY" in src, "monster.gd 击退指数衰减")
	_assert("defender.is_blocking" in src, "怪物攻击结算盾墙减伤")


func _check_skill_knockback() -> void:
	var skill_src := _read("res://scripts/combat/skill_data.gd")
	_assert("knockback_force" in skill_src, "SkillData 声明击退字段")
	for skill_path in ["res://resources/skills/i_shield_bash.tres", "res://resources/skills/i_retaliate.tres"]:
		var res := _read(skill_path)
		_assert("knockback_force" in res, "%s 配置击退力度" % skill_path.get_file())
	# 伤害入口应用击退（仅怪物）
	var player := _read("res://scripts/player/player.gd")
	_assert("extra_mult: float = 1.0" in player, "伤害结算支持连段附加倍率")
	_assert("add_knockback(push_dir.normalized() * skill.knockback_force)" in player,
		"命中怪物时施加击退")


func _report() -> void:
	print("=== M18b-2 校验: PASS=%d FAIL=%d ===" % [_pass, _fail])
	if _fail == 0:
		print("=== M18b-2 测试全部通过 ===")
	else:
		print("=== 失败项 ===")
		for f in _failures:
			print(" - ", f)
		print("=== M18b-2 存在失败项 ===")
	get_tree().quit(0 if _fail == 0 else 1)
