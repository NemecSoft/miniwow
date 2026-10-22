extends Node3D

## M47 / C0 验证：Planet 落位层是不是真的"自动适应"，而不是又一套凑数。
##
## 验证方法（对应 docs/conventions-relative-computation.md §6.2）：
##   同一套断言，在【不同位置】×【不同尺寸模型】上各跑一遍。
##   全部成立 → 是相对值；只有某个点成立 → 是凑数。
##
## 断言的不变量：
##   |模型几何最低点 - 该点地表| ≈ 0   （与落在星球哪个方向无关、与模型多高无关）

var _level: Node3D
var _probe_root: Node3D


func _ready() -> void:
	Network.SERVER_PORT = 8092          # 不抢正在跑的游戏实例
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("RPP: 需要窗口模式（要真实顶点与世界变换）")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "诊断", "blue")
	await get_tree().create_timer(6.0).timeout

	_probe_root = Node3D.new()
	_probe_root.name = "RelativePlaceProbe"
	get_tree().root.call_deferred("add_child", _probe_root)
	await get_tree().process_frame

	printerr("RPP: ===== 用自造模型验证（原点在几何中心，最低点在 -h/2）=====")
	await _test_sizes()

	printerr("RPP: ===== 用场景里真实模型验证（原点未知，完全靠算）=====")
	await _test_scene_model()

	printerr("RPP: ===== 反向对照：同样位置改用 += 绝对抬升会错多少 =====")
	await _test_absolute_contrast()

	printerr("RPP: 结束")
	get_tree().quit(0)


## 同一位置，三种高度的柱子：全部必须贴地。
func _test_sizes() -> void:
	var base_dir := _player_dir()
	var dirs := _spread_dirs(base_dir, 3)
	for h: float in [2.0, 6.0, 18.0]:
		var mi := _make_box("柱_h%.0f" % h, Vector3(1.0, h, 1.0))
		var worst := 0.0
		var rows: Array[String] = []
		for d: Vector3 in dirs:
			Planet.place_on_surface(mi, d, 0.0, true)
			var gap := _gap(mi)
			worst = maxf(worst, absf(gap))
			rows.append("%.3f" % gap)
		printerr("RPP[h=%.0f] 各方向贴地差 = [%s]  最大 |gap| = %.4f m  → %s" % [
			h, ", ".join(rows), worst, "OK" if worst < 0.15 else "FAIL"])
		mi.queue_free()


## 真实场景模型：原点在哪都不知道，只能靠顶点算。
func _test_scene_model() -> void:
	var src := _find_prop_mesh()
	if src == null:
		printerr("RPP[scene] 没找到可用的场景模型，跳过")
		return
	printerr("RPP[scene] 取样模型 = %s（mesh=%s）" % [
		str(src.name), str(src.mesh.get_class())])
	var worst := 0.0
	var rows: Array[String] = []
	for d: Vector3 in _spread_dirs(_player_dir(), 3):
		var clone := MeshInstance3D.new()
		clone.mesh = src.mesh
		clone.scale = src.global_transform.basis.get_scale()
		_probe_root.add_child(clone)
		Planet.place_on_surface(clone, d, 0.0, true)
		var gap := _gap(clone)
		worst = maxf(worst, absf(gap))
		rows.append("%.3f" % gap)
		clone.queue_free()
	printerr("RPP[scene] 各方向贴地差 = [%s]  最大 |gap| = %.4f m  → %s" % [
		", ".join(rows), worst, "OK" if worst < 0.15 else "FAIL"])


## 对照：把"抬高 2 米"写成世界 Y 平移，在球面上会偏成什么样。
func _test_absolute_contrast() -> void:
	var mi := _make_box("对照柱", Vector3(1.0, 2.0, 1.0))
	var rows: Array[String] = []
	for d: Vector3 in _spread_dirs(_player_dir(), 3):
		Planet.place_on_surface(mi, d, 0.0, true)
		var up := Planet.up_at(mi.global_position)
		var before := _gap(mi)
		# 旧写法：想"再抬高 2 米"，写成世界 Y
		mi.global_position.y += 2.0
		var after_y := _gap(mi)
		# 正解：沿当地法线抬 2 米
		mi.global_position.y -= 2.0
		mi.global_position += up * 2.0
		var after_up := _gap(mi)
		rows.append("%s 世界Y:%.2f 法线:%.2f" % [
			str(d.snapped(Vector3(0.01, 0.01, 0.01))), after_y - before, after_up - before])
	printerr("RPP[contrast] 想抬高 2.000m 的实际抬升量：")
	for r in rows:
		printerr("RPP[contrast]   %s" % r)
	printerr("RPP[contrast] 结论：世界Y 抬升量随位置漂移；沿当地法线恒为 2.000m。")
	mi.queue_free()


# ---------- 工具 ----------

func _make_box(nm: String, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = size          # BoxMesh 原点在几何中心 → 最低点 = -size.y/2
	mi.mesh = bm
	_probe_root.add_child(mi)
	return mi


## 模型最低点到当地地表的带符号差（负 = 陷进地里，正 = 悬空）
func _gap(mi: Node3D) -> float:
	var up := Planet.up_at(mi.global_position)
	var ground: float = Planet.ground_pos(mi.global_position.normalized()).dot(up)
	var lowest: float = Planet.model_lowest_projection(mi, up)
	if is_nan(lowest):
		return NAN
	return lowest - ground


func _player_dir() -> Vector3:
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		if (n as Node).has_method("is_local_player") and (n as Node).call("is_local_player"):
			return (n as Node3D).global_position.normalized()
	return Vector3.RIGHT


## 以 base 为起点，在一个近似正交的方向集上撒点（保证都能落在星球上）
func _spread_dirs(base: Vector3, count: int) -> Array:
	var out: Array = [base]
	var t1 := base.cross(Vector3.UP)
	if t1.length_squared() < 0.01:
		t1 = base.cross(Vector3.RIGHT)
	t1 = t1.normalized()
	var t2 := base.cross(t1).normalized()
	var offs := [t1 * 0.06, t2 * 0.06, (t1 + t2).normalized() * 0.09, -t1 * 0.05]
	for i in mini(count - 1, offs.size()):
		out.append((base + offs[i]).normalized())
	return out


func _find_prop_mesh() -> MeshInstance3D:
	var best: MeshInstance3D = null
	for n in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.is_queued_for_deletion():
			continue
		# 排除地形面（几万顶点，且它就是地表本身）
		if str(mi.name).begins_with("Face"):
			continue
		var nm := str(mi.name).to_lower()
		if nm.contains("tree") or nm.contains("house") or nm.contains("building") or nm.contains("crate"):
			return mi
		if best == null:
			best = mi
	return best
