extends RefCounted
## MiniWoW HUD 的 Reactive UI 视图层（M19-Reactive，Reactive UI v0.12.1 纯 GDScript API）。
##
## 结构：hud_view(props, children) 为唯一组件函数，全部视觉由 V.* 工厂声明。
## hud.gd 经 props["hud"]._setters 字典把外部信号转成 hooks state，驱动本视图重渲染；
## 冷却遮罩/图标压暗这类每帧高频数据走 ref 命令式直写（React escape hatch）。
##
## RUI 约定（见 core/style.gd、core/host_config.gd）：
##   · props     —— 节点普通属性：text / value / max_value / texture / anchor_* / offset_* / grow_* …
##   · style     —— mouse_filter / visible / modulate / size_flags_* / custom_minimum_size /
##                 anchors_preset / box 键(bg_color…)/ theme 通道(colors/constants/font_sizes/styleboxes)
##
## 铁律：hooks 调用顺序即 state 声明顺序，新增 state 必须追加在末尾，严禁插队。

# ---- 配色与数值：全部照抄原 hud.tscn，零发挥 ----
const PANEL_BG := Color(0.08, 0.08, 0.12, 0.85)
const PANEL_BORDER := Color(0.25, 0.22, 0.18, 1.0)
const HP_BG := Color(0.2, 0.05, 0.05, 1.0)
const HP_FILL := Color(0.85, 0.2, 0.2, 1.0)
const MP_BG := Color(0.05, 0.05, 0.2, 1.0)
const MP_FILL := Color(0.25, 0.45, 0.9, 1.0)
const XP_BG := Color(0.12, 0.1, 0.02, 1.0)
const XP_FILL := Color(0.95, 0.75, 0.15, 1.0)
const DEATH_BG := Color(0.02, 0.02, 0.03, 0.6)
const QUEST_READY := Color(1.0, 0.85, 0.3, 1.0)
const QUEST_ACTIVE := Color(0.65, 0.9, 0.65, 1.0)
const QUEST_PROGRESS := Color(0.75, 0.75, 0.75, 1.0)

const SKILL_BAR_SLOTS := 4
const SKILL_SLOT_SIZE := Vector2(96, 56)
const SKILL_ICON_SIZE := Vector2(44, 44)
const KEY_LABELS := ["左键", "1", "2", "3"]

static var _bar_boxes = null
static var _bar_boxes_theme := ""  # _bar_boxes 缓存对应的主题（切换主题后重建）

static func _bars() -> Dictionary:
	var theme_id: String = ThemeManager.theme_id()
	if _bar_boxes == null or _bar_boxes_theme != theme_id:
		_bar_boxes_theme = theme_id
		var mk := func(c: Color) -> StyleBoxFlat:
			var sb := StyleBoxFlat.new()
			sb.bg_color = c
			sb.set_corner_radius_all(2)
			return sb
		var boxes := {
			"hp_bg": mk.call(HP_BG), "hp_fill": mk.call(HP_FILL),
			"mp_bg": mk.call(MP_BG), "mp_fill": mk.call(MP_FILL),
			"xp_bg": mk.call(XP_BG), "xp_fill": mk.call(XP_FILL),
		}
		# M21-Theme：血条外壳用主题 bar_frame（整张拉伸：HUD 条仅 14px 高，
		# 九宫格边框比条还高会画爆；content margin 让 fill 缩进镂空区）
		var frame_tex: Texture2D = ThemeManager.bar_frame_texture()
		if frame_tex != null:
			for bar_name in ["hp", "mp", "xp"]:
				var frame := StyleBoxTexture.new()
				frame.texture = frame_tex
				frame.content_margin_left = 12.0
				frame.content_margin_right = 12.0
				frame.content_margin_top = 5.0
				frame.content_margin_bottom = 5.0
				boxes[bar_name + "_bg"] = frame
		_bar_boxes = boxes
	return _bar_boxes

## 面板样式：主题九宫格皮肤（素材缺失时 ThemeManager 内部回退色块）
static func _panel_style() -> Dictionary:
	return {"styleboxes": {"panel": ThemeManager.panel_stylebox()}}

