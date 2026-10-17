class_name SpringArmCharacter
extends Node3D

signal perspective_changed(first_person: bool)

const MOUSE_SENSIBILITY: float = 0.005

@export_category("Objects")
@export var _spring_arm: SpringArm3D = null
@export var _first_person_anchor: Node3D = null

@export_category("Camera Perspective")
@export_range(0.0, 10.0, 0.05) var third_person_distance := 5.0
@export_range(0.0, 1.0, 0.05) var first_person_distance := 0.0
@export_range(0.0, 3.0, 0.05) var third_person_height := 2.0
@export_range(1.0, 179.0, 1.0) var third_person_fov := 75.0
@export_range(1.0, 179.0, 1.0) var first_person_fov := 90.0

var is_first_person := false
var _orbiting := false
var _yaw := 0.0
var _pitch := 0.0

@onready var _camera: Camera3D = _spring_arm.get_node_or_null("Camera3D") as Camera3D


func _ready() -> void:
	_yaw = rotation.y
	_pitch = _spring_arm.rotation.x if _spring_arm else 0.0
	_apply_axis_lock()
	_apply_perspective()


func _process(_delta: float) -> void:
	_apply_axis_lock()
	if is_first_person and _spring_arm and _first_person_anchor:
		_spring_arm.global_position = _first_person_anchor.global_position


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	var current_scene := get_tree().get_current_scene()
	if current_scene and current_scene.has_method("is_camera_input_blocked"):
		if current_scene.is_camera_input_blocked():
			return

	# M19 WoW 式：按住右键隐藏指针并转视角，松开恢复可见
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	# M19：左键按住 = 环绕观察模式
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_orbiting = event.pressed

	if event.is_action_pressed("toggle_camera"):
		is_first_person = not is_first_person
		_apply_perspective()
		perspective_changed.emit(is_first_person)
		get_viewport().set_input_as_handled()
		return

	if not (event is InputEventMouseMotion):
		return
	# M19 WoW 式：右键按住 = 瞄准转向；左键按住 = 环绕观察（都不转角色）
	if not (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or _orbiting):
		return

	_yaw = wrapf(_yaw - event.relative.x * MOUSE_SENSIBILITY, -PI, PI)
	_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSIBILITY, -PI / 4.0, PI / 24.0)
	_apply_axis_lock()


## M19：载具相机模式——锁死本地 yaw（相机固定在载具正后方，载具转向=视角转向）
var yaw_locked := false

func set_yaw_locked(locked: bool) -> void:
	yaw_locked = locked
	if locked:
		rotation = Vector3(0.0, 0.0, 0.0)


func _apply_axis_lock() -> void:
	rotation = Vector3(0.0, 0.0 if yaw_locked else _yaw, 0.0)
	if _spring_arm:
		_spring_arm.rotation = Vector3(_pitch, 0.0, 0.0)
	if _camera:
		_camera.rotation = Vector3.ZERO


func _apply_perspective() -> void:
	if not _spring_arm:
		return
	if is_first_person:
		_spring_arm.spring_length = first_person_distance
		if _first_person_anchor:
			_spring_arm.global_position = _first_person_anchor.global_position
		if _camera:
			_camera.fov = first_person_fov
	else:
		_spring_arm.spring_length = third_person_distance
		_spring_arm.position = Vector3(0.0, third_person_height, 0.0)
		if _camera:
			_camera.fov = third_person_fov
