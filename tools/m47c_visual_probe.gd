extends Node3D

## M47-C：视觉检查（替代"只测数字"的错误做法）。
##
## 用户原话：「人走路是重影的，方向也不对！你的检查方式不对，优化你自己的检查方式，
## 现在的看不出问题来！」
##
## 旧探针只量位移/半径，测不出"两个模型叠在一起"和"脸朝反了"。
## 这个探针只做三件事：
##   A 清点每个玩家节点下**到底有几个可见的骨架/网格**（重影 = 两套同时在渲染）
##   B 走路时逐帧量「身体实际朝向」与「实际速度方向」的夹角（方向对不对）
##   C 引擎自存帧拍下来，人眼能看见

const OUT_DIR := "res://screenshots/m47"

var _level: Node3D
var _player: Node3D
var _shot_idx := 0


func _ready() -> void:
	Network.SERVER_PORT = 8094
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scn := load("res://scenes/level/level.tscn") as PackedScene
	_level = scn.instantiate() as Node3D
	get_tree().root.call_deferred("add_child", _level)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		printerr("VSP: 需要窗口模式（要真图）")
		get_tree().quit(0)
		return
	# 在创建玩家**之前**把职业定好：_apply_player_appearance 会读 player_info["class"]，
	# 这样 player_class 非空 → 不弹职业菜单，且建号即切到步兵模型。
	# 事后改 player_class 再调 _update_body_visual 会被菜单/覆盖逻辑吃掉。
	Network.player_info["class"] = "infantry"
	_level.call("_on_host_pressed", "诊断", "blue")
	for i in 40:
		await get_tree().create_timer(0.5).timeout
		_player = _find_player()
		if _player != null:
			break
	if _player == null:
		printerr("VSP: 找不到玩家")
		get_tree().quit(0)
		return
	await get_tree().create_timer(1.5).timeout

	# 直接把职业菜单节点删掉（探针只关心 3D 画面）。
	var ui := _level.get_node_or_null("ClassSelectUI")
	if ui != null:
		ui.queue_free()
		await get_tree().process_frame
	# 强制切到步兵（KayKit）模型 —— 用户是战士，这是他实际该看到的模型。
	# 关键实验：切过去之后，机器人骨架有没有真的被隐藏？
	var body = _player.get("_body")
	if body != null:
		body.set("use_alt_body", true)
	await get_tree().create_timer(1.0).timeout

	_dump_players()
	_dump_visual(_player, "本地玩家")

	printerr("VSP: ===== B 静止拍一张 =====")
	await _shot("m47c_00_idle")

	printerr("VSP: ===== C 按住 W：连续拍 6 帧（重影只在运动序列里看得见）=====")
	Input.action_press("move_forward")
	var seq := 0
	for i in 60:
		await get_tree().physics_frame
		if i % 10 == 0:
			await _shot("m47c_seq_%02d" % seq)
			seq += 1
		if i % 12 == 0:
			_report_facing(i)
	Input.action_release("move_forward")
	await get_tree().create_timer(0.6).timeout
	_report_facing(99)

	printerr("VSP: 结束")
	get_tree().quit(0)


## A：谁在同一个位置上存在多个视觉体
func _dump_players() -> void:
	printerr("VSP: ===== A 玩家节点清点 =====")
	var pc := _level.get_node_or_null("PlayersContainer")
	if pc == null:
		printerr("VSP[A] 没有 PlayersContainer")
		return
	var n := 0
	for c in pc.get_children():
		if not (c is Node3D):
			continue
		n += 1
		var p := c as Node3D
		printerr("VSP[A] #%d %s  pos=%s  authority=%s" % [
			n, str(p.name), str(p.global_position.snapped(Vector3(0.01, 0.01, 0.01))),
			str(p.get_multiplayer_authority())])
	printerr("VSP[A] PlayersContainer 共 %d 个玩家节点" % n)


