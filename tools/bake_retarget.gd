extends Node

## M16 骨骼重定向烘焙：Universal 动画库（Rigify DEF-* 53 骨）→ 机器人骨架（metarig 25 骨）。
## 方法：世界空间旋转增量搬运 + rest 对齐（M * R_src_world），
## 保证源处于 rest 时目标也处于自身 rest，源的旋转增量完整保留。
## 产出：res://assets/animations/retarget/strike_jab.tres（Punch_Jab 样张）
## 运行方式：godot --headless --path . res://tools/bake_retarget.tscn

## Universal → 机器人 骨骼映射（层级对齐：脊柱4节+头、肩肘腕、髋膝踝）
## M16c 修复：剔除 DEF-spine.002/.003——原版动画从不驱动这两节脊柱（31 轨道集
## 不含它们），烘焙动画若驱动，攻击结束切回 Idle/Run 后这两骨无轨道接管，
## 永远停在挥剑末帧的弯曲姿势（实测"挥拳后一直低头、走路也低头"）。
const BONE_MAP := {
	"DEF-hips": "spine",
	"DEF-spine.001": "spine.001",
	"DEF-neck": "spine.004",
	"DEF-head": "Head",
	"DEF-shoulder.L": "shoulder.L",
	"DEF-upper_arm.L": "upper_arm.L",
	"DEF-forearm.L": "forearm.L",
	"DEF-hand.L": "hand.L",
	"DEF-shoulder.R": "shoulder.R",
	"DEF-upper_arm.R": "upper_arm.R",
	"DEF-forearm.R": "forearm.R",
	"DEF-hand.R": "hand.R",
	"DEF-thigh.L": "thigh.L",
	"DEF-shin.L": "shin.L",
	"DEF-foot.L": "foot.L",
	# DEF-toe.L 剔除：原版动画只有 toe.R 无 toe.L（M16c 驱动集对齐原则，校验器抓出）
	"DEF-thigh.R": "thigh.R",
	"DEF-shin.R": "shin.R",
	"DEF-foot.R": "foot.R",
	"DEF-toe.R": "toe.R",
}

## 要烘焙的源动画名 → 输出文件名 + 动画资源名
const BAKE_LIST := {
	"Punch_Jab": {"file": "strike_jab.tres", "anim": "Strike"},
	# M16b：替换 Attack1 旋风斩（spine.001 绕 Y 轴近 360° 旋转 = 用户实测"转圈圈"）
	"Sword_Attack": {"file": "sword_slash.tres", "anim": "SwordSlash"},
}

const SRC_SKELETON_PATH := "Rig/Skeleton3D"
const DST_SKELETON_PATH := "RobotArmature/Skeleton3D"
const OUTPUT_DIR := "res://assets/animations/retarget/"


func _ready() -> void:
	printerr("BAKE: 开始")
	var src_scene: PackedScene = load("res://assets/animations/universal/universal_standard.glb")
	printerr("BAKE: glb 已加载")
	var src_root := src_scene.instantiate()
	get_tree().root.add_child.call_deferred(src_root)
	await get_tree().process_frame

	var dst_scene: PackedScene = load("res://scenes/monsters/robot_body.tscn")
	printerr("BAKE: robot_body 已加载")
	var dst_root := dst_scene.instantiate()
	get_tree().root.add_child.call_deferred(dst_root)
	await get_tree().process_frame
	printerr("BAKE: 两实例已挂树")

	var src_skel := src_root.get_node(SRC_SKELETON_PATH) as Skeleton3D
	var dst_skel := dst_root.get_node(DST_SKELETON_PATH) as Skeleton3D
	var src_anims := _find_animation_player(src_root)
	if src_skel == null or dst_skel == null or src_anims == null:
		push_error("BAKE: 骨架/动画节点未找到")
		get_tree().quit(1)
		return

	# 预计算源骨架全局 rest（local rest 沿父链累乘，含骨架根节点变换）
	var src_global_rest := {}
	for i in src_skel.get_bone_count():
		src_global_rest[src_skel.get_bone_name(i)] = _global_rest(src_skel, i)
	var dst_global_rest := {}
	for i in dst_skel.get_bone_count():
		dst_global_rest[dst_skel.get_bone_name(i)] = _global_rest(dst_skel, i)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	printerr("BAKE: 进入烘焙循环")

	for src_anim_name in BAKE_LIST:
		var info: Dictionary = BAKE_LIST[src_anim_name]
		if not src_anims.has_animation(src_anim_name):
			push_error("BAKE: 源动画不存在 " + src_anim_name)
			continue
		var src_anim := src_anims.get_animation(src_anim_name)
		printerr("BAKE: 烘焙 " + src_anim_name)
		var out_anim := _bake_one(src_anim, src_skel, dst_skel, src_global_rest, dst_global_rest)
		printerr("BAKE: 烘焙完成 " + src_anim_name)
		out_anim.resource_name = info["anim"]
		var out_path: String = OUTPUT_DIR + String(info["file"])
		var err := ResourceSaver.save(out_anim, out_path)
		if err == OK:
			print("BAKE: 完成 ", src_anim_name, " → ", out_path,
				" 时长=", out_anim.length, " track 数=", out_anim.get_track_count())
		else:
			push_error("BAKE: 保存失败 %s 错误=%s" % [out_path, err])

	get_tree().quit(0)


