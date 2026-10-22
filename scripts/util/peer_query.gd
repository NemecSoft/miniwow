class_name PeerQuery

## M28：统一"bot peer"判定——严禁再用无上界的 peer_id >= 9001 判 bot！
##
## 事故（M28）：server_mount_peer 等处的旧判定 `peer_id >= 9001 = bot` 源自
## M25 时代（ENet 客户端 id 还是 2/3/4 小号）。M26 已查明 ENet 客户端
## unique_id 是服务器分配的大随机数（9 亿级），恒 >= 9001 → 所有真人客户端
## 被误判成 bot → 客户端按 X 召唤飞行器时，玩家沙发的 not_bot_only 检查
## 把真人当 bot 拒绝上座（REJECT-B2），飞行器永远骑不上。
##
## 唯一可靠判据：bot id 段 = [BOT_ID_BASE, BOT_ID_MAX]（9001~9004，
## 与 BotController.BOT_CONFIGS 数量联动）。真人 ENet id 恰好撞进这 4 个
## 具体值的概率约 10^-9，记录在案可接受。双端一致、无网络状态依赖，
## 服务器/客户端均可安全调用（不要用 multiplayer.get_peers() 判——
## 客户端的 peers 视图只有服务器，无法识别其他端身份）。

static func is_bot_peer(peer_id: int) -> bool:
	return peer_id >= BotController.BOT_ID_BASE \
		and peer_id <= BotController.BOT_ID_MAX
