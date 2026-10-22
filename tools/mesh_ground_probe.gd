extends Node3D

## 网格地面探针：量「屏幕里你看到的那层地面」到底在哪个半径。
##
## 背景矛盾：
##   · body_aabb_probe 证明角色模型几何底边在 y=+0.007m（模型不悬空）
##   · PV 探针证明 玩家 r == Planet.mesh_height+RADIUS（差 -0.00m）
##   —— 但这是**循环论证**：_planet_frame_step 就是用 mesh_height 吸附的，
##      它当然等于自己。真正要问的是：**渲染出来的 ArrayMesh 在不在那个半径上**。
##
## 做法：直接读 PlanetSurface/FaceN 的 ArrayMesh 顶点与索引，
## 从玩家正上方沿 -当地法线 打射线求交，取最近交点半径。
## 再和 mesh_height / height_at 对比。
##
## 用法：godot --path . res://tools/mesh_ground_probe.tscn -- --world outland

var _level: Node3D


func _ready() -> void:
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("MGP: 需要窗口模式（要等关卡真正建完）")
		get_tree().quit(0)
		return
	_level.call("_on_host_pressed", "探针", "blue")
	await get_tree().create_timer(5.0).timeout

	var players := _level.get_node_or_null("PlayersContainer")
	if players == null or players.get_child_count() == 0:
		printerr("MGP: 没有玩家")
		get_tree().quit(0)
		return
	var player := players.get_child(0) as Node3D
	await get_tree().create_timer(0.5).timeout

	# 诊断：渲染网格高度缓存到底有没有被 TerrainStarter 灌进去
	printerr("MGP: [缓存] size=%d" % Planet._mesh_cache.size())
	for fi in Planet._mesh_cache.size():
		var e = Planet._mesh_cache[fi]
		printerr("MGP: [缓存] face%d type=%d %s" % [
			fi, typeof(e), ("len=%d" % (e as PackedFloat32Array).size()) if e is PackedFloat32Array else "非数组"])

	_measure(player, "出生点")
	# 沿前方向走 3 个采样点，确认不是单点巧合
	var fwd: Vector3 = -player.global_transform.basis.z
	for k in 3:
		player.global_position += fwd * 2.0
		await get_tree().physics_frame
		await get_tree().physics_frame
		_measure(player, "前方 %dm" % ((k + 1) * 2))

	get_tree().quit(0)


func _measure(player: Node3D, tag: String) -> void:
	var pos: Vector3 = player.global_position
	var up := Planet.up_at(pos)
	var r: float = pos.length()

	var h_mesh: float = Planet.mesh_height(up)
	var h_analytic: float = Planet.height_at(pos)

	var surf := _level.get_node_or_null("Environment/TerrainStarter/PlanetSurface")
	if surf == null:
		printerr("MGP[%s] 找不到 PlanetSurface" % tag)
		return

	var fu := Planet.face_uv(up)
	var face := int(fu[0])
	var face_node := surf.get_node_or_null("Face%d" % face) as MeshInstance3D
	if face_node == null:
		printerr("MGP[%s] 找不到 Face%d" % [tag, face])
		return

	var mesh: Mesh = face_node.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		printerr("MGP[%s] Face%d 没有 mesh" % [tag, face])
		return
	var arr: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var xf: Transform3D = face_node.global_transform

	var origin: Vector3 = up * (Planet.RADIUS + 4000.0)
	var best := INF
	var tris := 0
	var t := 0
	while t + 2 < idx.size():
		var a: Vector3 = xf * verts[idx[t]]
		var b: Vector3 = xf * verts[idx[t + 1]]
		var c: Vector3 = xf * verts[idx[t + 2]]
		var hit = Geometry3D.ray_intersects_triangle(origin, -up, a, b, c)
		if hit != null:
			var hpos := hit as Vector3
			var d: float = origin.distance_to(hpos)
			if d < best:
				best = d
				tris += 1
		t += 3

	var r_render: float = (Planet.RADIUS + 4000.0) - best if best < INF else NAN

	# 诊断：面节点变换 + 离玩家最近的**真实顶点**半径
	var xf_s: Vector3 = xf.basis.get_scale()
	printerr("MGP[%s]   面节点 origin=%s scale=%s" % [
		tag, str(xf.origin.snapped(Vector3.ONE * 0.001)), str(xf_s.snapped(Vector3.ONE * 0.0001))])
	var dv := INF
	var dv_r := 0.0
	for j in verts.size():
		var wp: Vector3 = xf * verts[j]
		var dd: float = wp.distance_to(pos)
		if dd < dv:
			dv = dd
			dv_r = wp.length()
	printerr("MGP[%s]   最近真实顶点 距玩家=%.2fm r=%.3f (差 %+.3f)" % [tag, dv, dv_r, dv_r - r])

	printerr("MGP[%s] ---- 玩家 r=%.3f  面=%d ----" % [tag, r, face])
	printerr("MGP[%s]   mesh_height 给出    r=%.3f  (差 %+.3f)" % [
		tag, Planet.RADIUS + h_mesh, (Planet.RADIUS + h_mesh) - r])
	printerr("MGP[%s]   height_at 解析给出  r=%.3f  (差 %+.3f)" % [
		tag, Planet.RADIUS + h_analytic, (Planet.RADIUS + h_analytic) - r])
	if best < INF:
		printerr("MGP[%s]   ★渲染网格实际交点  r=%.3f  (差 %+.3f)  ← 这才是你眼睛看到的" % [
			tag, r_render, r_render - r])
	else:
		printerr("MGP[%s]   ★射线没打中渲染网格（玩家可能站在地形之外）" % tag)
