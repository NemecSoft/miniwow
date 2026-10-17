class_name PetEntity
extends Node3D

## M19 宠物系统架构占位（与伙伴系统是两种独立系统）。
## 伙伴（companion）：漂浮跟随的纯表现小精灵，任务获得，不可战斗（已实现）。
## 宠物（pet）：战斗实体，协助角色攻击（猎人宝宝式），全职业皆可拥有。
##   - 独立属性集（PetAttributes：攻击力/生命/AI 状态机）
##   - 目标选择跟随主人攻击对象，服务器权威结算
##   - 每角色上限、召唤/收回/死亡重生流程
## 本基类暂未实现战斗——待宠物系统设计定稿后填充。

signal pet_state_changed(state: StringName)

enum PetState { IDLE, FOLLOW, ATTACK, DEAD }

var owner_player: CharacterBody3D
var state: PetState = PetState.IDLE
