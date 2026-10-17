extends Node

## M18b-3 探针：打印 Mannequin_Large.glb 场景树、动画轨道前缀、.res 动画的轨道根路径。
## 运行方式：godot --headless --path . res://tools/probe_kaykit.tscn

func _ready() -> void:
	var scene := load("res://assets/characters/infantry_kaykit/Mannequin_Large.glb") as PackedScene
	if scene == null:
		printerr("PROBE-FAIL: glb 加载失败")
		get_tree().quit(1)
		return
	var root := scene.instantiate()
	add_child(root)
	printerr("glb根transform=", (root as Node3D).transform)
	printerr("Rig_Large transform=", (root.get_node("Rig_Large") as Node3D).transform)
	printerr("=== glb 场景树 ===")
	_dump_tree(root, 0)

	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap:
		printerr("=== glb 自带 AnimationPlayer（父=%s）===" % ap.get_parent().name)
		for anim_name in ap.get_animation_list():
			var anim := ap.get_animation(anim_name)
			printerr("  anim: ", anim_name, " len=", "%.2f" % anim.length, " tracks=", anim.get_track_count())

	# 检查 .res 动画的轨道前缀（决定能否跨场景使用）
	var res := load("res://assets/characters/infantry_kaykit/animations/Idle_A.res") as Animation
	if res:
		printerr("=== Idle_A.res 轨道（前 %d 条）===" % mini(5, res.get_track_count()))
		for i in mini(5, res.get_track_count()):
			printerr("  ", res.track_get_path(i))

	# 检查骨骼名（武器挂点用）
	var skel := root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel:
		printerr("=== 骨架：", skel.name, " 骨骼数=", skel.get_bone_count(), " ===")
		for i in skel.get_bone_count():
			var bone_name := skel.get_bone_name(i)
			if "hand" in bone_name or "root" in bone_name or "hip" in bone_name:
				printerr("  bone[", i, "]=", bone_name, " height=", "%.2f" % (skel.get_bone_global_pose(i).origin.y))
	get_tree().quit(0)


func _dump_tree(node: Node, depth: int) -> void:
	if depth > 3:
		return
	var extra := ""
	if node is Skeleton3D:
		extra = " (Skeleton3D bones=%d)" % (node as Skeleton3D).get_bone_count()
	elif node is MeshInstance3D:
		extra = " (Mesh)"
	printerr("  ".repeat(depth + 1), node.name, " [", node.get_class(), "]", extra)
	for child in node.get_children():
		_dump_tree(child, depth + 1)

# 追加：打印 glb 根 transform
