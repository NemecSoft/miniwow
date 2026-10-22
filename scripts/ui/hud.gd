class_name HUD
extends CanvasLayer

## MiniWoW 战斗 HUD（M19-Reactive 版）。
##
## 架构：本脚本只做"驱动"——订阅玩家/属性/任务信号，把变化写进 Reactive UI 的
## hooks state（经 _setters 字典）；全部视觉声明在 hud_rui_view.gd（V 工厂组件树）。
## 冷却遮罩与图标压暗是每帧高频数据，走 ref 命令式直写，不进 state（避免每帧全树重渲染）。
##
## 对外接口与旧版完全一致：bind_player / bind_class_skills / set_player_stats /
## set_target / clear_target / show_death_panel / hide_death_panel / visible。

const HUDViewScript := preload("res://scripts/ui/hud_rui_view.gd")

const SKILL_BAR_SLOTS := 4 ## 槽位 0 = 普攻（左键），1~3 = 职业技能（1/2/3 键）

var player: Character = null
var target_attributes: AttributeSet = null
var theme_id: String = "wow"  ## M21-Theme：当前 UI 主题（视图 hooks 读取 + setter 回写）

var _app: ReactiveRoot
var _view: Object
var _setters := {} ## 由 hud_rui_view 渲染时回填的 state setter（key -> Callable）
var _overlay_refs: Array = [] ## 冷却遮罩 ColorRect 的 ref 盒子（{"current": node}）
var _icon_refs: Array = [] ## 技能图标 TextureRect 的 ref 盒子
var _slot_skill_ids: Array[String] = ["basic_attack", "", "", ""] ## 各槽位对应的技能 id
var _coord_readout: CoordReadout = null ## M49：常驻坐标读数（每帧直写，不走 Reactive）


func _ready() -> void:
	for i in SKILL_BAR_SLOTS:
		_overlay_refs.append({})
		_icon_refs.append({})
	theme_id = ThemeManager.theme_id()
	ThemeManager.theme_changed.connect(_on_theme_changed)
	_view = HUDViewScript.new()
	_app = ReactiveRoot.create(self, V.fc(_view.hud_view, {
		"hud": self,
		"overlay_refs": _overlay_refs,
		"icon_refs": _icon_refs,
	}))
	# 坐标读数后加：CanvasLayer 子节点按顺序绘制，保证压在 RUI 树之上
	_coord_readout = CoordReadout.new()
	_coord_readout.name = "CoordReadout"
	add_child(_coord_readout)


func _exit_tree() -> void:
	if ThemeManager.theme_changed.is_connected(_on_theme_changed):
		ThemeManager.theme_changed.disconnect(_on_theme_changed)
	if _app != null:
		_app.unmount()


## M21-Theme：主题切换 → 写 hooks state，HUD 全树重渲染换肤
func _on_theme_changed(new_id: String) -> void:
	theme_id = new_id
	_set_state("theme", new_id)


## 把一次外部变化写进对应 hooks state（渲染尚未发生时 setter 无效，静默跳过）
func _set_state(key: String, value) -> void:
	var setter: Callable = _setters.get(key, Callable())
	if setter.is_valid():
		setter.call(value)


func bind_player(new_player: Character) -> void:
	player = new_player
	# 视图的 useEffect 依赖此 state：绑定/换绑时自动重订阅全部信号
	_set_state("player", new_player)
	if _coord_readout != null:
		_coord_readout.player = new_player


## M5：绑定职业技能到 HUD 技能栏（槽位 1~3 对应 1/2/3 键；槽位 0 永远是普攻）
func bind_class_skills(skill_ids: Array) -> void:
	var list := []
	for i in SKILL_BAR_SLOTS:
		var skill_id := "basic_attack" if i == 0 else String(skill_ids[i - 1]) if i - 1 < skill_ids.size() else ""
		_slot_skill_ids[i] = skill_id
		var skill := SkillDatabase.get_skill(skill_id) if not skill_id.is_empty() else null
		list.append({
			"icon": skill.icon if skill else null,
			"name": tr(skill.skill_name) if skill else "-",
		})
	_set_state("skills", list)