## 按钮三态样式（主题化；RUI styleboxes 通道直传）
static func _button_styles() -> Dictionary:
	var normal: StyleBox = ThemeManager.button_stylebox("normal")
	var primary: StyleBox = ThemeManager.button_stylebox("primary")
	return {"styleboxes": {"normal": normal, "hover": primary, "pressed": primary, "focus": normal}}

static func _margin_style(m: int) -> Dictionary:
	return {"constants": {"margin_left": m, "margin_top": m, "margin_right": m, "margin_bottom": m}}

const IGNORE := {"mouse_filter": Control.MOUSE_FILTER_IGNORE}


func hud_view(props: Dictionary, _children):
	var hud: Object = props["hud"]
	var overlay_refs: Array = props["overlay_refs"]
	var icon_refs: Array = props["icon_refs"]

	# ---- hooks：顺序固定，新增追加末尾 ----
	var player_state = Hooks.useState(null)
	var hp_cur = Hooks.useState(1)
	var hp_max = Hooks.useState(1)
	var mp_cur = Hooks.useState(1)
	var mp_max = Hooks.useState(1)
	var xp_cur = Hooks.useState(0)
	var xp_need = Hooks.useState(100)
	var xp_text = Hooks.useState(tr("经验 0/100"))
	var gold = Hooks.useState(0)
	var name_text = Hooks.useState(tr("冒险者"))
	var level_text = Hooks.useState("Lv.1")
	var stats_text = Hooks.useState(tr("攻 0 · 防 0"))
	var target_name = Hooks.useState("")
	var target_hp = Hooks.useState(0)
	var target_hp_max = Hooks.useState(100)
	var target_visible = Hooks.useState(false)
	var skills = Hooks.useState([])
	var quests = Hooks.useState([])
	var death_visible = Hooks.useState(false)
	var theme_state = Hooks.useState(hud.theme_id)  # M21-Theme：主题 id，切换时全 HUD 重渲染换肤

	# ---- setter 回填给 hud.gd 驱动层 ----
	hud._setters["player"] = player_state[1]
	hud._setters["hp_cur"] = hp_cur[1]
	hud._setters["hp_max"] = hp_max[1]
	hud._setters["mp_cur"] = mp_cur[1]
	hud._setters["mp_max"] = mp_max[1]
	hud._setters["xp_cur"] = xp_cur[1]
	hud._setters["xp_need"] = xp_need[1]
	hud._setters["xp_text"] = xp_text[1]
	hud._setters["gold"] = gold[1]
	hud._setters["name"] = name_text[1]
	hud._setters["level"] = level_text[1]
	hud._setters["stats"] = stats_text[1]
	hud._setters["target_name"] = target_name[1]
	hud._setters["target_hp"] = target_hp[1]
	hud._setters["target_hp_max"] = target_hp_max[1]
	hud._setters["target_visible"] = target_visible[1]
	hud._setters["skills"] = skills[1]
	hud._setters["quests"] = quests[1]
	hud._setters["death"] = death_visible[1]
	hud._setters["theme"] = theme_state[1]

	# ---- 订阅本地玩家信号（player 变化时整体重订阅）----
	Hooks.useEffect(func():
		var p: Character = player_state[0]
		if p == null:
			return
		var attrs := CombatMath.get_attribute_set(p)

		var on_hp := func(c: int, m: int) -> void:
			hp_cur[1].call(c)
			hp_max[1].call(m)
		var on_mp := func(c: int, m: int) -> void:
			mp_cur[1].call(c)
			mp_max[1].call(m)
		var on_gold := func(total: int) -> void:
			gold[1].call(total)
		var on_level := func(_lv: int) -> void:
			level_text[1].call(hud._build_level_text(p))
		var on_class := func(_cid: String) -> void:
			level_text[1].call(hud._build_level_text(p))
		var on_exp := func(cur: int, need: int) -> void:
			xp_cur[1].call(cur)
			xp_need[1].call(need)
			xp_text[1].call(tr("经验 %d/%d") % [cur, need] if need > 0 else tr("已满级"))
		var on_quest := func() -> void:
			quests[1].call(hud._build_quest_entries(p))

		if attrs != null:
			on_hp.call(attrs.hp, attrs.max_hp)
			on_mp.call(attrs.mp, attrs.max_mp)
			attrs.hp_changed.connect(on_hp)
			attrs.mp_changed.connect(on_mp)
		on_gold.call(p.gold)
		on_level.call(p.level)
		on_exp.call(p.experience, LevelData.exp_to_next(p.level))
		on_quest.call()
		p.gold_changed.connect(on_gold)
		p.level_changed.connect(on_level)
		p.experience_changed.connect(on_exp)
		p.quest_state_changed.connect(on_quest)
		p.class_changed.connect(on_class)

		return func() -> void:
			if attrs != null and is_instance_valid(attrs):
				attrs.hp_changed.disconnect(on_hp)
				attrs.mp_changed.disconnect(on_mp)
			if is_instance_valid(p):
				p.gold_changed.disconnect(on_gold)
				p.level_changed.disconnect(on_level)
				p.experience_changed.disconnect(on_exp)
				p.quest_state_changed.disconnect(on_quest)
				p.class_changed.disconnect(on_class)
	, [player_state[0]])

	# ---- 组件树 ----
	return V.Control({
		"style": {"anchors_preset": Control.PRESET_FULL_RECT}.merged(IGNORE, true),
	}, [
		_player_frame(name_text[0], level_text[0], gold[0], stats_text[0],
			hp_cur[0], hp_max[0], mp_cur[0], mp_max[0],
			xp_cur[0], xp_need[0], xp_text[0]),
		_target_frame(target_visible[0], target_name[0], target_hp[0], target_hp_max[0]),
		_quest_tracker(quests[0]),
		_skill_bar(skills[0], overlay_refs, icon_refs),
		V.Label({
			"anchor_left": 0.5, "anchor_right": 0.5, "anchor_top": 1.0, "anchor_bottom": 1.0,
			"grow_horizontal": Control.GROW_DIRECTION_BOTH,
			"offset_left": -340.0, "offset_right": 340.0, "offset_top": -28.0, "offset_bottom": -6.0,
			"horizontal_alignment": 1,
			"text": "准星对准目标按左键选中并攻击 | 按住左键连续攻击 | Q 选择最近目标 | 1/2/3 释放职业技能",
			"style": {
				"modulate": Color(0.85, 0.85, 0.85, 0.9),
				"mouse_filter": Control.MOUSE_FILTER_IGNORE,
			},
		}),
		_death_panel(death_visible[0], hud),
	])


