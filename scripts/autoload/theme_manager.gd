extends Node
## M22：主题切换器（ThemeGen 方案，选型依据见 AGENTS.md 铁律零）。
##
## 架构（官方最佳实践）：
##   · 主题样式定义在 themes/<id>_theme.gd（ThemeGen 脚本），生成产物
##     themes/generated/<id>_theme.tres 是唯一样式来源——新增主题零代码
##   · 全局切换：get_tree().root.theme 一行，级联所有普通 Control 树
##     （CanvasLayer 下的 HUD 不吃级联，RUI 视图经下方 getter 直取，见 hud_rui_view.gd）
##   · 本类只负责：切换 + user://settings.cfg 持久化 + theme_changed 广播
##     + 给 HUD RUI 提供主题数据（panel/button/bar_frame）
##
## 约定：生成产物缺失（未生成/被删）时自动回退 StyleBoxFlat 色块——永远可运行。

signal theme_changed(theme_id: String)

const SETTINGS_PATH := "user://settings.cfg"
const THEME_SECTION := "ui"
const THEME_KEY := "theme"

const THEMES := ["wow", "sc2"]
const THEME_RESOURCE_PATH := "res://themes/generated/%s_theme.tres"

## 主题主色调（文字点缀/回退色块；与 themes/base_theme.gd ACCENTS 保持一致）
const THEME_ACCENTS := {
	"wow": Color(0.85, 0.68, 0.25),   # 金
	"sc2": Color(0.30, 0.85, 0.95),   # 青
}

var current_theme: String = "wow"

var _theme_res: Theme = null  # 当前生成的 Theme 资源（缺失为 null → 回退）


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var saved := String(cfg.get_value(THEME_SECTION, THEME_KEY, "wow"))
		if saved in THEMES:
			current_theme = saved
	# 动态实例化的 CanvasLayer UI（背包/商店/任务等）进树时自动挂主题
	get_tree().node_added.connect(_on_node_added)
	_apply()


## 应用主题：
##   1. root.theme —— 级联全部普通 Control 树
##   2. 遍历所有 CanvasLayer 下的根 Control 单独挂载——
##      官方坑：theme 只沿 Control/Window 父链传播，CanvasLayer 不转发级联
func _apply() -> void:
	var path := THEME_RESOURCE_PATH % current_theme
	_theme_res = load(path) if ResourceLoader.exists(path) else null
	get_tree().root.theme = _theme_res
	if is_inside_tree():
		_apply_to_layers(get_tree().root)


## 递归给每个 CanvasLayer 的直接 Control 子节点挂当前主题
func _apply_to_layers(node: Node) -> void:
	if node is CanvasLayer:
		for child in node.get_children():
			if child is Control:
				(child as Control).theme = _theme_res
	for child in node.get_children():
		_apply_to_layers(child)


## 新节点进树：CanvasLayer 下的顶层 Control 自动挂当前主题（动态 UI 全覆盖）
func _on_node_added(node: Node) -> void:
	if _theme_res != null and node is Control and node.get_parent() is CanvasLayer:
		(node as Control).theme = _theme_res


func theme_id() -> String:
	return current_theme


## 当前主题的 Theme 资源（需要整树级联的场景用）
func theme_resource() -> Theme:
	return _theme_res


func accent_color() -> Color:
	return THEME_ACCENTS.get(current_theme, Color.WHITE)


## 面板九宫格（HUD RUI 玩家框/目标框/任务框用；数据源=生成的主题）
func panel_stylebox() -> StyleBox:
	if _theme_res != null and _theme_res.has_stylebox("panel", "PanelContainer"):
		return _theme_res.get_stylebox("panel", "PanelContainer")
	return _flat_fallback(Color(0.08, 0.08, 0.12, 0.85), accent_color())


## 按钮样式（state: normal / primary；数据源=生成的主题）
func button_stylebox(state: String = "normal") -> StyleBox:
	if _theme_res != null:
		var type := "PrimaryButton" if state == "primary" else "Button"
		if _theme_res.has_stylebox("normal", type):
			return _theme_res.get_stylebox("normal", type)
	var primary := state == "primary"
	return _flat_fallback(
		Color(0.35, 0.28, 0.12, 1.0) if primary else Color(0.16, 0.16, 0.2, 1.0),
		accent_color())


## 血条外壳纹理（M21 验证：14px 高条用整张拉伸，不能九宫格）
func bar_frame_texture() -> Texture2D:
	if _theme_res != null and _theme_res.has_icon("bar_frame", "GameTheme"):
		return _theme_res.get_icon("bar_frame", "GameTheme")
	return null


func set_theme(theme_id: String) -> void:
	if not (theme_id in THEMES) or theme_id == current_theme:
		return
	current_theme = theme_id
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 读旧值合并（失败不阻塞）
	cfg.set_value(THEME_SECTION, THEME_KEY, theme_id)
	cfg.save(SETTINGS_PATH)
	_apply()
	theme_changed.emit(theme_id)


func toggle_theme() -> String:
	set_theme(THEMES[1] if current_theme == THEMES[0] else THEMES[0])
	return current_theme


# ---- 内部 ----

## 主题产物缺失时的回退色块（观感接近旧版）
func _flat_fallback(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	return sb
