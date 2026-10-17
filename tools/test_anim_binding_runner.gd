extends Node

## 动画绑定自动校验（M16d 收尾固化，配合设计文档 5.15 工作流 SOP）。
## 每绑定一个新动作（烘焙/换映射/加技能）后必须跑一遍，防"丢三落四"：
##   ① 技能 tres 引用的动画都存在于机器人动画库（原版 ∪ 重定向注入）
##   ② 每个技能动画都在 ALLOWED_ANIMATION_STATES 白名单
##   ③ 每个攻击类动画在 _on_animation_finished 有 is_attacking 复位分支
##   ④ 每个攻击类动画在 sync_animation_state 的 is_strike 集合里（远程同步锁）
##   ⑤ 烘焙动画驱动骨骼集 ⊆ 原版 Idle-loop 驱动集（防切换后 pose 残留低头）
##   ⑥ _play_attack_animation / _start_attack 硬编码动画名清单（人工核对）
## 运行方式：godot --headless --path . res://tools/test_anim_binding.tscn

var _pass_count := 0
var _failures: Array[String] = []


func _ready() -> void:
	var robot_scene := load("res://scenes/monsters/robot_body.tscn")
	var robot: Node3D = robot_scene.instantiate()
	add_child(robot)
	var anim_player := robot.get_node("AnimationPlayer") as AnimationPlayer
	var lib := anim_player.get_animation_library(&"")

	# 注入重定向动画（模拟 3d_godot_robot._ready 的运行时注入）
	var retarget_anims := {
		&"Strike": "res://assets/animations/retarget/strike_jab.tres",
		&"SwordSlash": "res://assets/animations/retarget/sword_slash.tres",
	}
	for anim_name in retarget_anims:
		if not lib.has_animation(anim_name):
			var res: Animation = load(retarget_anims[anim_name])
			lib.add_animation(anim_name, res)

	var engine_anim_names := {}
	for anim_name in lib.get_animation_list():
		engine_anim_names[anim_name] = true

	var player_src := _read_text("res://scripts/player/player.gd")
	var allowed := _parse_const_stringnames(player_src, "ALLOWED_ANIMATION_STATES")
	var finished_reset := _parse_match_branches(player_src, "func _on_animation_finished")
	var is_strike_line := _find_line_containing(player_src, "var is_strike :=")

	# ---- ① ② ③ ④：逐技能校验 ----
	var skill_dir := "res://resources/skills"
	var dir := DirAccess.open(skill_dir)
	var skill_count := 0
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		skill_count += 1
		var src := _read_text(skill_dir + "/" + f)
		var anim := _parse_skill_animation(src)
		if anim.is_empty():
			_fail("%s 缺少 animation 字段" % f)
			continue
		_check("%s → %s 动画存在于动画库" % [f, anim], engine_anim_names.has(anim),
			"库中无此动画（原版∪重定向）")
		_check("%s → %s 在白名单" % [f, anim], allowed.has(anim),
			"player.gd ALLOWED_ANIMATION_STATES 缺项")
		if _is_attack_skill(f):
			_check("%s → %s 有播完复位分支" % [f, anim], finished_reset.has(anim),
				"_on_animation_finished 缺 match 分支 → is_attacking 永不复位 → 定格末帧")
			_check("%s → %s 在远程 is_strike 集合" % [f, anim],
				is_strike_line.contains("\"%s\"" % anim) or is_strike_line.contains("&\"%s\"" % anim),
				"sync_animation_state 远程攻击锁缺项")
	_check("技能资源总数 > 0", skill_count > 0, "未找到技能文件")

	# ---- ⑤：烘焙动画骨骼集 ⊆ 原版驱动集（防低头残留，M16c 教训）----
	# 注意：动画库真实键名无 "-loop" 后缀（resource_name 是 "Idle-loop" 但库键是 "Idle"）
	var idle_anim := lib.get_animation(&"Idle")
	var idle_bones := _collect_bones(idle_anim)
	var retarget_dir := "res://assets/animations/retarget"
	if DirAccess.dir_exists_absolute(retarget_dir):
		var rdir := DirAccess.open(retarget_dir)
		for f in rdir.get_files():
			if not f.ends_with(".tres"):
				continue
			var baked: Animation = load(retarget_dir + "/" + f)
			var baked_bones := _collect_bones(baked)
			var leaked: Array[String] = []
			for b in baked_bones:
				if not idle_bones.has(b):
					leaked.append(b)
			_check("%s 驱动骨骼 ⊆ Idle-loop 驱动集" % f, leaked.is_empty(),
				"残留风险骨骼: %s（切回 Idle/Run 后无轨道接管 → 定格末帧）" % ", ".join(leaked))

	# ---- ⑥：硬编码动画名调用点清单（人工核对项）----
	var hard_coded := _find_all_lines(player_src, "_play_attack_animation(&\"")
	for line_no in hard_coded.keys():
		printerr("HARDCODE: player.gd:%d %s" % [line_no, hard_coded[line_no].strip_edges()])

	_report()