## 左上：玩家信息面板（原 PlayerFrame）
func _player_frame(p_name: String, p_level: String, p_gold: int, p_stats: String,
		hp_c: float, hp_m: float, mp_c: float, mp_m: float,
		xp_c: float, xp_n: float, xp_t: String) -> RUIVNode:
	var bars := _bars()
	return V.PanelContainer({
		"anchor_left": 0.0, "anchor_top": 0.0,
		"offset_left": 16.0, "offset_top": 16.0,
		"style": _panel_style(),
	}, [
		V.MarginContainer({"style": _margin_style(10)}, [
			V.VBoxContainer({"style": {"constants": {"separation": 4}}}, [
				V.HBoxContainer({"style": {"constants": {"separation": 12}}}, [
					V.Label({"text": p_name, "style": IGNORE}),
					V.Control({"style": {"size_flags_horizontal": Control.SIZE_EXPAND_FILL}}),
					V.Label({
						"text": tr("金币: %d") % p_gold,
						"style": {"modulate": Color(1.0, 0.85, 0.3, 1.0)}.merged(IGNORE, true),
					}),
					V.Label({
						"text": p_stats,
						"style": {"modulate": Color(0.55, 0.85, 1.0, 1.0)}.merged(IGNORE, true),
					}),
				]),
				V.Label({
					"text": p_level,
					"style": {"modulate": Color(0.7, 0.7, 0.7, 1.0)}.merged(IGNORE, true),
				}),
				V.ProgressBar({
					"max_value": hp_m, "value": hp_c, "show_percentage": false,
					"style": {
						"custom_minimum_size": Vector2(0, 14),
						"size_flags_horizontal": Control.SIZE_EXPAND_FILL,
						"mouse_filter": Control.MOUSE_FILTER_IGNORE,
						"styleboxes": {"background": bars["hp_bg"], "fill": bars["hp_fill"]},
					},
				}),
				V.ProgressBar({
					"max_value": mp_m, "value": mp_c, "show_percentage": false,
					"style": {
						"custom_minimum_size": Vector2(0, 14),
						"size_flags_horizontal": Control.SIZE_EXPAND_FILL,
						"mouse_filter": Control.MOUSE_FILTER_IGNORE,
						"styleboxes": {"background": bars["mp_bg"], "fill": bars["mp_fill"]},
					},
				}),
				V.ProgressBar({
					"max_value": maxf(1.0, xp_n), "value": xp_c, "show_percentage": false,
					"style": {
						"custom_minimum_size": Vector2(0, 12),
						"size_flags_horizontal": Control.SIZE_EXPAND_FILL,
						"mouse_filter": Control.MOUSE_FILTER_IGNORE,
						"styleboxes": {"background": bars["xp_bg"], "fill": bars["xp_fill"]},
					},
				}),
				V.Label({
					"text": xp_t,
					"horizontal_alignment": 1,
					"style": {"modulate": Color(0.95, 0.8, 0.35, 1.0)}.merged(IGNORE, true),
				}),
			]),
		]),
	])


