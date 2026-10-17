extends SceneTree

## M5 资产生成工具（一次性运行）：生成 12 个技能图标（64x64 扁平风，圆角底 + 白色符文）。
## 运行方式：godot --headless --script tools/generate_m5_assets.gd
## 之后需跑一次 --import 让 Godot 识别新 PNG。

const ICON_DIR := "res://assets/skills/icons/"
const SIZE := 64

## file=文件名, bg=底色, glyph=白色符文形状
const ICONS := [
	{"file": "heavy_strike.png", "bg": Color(0.63, 0.19, 0.16), "glyph": "slash"},
	{"file": "whirlwind.png", "bg": Color(0.75, 0.44, 0.19), "glyph": "ring"},
	{"file": "shield_wall.png", "bg": Color(0.44, 0.47, 0.5), "glyph": "shield"},
	{"file": "execute.png", "bg": Color(0.82, 0.13, 0.13), "glyph": "double_slash"},
	{"file": "fireball.png", "bg": Color(0.88, 0.31, 0.13), "glyph": "circle"},
	{"file": "frostbolt.png", "bg": Color(0.25, 0.63, 0.88), "glyph": "asterisk"},
	{"file": "arcane_blast.png", "bg": Color(0.56, 0.38, 0.82), "glyph": "ring"},
	{"file": "arcane_power.png", "bg": Color(0.72, 0.55, 0.9), "glyph": "triangle"},
	{"file": "smite.png", "bg": Color(0.85, 0.72, 0.2), "glyph": "circle"},
	{"file": "flash_heal.png", "bg": Color(0.25, 0.7, 0.42), "glyph": "cross"},
	{"file": "renew.png", "bg": Color(0.4, 0.78, 0.58), "glyph": "dots"},
	{"file": "holy_nova.png", "bg": Color(0.85, 0.78, 0.45), "glyph": "star"},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ICON_DIR)
	var ok := true
	for spec in ICONS:
		ok = _generate_icon(spec) and ok
	if ok:
		print("generate_m5_assets: 图标全部完成（%d 个）" % ICONS.size())
		quit(0)
	else:
		push_error("generate_m5_assets: 存在失败项")
		quit(1)


func _generate_icon(spec: Dictionary) -> bool:
	var image := Image.create(SIZE, SIZE, true, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(0, 0, SIZE, SIZE), Color(0, 0, 0, 0))
	var bg: Color = spec["bg"]
	var glyph: String = spec["glyph"]
	var white := Color(1.0, 1.0, 1.0, 1.0)
	var c := SIZE / 2.0
	for y in SIZE:
		for x in SIZE:
			if not _in_rounded_square(float(x) + 0.5, float(y) + 0.5, c):
				continue
			if _in_glyph(glyph, float(x) + 0.5, float(y) + 0.5, c):
				image.set_pixel(x, y, white)
			else:
				image.set_pixel(x, y, bg)
	var path: String = ICON_DIR + String(spec["file"])
	var err := image.save_png(path)
	if err != OK:
		push_error("保存图标失败: " + path)
		return false
	print("已生成图标: " + path)
	return true


## 圆角方形底板（四角切半径 12 的弧）
func _in_rounded_square(px: float, py: float, c: float) -> bool:
	var half := c - 1.0
	if absf(px - c) <= half - 12.0 or absf(py - c) <= half - 12.0:
		return absf(px - c) <= half and absf(py - c) <= half
	var dx := absf(px - c) - (half - 12.0)
	var dy := absf(py - c) - (half - 12.0)
	return dx * dx + dy * dy <= 12.0 * 12.0


func _in_glyph(glyph: String, px: float, py: float, c: float) -> bool:
	var dx := px - c
	var dy := py - c
	match glyph:
		"circle":
			return dx * dx + dy * dy <= 13.0 * 13.0
		"ring":
			var d2 := dx * dx + dy * dy
			return d2 <= 14.0 * 14.0 and d2 >= 10.0 * 10.0
		"slash":
			return _dist_to_segment(px, py, c - 13, c + 13, c + 13, c - 13) <= 4.0
		"double_slash":
			return _dist_to_segment(px, py, c - 14, c + 12, c + 10, c - 14) <= 3.5 \
				or _dist_to_segment(px, py, c - 6, c + 14, c + 14, c - 4) <= 3.5
		"triangle":
			# 向上三角形：顶点 (c, c-14)，底边 y=c+12
			return py >= c - 14.0 and py <= c + 12.0 and absf(dx) <= (py - (c - 14.0)) * 0.8
		"cross":
			return (absf(dx) <= 4.0 and absf(dy) <= 14.0) or (absf(dx) <= 14.0 and absf(dy) <= 4.0)
		"dots":
			for oy in [-13.0, 0.0, 13.0]:
				if dx * dx + (dy - oy) * (dy - oy) <= 4.5 * 4.5:
					return true
			return false
		"asterisk":
			# 三条 60° 线穿过中心
			return _dist_to_segment(px, py, c - 15, c - 8.7, c + 15, c + 8.7) <= 3.0 \
				or _dist_to_segment(px, py, c - 15, c + 8.7, c + 15, c - 8.7) <= 3.0 \
				or absf(dx) <= 3.0 and absf(dy) <= 15.0
		"shield":
			# 上宽下尖的盾形
			if py < c - 12.0 or py > c + 15.0:
				return false
			var t := (py - (c - 12.0)) / 27.0
			var half_width := 15.0 * (1.0 - t * t * 0.95)
			return absf(dx) <= half_width
		"star":
			return absf(dx) / 16.0 + absf(dy) / 16.0 <= 1.0
		_:
			return false


func _dist_to_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	var abx := bx - ax
	var aby := by - ay
	var length_sq := abx * abx + aby * aby
	if length_sq <= 0.0:
		return sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay))
	var t := clampf(((px - ax) * abx + (py - ay) * aby) / length_sq, 0.0, 1.0)
	var cx := ax + abx * t
	var cy := ay + aby * t
	return sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
