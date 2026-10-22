class_name GroundQuery
extends Object

## M25d：统一地面高度解析（约定见 docs/conventions-spawn-ground.md 条款 C2）。
## 全项目任何"贴地"需求都必须走这里，禁止各自手写射线/terrain 混合逻辑。
##
## 解析优先级：
##   1. 物理射线（GridMap 村底图 / Terrain3D 全图碰撞）——最可信，能测到村地板 2.25；
##   2. Terrain3D 数据 get_height()——非 NaN 且 |值| > MIN_TRUSTED_TERRAIN 才可信
##      （村区数据空洞精确返回 0，直接用会把实体压进村地板之下，M25 实测事故；
##       M39 起取绝对值，负高度真实地形同样可信）；
##   3. 都探不到 → NAN，调用方保留原位置兜底。

## 射线起点抬高量：tscn 估算 y 可能比真实地面低几十米（山坡），必须向上探够
const RAY_UP := 30.0
## 射线向下长度：覆盖断崖上方区域归位
const RAY_DOWN := 100.0
## Terrain3D 数据可信下限：村区数据空洞精确返回 0.0，绝不能当地面。
## M39 修正：原判据是 `th > 1.0`，把**负高度真实地形**也否决了——
## 远景丘陵烘焙值是 -4~-5m（< 1.0），39 个怪物全被误判"探不到地面"
## 刷 SPAWN_WARN 自由落体。改为「非 NaN 且非精确 0」即信任：
##   - NaN        = 无数据区 → 不可信（真·空洞）
##   - == 0.0 精确 = M25 村区空洞标记 → 不可信
##   - 其他任意值（含负）= 真实地形 → 可信
## 阈值取 0.01 是为了容差：真实地形恰好 -0.005m 也该被信任。
const MIN_TRUSTED_TERRAIN := 0.01


## 组合解析。返回 NAN 表示两端都探不到。
static func resolve(world: World3D, terrain_data: Terrain3DData, pos: Vector3, exclude: Array[RID] = []) -> float:
	var phys := ray_height(world, pos, exclude)
	if not is_nan(phys):
		return phys
	if terrain_data != null:
		var th: float = terrain_data.get_height(pos)
		if not is_nan(th) and absf(th) > MIN_TRUSTED_TERRAIN:
			return th
	return NAN


## 纯物理射线测地面（不排除自身时注意：实体自己的碰撞体会挡住射线）
static func ray_height(world: World3D, pos: Vector3, exclude: Array[RID] = []) -> float:
	if world == null or world.direct_space_state == null:
		return NAN
	var query := PhysicsRayQueryParameters3D.create(
		pos + Vector3.UP * RAY_UP, pos + Vector3(0, -RAY_DOWN, 0))
	if not exclude.is_empty():
		query.exclude = exclude
	var hit := world.direct_space_state.intersect_ray(query)
	return (hit.position.y as float) if not hit.is_empty() else NAN