## 顶部居中：目标框（原 TargetFrame）
func _target_frame(visible_flag: bool, t_name: String, t_hp: float, t_hp_max: float) -> RUIVNode:
	var bars := _bars()
	return V.PanelContainer({
		"anchor_left": 0.5, "anchor_right": 0.5, "anchor_top": 0.0, "anchor_bottom": 0.0,
		"grow_horizontal": Control.GROW_DIRECTION_BOTH,
		"offset_left": -160.0, "offset_right": 160.0, "offset_top": 16.0,
		"style": _panel_style().merged({
			"visible": visible_flag,
			"mouse_filter": Control.MOUSE_FILTER_IGNORE,
		}, true),
	}, [
		V.MarginContainer({"style": _margin_style(10)}, [
			V.VBoxContainer({"style": {"constants": {"separation": 4}}}, [
				V.Label({"text": t_name, "style": IGNORE}),
				V.ProgressBar({
					"max_value": t_hp_max, "value": t_hp, "show_percentage": false,
					"style": {
						"custom_minimum_size": Vector2(300, 14),
						"size_flags_horizontal": Control.SIZE_EXPAND_FILL,
						"mouse_filter": Control.MOUSE_FILTER_IGNORE,
						"styleboxes": {"background": bars["hp_bg"], "fill": bars["hp_fill"]},
					},
				}),
			]),
		]),
	])


## 右上：任务追踪（原 QuestTracker）
func _quest_tracker(entries: Array) -> RUIVNode:
	var rows := []
	for q in entries:
		var ready: bool = q["status"] == "ready"
		var name_color: Color = QUEST_READY if ready else QUEST_ACTIVE
		var prog_color: Color = QUEST_READY if ready else QUEST_PROGRESS
		rows.append(V.VBoxContainer({
			"key": str(q["id"]),
			"style": {"constants": {"separation": 2}, "mouse_filter": Control.MOUSE_FILTER_IGNORE},
		}, [
			V.Label({
				"text": "【%s】" % q["name"],
				"style": {"modulate": name_color, "mouse_filter": Control.MOUSE_FILTER_IGNORE},
			}),
			V.Label({
				"text": str(q["progress"]),
				"style": {"modulate": prog_color, "mouse_filter": Control.MOUSE_FILTER_IGNORE},
			}),
		]))
	return V.PanelContainer({
		"anchor_left": 1.0, "anchor_right": 1.0, "anchor_top": 0.0, "anchor_bottom": 0.0,
		"grow_horizontal": Control.GROW_DIRECTION_BEGIN,
		"offset_right": -16.0, "offset_top": 16.0,
		"style": _panel_style().merged({
			"visible": not entries.is_empty(),
			"mouse_filter": Control.MOUSE_FILTER_IGNORE,
		}, true),
	}, [
		V.MarginContainer({"style": _margin_style(10)}, [
			V.VBoxContainer({"style": {"constants": {"separation": 4}}}, [
				V.Label({
					"text": tr("任务"),
					"style": {"modulate": QUEST_READY, "mouse_filter": Control.MOUSE_FILTER_IGNORE},
				}),
				V.HSeparator({"style": {"constants": {"separation": 4}}}),
				V.VBoxContainer({"style": {"constants": {"separation": 6}}}, rows),
			]),
		]),
	])


