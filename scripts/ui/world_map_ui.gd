class_name WorldMapUI
extends Control

## M37：世界地图（M 键开关）。
##
## 架构：一张俯视 2D 地图，底图由 Terrain3D 高度实时采样生成，
## 叠加层用 _draw() 画地标/玩家/队友/罗盘/比例尺。
##
## 为什么不用 SubViewport 相机俯拍：
##   俯拍相机在雾中森林里根本看不清（雾深度 15~200m 挡住一切），
##   且每帧多一个渲染 pass。改为"高度→颜色"的合成底图，
##   既能反映真实起伏（丘陵/平地/铁轨带），又零运行时代价。
##
## 世界→地图坐标：地图世界范围固定 MAP_MIN_X~MAP_MAX_X / MAP_MIN_Z~MAP_MAX_Z，
## x 向右、z 向下（俯视惯例：北 = -Z，屏幕上方为北）。
##
## 铁律（沿用 M35）：地形采样必须查 is_finite/NaN —— 超出数据区的
## get_height 返回 NaN，NaN 参与插值会把整张图染成花屏。

## M39：任务点/怪物拉到 1500m 外（世界 z≈-1550~-1712），地图必须覆盖到。
## MAP_MIN_Z -760 → -1800。地图纵向跨度从 1100m 变 2140m，为保持底图
## 每像素代表的米数不变（8m/px），TEX_RES 同步 190 → 370。
const MAP_MIN_X := -760.0
const MAP_MAX_X := 760.0
const MAP_MIN_Z := -1800.0
const MAP_MAX_Z := 340.0

# ===== 【M47 球面】圆盘投影（方位等距 azimuthal equidistant）=====
# 地图不再是矩形平面贴图，而是一张**圆盘**：
#   圆心 = 本地玩家所在方向
#   圆周 = 它的对跖点（角距 180°）
# 选方位等距的理由：**沿半径的距离是线性的**，所以比例尺、测距、
# 同心圆网格全都直观，而且"地形是圆的"一眼可见。
# 极点每次打开地图时按玩家位置重算（玩家永远在圆心）。
const DISK_MARGIN := 0.94          ## 圆盘占控件的比例（留边不顶满）
var _pole := Vector3.UP
var _e1 := Vector3.RIGHT
var _e2 := Vector3.BACK

## 底图像素分辨率（正方形采样网格）
const TEX_RES := 370

## ---- 地标（世界坐标 → 地图标注）----
## label_offset：标签相对标记点的偏移，避免密集区标签重叠。
const LANDMARKS := [
	{"pos": Vector3(0.0, 0.0, -130.0), "name": "新手村", "color": Color(0.95, 0.82, 0.35), "star": true, "off": Vector2(-30.0, -22.0)},
	{"pos": Vector3(0.0, 0.0, -100.0), "name": "气球训练场", "color": Color(0.90, 0.35, 0.55), "star": false, "off": Vector2(12.0, 20.0)},
	{"pos": Vector3(170.0, 0.0, -300.0), "name": "家园", "color": Color(0.55, 0.85, 0.55), "star": true, "off": Vector2(14.0, -10.0)},
	{"pos": Vector3(0.0, 0.0, 80.0), "name": "林海铁轨", "color": Color(0.62, 0.58, 0.52), "star": false, "off": Vector2(-26.0, 20.0)},
	{"pos": Vector3(1100.0, 210.0, -1700.0), "name": "浮空城区", "color": Color(0.45, 0.75, 0.95), "star": true, "off": Vector2(0.0, 0.0)},
	{"pos": Vector3(0.0, 0.0, -1650.0), "name": "狩猎区", "color": Color(0.90, 0.42, 0.32), "star": true, "off": Vector2(14.0, -10.0)},
]

const RAIL_Z := 80.0
const RAIL_X_MIN := -700.0
const RAIL_X_MAX := 620.0

## 底图配色（按高度分层）
const COLOR_LOW := Color(0.16, 0.26, 0.18) ## 低地/林地
const COLOR_MID := Color(0.28, 0.36, 0.24) ## 丘陵
const COLOR_HIGH := Color(0.45, 0.42, 0.32) ## 高地
const COLOR_FLAT := Color(0.32, 0.34, 0.24) ## 新手村平地
const COLOR_UNKNOWN := Color(0.07, 0.07, 0.10) ## 无数据区（NaN）
const COLOR_RAIL := Color(0.50, 0.45, 0.38) ## 铁轨带

const MAP_BG := Color(0.03, 0.03, 0.05, 0.90)

