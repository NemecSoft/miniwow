extends Node

## 二分诊断：只加载 robot_body.tscn 并实例化

func _ready() -> void:
	printerr("DIAG: 开始加载 robot_body")
	var dst_scene: PackedScene = load("res://scenes/monsters/robot_body.tscn")
	printerr("DIAG: 场景资源已加载")
	var dst_root := dst_scene.instantiate()
	printerr("DIAG: 已实例化")
	get_tree().root.add_child.call_deferred(dst_root)
	await get_tree().process_frame
	printerr("DIAG: 已挂树")
	var skel := dst_root.get_node("RobotArmature/Skeleton3D") as Skeleton3D
	printerr("DIAG: Skeleton3D 骨骼数=", skel.get_bone_count() if skel else -1)
	get_tree().quit(0)
