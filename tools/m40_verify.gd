extends Node3D
## M40 headless 校验探针：逐项断言五大系统 + 音效资源。
## 沙箱无显示服务（DISPLAY 为空），无法做引擎自存帧像素截图，
## 故改用程序化断言。每次断言立即追加写入 user://m40_verify.log，
## 即便进程被 SIGTERM 杀掉也能看到已完成的进度。
##
## 用法（headless）：
##   godot --headless --path <项目> res://tools/m40_verify.tscn
## 退出码：全 PASS=0，有 FAIL=1，被中断无输出=超时。

const LOG_PATH := "user://m40_verify.log"
var _results: Array = []


func _ready() -> void:
	# 清空旧日志
	var clear := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if clear != null:
		clear.store_string("")
		clear.close()
	_log("M40-VERIFY: 开始")
	await _verify_sfx()
	await _verify_storm()
	await _verify_spells()
	await _verify_partner()
	await _verify_airplane()
	await _verify_sword()
	_print_summary()
	var ok := true
	for r in _results:
		if not r.ok:
			ok = false
	_log("M40-VERIFY: 退出码=%d" % (0 if ok else 1))
	get_tree().quit(0 if ok else 1)


func _log(s: String) -> void:
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(s)
	f.close()


func _pass(name: String, ok: bool, detail: String = "") -> void:
	_results.append({"name": name, "ok": ok})
	var line := ("PASS | " if ok else "FAIL | ") + name
	if detail != "":
		line += " | " + detail
	printerr(line)
	_log(line)


func _print_summary() -> void:
	var pass_n := 0
	for r in _results:
		if r.ok:
			pass_n += 1
	_log("M40-VERIFY: 共 %d 项，通过 %d，失败 %d" % [_results.size(), pass_n, _results.size() - pass_n])


## ---- 音效：遍历 SfxManager._LIBRARY，确认每条路径都能 load 非 null ----
func _verify_sfx() -> void:
	if SfxManager == null:
		_pass("sfx: autoload SfxManager 存在", false, "SfxManager 为 null")
		return
	_pass("sfx: autoload SfxManager 存在", true)
	var lib: Dictionary = SfxManager._LIBRARY
	var null_list: Array = []
	var total := 0
	var idx := 0
	for key in lib.keys():
		total += 1
		idx += 1
		var p: String = lib[key]
		if load(p) == null:
			null_list.append(str(key) + " -> " + p)
		if idx % 30 == 0:
			_log("sfx: 进度 %d/%d" % [idx, lib.size()])
	_pass("sfx: 字典 %d 条全部可加载" % total, null_list.is_empty(),
		("不可加载: " + str(null_list)) if not null_list.is_empty() else "全部非 null")


## ---- 暴风雨：实例化 StormSystem，开启后查雨粒子 ----
func _verify_storm() -> void:
	var scn := load("res://scenes/environment/storm_system.tscn") as PackedScene
	if scn == null:
		_pass("storm: 场景可加载", false)
		return
	_pass("storm: 场景可加载", true)
	var inst := scn.instantiate() as Node3D
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	var rain := inst.get_node_or_null("Rain")
	if rain == null:
		_pass("storm: Rain 节点存在", false)
		return
	_pass("storm: Rain 节点存在", true, "amount=%d emitting=%s" % [rain.amount, str(rain.emitting)])
	if inst.has_method("set_storm"):
		inst.set_storm(true)
		await get_tree().process_frame
		await get_tree().process_frame
		_pass("storm: set_storm(true) 后雨在发射", rain.emitting == true)
	else:
		_pass("storm: 有 set_storm 方法", false)
	var flash := inst.get_node_or_null("LightningFlash")
	_pass("storm: 闪电灯 LightningFlash 存在", flash != null)