func _bake_one(
	src_anim: Animation,
	src_skel: Skeleton3D,
	dst_skel: Skeleton3D,
	src_global_rest: Dictionary,
	dst_global_rest: Dictionary
) -> Animation:
	# 按帧采样的骨架级烘焙（正确算法）：
	#   源世界旋转(t) = 源父链世界旋转(t) * 源局部 pose(t)     —— 父骨动画贡献必须包含
	#   目标世界旋转(t) = M * 源世界旋转(t)，M = 目标rest世界 * 源rest世界⁻¹
	#   目标局部(t) = 目标父骨世界旋转(t)⁻¹ * 目标世界旋转(t)  —— 父骨用重定向后的动画值
	# Godot 导入动画的局部 pose 是绝对值（rest 时 pose==rest），不是增量。

	# 源骨架每根骨的 rotation 轨道索引（无轨道 = 动画中保持 rest）
	var src_rot_track := {}
	for t in src_anim.get_track_count():
		if src_anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(src_anim.track_get_path(t).get_subname(0))
		src_rot_track[bone] = t
	# hips 位置轨道（重心起伏）
	var src_hips_track := -1
	if src_anim.find_track(NodePath(SRC_SKELETON_PATH + ":DEF-hips"), Animation.TYPE_POSITION_3D) >= 0:
		src_hips_track = src_anim.find_track(NodePath(SRC_SKELETON_PATH + ":DEF-hips"), Animation.TYPE_POSITION_3D)

	# 采样时间 = 全部源 rotation key 时间并集（+0 与 length 尾帧）
	var time_set := {}
	for t in src_anim.get_track_count():
		if src_anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		for k in src_anim.track_get_key_count(t):
			time_set[src_anim.track_get_key_time(t, k)] = true
	time_set[0.0] = true
	time_set[src_anim.length] = true
	var times := time_set.keys()
	times.sort()

	# 骨架根节点变换（Rig / RobotArmature，实例化后读，本地无更高层变换）
	var src_root_xform := (src_skel.get_parent() as Node3D).transform
	var dst_root_xform := (dst_skel.get_parent() as Node3D).transform
	var src_root_q := src_root_xform.basis.get_rotation_quaternion()
	var dst_root_q := dst_root_xform.basis.get_rotation_quaternion()

	# 源骨拓扑序处理（glb joints 顺序保证父在子前）
	var out := Animation.new()
	out.length = src_anim.length
	out.step = src_anim.step
	var rot_track_of := {} # 目标骨名 -> 输出轨道索引
	for i in src_skel.get_bone_count():
		var src_bone := src_skel.get_bone_name(i)
		if not BONE_MAP.has(src_bone):
			continue
		var dst_bone: String = BONE_MAP[src_bone]
		if not rot_track_of.has(dst_bone):
			var track := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(track, NodePath(DST_SKELETON_PATH + ":" + dst_bone))
			out.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
			rot_track_of[dst_bone] = track
	var hips_track := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hips_track, NodePath(DST_SKELETON_PATH + ":spine"))

	# 预计算：每骨的 M（rest 对齐四元数）与源/目标 rest 世界旋转
	var m_of := {} # 源骨名 -> Quaternion
	var src_rest_world_q := {}
	var dst_rest_world_q := {}
	for src_bone in BONE_MAP:
		var src_r: Transform3D = src_global_rest[src_bone]
		var dst_r: Transform3D = dst_global_rest[BONE_MAP[src_bone]]
		var sq := src_r.basis.get_rotation_quaternion()
		var dq := dst_r.basis.get_rotation_quaternion()
		src_rest_world_q[src_bone] = sq
		dst_rest_world_q[BONE_MAP[src_bone]] = dq
		m_of[src_bone] = dq * sq.inverse()

	# 源 rest 世界旋转按拓扑序的查找表（父链用）
	var src_rest_q_by_idx := {}
	for i in src_skel.get_bone_count():
		src_rest_q_by_idx[i] = src_rest_world_q.get(
			src_skel.get_bone_name(i),
			src_global_rest.get(src_skel.get_bone_name(i), Transform3D.IDENTITY).basis.get_rotation_quaternion()
		)
	var dst_rest_q_by_idx := {}
	for i in dst_skel.get_bone_count():
		dst_rest_q_by_idx[i] = dst_rest_world_q.get(
			dst_skel.get_bone_name(i),
			dst_global_rest[dst_skel.get_bone_name(i)].basis.get_rotation_quaternion()
		)
	# 目标骨索引反查源骨名（父链递推用）
	var dst_src_of := {} # 目标骨名 -> 源骨名
	for src_bone in BONE_MAP:
		dst_src_of[BONE_MAP[src_bone]] = src_bone

	var src_hips_rest_pos: Vector3 = src_skel.get_bone_rest(src_skel.find_bone("DEF-hips")).origin
	var dst_spine_rest_pos: Vector3 = dst_skel.get_bone_rest(dst_skel.find_bone("spine")).origin
	var src_hips_rest_world_pos: Vector3 = src_global_rest["DEF-hips"].origin

	for t_time in times:
		# ---- 逐骨局部增量搬运（Godot 官方重定向语义）----
		# dst_local(t) = dst_rest_local * (src_rest_local⁻¹ * src_local(t))
		# 两骨架同源 Blender 人形（局部轴语义一致），T-pose vs A-pose 的 rest
		# 差异天然抵消：各自从自身 rest 做相同的关节旋转。
		for i in src_skel.get_bone_count():
			var src_bone := src_skel.get_bone_name(i)
			if not BONE_MAP.has(src_bone):
				continue
			var dst_bone: String = BONE_MAP[src_bone]
			var dst_idx := dst_skel.find_bone(dst_bone)
			var src_local_q: Quaternion
			if src_rot_track.has(src_bone):
				src_local_q = src_anim.rotation_track_interpolate(src_rot_track[src_bone], t_time)
			else:
				src_local_q = src_skel.get_bone_rest(i).basis.get_rotation_quaternion()
			var src_rest_local_q: Quaternion = src_skel.get_bone_rest(i).basis.get_rotation_quaternion()
			var dst_rest_local_q: Quaternion = dst_skel.get_bone_rest(dst_idx).basis.get_rotation_quaternion()
			var delta_local: Quaternion = src_rest_local_q.inverse() * src_local_q
			out.rotation_track_insert_key(rot_track_of[dst_bone], t_time, dst_rest_local_q * delta_local)

		# ---- hips 位置增量（M 旋转搬运，目标父为 RobotArmature 静止单位变换）----
		if src_hips_track >= 0:
			var hips_local: Vector3 = src_anim.position_track_interpolate(src_hips_track, t_time)
			# hips 局部位置 → 世界：Rig * root骨rest * 局部（root 位置轨道仅 1 帧静止，
			# 但其 rest 旋转承担 Z-up→Y-up 转换，漏乘会让 delta 全错）
			var root_idx := src_skel.find_bone("root")
			var root_rest := src_skel.get_bone_rest(root_idx) if root_idx >= 0 else Transform3D.IDENTITY
			var hips_world: Vector3 = src_root_xform * (root_rest * hips_local)
			var delta: Vector3 = hips_world - src_hips_rest_world_pos
			var dst_world_pos: Vector3 = dst_spine_rest_pos + dst_root_q * delta
			out.position_track_insert_key(hips_track, t_time, dst_world_pos)

	return out


## 沿父链累乘 rest，得到骨骼的全局 rest（含骨架根节点变换，本地实例无父级变换）
func _global_rest(skel: Skeleton3D, bone_idx: int) -> Transform3D:
	var result := skel.get_bone_rest(bone_idx)
	var parent := skel.get_bone_parent(bone_idx)
	while parent >= 0:
		result = skel.get_bone_rest(parent) * result
		parent = skel.get_bone_parent(parent)
	# 骨架根节点（Rig / RobotArmature）变换
	var node := skel.get_parent()
	while node != null and node is Node3D:
		result = (node as Node3D).transform * result
		node = node.get_parent()
	return result


func _parent_global_rest(skel: Skeleton3D, bone_idx: int, cache: Dictionary) -> Transform3D:
	var parent := skel.get_bone_parent(bone_idx)
	if parent < 0:
		# 根骨的"父"是骨架根节点变换
		var skel_parent := skel.get_parent()
		var xform := Transform3D.IDENTITY
		while skel_parent != null and skel_parent is Node3D:
			xform = (skel_parent as Node3D).transform * xform
			skel_parent = skel_parent.get_parent()
		return xform
	return cache[skel.get_bone_name(parent)]


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