func _is_attack_skill(file_name: String) -> bool:
	# 有直接伤害/近战动作的技能需要攻击锁复位；纯 buff/施法（Emote2 类）不需要
	var attack_skills := ["basic_attack", "heavy_strike", "whirlwind", "execute",
		"fireball", "frostbolt", "arcane_blast", "holy_nova", "smite"]
	for k in attack_skills:
		if file_name.contains(k):
			return true
	return false


func _parse_skill_animation(src: String) -> String:
	var re := RegEx.new()
	re.compile("animation = &\"([A-Za-z0-9_.-]+)\"")
	var m := re.search(src)
	return m.get_string(1) if m else ""


func _parse_const_stringnames(src: String, const_name: String) -> Dictionary:
	var out := {}
	var re := RegEx.new()
	re.compile("%s := \\{([\\s\\S]*?)\\}" % const_name)
	var m := re.search(src)
	if m:
		var re2 := RegEx.new()
		re2.compile("&\"([A-Za-z0-9_.-]+)\"")
		for r in re2.search_all(m.get_string(1)):
			out[r.get_string(1)] = true
	return out


func _parse_match_branches(src: String, func_sig: String) -> Dictionary:
	var out := {}
	var start := src.find(func_sig)
	if start < 0:
		return out
	# 取函数体到下一个顶级 func 为止
	var body := src.substr(start, src.find("\nfunc ", start + 10) - start)
	var re := RegEx.new()
	# match 分支形如 "\n\t\t&\"Attack1\":"（不能用 ^，Godot RegEx 默认非多行）
	re.compile("\\n\\t\\t&\"([A-Za-z0-9_.-]+)\":")
	for r in re.search_all(body):
		out[r.get_string(1)] = true
	return out


func _collect_bones(anim: Animation) -> Dictionary:
	var out := {}
	for t in anim.get_track_count():
		var path := anim.track_get_path(t)
		var sub := String(path.get_subname(0))
		if not sub.is_empty():
			out[sub] = true
	return out


func _find_line_containing(src: String, needle: String) -> String:
	for line in src.split("\n"):
		if line.contains(needle):
			return line
	return ""


func _find_all_lines(src: String, needle: String) -> Dictionary:
	var out := {}
	var lines := src.split("\n")
	for i in lines.size():
		if lines[i].contains(needle):
			out[i + 1] = lines[i]
	return out


func _read_text(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	return f.get_as_text() if f else ""


func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass_count += 1
	else:
		_failures.append("%s -> %s" % [name, detail])
		printerr("FAIL | %s -> %s" % [name, detail])


func _fail(name: String) -> void:
	_failures.append(name)
	printerr("FAIL | %s" % name)


func _report() -> void:
	printerr("========================================")
	printerr("动画绑定校验: PASS=%d FAIL=%d" % [_pass_count, _failures.size()])
	if _failures.is_empty():
		printerr("=== 动画绑定校验全部通过 ===")
	else:
		for f in _failures:
			printerr("  未通过: %s" % f)
	get_tree().quit(0 if _failures.is_empty() else 1)
