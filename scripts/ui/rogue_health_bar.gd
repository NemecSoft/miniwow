class_name RogueHealthBar
extends Node3D

## M18b-6：roguelite 双层头顶血条。
## 结构与数值照抄 godot-roguelite Components/health_bar.tscn / health_bar.gd：
## 彩色前条（立即跳变）+ 灰色后条（0.2s 缓动跟随，形成掉血残影）。
## 适配层：原版由 HealthComponent 信号驱动；MiniWoW 无该组件，
## 改为 monster.gd / player.gd 在血量同步接收端直接调 set_health()。

@export var health_color: Color = Color(0.8901961, 0.2901961, 0.25882354, 1)

@onready var front_progress_bar: ProgressBar = $SubViewport/FrontProgressBar
@onready var health_progress_bar: ProgressBar = $SubViewport/HealthProgressBar
@onready var sprite_3d: Sprite3D = $Sprite3D

func _ready() -> void:
	front_progress_bar.value = 100.0
	health_progress_bar.value = 100.0
	# resource_local_to_scene 保证多实例各自改色不串（tscn 中已声明）
	front_progress_bar.get_theme_stylebox("fill").bg_color = health_color
	# 等宿主把模型可见性定下来（步兵/机器人形态切换在 _ready 里）再量包围盒
	call_deferred("_fit_above_owner")


## 【M53】血条位置与宽度全部按**宿主自己的几何**推导，不再写死 2.4 / 2.6 / 1.5。
##
## 旧 tscn 里玩家 y=2.4、怪物 y=2.6、玩家 scale=1.5 —— 三个魔数：
##   · 换职业/换体型 → 血条要么糊在脸上要么飘在天上
##   · Sprite3D 用 billboard=FIXED_Y（固定世界 Y 轴），球面上"上"是当地法线，
##     镜头一转血条就被拉斜，看起来像一条横带飘在半空（用户报的"重影"之一）
##
## 高度取**物理碰撞体**而不是网格 AABB：角色是蒙皮网格，`mesh.get_aabb()` 返回的是
## 绑定姿势的盒子（实测玩家量出 1.01m，人实际 1.8m），用它血条会埋进胸口。
## 碰撞胶囊才是"这个人占多大空间"的权威答案。
func _fit_above_owner() -> void:
	var host := get_parent() as Node3D
	if host == null:
		return
	var top: float = _host_top(host)
	var width: float = _host_width(host)
	if top <= 0.0 or width <= 0.0:
		return
	var sprite := get_node_or_null("Sprite3D") as Sprite3D
	if sprite == null:
		return
	# 血条自身在世界里的高度/宽度（pixel_size × 视口像素 × 节点缩放）
	var tex_h: float = float(sprite.texture.get_height()) if sprite.texture != null else 16.0
	var tex_w: float = float(sprite.texture.get_width()) if sprite.texture != null else 128.0
	# 宽度：略宽于模型（BAR_WIDTH_RATIO 是"血条相对体型"的设计比例，不是世界尺寸）
	var want_w: float = width * BAR_WIDTH_RATIO
	# 必须**均匀**缩放：Sprite3D 是 billboard，非均匀缩放会把平面拉歪
	# （实测把 scale.x 单独压小后，血条被拉成一根竖条）。
	# 所以只决定"多宽"，高度由纹理本身的 8:1 比例带出来。
	var uniform: float = want_w / (sprite.pixel_size * tex_w)
	scale = Vector3(uniform, uniform, uniform)
	var bar_h: float = sprite.pixel_size * tex_h * uniform
	# 间距：血条下沿与模型顶部留出血条自身高度的一半，永不相交
	position.y = top + bar_h * 0.5


## 宿主"有多高"：碰撞体与网格 AABB 取**较大者**。
## 只用碰撞体会低估（怪物胶囊统一 1.7m，但狼模型只有 0.8m 时血条飘得老高）；
## 只用网格 AABB 会低估（蒙皮网格返回绑定姿势盒子）。两者取大最稳。
func _host_top(host: Node3D) -> float:
	var best := -INF
	for n in host.find_children("*", "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		if cs == null or cs.shape == null or not cs.is_visible_in_tree():
			continue
		if cs.get_parent() is Area3D:
			continue # 交互探测区不是身体尺寸
		var shape := cs.shape
		var h := 0.0
		if shape is CapsuleShape3D:
			h = (shape as CapsuleShape3D).height
		elif shape is BoxShape3D:
			h = (shape as BoxShape3D).size.y
		elif shape is CylinderShape3D:
			h = (shape as CylinderShape3D).height
		if h <= 0.0:
			continue
		best = maxf(best, cs.position.y + h * 0.5 * cs.scale.y)
	for n in host.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var rel := host.global_transform.affine_inverse() * mi.global_transform
		var ab: AABB = mi.mesh.get_aabb()
		best = maxf(best, (rel * ab.get_center()).y + ab.size.y * rel.basis.get_scale().y * 0.5)
	return best if best != -INF else 0.0


## 宿主"有多宽"：碰撞体与网格 AABB 取较大者（同上）。
func _host_width(host: Node3D) -> float:
	var best := 0.0
	for n in host.find_children("*", "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		if cs.get_parent() is Area3D:
			continue
		var shape := cs.shape
		var w := 0.0
		if shape is CapsuleShape3D:
			w = (shape as CapsuleShape3D).radius * 2.0
		elif shape is BoxShape3D:
			w = (shape as BoxShape3D).size.x
		elif shape is CylinderShape3D:
			w = (shape as CylinderShape3D).radius * 2.0
		best = maxf(best, w * absf(cs.scale.x))
	for n in host.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var rel := host.global_transform.affine_inverse() * mi.global_transform
		best = maxf(best, mi.mesh.get_aabb().size.x * rel.basis.get_scale().x)
	return best


## 血条宽度相对模型宽度的比例（设计值：略宽于肩膀，读得清又不糊住身体）
const BAR_WIDTH_RATIO := 1.15

func set_health(current: float, max_value: float) -> void:
	if max_value <= 0.0:
		return
	# 原版逻辑：彩条立即跳到目标百分比，灰条 0.2s 从彩条旧值滑过去（残影）
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	var target_health_percentage := (current / max_value) * 100.0
	tween.tween_property(health_progress_bar, "value", target_health_percentage, 0.2) \
			.from(front_progress_bar.value)
	front_progress_bar.value = target_health_percentage

func fade_out() -> void:
	# 原版 defeat()：0.2s 淡出（死亡时调用）
	var tween = create_tween()
	tween.tween_property(sprite_3d, "transparency", 1.0, 0.2).from(0.0)
