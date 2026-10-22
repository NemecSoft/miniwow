class_name VillageData
extends RefCounted

## 村庄布局数据（由 tools/village_gen.mjs 生成的 JSON）。
## 换 seed 重新生成即可得到完全不同的村落布局：
##   node tools/village_gen.mjs --seed 12345 --out data/worldgen/mulgore_village.json
##
## 加载后会把路网注册进 WorldShape._village_roads，
## 保证"地形遮罩画的路"与"实际摆放的建筑/道具"共用同一份数据。

const JSON_PATH := "res://data/worldgen/mulgore_village.json"

static var _loaded := false
static var seed := 0
static var center := Vector2(0.0, -130.0)
static var inner_radius := 118.0
static var outer_radius := 268.0
## Array[Array[Vector2]]：每条路一串点
static var roads: Array = []
## Array[Dictionary]：{x, z, w, d, rot, style, floors}
static var buildings: Array = []
## Array[Dictionary]：{x, z, w, h, rot}
static var fields: Array = []
## Array[Dictionary]：{x, z, type, rot, scale}
static var props: Array = []


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(JSON_PATH):
		push_warning("[VillageData] 缺少 %s，跳过村庄布局（跑 tools/village_gen.mjs 生成）" % JSON_PATH)
		return
	var f := FileAccess.open(JSON_PATH, FileAccess.READ)
	if f == null:
		push_warning("[VillageData] 无法打开 %s" % JSON_PATH)
		return
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[VillageData] JSON 解析失败")
		return
	seed = int(parsed.get("seed", 0))
	var c = parsed.get("center", [0.0, -130.0])
	center = Vector2(float(c[0]), float(c[1]))
	inner_radius = float(parsed.get("inner_radius", 118.0))
	outer_radius = float(parsed.get("outer_radius", 268.0))

	roads = []
	for r in parsed.get("roads", []):
		var pts: Array = []
		for p in r.get("points", []):
			pts.append(Vector2(float(p[0]), float(p[1])))
		if pts.size() >= 2:
			roads.append({"points": pts, "width": float(r.get("width", 5.0)), "kind": str(r.get("kind", "lane"))})
	# 注册给 WorldShape：地形遮罩据此画村道，与建筑同一套坐标
	WorldShape.register_village_roads(roads.map(func(r): return r["points"]))

	buildings = parsed.get("buildings", [])
	fields = parsed.get("fields", [])
	props = parsed.get("props", [])
	print("[VillageData] seed=%d roads=%d buildings=%d fields=%d props=%d" % [
		seed, roads.size(), buildings.size(), fields.size(), props.size()])
