class_name ShakeCamera3D
extends Node

## M18b-2：相机震屏（roguelite shake_camera_3d.gd 机制移植）。
## 原版 extends Camera3D 直接挂相机；本项目相机在 player.tscn 场景树内
## （SpringArmOffset/SpringArm3D/Camera3D，含第一/第三人称切换逻辑），
## 不宜替换节点类型，故改为 Node 持相机引用、每帧写 h_offset/v_offset。
## 快速衰减：quick_shake 用 tween 把 trauma 从峰值拉回 0（0.3s）。

const SHAKE_DECAY_DURATION := 0.3
const NOISE_FREQUENCY := 20.0

var camera: Camera3D = null
var trauma := 0.0
var _noise := FastNoiseLite.new()
var _shake_tween: Tween = null


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = NOISE_FREQUENCY


func _process(_delta: float) -> void:
	if camera == null:
		return
	if trauma <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		return
	var time := float(Time.get_ticks_msec())
	camera.h_offset = _noise.get_noise_2d(time, 0.0) * trauma
	camera.v_offset = _noise.get_noise_2d(0.0, time) * trauma


## 触发一次短促震动（magnitude 为最大偏移量，米）
func quick_shake(magnitude: float) -> void:
	if camera == null:
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	trauma = magnitude
	_shake_tween = create_tween()
	_shake_tween.tween_property(self, "trauma", 0.0, SHAKE_DECAY_DURATION).from(magnitude)
