extends Node

## 技能注册表（autoload）。启动时加载 resources/skills/ 下的全部技能资源。

const SKILL_PATHS := {
	"basic_attack": "res://resources/skills/basic_attack.tres",
	"heavy_strike": "res://resources/skills/heavy_strike.tres",
	# 战士
	"w_whirlwind": "res://resources/skills/w_whirlwind.tres",
	"w_shield_wall": "res://resources/skills/w_shield_wall.tres",
	"w_execute": "res://resources/skills/w_execute.tres",
	# 法师
	"m_fireball": "res://resources/skills/m_fireball.tres",
	"m_frostbolt": "res://resources/skills/m_frostbolt.tres",
	"m_arcane_blast": "res://resources/skills/m_arcane_blast.tres",
	"m_arcane_power": "res://resources/skills/m_arcane_power.tres",
	# 牧师
	"p_smite": "res://resources/skills/p_smite.tres",
	"p_flash_heal": "res://resources/skills/p_flash_heal.tres",
	"p_renew": "res://resources/skills/p_renew.tres",
	"p_holy_nova": "res://resources/skills/p_holy_nova.tres",
	# 步兵（M18b，GDD §6.4 剑盾坦克）
	"i_shield_bash": "res://resources/skills/i_shield_bash.tres",
	"i_retaliate": "res://resources/skills/i_retaliate.tres",
	"i_iron_wall": "res://resources/skills/i_iron_wall.tres",
	"i_last_stand": "res://resources/skills/i_last_stand.tres",
}

var _skills := {}


func _ready() -> void:
	for skill_id in SKILL_PATHS:
		var skill := load(SKILL_PATHS[skill_id]) as SkillData
		if skill:
			_skills[skill_id] = skill


func get_skill(skill_id: String) -> SkillData:
	return _skills.get(skill_id)


func get_all_skills() -> Array:
	return _skills.values()
