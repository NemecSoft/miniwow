class_name ClassPreviewViewport
extends SubViewportContainer

## M24：职业卡 3D 模型预览（通用组件，官方成熟方案）。
## 方案照抄 Godot 官方 snippet（GitLab 2323028「Render a scene to texture」）：
##   不调相机适配模型，而是把模型归一化缩放 + 居中去适配固定相机——任何模型零调参。
##   核心 API：VisualInstance3D.get_transformed_aabb() 递归合并 → 缩放物体充满视锥。
## 每张卡顶部一个透明背景小视口：实例化该职业模型 + 职业色底光 + 缓慢自转。
## 模型外观与游戏内一致：默认 GodotRobot 身体，步兵用 KayKit Mannequin
## （同 player.gd sync_class 的 use_alt_body 逻辑）。

const BODY_SCENE := "res://scenes/monsters/robot_body.tscn"
const ALT_BODY_SCENE := "res://scenes/characters/infantry_mannequin.tscn"

## 相机固定参数：模型会缩放适配这个视锥，永远不需要动
const CAM_DIST := 4.0
const CAM_FOV := 40.0
const FILL_RATIO := 0.55  # 模型高度占视锥高度的比例（留边距）

var _model_root: Node3D = null   # 自转与缩放适配都作用在这个节点上
var _vp: SubViewport = null      # 内部 3D 视口（懒创建，调用顺序无关）
var _spin_speed := 0.9           # 弧度/秒，缓慢展示


func _ready() -> void:
	_ensure_viewport()


## 懒初始化：无论 _ready 还是 show_class 先到，视口都保证存在
func _ensure_viewport() -> void:
	if _vp != null:
		return
	stretch = true
	custom_minimum_size = Vector2(0, 118)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_vp = SubViewport.new()
	_vp.transparent_bg = true          # 透出卡片木纹背景
	_vp.own_world_3d = true            # 独立 3D 世界，不受游戏场景相机/雾影响
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)

	# 相机：固定在 (0,0,CAM_DIST) 沿 -Z 看原点，一次设好永不再调（官方法核心）
	var cam := Camera3D.new()
	cam.fov = CAM_FOV
	cam.position = Vector3(0, 0, CAM_DIST)
	_vp.add_child(cam)

	# 主光 + 逆光：保证模型在透明背景下清晰立体
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	_vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.5
	_vp.add_child(fill)


## 展示指定职业：class_tint = 职业主题色（脚下光圈颜色）
func show_class(class_id: String, class_tint: Color, use_alt_body: bool) -> void:
	_ensure_viewport()
	if _model_root != null:
		_model_root.queue_free()
		_model_root = null

	var scene_path := ALT_BODY_SCENE if use_alt_body else BODY_SCENE
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return
	var model: Node3D = packed.instantiate()
	_model_root = Node3D.new()
	_model_root.add_child(model)
	_vp.add_child(_model_root)

	# 播 Idle 待机动画（两套模型的动画库键名都叫 "Idle"）
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if anim and anim.has_animation("Idle"):
		anim.play("Idle")

	# 官方法 fit：skinned mesh 的视觉姿态由动画驱动，先等首帧再算 AABB
	_fit_model.call_deferred(model)

	# 职业色底光：用模型局部坐标定位在脚下前方，fit 时随模型一起缩放居中
	var aabb := _compute_aabb(model)
	var glow := OmniLight3D.new()
	glow.light_color = class_tint
	glow.light_energy = 1.1
	glow.omni_range = 2.2
	glow.position = Vector3(0, aabb.position.y + 0.1, aabb.size.z * 0.3)
	_model_root.add_child(glow)


func _process(delta: float) -> void:
	if _model_root != null and visible:
		_model_root.rotate_y(delta * _spin_speed)


## 官方 snippet 核心：归一化缩放 + 居中，让任何模型恰好充满固定视锥
func _fit_model(model: Node3D) -> void:
	if not is_inside_tree():
		_apply_fit(model)  # 未进树时无动画帧可等，用静态 AABB 直接 fit
		return
	await get_tree().process_frame  # 等 Idle 首帧姿态生效
	if is_instance_valid(_model_root) and model.get_parent() == _model_root:
		_apply_fit(model)


func _apply_fit(model: Node3D) -> void:
	if _model_root == null or not is_instance_valid(_model_root):
		return
	var aabb := _compute_aabb(model)
	# 缩放以模型高度为主导（人形预览高度优先）：横向武器/挂件不会压小整体缩放
	var max_side := maxf(aabb.size.y, 0.001)
	if max_side <= 0.001:
		return
	var view_height := 2.0 * tan(deg_to_rad(CAM_FOV) * 0.5) * CAM_DIST
	var s := view_height * FILL_RATIO / max_side
	var xform := Transform3D()
	xform.basis = xform.basis.scaled(Vector3(s, s, s))
	xform.origin = -(xform.basis * aabb.get_center())  # 官方居中技巧：缩放后中心归零
	_model_root.transform = xform


## AABB 递归合并（官方 snippet 思路的 Godot 4 版：get_transformed_aabb 已在 4.x 移除，
## 改为局部 get_aabb() + 沿父链累积 transform，不依赖 SceneTree——组件可未进树被调用）。
## skinned mesh 例外：静态 mesh AABB 会严重虚胖（KayKit mannequin 实测 4.2m，人形
## 实际 1.8m），凡带 Skeleton3D 的模型一律改用骨骼关节点盒（_skeleton_aabb）。
func _compute_aabb(n: Node3D, parent_xform := Transform3D.IDENTITY) -> AABB:
	var skeletons := n.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		return _skeleton_aabb(n, skeletons)

	var xform := parent_xform * n.transform
	var aabb := AABB()
	var first := true
	if n is VisualInstance3D:
		aabb = xform * (n as VisualInstance3D).get_aabb()
		first = false
	for child in n.get_children():
		if child is Node3D:
			var child_aabb := _compute_aabb(child as Node3D, xform)
			if child_aabb.size.length() <= 0.0:
				continue  # 空包围盒（如纯骨架节点）不参与合并
			if first:
				aabb = child_aabb
				first = false
			else:
				aabb = aabb.merge(child_aabb)
	return aabb


## 骨骼关节点盒：Idle 首帧后取各骨骼 global pose（关节连线即身体轮廓），
## 换算到模型空间合并，加 10% padding 覆盖头脚超出关节的体积。任何骨架模型自适应。
func _skeleton_aabb(model: Node3D, skeletons: Array) -> AABB:
	var min_v := Vector3.INF
	var max_v := -Vector3.INF
	for s in skeletons:
		var skel := s as Skeleton3D
		# 骨架节点在 model 空间的累积变换（不经过 SceneTree，纯局部链）
		var xform := Transform3D.IDENTITY
		var chain: Array = []
		var node: Node = skel
		while node != null and node != model:
			chain.push_front(node)
			node = node.get_parent()
		for nd in chain:
			xform = xform * (nd as Node3D).transform
		for i in skel.get_bone_count():
			var p: Vector3 = xform * skel.get_bone_global_pose(i).origin
			min_v = min_v.min(p)
			max_v = max_v.max(p)
	if min_v.x > max_v.x:
		return AABB()  # 无有效骨骼点，退回空盒（调用方按无效处理）
	var aabb := AABB(min_v, max_v - min_v)
	return aabb.grow(aabb.size.length() * 0.1)
