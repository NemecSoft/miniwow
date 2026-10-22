# Blender + Godot MCP 游戏开发工作流

> 2026-10-20 建立。全机系统级安装，任何 AI 助手（WorkBuddy / Claude Code / Claude Desktop / Cursor / VS Code / Windsurf）均可用。
> 首个实战成果：浮空城中央广场的**奥术方尖碑**（Blender MCP 建模 → glb → Godot MCP 接入）。

---

## 1. 系统级安装布局

| 组件 | 位置 | 说明 |
|---|---|---|
| godot-mcp 0.1.0 | `C:\Tools\mcp\godot-mcp\` | npm 包 `@coding-solo/godot-mcp`，自带 `build/index.js`，无需 build |
| mcp-for-blender 1.30.0 | `C:\Tools\mcp\blender-mcp-venv\` | 独立 venv，入口 `Scripts\mcp-for-blender.exe` |
| Blender 5.4 | `C:\Tools\Blender\blender.exe` | 本体 |
| blender_mcp addon | `%APPDATA%\Blender Foundation\Blender\5.4\scripts\addons\blender_mcp_addon.py` | 已命令行启用（persistent） |
| `GODOT_PATH` 环境变量 | `C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe` | godot-mcp 找引擎用（setx 用户级） |

**客户端配置分发**（均已写入，客户端装上即用）：
- WorkBuddy：`~/.workbuddy/mcp.json`（重启后在连接器页 Trust）
- Claude Code：`~/.claude.json` 顶层 `mcpServers`
- Claude Desktop / Cursor / VS Code / Windsurf：各自标准 mcp 配置文件

## 2. 两条驱动通道

两个 MCP 都是 stdio JSON-RPC server，除了等宿主 AI 客户端挂载，还可以**直接用脚本驱动**（自动化流水线必备，本仓库已备好客户端）：

| 通道 | 客户端脚本 | 协议 |
|---|---|---|
| Blender MCP | `tools/blendmcp_client.py` | TCP 9876，addon 自有 JSON 协议（`execute_code` / `get_scene_info` / `get_object_info`） |
| Godot MCP | `tools/godotmcp_client.py` | stdio MCP 2.0（initialize → initialized → tools/call） |

```bash
# Blender 侧：执行任意 Blender Python（stdin 传入）
python tools/blendmcp_client.py code < tools/build_monument.blendpy

# Godot 侧：调用 14 个工具之一
python tools/godotmcp_client.py get_godot_version {}
python tools/godotmcp_client.py get_project_info {"projectPath":"D:/AI/GodotProject/MiniWoW/MiniWoW"}
```

## 3. godot-mcp 工具清单（14 个）

`launch_editor` `run_project` `get_debug_output` `stop_project` `get_godot_version`
`list_projects` `get_project_info` `create_scene` `add_node` `load_sprite`
`export_mesh_library` `save_scene` `get_uid` `update_project_uids`

注意：`run_project` 会拉起长驻进程，自动化流水线里更常用 `get_godot_version` / `get_project_info` 做探活，批量操作直接命令行 Godot（`--headless --editor --quit` 导入、`--quit-after N` 实跑）。

## 4. Blender MCP 工作流（建模 → glb）

1. **启动**（GUI + 自动开 server）：
   ```
   blender.exe --python tools/startup_blender_mcp.py
   ```
   脚本做三件事：启用 addon → 清空场景（`read_homefile(use_empty=True)`）→ `bpy.ops.blendermcp.start_server()`。
   手动等价操作：Blender 打开后 N 面板 → BlenderMCP → Start Server。
2. **建模**：写 `.blendpy` 脚本（纯 bpy 代码），经 `blendmcp_client.py code` 推送执行。参考 `tools/build_monument.blendpy`：
   - 材质用 `next(n for n in nodes if n.type=='BSDF_PRINCIPLED')` 查找（Blender 5.4 节点名不再是 "Principled BSDF"）
   - 发光件：Emission Color + Emission Strength（glb 会带 KHR_materials_emissive）
3. **导出**：`bpy.ops.export_scene.gltf(filepath=..., export_format='GLB', export_yup=True, export_apply=True)` 直接写进 `MiniWoW/assets/models/`。
4. **渲染自证**：同一通道设相机/太阳光/世界背景色，`bpy.ops.render.render(write_still=True)` 出 PNG——不用进游戏就能验收模型。

## 5. Godot 接入流程

1. **导入 glb**（必须跑一次，同时重建全局类缓存）：
   ```
   godot.exe --headless --editor --path <项目> --quit
   ```
   产物：`assets/models/xxx.glb.import` + `.godot/imported/`。
2. **场景挂载**：运行时 `load("res://assets/models/xxx.glb").instantiate()`（参考 `city_zone.gd` 的 `_spawn_monument()`：glb 实例 + StaticBody3D 碰撞 + OmniLight3D 兜底发光）。
3. **验证**：`--headless --quit-after 200` 实跑，grep `SCRIPT ERROR|parse error|formatting`。
4. **-class_name 变更后**：同第 1 步重建缓存，否则全局类全线失效。

## 6. 实战记录：奥术方尖碑（2026-10-20）

- 建模脚本 `tools/build_monument.blendpy`（1380 顶点，6×6×13.7 m）：
  三层八角底座 → 9 段收分扭转柱身（每段转 8°，r×0.88）→ 2 道金环（Torus，metal 0.9）
  → 顶部拉长八面体晶体（自发光 #33ffee 强度 4）→ 8 枚环绕悬浮碎块 → join 合并单对象。
- 导出：`arcane_monument.glb`（240 KB）→ Godot headless 导入 → `city_zone.gd` 中央广场街区
  （x∈23~69, z∈-29~42，原本会生成楼，改为铺砖+方尖碑+圆柱碰撞）。
- 效果图：`monument_preview.png`（Blender EEVEE 直渲）。

## 7. 踩坑清单

| 坑 | 对策 |
|---|---|
| Blender 5.4 材质节点 `nodes.get('Principled BSDF')` 返回 None | 按类型找：`n.type == 'BSDF_PRINCIPLED'` |
| 清华 PyPI 镜像没同步 `mcp-for-blender` 新包名 | 官方源直装：`pip install mcp-for-blender --index-url https://pypi.org/simple/` |
| Blender 5.x 系统级 `scripts/addons` 目录已移除 | 放用户目录 `%APPDATA%\Blender Foundation\Blender\5.4\scripts\addons\`，legacy addon 照收 |
| addon server 不自启 | 启动参数挂 `startup_blender_mcp.py`，或 N 面板手动 Start Server |
| WorkBuddy 会话内 MCP 工具未注册 | 重启 WorkBuddy 并在连接器页 Trust；会话内可先用脚本直驱协议（本文第 2 节） |
| glb 放进项目后 `load()` 为 null | 先跑 `--headless --editor --quit` 导入，确认 `.import` 文件生成 |
