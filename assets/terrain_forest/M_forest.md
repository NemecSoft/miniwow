# M_forest.tres 说明（M39 · 需求 3 地形材质）

> 为什么单独开这个文件：`.tres` **不支持 `##` 注释**（M21d 铁律）。
> M39 第一次把说明写进 `M_forest.tres` 里，`godot` 直接报
> `M_forest.tres:3 - Parse Error: Unexpected end of file`，
> `load()` 静默返回 null → `terrain.material` 为空 → **地形退回默认纯白，
> 截图里看起来"材质改动完全没生效"**。注释只能放这里。

## 来源

从 `assets/terrain_demo/data/M_terrain.tres` 复制而来，**只改视觉参数**。
demo 原始资源保持不动 —— 想回滚只要把 `scripts/environment/terrain_starter.gd` 里
4 处 `load(FOREST_MATERIAL)` 改回 `load(DEMO_MATERIAL)`。

`terrain_starter.gd` 里的注释已标注这一点（常量 `FOREST_MATERIAL`）。

## 改动点（5 项，全部是视觉参数，不改地形数据）

| 参数 | demo 原值 | 本文件值 | 目的 |
|---|---|---|---|
| `dual_scale_near` | 100.0 | **28.0** | 贴图平铺密度提高约 3.5 倍，近处不再"糊成一片色块" |
| `dual_scale_far` | 170.0 | **52.0** | 同上，覆盖远景 |
| `dual_scale_reduction` | 0.3 | **0.65** | 远处纹理衰减放缓，远景不失去层次 |
| `macro_variation1` | (0.855, 0.8625, 0.9) 冷灰蓝 | **(0.62, 0.72, 0.44) 暖草绿** | 大尺度地面加绿区块，打散"单色大地" |
| `macro_variation2` | (0.9, 0.885, 0.81) 暖白 | **(0.86, 0.79, 0.56) 枯黄** | 与绿交替出现，形成草/枯草斑块 |
| `macro_variation_slope` | 0.333 | **0.55** | 色块随坡度分层：缓坡偏草、陡坡偏岩 |
| `blend_sharpness` | 0.5 | **0.85** | 岩/草混合边界更清晰 |
| `auto_slope` | 0.45 | **0.32** | 草覆盖面积更大（雾中森林不该满眼岩石） |

贴图集（`assets/terrain_demo/data/assets.tres`）**未改**：槽 0 = Cliff(rock023)、
槽 1 = Grass(ground037)。`auto_shader_enabled = true` 按 `auto_slope` 自动混合，
不需要手写 shader。

## 验证方式

```bash
# 材质是否真的挂上了（material_path 非空 + 无 Parse Error）
godot --headless --path . res://tools/m39_mat_probe.tscn
# 期望日志：MAT-PROBE: material_path=res://assets/terrain_forest/M_forest.tres
# 若看到 "Failed loading resource" → .tres 语法坏了（八成又是写了 ## 注释）
```

截图对照见 `screenshots/m39/m39_diag_*.png`。