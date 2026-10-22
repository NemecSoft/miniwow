extends Node

## M39 一次性烘焙工具：把 terrain_forest 数据区南扩到 z=-1792。
##
## 【为什么要扩】需求 2 要求怪物/任务点拉到 1500m 外（世界 z≈-1650）。
## headless 实测（M39 探针）：烘焙目录里 region_size 实际是 **256**（不是代码里
## 写的 DEMO_REGION_SIZE=1024），数据区只覆盖 x[-256,512] / z[-768,512]。
## z=-1600 处 get_height 返回 NaN → 怪物自由落体、飞行器 autopilot 探不到
## 地面会往下坠。必须先把数据铺过去。
##
## 【范围】新增 region（region_size=256）：
##   (0,-3)：M35 历史漏块——实测 x∈[0,256]/z[-768,-512] 整块无数据，
##          而 x=0 恰在此缺口内（探针：最后有效 z=-510 / 第一个 NaN z=-514），
##          bot 从村往南飞的航路会踩空。必须补。
##   (-1,-4) (0,-4) … (-1,-7) (0,-7)：南扩 4 行 → x[-256,256] / z[-1792,-768]
##   怪物落点 x∈[-85,88]、z∈[-1712,-1550] 全在其中；
##   bot 从村 (0,·,-130) 直飞过去的航路也全程有地面。
##
## 【风格】与 M35 丘陵同参（SimpleSmooth / freq 0.0012 / seed 20261021 / ±7m）；
## 像素按**世界坐标**手写采样，不用 noise.get_image()——实测 noise.offset
## 对 get_image() 不生效（8 块 region 中心高度完全相同，图案 256m 一格重复）。
##
## 【边缘】新 region 的四边 64m 带 blend 到 0（与 M35 做法一致），
## 防止 clipmap 环边顶点 0↔7m 跳变被拉成垂直黑墙。
##
## 跑法：
##   godot --headless --path . res://tools/m39_bake_far_terrain.tscn
## 幂等：已存在的 region 会先 remove 再重建，重复跑结果一致。

const FOREST_DIR := "res://assets/terrain_forest"
const REGION_SIZE := 256
## 新增 region 列表（Vector2i(region_x, region_z)）
const NEW_REGIONS := [
	Vector2i(0, -3),
	Vector2i(-1, -4), Vector2i(0, -4),
	Vector2i(-1, -5), Vector2i(0, -5),
	Vector2i(-1, -6), Vector2i(0, -6),
	Vector2i(-1, -7), Vector2i(0, -7),
]
const NOISE_SEED := 20261021
const HEIGHT_MIN := -7.0
const HEIGHT_MAX := 7.0
const EDGE_BLEND := 64.0

var _t: Terrain3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOREST_DIR))
	_t = Terrain3D.new()
	_t.name = "Terrain3D"
	_t.region_size = REGION_SIZE
	_t.data_directory = FOREST_DIR
	add_child(_t, true)
	await get_tree().process_frame
	await _bake()
	get_tree().quit()


