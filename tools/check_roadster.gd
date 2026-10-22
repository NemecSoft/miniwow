extends SceneTree

## 验证 roadster2.glb 导入结构（headless 一次性跑）

func _init() -> void:
	var ps: PackedScene = load("res://assets/models/roadster2.glb")
	if ps == null:
		push_error("LOAD FAILED")
		quit(1)
		return
	var root := ps.instantiate()
	_dump(root, 0)
	# 尺寸统计
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for mesh_inst in _find_meshes(root):
		var ab: AABB = mesh_inst.get_aabb()
		mn = mn.min(ab.position + mesh_inst.position)
		mx = mx.max(ab.position + ab.size + mesh_inst.position)
	print("TOTAL_AABB min=", mn, " max=", mx, " size=", mx - mn)
	root.free()
	quit(0)

func _find_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_meshes(c))
	return out

func _dump(n: Node, depth: int) -> void:
	var info := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		info = " surfaces=%d aabb=%s" % [mi.mesh.get_surface_count() if mi.mesh else 0, mi.get_aabb().size]
	if n is Node3D:
		info += " pos=%s" % (n as Node3D).position
	print("  ".repeat(depth), n.name, " [", n.get_class(), "]", info)
	for c in n.get_children():
		_dump(c, depth + 1)
