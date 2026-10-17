extends Node

## 数值验证 strike_jab.tres：打印关键骨骼在多个时刻相对 rest 的旋转角度

func _ready() -> void:
	var anim: Animation = load("res://assets/animations/retarget/strike_jab.tres")
	var body_scene: PackedScene = load("res://scenes/monsters/robot_body.tscn")
	var body := body_scene.instantiate()
	get_tree().root.add_child.call_deferred(body)
	await get_tree().process_frame
	var skel := body.get_node("RobotArmature/Skeleton3D") as Skeleton3D

	for t_time in [0.0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.86]:
		var line := "t=%.2f " % t_time
		for bone_name in ["upper_arm.R", "forearm.R", "upper_arm.L", "forearm.L", "spine", "spine.001"]:
			var idx := skel.find_bone(bone_name)
			var rest_q := skel.get_bone_rest(idx).basis.get_rotation_quaternion()
			var track := anim.find_track(NodePath("RobotArmature/Skeleton3D:" + bone_name), Animation.TYPE_ROTATION_3D)
			var pose_q: Quaternion = rest_q
			if track >= 0:
				pose_q = anim.rotation_track_interpolate(track, t_time)
			var angle := rad_to_deg(pose_q.angle_to(rest_q))
			line += "%s=%.0f°  " % [bone_name, angle]
		printerr(line)
	get_tree().quit(0)
