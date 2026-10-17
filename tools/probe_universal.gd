extends Node

## M16 重定向试验探针（测试场景方式运行，autoload 可用）：
## 确认 Universal glb 实例化后的节点结构、Skeleton3D 骨骼 rest、
## Punch_Jab 动画的 track 格式，为烘焙重定向做准备。
## 运行方式：godot --headless --path . res://tools/probe_universal.tscn

func _ready() -> void:
	var scene: PackedScene = load("res://assets/animations/universal/universal_standard.glb")
	if scene == null:
		push_error("PROBE: glb 加载失败")
		get_tree().quit(1)
		return
	var inst := scene.instantiate()
	get_tree().root.add_child.call_deferred(inst)
	await get_tree().process_frame
	await get_tree().process_frame

	print("PROBE: 根节点=", inst.name, " 类=", inst.get_class())
	for child in inst.get_children():
		print("  子节点: ", child.name, " (", child.get_class(), ")")

	var skel := _find_skeleton(inst)
	if skel == null:
		push_error("PROBE: 未找到 Skeleton3D")
		get_tree().quit(1)
		return
	print("PROBE: Skeleton3D 路径=", inst.get_path_to(skel), " 骨骼数=", skel.get_bone_count())
	for i in mini(skel.get_bone_count(), 10):
		print("  骨[", i, "] ", skel.get_bone_name(i), " rest=", skel.get_bone_rest(i))

	var anims := _find_animation_player(inst)
	if anims == null:
		push_error("PROBE: 未找到 AnimationPlayer")
		get_tree().quit(1)
		return
	for lib_name in anims.get_animation_library_list():
		var lib := anims.get_animation_library(lib_name)
		print("PROBE: 库 '", lib_name, "' 动画数=", lib.get_animation_list().size())

	if anims.has_animation("Punch_Jab"):
		var anim := anims.get_animation("Punch_Jab")
		print("PROBE: Punch_Jab 长度=", anim.length, " track 数=", anim.get_track_count())
		var shown := 0
		for t in anim.get_track_count():
			var track_path := anim.track_get_path(t)
			if shown < 6:
				print("  track[", t, "] 类型=", anim.track_get_type(t),
					" 路径=", track_path, " keys=", anim.track_get_key_count(t))
				shown += 1
			# 打印唯一的骨骼名样本（去重计数用）
		var bone_set := {}
		for t in anim.get_track_count():
			var path := anim.track_get_path(t)
			var bone_name := String(path.get_concatenated_names())
			bone_set[path.get_subname(0)] = true
		print("PROBE: track 涉及骨骼数=", bone_set.size())
		var names := bone_set.keys()
		names.sort()
		print("PROBE: 骨骼名=", names)
		# 第 0 帧旋转样本（track_get_key_rotation 在 4.7 不存在，统一用 track_interpolate）
		for t in anim.get_track_count():
			var path := anim.track_get_path(t)
			if String(path.get_subname(0)) in ["DEF-hips", "DEF-upper_arm.R", "DEF-spine.001"] \
					and anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				var key_rot: Quaternion = anim.track_interpolate(t, 0.0)
				print("  样本 ", path.get_subname(0), " 第0帧旋转=", key_rot,
					" 节点名=", path.get_concatenated_names())
	else:
		print("PROBE: 无 Punch_Jab！可用动画=", anims.get_animation_list())

	get_tree().quit(0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
