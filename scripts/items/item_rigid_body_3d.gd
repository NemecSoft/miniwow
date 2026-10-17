class_name ItemRigidBody3D
extends RigidBody3D

## 世界掉落物（M8）：怪物死亡掉到地上的实体，玩家按 E 拾取入包。
## 生成/移除仅服务器执行；客户端经 level 的 ItemMultiplayerSpawner 自动同步生成，
## 位姿经本场景自带的 MultiplayerSynchronizer 同步（模板机制）。

@export var item_id: String = ""
@export var quantity: int = 1 ## 堆叠数量（鸡腿等可堆叠物一次掉多个）