@onready var _map_rect: Control = $Center/MapFrame/MapArea
@onready var _map_view: Control = $Center/MapFrame/MapArea/MapView
@onready var _title_label: Label = $Center/MapFrame/Header/Title
@onready var _coords_label: Label = $Center/MapFrame/Header/Coords
@onready var _hint_label: Label = $Center/MapFrame/Footer/Hint

var _terrain: Terrain3D = null
var _tex: ImageTexture = null
var _map_size := Vector2(620.0, 620.0)

## 本地玩家 + 其他玩家（每帧刷新）
var _local_player: Node3D = null
var _players_root: Node = null
var _level: Node = null


func _ready() -> void:
	visible = false
	set_process(false)
	_map_view.draw.connect(_draw_map)
	# 【M47】Panel 默认带深色矩形底，会把圆盘套进方框里。
	# 换成空样式，让圆盘直接浮在暗化背景上 —— 地图本身就是圆的。
	var area := get_node_or_null("Center/MapFrame/MapArea") as Panel
	if area != null:
		area.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	resized.connect(_update_layout)
	call_deferred("_update_layout")


func _update_layout() -> void:
	var avail := size - Vector2(80.0, 80.0)
	var side := minf(avail.x, avail.y)
	side = maxf(side, 260.0)
	_map_size = Vector2(side, side)
	_map_rect.size = _map_size
	_map_view.size = _map_size
	_map_view.queue_redraw()


## 打开地图（由 level.gd 调用）
func open_map(level: Node) -> void:
	_level = level
	_players_root = level.get_node_or_null("PlayersContainer")
	_terrain = _find_terrain(level)
	_build_terrain_texture()
	_update_layout()
	visible = true
	set_process(true)
	_map_view.queue_redraw()


## 关闭地图
func close_map() -> void:
	visible = false
	set_process(false)


func is_map_visible() -> bool:
	return visible


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_player_markers()
	_map_view.queue_redraw()


## ---- 地形采样 ----

func _find_terrain(level: Node) -> Terrain3D:
	var starter := level.get_node_or_null("Environment/TerrainStarter")
	if starter == null:
		return null
	return starter.get("terrain") as Terrain3D


## 圆盘的极点 = 玩家所在方向；圆周 = 对跖点。
## 每次开图重算，所以玩家永远在圆心。
func _ensure_pole() -> void:
	_update_player_markers()
	var pos := Vector3.ZERO
	if _local_player != null:
		pos = _local_player.global_position
	if pos.length_squared() < 1.0:
		pos = Planet.surface_pos(Planet.dir_of(0, 0.5, 0.5))
	_pole = Planet.up_at(pos)
	# 切平面正交基：e1/e2 都在过极点的切平面里，用来表示方位角
	var b := Planet.align_basis(_pole, Vector3.FORWARD)
	_e1 = b.x
	_e2 = b.z


## 方向 → 圆盘归一化坐标（-1..1，圆心 0，圆周 1）
func _disk_of(dir: Vector3) -> Vector2:
	if dir.length_squared() < 0.000001:
		return Vector2.ZERO
	var d := dir.normalized()
	var c := clampf(d.dot(_pole), -1.0, 1.0)
	var alpha := acos(c)                     # 与圆心的角距 0..π
	var t := d - _pole * c                   # 切平面分量 → 方位角
	if t.length_squared() < 1e-10:
		return Vector2.ZERO
	t = t.normalized()
	var theta := atan2(t.dot(_e2), t.dot(_e1))
	return Vector2(cos(theta), sin(theta)) * (alpha / PI)


## 圆盘坐标（-1..1）→ 方向。与 _disk_of 严格互逆。
func _dir_of_disk(uv: Vector2) -> Vector3:
	var rr := uv.length()
	var alpha := rr * PI
	var theta := atan2(uv.y, uv.x)
	var d: Vector3 = _pole * cos(alpha) \
		+ (_e1 * cos(theta) + _e2 * sin(theta)) * sin(alpha)
	return d.normalized() if d.length_squared() > 1e-10 else _pole