func _bake() -> void:
	var d := _t.data
	print("[M39-BAKE] 载入 region_size=", _t.region_size, " 现有 region=", d.get_region_count())
	# 村基准点必须在（扩region 不能破坏既有数据）
	print("[M39-BAKE] 村基准 h(0,-130)=", d.get_height(Vector3(0, 0, -130)))

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.0012
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0
	noise.seed = NOISE_SEED

	var built := 0
	var existing := d.get_regions_all()
	for loc in NEW_REGIONS:
		# 幂等：先删掉同名旧 region（remove_regionl 走 false=不报错）
		if existing.has(loc):
			d.remove_regionl(loc, false)
		var ox: int = loc.x * REGION_SIZE
		var oz: int = loc.y * REGION_SIZE
		#【M39 修正】手写像素按**世界坐标**采样，不用 get_image()：
		# 实测 FastNoiseLite.offset 对 get_image() 不生效——8 块 region
		# 中心高度完全相同（-4.145/-3.322），每块图案完全重复，
		# 站在高处一眼看出 256m 一格的拼贴缝。get_noise_2d(world_x, world_z)
		# 直接喂世界坐标 → 跨 region 图案天然连续。
		var img := Image.create_empty(REGION_SIZE, REGION_SIZE, false, Image.FORMAT_RF)
		for y in range(REGION_SIZE):
			for x in range(REGION_SIZE):
				var wx: float = float(ox + x)
				var wz: float = float(oz + y)
				# ±7m：噪声 [-1,1] → 高度值，随后 import_images 的 min/max 再归一
				var h: float = noise.get_noise_2d(wx, wz) * 0.5 + 0.5
				img.set_pixel(x, y, Color(h, h, h, 1.0))
		# 【M39 顶点色补丁】import_images 的 images 数组 = [height, control, color]，
		# 原代码第三格传 null → color_maps 全空。Terrain3D 的 clipmap 内环
		#（相机周围一圈，用它做 LOD 混合）没有顶点色就渲染成一块蓝色空洞
		#（screenshots/m39/m39_2a_hunt.png）。补一张纯白 RGB + A=1 的 color 图。
		# 顺带把 control_map 也补上（草地 type=1，避免无 control 时按纯岩处理）。
		var ctrl := Image.create_empty(REGION_SIZE, REGION_SIZE, false, Image.FORMAT_RF)
		var colr := Image.create_empty(REGION_SIZE, REGION_SIZE, false, Image.FORMAT_RGB8)
		for y in range(REGION_SIZE):
			for x in range(REGION_SIZE):
				ctrl.set_pixel(x, y, Color(1.0, 0.0, 0.0, 1.0))   # 草地(下槽)
				colr.set_pixel(x, y, Color(1.0, 1.0, 1.0))          # 纯白顶点色
		d.import_images([img, ctrl, colr], Vector3(ox, 0, oz), HEIGHT_MIN, HEIGHT_MAX)
		built += 1
		print("[M39-BAKE] import region=", loc, " origin=(", ox, ",", oz, ")")

	# import_images 是内存写，Terrain3D 内部 buffer 提交要若干帧——
	# 没提交前 get_height 读 NaN。逐 region 等探针点读到非 NaN。
	for loc in NEW_REGIONS:
		var ox: int = loc.x * REGION_SIZE
		var oz: int = loc.y * REGION_SIZE
		var probe := Vector3(float(ox) + 128.0, 0.0, float(oz) + 128.0)
		var waited := 0
		while waited < 600 and is_nan(d.get_height(probe)):
			await get_tree().process_frame
			waited += 1
		print("[M39-BAKE] region ", loc, " 就绪 frames=", waited, " h=", d.get_height(probe))

	# ===== 旧 region 补顶点色 =====
	# M35 时代 import 时 images 数组第三格（color）传的是 null，全项目
	# color_maps 都空。Terrain3D 的 clipmap 内环（相机周围一圈，用顶点色做
	# LOD 混合）没颜色就渲染成一块规整的蓝色空洞——村附近不明显（内环
	# 被 GridMap 村底图盖住），1500m 外的狩猎区就是一片蓝。
	# 这里给**全部** region（含 M35 老数据）补纯白顶点色，不改高度。
	var patched := 0
	for loc2 in d.get_regions_all():
		var ox2: int = loc2.x * REGION_SIZE
		var oz2: int = loc2.y * REGION_SIZE
		var ctrl2 := Image.create_empty(REGION_SIZE, REGION_SIZE, false, Image.FORMAT_RF)
		var colr2 := Image.create_empty(REGION_SIZE, REGION_SIZE, false, Image.FORMAT_RGB8)
		for y in range(REGION_SIZE):
			for x in range(REGION_SIZE):
				ctrl2.set_pixel(x, y, Color(1.0, 0.0, 0.0, 1.0))
				colr2.set_pixel(x, y, Color(1.0, 1.0, 1.0))
		d.import_images([null, ctrl2, colr2], Vector3(ox2, 0, oz2), 0.0, 0.0)
		patched += 1
	print("[M39-BAKE] 顶点色补丁完成 region 数=", patched)

	# 四边 64m blend 到 0（与 M35 _generate_forest_terrain 同做法）
	var blend_changed := 0
	for loc in NEW_REGIONS:
		var ox: int = loc.x * REGION_SIZE
		var oz: int = loc.y * REGION_SIZE
		for x in range(ox, ox + REGION_SIZE, 4):
			for z in range(oz, oz + REGION_SIZE, 4):
				var h: float = d.get_height(Vector3(x, 0, z))
				if is_nan(h):
					continue
				var dx: float = minf(float(x - ox), float(ox + REGION_SIZE - x))
				var dz: float = minf(float(z - oz), float(oz + REGION_SIZE - z))
				var f: float = clampf(minf(dx, dz) / EDGE_BLEND, 0.0, 1.0)
				if f < 1.0:
					d.set_height(Vector3(x, 0, z), h * f)
					blend_changed += 1
	print("[M39-BAKE] 边缘 blend 完成 changed=", blend_changed, " built=", built)

	# 清理：import/set_height 会把 clipmap 环触及范围 blank 成空 region。
	# 白名单 = 原有 13 个 + 本次新增 8 个 + x 向缓冲（航路 x∈[-256,256] 已含）。
	var keep := {}
	for x in [-1, 0, 1]:
		for y in range(-8, 2):
			keep[Vector2i(x, y)] = true
	var removed := 0
	for loc in d.get_regions_all():
		if not keep.has(loc):
			d.remove_regionl(loc, false)
			removed += 1
	print("[M39-BAKE] 空白 region 清理 removed=", removed, " 剩余=", d.get_region_count())

	d.save_directory(ProjectSettings.globalize_path(FOREST_DIR))
	print("[M39-BAKE] 已保存 ", FOREST_DIR, " regions=", d.get_region_count())

	# ===== 保存后立刻读回验证（防"存了但读不出"的幻觉）=====
	var bad := 0
	var checked := 0
	for loc in NEW_REGIONS:
		var ox: int = loc.x * REGION_SIZE
		var oz: int = loc.y * REGION_SIZE
		for dx in [32, 128, 224]:
			for dz in [32, 128, 224]:
				var p := Vector3(float(ox + dx), 0.0, float(oz + dz))
				var h: float = d.get_height(p)
				checked += 1
				if not is_finite(h):
					bad += 1
					print("[M39-BAKE] !! 读回 NaN ", p)
	print("[M39-BAKE] 读回验证 bad=", bad, "/", checked)
	# 怪物真实落点区抽查（容器 z=-1650，局部 x[-85,88] z[-62,100]）
	for x in [-85, 0, 88]:
		for z in [-1712, -1650, -1550]:
			var p2 := Vector3(float(x), 0.0, float(z))
			print("[M39-BAKE] 落点 (%.0f,%.0f) h=%s" % [x, z, str(d.get_height(p2))])
	print("[M39-BAKE] 村基准复核 h(0,-130)=", d.get_height(Vector3(0, 0, -130)))