## A2：一个玩家节点下有几个"真正在渲染"的骨架
func _dump_visual(root: Node3D, tag: String) -> void:
	printerr("VSP[A2] ===== " + tag + " 的可见视觉体 =====")
	var skels := 0
	var meshes := 0
	for n in root.find_children("*", "", true, false):
		var nd := n as Node3D
		if nd != null and (nd is Skeleton3D):
			skels += 1
			printerr("VSP[A2]   Skeleton3D  路径=" + str(root.get_path_to(nd)) \
				+ "  自身visible=" + str(nd.visible) \
				+ "  有效可见=" + str(nd.is_visible_in_tree()))
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			meshes += 1
	printerr("VSP[A2] 骨架数=" + str(skels) + "  网格数=" + str(meshes))
	# 关键：两套模型**各自**有多少网格、多少在真正渲染。
	# "重影" = 两条分支同时有网格在可见树里。
	for branch in ["GodotRobot3D/RobotArmature", "GodotRobot3D/InfantryVisual"]:
		var nd := root.get_node_or_null(branch) as Node3D
		if nd == null:
			printerr("VSP[A2]   " + branch + "  不存在")
			continue
		var total := 0
		var visible_meshes := 0
		for n in nd.find_children("*", "MeshInstance3D", true, false):
			total += 1
			if (n as Node3D).is_visible_in_tree():
				visible_meshes += 1
		printerr("VSP[A2]   " + branch + "  自身visible=" + str(nd.visible) \
			+ "  有效可见=" + str(nd.is_visible_in_tree()) \
			+ "  网格=" + str(total) + " 其中可见=" + str(visible_meshes))
	# 直挂在 GodotRobot3D 下、不属于上面两条分支的网格（会变成永不隐藏的残影）
	var stray := 0
	for n in root.get_node("GodotRobot3D").find_children("*", "MeshInstance3D", true, false):
		var p := str(root.get_path_to(n as Node))
		if p.contains("RobotArmature/") or p.contains("InfantryVisual/"):
			continue
		stray += 1
		printerr("VSP[A2]   游离网格: " + p + " 可见=" + str((n as Node3D).is_visible_in_tree()))
	printerr("VSP[A2] 游离网格数=" + str(stray))

	# 【关键】把**真的在渲染**的网格逐个列出来，带世界包围盒尺寸。
	# "重影/头身分离"必须靠这张表定位：谁大得离谱、谁不该在。
	printerr("VSP[A3] ===== 真正在渲染的网格（is_visible_in_tree）=====")
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		printerr("VSP[A3]   " + str(root.get_path_to(mi)) \
			+ "  世界尺寸=(" + str(snappedf(aabb.size.x, 0.01)) \
			+ ", " + str(snappedf(aabb.size.y, 0.01)) \
			+ ", " + str(snappedf(aabb.size.z, 0.01)) + ")" \
			+ "  中心y=" + str(snappedf(aabb.position.y + aabb.size.y * 0.5, 0.01)))


## B：脸朝哪 vs 实际往哪走
func _report_facing(i: int) -> void:
	var v: Vector3 = _player.get("velocity")
	var body = _player.get("_body")
	if body == null:
		printerr("VSP[B] _body 为空")
		return
	var b := (body as Node3D).global_transform.basis
	var face: Vector3 = b.z            # 模型正面 = 局部 +Z
	var up: Vector3 = Planet.up_at(_player.global_position)
	var vh: Vector3 = v - up * v.dot(up)
	var line := "VSP[B] 帧%02d |v|=%.2f " % [i, v.length()]
	line += "脸方向=(%.2f,%.2f,%.2f) " % [face.x, face.y, face.z]
	if vh.length() > 0.1:
		var ang: float = rad_to_deg(face.angle_to(vh))
		line += "速度方向=(%.2f,%.2f,%.2f) 夹角=%.1f° " % [vh.normalized().x, vh.normalized().y, vh.normalized().z, ang]
		line += "→ " + ("对" if ang < 25.0 else ("歪" if ang < 70.0 else "反了"))
	else:
		line += "（没在动）"
	# 身体本地 Y 与当地法线的夹角（模型是否立正）
	var body_up: Vector3 = b.y
	line += "  身体Y·法线夹角=%.1f°" % rad_to_deg(body_up.angle_to(up))
	printerr(line)


func _shot(base: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("VSP: 取帧失败")
		return
	var nm := "%s/%s.png" % [OUT_DIR, base]
	img.save_png(nm)
	printerr("VSP: 已存 " + nm)


func _find_player() -> Node3D:
	var pc := _level.get_node_or_null("PlayersContainer")
	if pc != null:
		for c in pc.get_children():
			if c is Node3D:
				return c as Node3D
	return null