## 高度采样生成**圆盘**底图。圆外全透明，所以画出来一定是个圆。
func _build_terrain_texture() -> void:
	_ensure_pole()
	var img := Image.create(TEX_RES, TEX_RES, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var has_ocean := Planet.has_ocean()
	var denom := float(TEX_RES - 1)
	for j in TEX_RES:
		var v := float(j) / denom * 2.0 - 1.0
		for i in TEX_RES:
			var u := float(i) / denom * 2.0 - 1.0
			var uv := Vector2(u, v)
			if uv.length() > 1.0:
				continue                    # 圆外留透明
			var h: float = Planet.mesh_height(_dir_of_disk(uv))
			if not is_finite(h):
				continue
			var col: Color
			if has_ocean and h < 0.0:
				# 海洋：越深越暗
				col = Color(0.05, 0.16, 0.34).lerp(Color(0.02, 0.07, 0.18),
					clampf(-h / 40.0, 0.0, 1.0))
			elif h < -1.5:
				col = COLOR_LOW
			elif h < 2.5:
				col = COLOR_MID
			else:
				col = COLOR_HIGH
			# 圆盘边缘轻微压暗，视觉上更有球感
			var edge := clampf((uv.length() - 0.82) / 0.18, 0.0, 1.0)
			col = col.darkened(edge * 0.45)
			img.set_pixel(i, j, col)
	_tex = ImageTexture.create_from_image(img)


## ---- 绘制 ----

func _draw_map() -> void:
	var c := _map_view
	var ts := c.size
	var r := _disk_radius(ts)
	var center := ts * 0.5
	# 【M47】底板也画成圆：地图本身就是个圆盘，圆外留透明，
	# 不再套一个黑矩形（用户要求"地图要是圆的"，不是"圆画在方框里"）。
	c.draw_circle(center, r + 3.0, MAP_BG)
	if _tex != null:
		c.draw_texture_rect(_tex, Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), false)
	_draw_grid(c, ts)
	_draw_landmarks(c, ts)
	_draw_players(c, ts)
	_draw_compass(c, ts)
	_draw_scale_bar(c, ts)
	_update_labels(ts)


## 网格：以玩家（圆心）为极点的等角距同心圆 + 辐射线。
## 【M47 球面】球面上没有"经纬直线"，只有角距和方位角。
func _draw_grid(c: Control, ts: Vector2) -> void:
	var col := Color(1.0, 1.0, 1.0, 0.07)
	var center := ts * 0.5
	var R := _disk_radius(ts)
	for k in range(1, 6):
		c.draw_arc(center, R * float(k) / 6.0, 0.0, TAU, 96, col, 1.0)
	for k in 8:
		var a := TAU * float(k) / 8.0
		c.draw_line(center, center + Vector2(cos(a), sin(a)) * R, col, 1.0)
	# 圈外再画一道亮边，强调"这是个球"
	c.draw_arc(center, R, 0.0, TAU, 128, Color(0.55, 0.78, 1.0, 0.55), 2.0)


## 【M47 球面】平面世界的铁轨横线在球面上没有对应物，已随矩形地图一起移除。


## 地标（★ 为主要据点）
## LANDMARKS 里存的是**平面坐标**（旧世界布局），这里先转成球面方向再投影。
func _draw_landmarks(c: Control, ts: Vector2) -> void:
	for lm in LANDMARKS:
		var pos: Vector3 = lm["pos"]
		var col: Color = lm["color"]
		var is_star: bool = lm["star"]
		var p := _world_to_map(Planet.surface_pos(Planet.dir_from_plane(pos.x, pos.z)), ts)
		# 圆盘边缘挤压严重，离边太近的名字干脆不画，避免糊成一团
		if p.distance_to(ts * 0.5) > _disk_radius(ts) - 6.0:
			continue
		if is_star:
			# 星星：外圈菱形 + 内点
			c.draw_colored_polygon(PackedVector2Array([
				p + Vector2(0.0, -9.0), p + Vector2(8.0, 0.0),
				p + Vector2(0.0, 9.0), p + Vector2(-8.0, 0.0)
			]), col)
			c.draw_circle(p, 3.0, Color(1.0, 1.0, 1.0, 0.9))
		else:
			c.draw_circle(p, 5.0, col)
			c.draw_arc(p, 7.0, 0.0, TAU, 20, Color(col.r, col.g, col.b, 0.5), 1.5)
		# 名字（带描边阴影，浅色地图上也可读）
		var font := ThemeDB.fallback_font
		var off: Vector2 = lm["off"]
		var label_pos := p + off
		var text := String(lm["name"])
		c.draw_string(font, label_pos + Vector2(1.0, 1.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.0, 0.0, 0.0, 0.85))
		c.draw_string(font, label_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 1.0, 1.0, 0.95))


