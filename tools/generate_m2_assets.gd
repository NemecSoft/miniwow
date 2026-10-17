extends SceneTree

## M2 资产生成工具（一次性运行）：
## 1. 基于模板自带的 GodotPalette.png 生成 4 个怪物配色（gray/brown/purple/bone）
## 2. 从 player.tscn 手术出精简的机器人身体场景 robot_body.tscn
##    （去掉相机/HUD/名牌/同步器/脚本，保留骨架、动画、装备挂点）
## 运行方式：godot --headless --script tools/generate_m2_assets.gd

const PALETTE_DIR := "res://assets/characters/player/GodotRobotPaletteSwap/"
const PALETTE_SRC := "res://assets/characters/player/GodotRobotPaletteSwap/GodotPalette.png"


func _initialize() -> void:
	var palette_ok := _generate_palettes()
	var body_ok := _generate_robot_body()
	if palette_ok and body_ok:
		print("generate_m2_assets: 全部完成")
		quit(0)
	else:
		push_error("generate_m2_assets: 存在失败项")
		quit(1)


func _generate_palettes() -> bool:
	var src := Image.load_from_file(PALETTE_SRC)
	if src == null:
		push_error("无法加载调色板源图: " + PALETTE_SRC)
		return false
	print("源图尺寸: %dx%d" % [src.get_width(), src.get_height()])
	var variants := {
		"gray": {"hue": 0.0, "sat": 0.12, "val": 1.0},
		"brown": {"hue": 28.0, "sat": 1.15, "val": 0.95},
		"purple": {"hue": 105.0, "sat": 1.1, "val": 1.0},
		"bone": {"hue": -15.0, "sat": 0.3, "val": 1.2},
	}
	for variant_name in variants:
		var params: Dictionary = variants[variant_name]
		var image := _recolor(src, params.hue, params.sat, params.val)
		var path: String = PALETTE_DIR + "Godot" + variant_name.capitalize() + "Palette.png"
		var err := image.save_png(path)
		if err != OK:
			push_error("保存调色板失败: " + path)
			return false
		print("已生成调色板: " + path)
	return true


func _recolor(src: Image, hue_shift: float, sat_mul: float, val_mul: float) -> Image:
	var image := src.duplicate() as Image
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a <= 0.0:
				continue
			var h := wrapf(color.h * 360.0 + hue_shift, 0.0, 360.0) / 360.0
			var s := clampf(color.s * sat_mul, 0.0, 1.0)
			var v := clampf(color.v * val_mul, 0.0, 1.0)
			image.set_pixel(x, y, Color.from_hsv(h, s, v, color.a))
	return image


func _generate_robot_body() -> bool:
	var packed_player := load("res://scenes/level/player.tscn") as PackedScene
	if packed_player == null:
		push_error("无法加载 player.tscn")
		return false
	var player := packed_player.instantiate()
	# 摘掉玩家专属节点（相机/弹簧臂/第一人称HUD/名牌/同步器/属性/拾取区）
	var remove_paths := [
		"CollisionShape3D",
		"SpringArmOffset",
		"FirstPersonHUD",
		"PlayerNick",
		"MultiplayerSynchronizer",
		"AttributeSet",
		"GodotRobot3D/InfrontArea3D",
	]
	for node_path in remove_paths:
		var node := player.get_node_or_null(node_path)
		if node:
			node.get_parent().remove_child(node)
			node.free()
	# 去掉根节点的玩家脚本和机器人身体脚本（动画由 monster.gd 直接驱动）
	player.set_script(null)
	var body := player.get_node_or_null("GodotRobot3D") as Node3D
	if body == null:
		push_error("找不到 GodotRobot3D")
		return false
	body.set_script(null)
	# 删除第一人称相机残骸
	for junk_path in ["FirstPersonCameraSource"]:
		var junk := body.get_node_or_null(junk_path)
		if junk:
			body.remove_child(junk)
			junk.free()
	# 删除挂点下预设装备：改由 monster.gd 运行时按 MonsterData 动态挂载，
	# 避免 pack() 把 fbx/glb 内部结构内联烘焙进场景（否则文件膨胀且 import 报错）
	for attach_path in [
		"RobotArmature/Skeleton3D/LeftHandAttach",
		"RobotArmature/Skeleton3D/HeadAttach",
		"RobotArmature/Skeleton3D/BackAttach",
	]:
		var attach := body.get_node_or_null(attach_path)
		if attach:
			for equipment in attach.get_children():
				attach.remove_child(equipment)
				equipment.free()
	# 把 body 子树所有节点的 owner 改为 body 自身，以便以 body 为根重新打包
	_set_owner_recursive(body, body)
	var packed_body := PackedScene.new()
	var err := packed_body.pack(body)
	if err != OK:
		push_error("打包 robot_body 失败: " + str(err))
		return false
	err = ResourceSaver.save(packed_body, "res://scenes/monsters/robot_body.tscn")
	if err != OK:
		push_error("保存 robot_body.tscn 失败: " + str(err))
		return false
	print("已生成场景: res://scenes/monsters/robot_body.tscn")
	return true


func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	node.owner = new_owner
	for child in node.get_children():
		_set_owner_recursive(child, new_owner)
