extends Node

## 探针 v2：直接测 SunLight 能量与角度（最终决定画面亮暗的东西），
## 对比 SIMPLE/REALISTIC 两种天体模式 × 北京参数。
## headless 跑：godot --headless --path . res://tools/probe_sky3d.tscn

func _ready() -> void:
	for mode_name in ["SIMPLE", "REALISTIC"]:
		var sky3d := Sky3D.new()
		add_child(sky3d)
		var tod = sky3d.tod
		var sun: DirectionalLight3D = sky3d.sun
		tod.celestials_calculations = TimeOfDay.CelestialMode.SIMPLE if mode_name == "SIMPLE" else TimeOfDay.CelestialMode.REALISTIC
		tod.utc = 8.0
		tod.longitude = deg_to_rad(116.4)
		tod.latitude = deg_to_rad(39.9)
		tod.day = 17
		tod.month = 10
		tod.year = 2026
		print("=== %s 模式（utc=8, 北京经纬度）===" % mode_name)
		for t in [6.0, 9.0, 12.0, 15.0, 18.0]:
			tod.current_time = t
			await get_tree().process_frame
			var energy: float = sun.light_energy
			var fwd: Vector3 = -sun.global_transform.basis.z # 光照来向
			print("  %.0f:00 sun_energy=%.2f 光来自 %s" % [t, energy, fwd])
		sky3d.queue_free()
		await get_tree().process_frame
	print("=== done ===")
	get_tree().quit()
