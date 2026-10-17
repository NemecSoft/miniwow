extends Node

## M12 探针：确认 villager.glb 导入后的节点结构与动画名

func _ready() -> void:
	var scene := load("res://assets/characters/npc/villager.glb") as PackedScene
	if scene == null:
		print("PROBE: glb 加载失败")
		get_tree().quit()
		return
	var inst := scene.instantiate()
	add_child.call_deferred(inst)
	call_deferred("_inspect", inst)


func _inspect(inst: Node) -> void:
	print("PROBE: 根节点=", inst.name, " 类型=", inst.get_class())
	_dump(inst, 0)
	var anim := _find_anim(inst)
	if anim:
		print("PROBE: 动画总数=", anim.get_animation_list().size())
		for n in anim.get_animation_list():
			print("PROBE: anim=", n, " len=", "%.2f" % anim.get_animation(n).length)
	var mesh_count := _count_meshes(inst)
	print("PROBE: mesh数=", mesh_count)
	get_tree().quit()


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var r := _find_anim(child)
		if r:
			return r
	return null


func _count_meshes(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		count = 1
	for child in node.get_children():
		count += _count_meshes(child)
	return count


func _dump(node: Node, depth: int) -> void:
	if depth <= 3:
		print("PROBE: ", "  ".repeat(depth), node.name, " (", node.get_class(), ")")
	for child in node.get_children():
		_dump(child, depth + 1)
