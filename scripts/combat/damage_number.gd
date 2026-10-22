class_name DamageNumber
extends Label3D

## 伤害飘字：纯表现层，收到服务器伤害广播后各客户端本地生成，互不信赖。

static func spawn(parent: Node, world_position: Vector3, amount: int, is_crit: bool, tint: Color = Color(1.0, 0.9, 0.3)) -> void:
	if parent == null:
		return
	var label := DamageNumber.new()
	label.text = str(amount)
	label.font = load("res://assets/fonts/Kurland.ttf")
	label.pixel_size = 0.09 if is_crit else 0.06
	label.modulate = Color(1.0, 0.55, 0.1) if is_crit else tint
	label.outline_size = 12
	label.outline_modulate = Color(0, 0, 0, 1)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = world_position + Vector3(randf_range(-0.35, 0.35), randf_range(0, 0.4), randf_range(-0.35, 0.35))
	label.scale = Vector3.ONE * (1.4 if is_crit else 1.0)
	parent.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position", label.position + Vector3(0, 1.4, 0), 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.tween_callback(label.queue_free)


## 受击抖动：原地弹一下，给"打中了"的反馈。
## M25e 修复（"bot 被打变大"根因）：旧实现回弹目标取调用时的 node.scale，
## 怪物被连续攻击时每次回弹基准都被前一次放大，scale 指数级上涨
## （4 bot 围殴狼实测叠到 1.25+）；并发 tween 也无人管理互相打架。
## 现改为：固定基准 Vector3.ONE 弹起，节点上托管 tween，新抖动先 kill 旧抖动。
## 前提：受击抖动对象的根 scale 基准为 1（怪物/玩家的 scale_factor 都作用于
## 子节点 body_model，不碰根——monster.gd _apply_body_variant）。
static func shake(node: Node3D) -> void:
	if node == null:
		return
	# M25e：必须 has_meta 前置——Godot 4.7 的 get_meta 对缺失 key 一律报引擎
	# ERROR 并刷屏（实测：带 null default 的双参版本也报，每次受击两条错误）
	var old_tween: Tween = null
	if node.has_meta("_shake_tween"):
		old_tween = node.get_meta("_shake_tween") as Tween
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	var tween := node.create_tween()
	node.set_meta("_shake_tween", tween)
	# 供体型看门狗识别"合法抖动窗口"（level.gd）：抖动总时长 0.13s，留余量
	node.set_meta("_shake_until_msec", Time.get_ticks_msec() + 300)
	tween.tween_property(node, "scale", Vector3.ONE * 1.15, 0.05)
	tween.tween_property(node, "scale", Vector3.ONE, 0.08)
