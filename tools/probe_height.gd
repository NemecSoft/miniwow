extends Node

## M20c 地形高度诊断：验证 headless 加载的地形数据在关键坐标的 get_height 值。
## 疑点：bot 传送到 (-20,-12)（保护区 (0,0) r=55 内，应为盆地 -0.5），
## 但 MoveTo 地形跟随把 y 推向 65m（暗示 get_height 返回 ~62 平原高度）。

const POINTS := [
	Vector3(0, 0, 0),        # 保护区中心
	Vector3(-20, 0, -12),    # bot 传送点
	Vector3(-30, 0, -22),    # 任务官
	Vector3(15, 0, 40),      # Wolf1 新位置
	Vector3(35, 0, 38),      # Wolf3 新位置
	Vector3(45, 0, 50),      # 狼旧位置（保护区(60,70)内）
	Vector3(0, 0, 320),      # RESPAWN_POINT 山脊
]

var _elapsed := 0.0


func _ready() -> void:
	var lvl = load("res://scenes/level/level.tscn").instantiate()
	lvl.name = "Level"
	get_tree().root.call_deferred("add_child", lvl)
	print("=== M20c 地形高度探针启动 ===")


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 3.0:
		return
	var starter := get_node_or_null("/root/Level/Environment/TerrainStarter")
	print("terrain_starter=%s" % starter)
	if starter == null:
		get_tree().quit(0)
		return
	var terrain = starter.get("terrain")
	print("terrain=%s" % terrain)
	if terrain == null:
		get_tree().quit(0)
		return
	var data = terrain.get("data")
	print("data=%s" % data)
	if data == null:
		get_tree().quit(0)
		return
	print("terrain.global_position.y=%.4f" % terrain.global_position.y)
	for p in POINTS:
		var h: float = data.get_height(p)
		var ground_y: float = terrain.global_position.y + h + 0.5
		print("height(%.0f,%.0f) = %.3f  → bot 站立地面 y=%.3f" % [p.x, p.z, h, ground_y])
	get_tree().quit(0)
