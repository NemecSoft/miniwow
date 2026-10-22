extends Node3D

## 量"角色模型几何底边"到底在玩家根节点原点（y=0）的哪个高度。
##
## 背景：PV 探针只证明了「根节点 r == 网格表面 r（差 -0.00m）」，
## 即**节点**贴地。但用户截图里角色明显悬空 —— 那只能是**模型本身**
## 的几何底边不在 y=0（美术资产的 pivot 抬高了），或者骨骼动画把脚抬起来了。
##
## 这个探针只做一件事：实例化 player.tscn，把每个 MeshInstance3D 的
## 顶点集合变换到玩家本地空间，求最低 y。== 0 表示贴地，> 0 表示悬空 N 米。
##
## 用法：godot --headless --path . res://tools/body_aabb_probe.tscn

func _ready() -> void:
	var scn := load("res://scenes/level/player.tscn") as PackedScene
	if scn == null:
		printerr("AABBP: 加载不到 player.tscn")
		get_tree().quit(1)
		return
	var p := scn.instantiate() as Node3D
	add_child(p)
	for i in 4:
		await get_tree().process_frame

	var inv: Transform3D = p.global_transform.affine_inverse()
	var rows: Array = []
	_collect(p, inv, rows)
	rows.sort_custom(func(a, b): return a[1] < b[1])

	printerr("AABBP: ===== 模型各 Mesh 在【玩家本地坐标】的 y 范围（玩家原点 y=0）=====")
	for r in rows:
		printerr("AABBP:  %-58s y: %+7.3f ~ %+7.3f  (高 %.3f)" % [
			r[0], r[1], r[2], r[2] - r[1]])
	if rows.is_empty():
		printerr("AABBP: 没扫到任何 MeshInstance3D")
	else:
		var lowest: float = rows[0][1]
		printerr("AABBP: --------------------------------------------------")
		printerr("AABBP: 全局最低点 y = %+.3f m" % lowest)
		if absf(lowest) < 0.03:
			printerr("AABBP: 判定 → 模型贴地（偏差 <3cm）")
		else:
			printerr("AABBP: 判定 → **%s %.3f m**，需要把 _body 的 y 偏移 %+.3f 补偿" % [
				"悬空" if lowest > 0.0 else "陷入地面", absf(lowest), -lowest])

	# 顺带量碰撞胶囊：胶囊中心/半径，判断物理胶囊是否与模型对齐
	var cs := p.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null and cs.shape is CapsuleShape3D:
		var cap := cs.shape as CapsuleShape3D
		var c: Vector3 = cs.position
		printerr("AABBP: 碰撞胶囊 中心 y=%+.3f 半径=%.3f 高=%.3f → 胶囊底 y=%+.3f" % [
			c.y, cap.radius, cap.height, c.y - cap.height * 0.5])
	get_tree().quit(0)


func _collect(n: Node, inv: Transform3D, rows: Array) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		var lo := INF
		var hi := -INF
		var mesh: Mesh = mi.mesh
		var t_local: Transform3D = inv * mi.global_transform
		for s in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(s)
			var verts = arr[Mesh.ARRAY_VERTEX]
			if verts == null:
				continue
			# 采样上限，避免大网格拖死
			var step: int = maxi(1, int(verts.size() / 4000))
			var i := 0
			while i < verts.size():
				var w: Vector3 = t_local * (verts[i] as Vector3)
				lo = minf(lo, w.y)
				hi = maxf(hi, w.y)
				i += step
		if lo < INF:
			rows.append([str(mi.get_path()), lo, hi])
	for c in n.get_children():
		_collect(c, inv, rows)
