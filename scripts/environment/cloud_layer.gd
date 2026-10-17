extends Node3D

## M6 蓝天白云：3D 云层（纯表现层，不走网络，各端本地漂移）。
## 12 朵云 × 3 个压扁球体簇，统一速度向东漂移，出界环绕（需求：方向/速度统一）。
## 材质纯白粗糙；不投影（避免云影在地面乱跳形成动态黑斑）。

const CLOUD_COUNT := 12
const BLOBS_PER_CLOUD := 3
const DRIFT_SPEED := 2.0 ## 统一漂移速度（米/秒）
const WRAP_MIN_X := -150.0
const WRAP_MAX_X := 150.0
const HEIGHT_MIN := 55.0
const HEIGHT_MAX := 78.0
const Z_CENTER := 45.0 ## 世界内容集中在 z∈[-30,155]，云层覆盖之


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261016
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.roughness = 1.0
	material.metallic = 0.0
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	for i in CLOUD_COUNT:
		var cluster := Node3D.new()
		cluster.position = Vector3(
			rng.randf_range(WRAP_MIN_X, WRAP_MAX_X),
			rng.randf_range(HEIGHT_MIN, HEIGHT_MAX),
			rng.randf_range(Z_CENTER - 95.0, Z_CENTER + 110.0)
		)
		for j in BLOBS_PER_CLOUD:
			var blob := MeshInstance3D.new()
			blob.mesh = sphere
			blob.material_override = material
			blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			blob.scale = Vector3(
				rng.randf_range(5.0, 10.0),
				rng.randf_range(2.2, 3.6),
				rng.randf_range(4.0, 8.0)
			)
			blob.position = Vector3(
				rng.randf_range(-4.0, 4.0),
				rng.randf_range(-1.2, 1.2),
				rng.randf_range(-3.0, 3.0)
			)
			cluster.add_child(blob)
		add_child(cluster)


func _process(delta: float) -> void:
	for cluster in get_children():
		if cluster is Node3D:
			cluster.position.x += DRIFT_SPEED * delta
			if cluster.position.x > WRAP_MAX_X:
				cluster.position.x -= (WRAP_MAX_X - WRAP_MIN_X)