## 屏幕外地标：画边缘箭头 + 距离
func _draw_offmap_pointer(c: Control, ts: Vector2, world_pos: Vector3, col: Color, name_text: String) -> void:
	var center := ts * 0.5
	var dir := (world_pos - Vector3(0.0, 0.0, -130.0))
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var edge := center + Vector2(dir.x, dir.z) * (minf(ts.x, ts.y) * 0.42)
	var perp := Vector2(-dir.z, dir.x)
	var tip := edge + Vector2(dir.x, dir.z) * 14.0
	c.draw_colored_polygon(PackedVector2Array([
		tip, edge + perp * 7.0, edge - perp * 7.0
	]), col)
	var dist := int(world_pos.distance_to(Vector3(0.0, 0.0, -130.0)))
	var font := ThemeDB.fallback_font
	var text := "%s %dm" % [name_text, dist]
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var lp := tip + Vector2(-w * 0.5, 18.0)
	c.draw_string(font, lp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 1.0, 1.0, 0.9))


## 玩家标记：本地玩家箭头（带朝向）+ 队友圆点
func _draw_players(c: Control, ts: Vector2) -> void:
	if _players_root == null:
		return
	var R := _disk_radius(ts)
	var center := ts * 0.5
	for child in _players_root.get_children():
		if not (child is Node3D):
			continue
		var p3 := child as Node3D
		var is_local := p3 == _local_player
		var mp := _world_to_map(p3.global_position, ts)
		if mp.distance_to(center) > R + 6.0:
			continue
		if is_local:
			_draw_player_arrow(c, mp, _facing_dir_on_disk(p3))
		else:
			c.draw_circle(mp, 4.0, Color(0.45, 0.90, 0.50, 0.9))
			c.draw_arc(mp, 6.0, 0.0, TAU, 16, Color(0.0, 0.0, 0.0, 0.6), 1.0)


## M38：取玩家"屏幕上模型的实际朝向"（世界 yaw，atan2(x, z) 语义）。
## 真值来源 = 身体节点（GodotRobot3D）的世界 basis.z —— 模型正面即局部 +Z
## （3d_godot_robot.gd apply_rotation 的约定：body.rotation.y 使模型 +Z 指向移动方向）。
## 不用根节点 rotation.y：那是相机/转身轴，与模型朝向解耦（player.gd _body_anchor_yaw）。
## 取不到身体节点时退回根节点 basis.z（模型正面朝 +Z 的常规约定）。
func _player_facing_yaw(p3: Node3D) -> float:
	var body := _find_body_node(p3)
	if body != null:
		var bz := body.global_transform.basis.z
		if bz.length_squared() > 0.0001:
			return atan2(bz.x, bz.z)
	var rz := p3.global_transform.basis.z
	if rz.length_squared() > 0.0001:
		return atan2(rz.x, rz.z)
	return 0.0


## 找玩家的身体节点。player.tscn 里身体节点名为 "GodotRobot3D"，
## 玩家脚本用 @export var _body: Node3D 暴露（node_paths 绑定到 GodotRobot3D）。
## 两路都取：先读脚本导出的 _body 字段，再按节点名兜底。
func _find_body_node(p3: Node3D) -> Node3D:
	var body = p3.get("_body")
	if body is Node3D:
		return body as Node3D
	var named := p3.get_node_or_null("GodotRobot3D")
	if named is Node3D:
		return named as Node3D
	return null


## 本地玩家箭头（世界 -Z 为北 → 屏幕上方）
## M38：方向真值改用"身体节点"的世界朝向，而不是玩家根节点的 rotation.y。
## 原因（M19 起的既有设计）：根节点 rotation.y 是**相机/转身轴**（右键拖动转视角时
## 它跟着转），而屏幕上角色模型的朝向由 _body.apply_rotation(velocity) 驱动，
## 步行时身体朝**移动方向**、与根节点 rotation.y 刻意解耦（见 player.gd
## _body_anchor_yaw 注释）。用根节点 yaw 画箭头，在"侧身移动"时会与实际朝向差一大截。
## 模型正面 = body 的局部 +Z（见 3d_godot_robot.gd apply_rotation 约定），
## 故世界朝向向量 = body.global_transform.basis.z，投影到 XZ 平面即可。
## 屏幕映射：世界 x 向右、世界 z 向下（北=-Z 在上），
## 故屏幕方向 = Vector2(world_dir.x, world_dir.z)。
## 【M47 球面】圆盘上的朝向：把身体正面向量投影到圆盘切平面基 (e1, e2)。
## 旧实现把世界 yaw 硬映射成屏幕方向 —— 那只在"地图 xz = 世界 xz"时成立。
## 圆盘以玩家方向为极点旋转过，必须先把向量投影到 (e1,e2) 再画。
func _facing_dir_on_disk(p3: Node3D) -> Vector2:
	var body := _find_body_node(p3)
	var f := Vector3.ZERO
	if body != null:
		f = body.global_transform.basis.z
	else:
		f = p3.global_transform.basis.z
	var v := Vector2(f.dot(_e1), f.dot(_e2))
	if v.length_squared() < 0.0001:
		return Vector2(0.0, 1.0)
	return v.normalized()