## 底部居中：技能栏（原 SkillBar）
func _skill_bar(skill_list: Array, overlay_refs: Array, icon_refs: Array) -> RUIVNode:
	var slots := []
	for i in SKILL_BAR_SLOTS:
		var skill: Dictionary = skill_list[i] if i < skill_list.size() else {}
		var icon: Texture2D = skill.get("icon")
		slots.append(V.Panel({
			"style": _panel_style().merged({
				"custom_minimum_size": SKILL_SLOT_SIZE,
				"mouse_filter": Control.MOUSE_FILTER_IGNORE,
			}, true),
		}, [
			V.MarginContainer({
				"anchor_left": 0.0, "anchor_top": 0.0, "anchor_right": 1.0, "anchor_bottom": 1.0,
				"offset_left": 2.0, "offset_top": 2.0, "offset_right": -2.0, "offset_bottom": -2.0,
				"style": _margin_style(6),
			}, [
				V.HBoxContainer({"style": {"constants": {"separation": 6}}}, [
					V.TextureRect({
						"texture": icon,
						"expand_mode": 1,
						"stretch_mode": 5,
						"style": {
							"custom_minimum_size": SKILL_ICON_SIZE,
							"size_flags_vertical": Control.SIZE_SHRINK_CENTER,
							"mouse_filter": Control.MOUSE_FILTER_IGNORE,
						},
						"ref": icon_refs[i],
					}),
					V.VBoxContainer({
						"style": {"constants": {"separation": 0}, "mouse_filter": Control.MOUSE_FILTER_IGNORE},
					}, [
						V.Label({
							"text": KEY_LABELS[i],
							"style": {"modulate": Color(1.0, 0.9, 0.5, 1.0), "mouse_filter": Control.MOUSE_FILTER_IGNORE},
						}),
						V.Label({
							"text": str(skill.get("name", "-")),
							"style": IGNORE,
						}),
					]),
				]),
			]),
			# 冷却遮罩：绝对定位覆盖槽体（原 CooldownOverlay），后添加故绘制在上层
			V.ColorRect({
				"offset_left": 2.0, "offset_top": 2.0, "offset_right": 94.0, "offset_bottom": 54.0,
				"color": Color(0, 0, 0, 0.65),
				"style": IGNORE,
				"ref": overlay_refs[i],
			}),
		]))
	return V.HBoxContainer({
		"anchor_left": 0.5, "anchor_right": 0.5, "anchor_top": 1.0, "anchor_bottom": 1.0,
		"grow_horizontal": Control.GROW_DIRECTION_BOTH,
		"offset_bottom": -36.0,
		"style": {"constants": {"separation": 8}, "mouse_filter": Control.MOUSE_FILTER_IGNORE},
		"alignment": 1,
	}, slots)


## 死亡面板（原 DeathPanel）
func _death_panel(visible_flag: bool, hud: Object) -> RUIVNode:
	return V.PanelContainer({
		"anchor_left": 0.0, "anchor_top": 0.0, "anchor_right": 1.0, "anchor_bottom": 1.0,
		"style": {
			"bg_color": DEATH_BG,
			"visible": visible_flag,
		},
	}, [
		V.CenterContainer({}, [
			V.VBoxContainer({
				"alignment": 1,
				"style": {
					"custom_minimum_size": Vector2(280, 0),
					"constants": {"separation": 16},
					"mouse_filter": Control.MOUSE_FILTER_IGNORE,
				},
			}, [
				V.Label({
					"text": tr("你死了"),
					"horizontal_alignment": 1,
					"style": {"font_sizes": {"font_size": 32}},
				}),
				V.Label({
					"text": tr("别灰心，回村满血再来"),
					"horizontal_alignment": 1,
					"style": {"modulate": Color(0.75, 0.75, 0.75, 1.0), "mouse_filter": Control.MOUSE_FILTER_IGNORE},
				}),
				V.Button({
					"text": tr("释放灵魂（回村复活）"),
					"onPressed": func() -> void:
						hud._on_release_pressed(),
					"style": _button_styles(),
				}),
			]),
		]),
	])
