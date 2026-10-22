@tool
extends ProgrammaticTheme
class_name BaseGameTheme
## M22：双主题共享样式骨架（ThemeGen 方案，选型见 AGENTS.md 铁律零）。
##
## 职责：
##   · 把 assets/ui/themes/<id>/ 的 ImageGen 纹理组装成官方 Theme 资源
##   · Panel/PanelContainer 九宫格、Button 四态、Label、语义变体（PrimaryButton/TitleLabel）
##   · 血条外壳纹理以自定义 icon 条目 "GameTheme/bar_frame" 存进主题
##
## 约定：
##   · 子主题脚本只覆盖 theme_id() 返回 "wow"/"sc2"（将来 "genshin"）
##   · 纹理缺失（未生成/被删）自动回退 StyleBoxFlat——主题永远可生成
##   · 生成产物 themes/generated/<id>_theme.tres 是唯一运行时依赖（导出后不带本插件也能跑）

## 主题主色（文字点缀/回退色块用；与原 ThemeManager.THEME_ACCENTS 一致）
const ACCENTS := {
	"wow": Color(0.85, 0.68, 0.25),   # 金
	"sc2": Color(0.30, 0.85, 0.95),   # 青
}

## 面板九宫格参数（panel_small 1024x768 边框约 60px；
## content margin 78 对大面板太厚会把内容挤出框，56 实测合适）
const PANEL_TEX_MARGIN := 60.0
const PANEL_CONTENT_MARGIN := 56.0
## 按钮九宫格参数（按钮显示高度约 36-40px，512x256 素材边框等比 ≈10px，
## 超过按钮高度一半会画爆）
const BUTTON_TEX_MARGIN := 10.0


## 子类覆盖：返回主题 id（"wow" / "sc2" / 将来 "genshin"）
func theme_id() -> String:
	return "wow"


func setup() -> void:
	var id := theme_id()
	set_save_path("res://themes/generated/%s_theme.tres" % id)
	set_theme_generator(_generate)


func _generate() -> void:
	_define_game_theme(theme_id())


# ---- 样式定义 ----

func _define_game_theme(id: String) -> void:
	var accent: Color = ACCENTS.get(id, Color.WHITE)
	var tex_panel := _tex(id, "panel_small")
	var tex_panel_large := _tex(id, "panel_large")
	var tex_btn := _tex(id, "button_normal")
	var tex_btn_primary := _tex(id, "button_primary")

	# ---- 面板（Panel / PanelContainer 同款九宫格）----
	var panel_box := _panel_box(tex_panel, accent)
	define_style("Panel", {"panel": panel_box})
	define_style("PanelContainer", {"panel": panel_box})
	# 大面板变体（背包/商店等大窗口可选用）
	define_variant_style("LargePanel", "Panel", {
		"panel": _panel_box(tex_panel_large, accent) if tex_panel_large != null else panel_box,
	})

	# ---- 按钮（normal 用普通按钮纹理；hover/pressed 用主按钮纹理做高亮反馈）----
	var btn_normal := _button_box(tex_btn, accent, false)
	var btn_hover := _button_box(tex_btn_primary, accent, false) \
			if tex_btn_primary != null else _button_box(tex_btn, accent, true)
	var btn_pressed := _button_box(tex_btn_primary, accent, true) \
			if tex_btn_primary != null else _button_box(tex_btn, accent, true)
	define_style("Button", {
		"normal": btn_normal,
		"hover": btn_hover,
		"pressed": btn_pressed,
		"disabled": _button_box(tex_btn, Color(0.6, 0.6, 0.6), false),
		"focus": stylebox_empty({}),
		"font_color": Color(0.95, 0.93, 0.86),
		"font_hover_color": Color(1, 1, 1),
		"font_pressed_color": Color(0.9, 0.88, 0.8),
		"font_disabled_color": Color(0.55, 0.55, 0.55),
		"font_size": 15,
	})

	# ---- 语义变体：主按钮（确认/购买等高亮动作）----
	define_variant_style("PrimaryButton", "Button", {
		"normal": _button_box(tex_btn_primary, accent, false) if tex_btn_primary != null else btn_hover,
	})

	# ---- 标签 ----
	define_style("Label", {
		"font_color": Color(0.92, 0.92, 0.92),
		"font_size": 15,
	})
	define_variant_style("TitleLabel", "Label", {
		"font_color": accent,
		"font_size": 22,
	})

	# ---- 进度条（经验条等；血条 HUD 走自定义外壳，见下）----
	define_style("ProgressBar", {
		"background": stylebox_flat({
			"bg_color": Color(0.10, 0.10, 0.14, 0.9),
			"corner_radius_": corner_radius(4),
		}),
		"fill": stylebox_flat({
			"bg_color": accent,
			"corner_radius_": corner_radius(4),
		}),
	})

	# ---- 语义变体：行卡片（任务列表行等紧凑小元素，扁平底+主题色细边）----
	define_variant_style("RowCard", "PanelContainer", {
		"panel": stylebox_flat({
			"bg_color": Color(0.10, 0.10, 0.14, 0.9),
			"border_color": Color(accent.r * 0.55, accent.g * 0.55, accent.b * 0.55),
			"border_width_": border_width(1),
			"corner_radius_": corner_radius(4),
			"content_margins_": content_margins(8, 6),
		}),
	})

	# ---- 自定义条目：血条外壳纹理（HUD RUI 经 ThemeManager 读取）----
	var tex_bar := _tex(id, "bar_frame")
	if tex_bar != null:
		current_theme.add_type("GameTheme")
		current_theme.set_icon("bar_frame", "GameTheme", tex_bar)


# ---- 工具 ----

func _tex(id: String, role: String) -> Texture2D:
	var path := "res://assets/ui/themes/%s/%s_%s.png" % [id, id, role]
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## 面板九宫格（纹理缺失时回退深色色块+主题色描边）
func _panel_box(tex: Texture2D, accent: Color) -> Dictionary:
	if tex != null:
		return stylebox_texture({
			"texture": tex,
			"texture_margins_": texture_margins(PANEL_TEX_MARGIN),
			"content_margins_": content_margins(PANEL_CONTENT_MARGIN, PANEL_CONTENT_MARGIN * 0.6),
		})
	return stylebox_flat({
		"bg_color": Color(0.08, 0.08, 0.12, 0.92),
		"border_color": accent,
		"border_width_": border_width(2),
		"corner_radius_": corner_radius(6),
	})


## 按钮九宫格（darken=true 时整体压暗，用于 pressed 态；纹理缺失回退色块）
func _button_box(tex: Texture2D, accent: Color, darken: bool) -> Dictionary:
	if tex != null:
		var tint := Color(0.78, 0.78, 0.78) if darken else Color(1, 1, 1)
		return stylebox_texture({
			"texture": tex,
			"modulate_color": tint,
			"texture_margins_": texture_margins(BUTTON_TEX_MARGIN),
			"content_margins_": content_margins(14, 7),
		})
	return stylebox_flat({
		"bg_color": Color(0.16, 0.16, 0.2) if darken else Color(0.22, 0.22, 0.28),
		"border_color": accent,
		"border_width_": border_width(2),
		"corner_radius_": corner_radius(6),
		"content_margins_": content_margins(14, 7),
	})
