class_name CoordReadout
extends PanelContainer

## 屏幕常驻坐标读数（M49）。
##
## 两行：
##   ① 世界坐标 X / Y / Z（米，原点 = 星球球心）
##   ② 球面专属换算：R = 到球心距离、地面 = 该方向地形网格表面半径、离地 = R - 地面
##      （离地正数 = 悬空，负数 = 陷进地里，是排查「悬空/钻地」最直接的数）
##
## 为什么不进 Reactive HUD 视图：坐标每帧都变，走 hooks state 会每帧触发整棵 HUD
## 重渲染。这与技能栏冷却遮罩是同一套「高频数据命令式直写」策略（见 hud.gd 注释）。
##
## 地面高度取 Planet.mesh_height()（顶点缓存三角插值），与渲染网格逐三角形一致，
## 不用解析式——解析式在村区返回 0，会把站在广场上的玩家误判成「悬空 2 米」。

## 位置不写死：每 0.5s 量一次左上玩家面板的实际底边，贴在它下面 8px。
## 换主题时玩家面板高度会变，写死 offset 迟早压住（C0：不凑数，算相对值）。
const ANCHOR_GAP := 8.0
const ANCHOR_RECHECK := 0.5
const PAD := Vector2(10.0, 6.0)

var player: Node3D = null

var _pos_label: Label
var _detail_label: Label
var _anchor: Control = null
var _anchor_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(16.0, 192.0) # 首帧兜底，之后由 _follow_player_frame 接管
	add_theme_stylebox_override("panel", _bg())

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	add_child(box)

	_pos_label = _make_label(box, 15, Color(1.0, 1.0, 1.0, 0.96))
	_detail_label = _make_label(box, 12, Color(0.75, 0.81, 0.88, 0.9))
	_pos_label.text = "X        -   Y        -   Z        -"
	_detail_label.text = "等待玩家…"


func _process(delta: float) -> void:
	_follow_player_frame(delta)
	var p := player
	if p == null or not is_instance_valid(p):
		_pos_label.text = "X        -   Y        -   Z        -"
		_detail_label.text = "等待玩家…"
		return
	var wpos: Vector3 = p.global_position
	# NaN 闸：位置被写坏时 atan2/normalize 会连锁刷屏，这里直接显示占位符
	if not (is_finite(wpos.x) and is_finite(wpos.y) and is_finite(wpos.z)):
		_pos_label.text = "X      NaN   Y      NaN   Z      NaN"
		_detail_label.text = "位置非有限值（有代码写坏了坐标）"
		return
	var r: float = wpos.length()
	var up: Vector3 = Planet.up_at(wpos)
	# mesh_height 返回的是「相对 RADIUS 的高度」，不是半径 —— 必须加 RADIUS 才是到球心距离
	var ground_r: float = Planet.RADIUS + Planet.mesh_height(up)
	var alt: float = r - ground_r
	_pos_label.text = "X %8.1f   Y %8.1f   Z %8.1f" % [wpos.x, wpos.y, wpos.z]
	_detail_label.text = "R %.1f   地面 %.1f   离地 %+.1f m" % [r, ground_r, alt]


## 贴着左上玩家面板的底边。RUI 重渲染会重建节点，所以定期重查引用。
func _follow_player_frame(delta: float) -> void:
	_anchor_timer -= delta
	if _anchor == null or not is_instance_valid(_anchor) or _anchor_timer <= 0.0:
		_anchor = _find_player_frame()
		_anchor_timer = ANCHOR_RECHECK
	if _anchor == null:
		return
	var target_y: float = _anchor.get_global_rect().end.y + ANCHOR_GAP
	if absf(position.y - target_y) > 0.5:
		position.y = target_y


## 玩家面板的特征：靠左上角（x/y 都 < 64）、有实际高度、宽度最大。
func _find_player_frame() -> Control:
	var hud := get_parent()
	if hud == null:
		return null
	var best: Control = null
	for c in hud.find_children("*", "PanelContainer", true, false):
		var pc := c as Control
		if pc == null or pc == self or not pc.is_visible_in_tree():
			continue
		var r := pc.get_global_rect()
		if r.position.x > 64.0 or r.position.y > 64.0 or r.size.y < 40.0:
			continue
		if best == null or r.size.x > best.get_global_rect().size.x:
			best = pc
	return best


func _make_label(parent: Node, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l


func _bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.06, 0.62)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = PAD.x
	sb.content_margin_right = PAD.x
	sb.content_margin_top = PAD.y
	sb.content_margin_bottom = PAD.y
	return sb
