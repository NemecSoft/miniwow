class_name BalloonStone
extends Node3D

## 投掷石块（M36 气球夺剑）：玩家扔出去打气球的石头。
## 服务器权威份 + 客户端表现份共用本场景/脚本：
## - 权威份（is_authority=true）由 BalloonArena 持有，命中检测在 arena 服务器循环做
## - 表现份各端本地创建，只跑视觉（抛物线 + 寿命自毁），不发任何 rpc
## 手动积分而非 RigidBody3D：零物理引擎不确定性，两端轨迹由同一初速度决定。

const STONE_GRAVITY := 12.0 ## 与 BalloonArena.STONE_GRAVITY 保持一致

var velocity: Vector3 = Vector3.ZERO
var ground_y: float = 0.0
var lifetime: float = 5.0
var is_authority: bool = false ## 服务器权威份（arena 命中检测对象）

var _life: float = 0.0
var _landed: bool = false


func setup(throw_velocity: Vector3, ground_height: float, life: float = 5.0) -> void:
	velocity = throw_velocity
	ground_y = ground_height
	lifetime = life


func _physics_process(delta: float) -> void:
	if _life >= lifetime:
		queue_free()
		return
	_life += delta
	if _landed:
		return
	velocity.y -= STONE_GRAVITY * delta
	# M33 NaN 铁律：位置写回前逐分量检查，非有限立即销毁（防污染场景树）
	if not (is_finite(velocity.x) and is_finite(velocity.y) and is_finite(velocity.z)):
		queue_free()
		return
	position += velocity * delta
	if position.y <= ground_y + 0.06:
		position.y = ground_y + 0.06
		velocity = Vector3.ZERO
		_landed = true
		# 落地后躺 1.2 秒消失（不无限堆积）
		lifetime = _life + 1.2
