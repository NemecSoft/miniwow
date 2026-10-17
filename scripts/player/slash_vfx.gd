@tool
extends MeshInstance3D

@export var weapon_slot: WeaponSlot
@export var attack_type: WeaponSlot.mode

func _process(delta: float) -> void:
	visible = weapon_slot.attack_mode == attack_type
	material_override.set_shader_parameter("Threshold", weapon_slot.vfx_threshold)