## M3：装备加成变化时由玩家调用（换装/登录同步）
func set_player_stats(atk: int, def_value: int) -> void:
	_set_state("stats", tr("攻 %d · 防 %d") % [atk, def_value])


## M4：等级/经验刷新（旧版公开接口，内部转 state）
func set_experience(current: int, needed: int) -> void:
	_set_state("xp_cur", current)
	_set_state("xp_need", needed)
	_set_state("xp_text", tr("经验 %d/%d") % [current, needed] if needed > 0 else tr("已满级"))


## 等级标签附带职业名（Lv.3 · 法师），由视图层信号回调调用
func _build_level_text(p: Character) -> String:
	var suffix := ""
	if not p.player_class.is_empty():
		var class_data := ClassDatabase.get_class_data(p.player_class)
		if class_data:
			suffix = " · " + tr(class_data.display_name)
	return "Lv.%d%s" % [p.level, suffix]


## M4：任务追踪数据（右侧面板）：列出进行中/可交付任务与进度，由视图层信号回调调用
func _build_quest_entries(p: Character) -> Array:
	var entries := []
	for quest in QuestDatabase.get_all_quests():
		var status := p.get_quest_status(quest.id)
		if status != "active" and status != "ready":
			continue
		var progress := "%s %d/%d" % [
			tr(quest.objective_text), p.get_quest_count(quest.id), quest.required_count
		]
		if status == "ready":
			progress += tr("（可交付）")
		entries.append({
			"id": quest.id,
			"name": tr(quest.name),
			"status": status,
			"progress": progress,
		})
	return entries


func set_target(new_target: Node) -> void:
	if new_target == null:
		clear_target()
		return
	var attrs := CombatMath.get_attribute_set(new_target)
	if attrs == null:
		clear_target()
		return
	target_attributes = attrs
	_set_state("target_name", _get_target_display_name(new_target))
	_set_state("target_hp", attrs.hp)
	_set_state("target_hp_max", attrs.max_hp)
	_set_state("target_visible", true)
	if not attrs.hp_changed.is_connected(_on_target_hp_changed):
		attrs.hp_changed.connect(_on_target_hp_changed)


func clear_target() -> void:
	if target_attributes and target_attributes.hp_changed.is_connected(_on_target_hp_changed):
		target_attributes.hp_changed.disconnect(_on_target_hp_changed)
	target_attributes = null
	_set_state("target_visible", false)


func _get_target_display_name(node: Node) -> String:
	if node is TrainingDummy:
		return "%s Lv.%d" % [tr(node.display_name), node.level]
	if node is Monster:
		return "%s Lv.%d" % [tr(node.data.display_name), node.data.level]
	if node is Character and node.nickname:
		return "%s Lv.%d" % [node.nickname.text, node.level]
	return str(node.name)


func show_death_panel() -> void:
	_set_state("death", true)


func hide_death_panel() -> void:
	_set_state("death", false)


## 每帧高频数据走 ref 命令式直写：冷却遮罩压缩比例 + 蓝耗不足图标压暗
func _process(_delta: float) -> void:
	if player == null:
		return
	var attrs := CombatMath.get_attribute_set(player)
	for i in SKILL_BAR_SLOTS:
		var overlay = _overlay_refs[i].get("current")
		if overlay != null:
			overlay.scale.y = player.get_skill_cooldown_ratio(_slot_skill_ids[i])
		var icon = _icon_refs[i].get("current")
		if icon != null:
			var skill := SkillDatabase.get_skill(_slot_skill_ids[i]) if not _slot_skill_ids[i].is_empty() else null
			var mp_cost := skill.mp_cost if skill else 0
			var affordable := attrs == null or attrs.mp >= mp_cost
			icon.modulate = Color(1, 1, 1, 1) if affordable else Color(0.45, 0.45, 0.5, 1)


func _on_target_hp_changed(current: int, _maximum: int) -> void:
	_set_state("target_hp", current)


func _on_release_pressed() -> void:
	if player:
		player.request_respawn_action()
