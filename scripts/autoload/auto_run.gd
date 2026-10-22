extends Node
## M39：自动行走 / 自动飞行状态机（WoW Auto-Run 机制）。
##
## 【WoW 原生机制，已联网查证】
##   ① Toggle Autorun（切换式）：默认绑定 NumLock / 小键盘 +
##      —— 按一次开启，角色持续沿当前朝向前进；再按一次关闭；
##         按任意移动键会自动中断（WoW 原版行为）。
##   ② 鼠标前进（按住式）：同时按住鼠标左键 + 右键且不移动鼠标时，
##      角色沿当前朝向直线前进；松开任一键即停。
##      这与"按住右键拖鼠标转向"配合使用。
##
## 【本项目约定】
##   · 小键盘 +（toggle_autorun 动作）→ 切换式
##   · 鼠标左右键同时按住           → 按住式
##   · 两者互斥：鼠标按住时接管并关闭切换态（与 WoW 一致：手动输入优先）
##   · 任意移动键（move_*/jump/crouch）→ 立即停止全部自动状态
##   · 打开任何 UI（背包/商店/任务/地图/聊天）→ 由调用方 stop()
##
## 【落地 vs 飞行】
##   落地时 = 持续按住 W 前进（沿角色朝向）；
##   骑乘飞行器时 = 持续前进 + 轻微爬升（沿相机视线），由 hover_couch.gd 消费。

signal auto_run_changed(active: bool)

## 切换式（小键盘 +）状态
var _toggle_active := false
## 按住式（鼠标双键）状态
var _mouse_hold_active := false


func is_active() -> bool:
	return _toggle_active or _mouse_hold_active


## 切换式开关（小键盘 +）
func toggle() -> bool:
	_toggle_active = not _toggle_active
	if not _toggle_active:
		_mouse_hold_active = false
	auto_run_changed.emit(is_active())
	return _toggle_active


## 按住式（鼠标双键同时按住）
func set_mouse_hold(active: bool) -> void:
	if _mouse_hold_active == active:
		return
	_mouse_hold_active = active
	if active:
		# 手动输入优先：接管并关闭切换态
		_toggle_active = false
	auto_run_changed.emit(is_active())


## 全停（任意移动键 / 打开 UI / 死亡 / 下车）
func stop() -> void:
	if not _toggle_active and not _mouse_hold_active:
		return
	_toggle_active = false
	_mouse_hold_active = false
	auto_run_changed.emit(false)


## 供 UI 显示当前状态文本
func status_text() -> String:
	if _mouse_hold_active:
		return "自动前进（鼠标）"
	if _toggle_active:
		return "自动前进"
	return ""
