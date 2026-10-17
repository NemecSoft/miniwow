extends SceneTree

func _init() -> void:
	var scene := load("res://scenes/level/player.tscn") as PackedScene
	var player := scene.instantiate()
	player.name = "1"
	root.add_child(player)
	await process_frame
	await process_frame
	var body := player.get_node_or_null("GodotRobot3D") as Node3D
	var anim := player.get_node_or_null("GodotRobot3D/AnimationPlayer") as AnimationPlayer
	# 先跑 180 物理帧（复现 _test_player_facing 的时长与状态）
	for i in range(180):
		body.apply_rotation(Vector3(0, 0, -3))
		await physics_frame
	print("PROBE: 180帧后 anim=%s is_playing=%s current='%s'" % [
		anim != null, str(anim.is_playing() if anim else false), anim.current_animation if anim else ""])
	print("PROBE: body.animation_player(脚本引用)=%s has_animation(Attack1)=%s" % [
		str(body.get("animation_player") != null),
		str(anim.has_animation("Attack1") if anim else false)])
	print("PROBE: _last_requested_animation='%s' is_attacking=%s" % [
		str(player.get("_last_requested_animation")), str(player.is_attacking)])
	# 现在触发攻击动画
	player._request_animation(&"Attack1", true)
	print("PROBE: 触发后 is_attacking=%s current='%s' is_playing=%s" % [
		str(player.is_attacking), anim.current_animation, str(anim.is_playing())])
	player._request_animation(&"Idle")
	print("PROBE: 请求Idle后 current='%s'" % anim.current_animation)
	quit(0)