func _draw_player_arrow(c: Control, p: Vector2, dir: Vector2) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var col := Color(0.95, 0.95, 1.0, 1.0)
	c.draw_colored_polygon(PackedVector2Array([
		p + dir * 11.0, p - dir * 6.0 + perp * 6.0, p - dir * 6.0 - perp * 6.0
	]), col)
	c.draw_arc(p, 13.0, 0.0, TAU, 24, Color(0.95, 0.95, 1.0, 0.45), 1.5)


## 屏幕方向向量 → 地图屏幕方向。
## world yaw 语义：body 的 basis.z 指向的方向，atan2(bz.x, bz.z) 求得
## （Godot 的 yaw 约定：+X 为 0，绕 Y 顺时针为正 —— 用 atan2(x, z) 换算，
## 不能用 atan2(z, x)，否则朝向差 90°）。
## 屏幕方向 = (world.x, world.z)：地图 x 向右、z 向下。
func _facing_to_screen(yaw: float) -> Vector2:
	var dir := Vector2(sin(yaw), cos(yaw))
	if dir.length_squared() < 0.0001:
		return Vector2(0.0, 1.0)
	return dir.normalized()


## 罗盘（北 = 上）
func _draw_compass(c: Control, ts: Vector2) -> void:
	var center := Vector2(ts.x - 42.0, 42.0)
	var font := ThemeDB.fallback_font
	var marks := {"N": Vector2(0.0, -22.0), "S": Vector2(0.0, 30.0), "W": Vector2(-30.0, 6.0), "E": Vector2(30.0, 6.0)}
	for key in marks:
		var off: Vector2 = marks[key]
		var col := Color(0.95, 0.85, 0.45, 0.95) if key == "N" else Color(1.0, 1.0, 1.0, 0.6)
		c.draw_string(font, center + off, key, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
	c.draw_arc(center, 24.0, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.25), 1.0)


## 比例尺（200m）。方位等距投影沿半径是线性的：
## 圆盘半径 R 像素 ↔ 角距 180° ↔ 弧长 π·RADIUS 米。
func _draw_scale_bar(c: Control, ts: Vector2) -> void:
	var R := _disk_radius(ts)
	var meters_per_px := PI * Planet.RADIUS / maxf(R, 1.0)
	var px := 200.0 / meters_per_px
	var y := ts.y - 22.0
	var x0 := 22.0
	c.draw_line(Vector2(x0, y), Vector2(x0 + px, y), Color(1.0, 1.0, 1.0, 0.8), 2.0)
	c.draw_line(Vector2(x0, y - 4.0), Vector2(x0, y + 4.0), Color(1.0, 1.0, 1.0, 0.8), 2.0)
	c.draw_line(Vector2(x0 + px, y - 4.0), Vector2(x0 + px, y + 4.0), Color(1.0, 1.0, 1.0, 0.8), 2.0)
	c.draw_string(ThemeDB.fallback_font, Vector2(x0, y - 8.0), "200m",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 1.0, 1.0, 0.75))


## ---- 坐标换算 ----

## 世界坐标 → 圆盘像素。球面上"位置"只由方向决定，与半径无关。
func _world_to_map(world_pos: Vector3, ts: Vector2) -> Vector2:
	var uv := _disk_of(Planet.up_at(world_pos))
	var r := minf(ts.x, ts.y) * 0.5 * DISK_MARGIN
	return ts * 0.5 + uv * r


## 圆盘半径（像素）
func _disk_radius(ts: Vector2) -> float:
	return minf(ts.x, ts.y) * 0.5 * DISK_MARGIN


## ---- 每帧刷新玩家信息 ----

func _update_player_markers() -> void:
	if _level == null:
		return
	if _local_player == null and _level.has_method("_get_local_player"):
		_local_player = _level._get_local_player() as Node3D
	if _local_player == null:
		return
	# 标题栏坐标（三个轴都给：球面世界 Y 也是真实高度，只给 XZ 看不出高低）
	var wp := _local_player.global_position
	_coords_label.text = "坐标 X %.0f  Y %.0f  Z %.0f" % [wp.x, wp.y, wp.z]


func _update_labels(ts: Vector2) -> void:
	_title_label.text = "艾泽拉斯大陆 · 灰谷森林"
	if _hint_label != null:
		_hint_label.text = "M 键 / ESC 关闭地图    ·    ★ 主要据点"