## ---- 法术：实例化 Projectile，setup 三种元素，查拖尾 + 爆发场景 ----
func _verify_spells() -> void:
	var scn := load("res://scenes/combat/projectile.tscn") as PackedScene
	if scn == null:
		_pass("spell: projectile 场景可加载", false)
		return
	_pass("spell: projectile 场景可加载", true)
	var p := scn.instantiate()
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	p.setup(Vector3.FORWARD, 18.0, 12.0, "m_fireball", Color(1, 0.45, 0.12))
	await get_tree().process_frame
	var trail := p.get_node_or_null("Trail")
	var trail_ok: bool = trail != null and (trail is GPUParticles3D) and trail.emitting
	_pass("spell: 火球拖尾发射", trail_ok)
	var bursts := ["res://scenes/vfx/spell_fire_burst.tscn",
		"res://scenes/vfx/spell_frost_burst.tscn",
		"res://scenes/vfx/spell_arcane_burst.tscn"]
	var bok := true
	for b in bursts:
		if load(b) == null:
			bok = false
	_pass("spell: 火/冰/奥术 三套爆发场景可加载", bok)
	p.setup(Vector3.FORWARD, 18.0, 12.0, "m_frostbolt", Color(0.5, 0.85, 1))
	await get_tree().process_frame
	p.setup(Vector3.FORWARD, 18.0, 12.0, "m_arcane", Color(0.7, 0.4, 1))
	await get_tree().process_frame
	_pass("spell: 冰/奥术前摇 setup 无异常", true)


## ---- 小精灵：实例化 partner，查 AuraGlow + EmberTrail，测主题切换 ----
func _verify_partner() -> void:
	var scn := load("res://scenes/npcs/partner.tscn") as PackedScene
	if scn == null:
		_pass("partner: 场景可加载", false)
		return
	_pass("partner: 场景可加载", true)
	var inst := scn.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	var glow := inst.get_node_or_null("AuraGlow")
	var ember := inst.get_node_or_null("EmberTrail")
	var ok: bool = glow != null and (glow is GPUParticles3D) \
		and ember != null and (ember is GPUParticles3D)
	_pass("partner: AuraGlow+EmberTrail 存在且发射",
		ok and glow.emitting and ember.emitting)
	if inst.has_method("set_aura_theme"):
		inst.set_aura_theme(Color(0.7, 0.4, 1))
		await get_tree().process_frame
		var mat := glow.material_override as StandardMaterial3D
		var changed := mat != null and mat.emission.is_equal_approx(Color(0.7, 0.4, 1))
		_pass("partner: set_aura_theme 改发光色", changed)
	else:
		_pass("partner: 有 set_aura_theme 方法", false)


## ---- 飞机：实例化 air_vehicle，查巡航参数与模型子节点 ----
func _verify_airplane() -> void:
	var scn := load("res://scenes/vehicles/air_vehicle.tscn") as PackedScene
	if scn == null:
		_pass("airplane: 场景可加载", false)
		return
	_pass("airplane: 场景可加载", true)
	var inst := scn.instantiate() as Node
	add_child(inst)
	await get_tree().process_frame
	var center: Variant = inst.get("center")
	var has_center: bool = center != null and not (center as Vector3).is_equal_approx(Vector3.ZERO)
	_pass("airplane: center 巡航中心已设", has_center, "center=%s" % str(center))
	var model := inst.get_node_or_null("PlaneModel")
	_pass("airplane: PlaneModel 子节点存在", model != null)


## ---- 短剑：字典映射 + 场景节点 + 同步器属性 ----
func _verify_sword() -> void:
	var ok_dict := false
	if "WEAPON_NODES_BY_ITEM" in Character:
		ok_dict = Character.WEAPON_NODES_BY_ITEM.has("sword_short")
	_pass("sword: Character.WEAPON_NODES_BY_ITEM 含 sword_short", ok_dict)
	var f := FileAccess.open("res://scenes/level/player.tscn", FileAccess.READ)
	var txt := ""
	if f != null:
		txt = f.get_as_text()
		f.close()
	var has_node := txt.contains('name="SwordShort"')
	var has_sync := txt.contains("LeftHandAttach/SwordShort:visible")
	_pass("sword: player.tscn 含 SwordShort 节点", has_node)
	_pass("sword: 同步器含 SwordShort:visible", has_sync)
