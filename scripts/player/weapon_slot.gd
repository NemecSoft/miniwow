extends BoneAttachment3D
class_name WeaponSlot

signal ranged_attack
signal slash
enum mode {NONE, SLASH, STAB}

@export var shapecast: ShapeCast3D
@export var attack_mode: mode = mode.NONE
@export var vfx_threshold: float = 0.0
@export var enabled: bool = false:
	set(value):
		if enabled == false and value == true:
			slash.emit()
		enabled = value
		if shapecast:
			shapecast.enabled = enabled
