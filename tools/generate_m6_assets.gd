extends SceneTree

## M6 场景环境资产生成工具：
## 1) assets/environment/textures/prototype_ground.png —— 亮色村庄广场地面
##    （原 prototype_dark.png 近黑，是"地面灰暗压抑"的根源；保持 2x2 网格缝特征）
## 2) 运行：Godot --headless --script tools/generate_m6_assets.gd

func _init() -> void:
	_generate_ground_texture()
	quit(0)


func _generate_ground_texture() -> void:
	const SIZE := 1024
	const SEAM := 3
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)

	# 四块地砖略有明暗差异（阳光下的石板广场感）
	var tiles := [
		Rect2i(0, 0, SIZE / 2, SIZE / 2),
		Rect2i(SIZE / 2, 0, SIZE / 2, SIZE / 2),
		Rect2i(0, SIZE / 2, SIZE / 2, SIZE / 2),
		Rect2i(SIZE / 2, SIZE / 2, SIZE / 2, SIZE / 2),
	]
	var tile_colors := [
		Color(0.80, 0.77, 0.70, 1.0),
		Color(0.76, 0.73, 0.66, 1.0),
		Color(0.77, 0.74, 0.67, 1.0),
		Color(0.79, 0.76, 0.69, 1.0),
	]
	for i in tiles.size():
		image.fill_rect(tiles[i], tile_colors[i])

	# 网格缝（中线 + 四边，比砖面深但绝不死黑）
	var seam := Color(0.58, 0.55, 0.48, 1.0)
	image.fill_rect(Rect2i(SIZE / 2 - SEAM / 2, 0, SEAM, SIZE), seam)
	image.fill_rect(Rect2i(0, SIZE / 2 - SEAM / 2, SIZE, SEAM), seam)
	image.fill_rect(Rect2i(0, 0, SIZE, SEAM), seam)
	image.fill_rect(Rect2i(0, SIZE - SEAM, SIZE, SEAM), seam)
	image.fill_rect(Rect2i(0, 0, SEAM, SIZE), seam)
	image.fill_rect(Rect2i(SIZE - SEAM, 0, SEAM, SIZE), seam)

	# 轻微噪点，避免大面积纯色显得假
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261016
	for _i in 6000:
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - 1)
		var shade := rng.randf_range(-0.025, 0.025)
		var c := image.get_pixel(x, y)
		c.r = clampf(c.r + shade, 0.0, 1.0)
		c.g = clampf(c.g + shade, 0.0, 1.0)
		c.b = clampf(c.b + shade, 0.0, 1.0)
		image.set_pixel(x, y, c)

	var error := image.save_png("res://assets/environment/textures/prototype_ground.png")
	if error != OK:
		push_error("generate_m6_assets: 地面贴图保存失败 %d" % error)
		return
	print("generate_m6_assets: prototype_ground.png 已生成（%dx%d 亮色广场地面）" % [SIZE, SIZE])
