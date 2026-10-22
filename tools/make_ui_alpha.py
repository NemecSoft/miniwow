#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/make_ui_alpha.py —— ImageGen UI 素材后处理：无 alpha → 透明背景 RGBA。

背景：ImageGen 的 background=transparent 参数未生效（输出全是 RGB），
右下角带"AI 生成"水印笔画（画在面板本体上）。

方案演进（全部实测踩坑，勿回退）：
  1. 梯度墙 + PIL floodfill：AI 图全局噪点/柔光使墙占比 38%，背景被墙网
     切碎，floodfill 爬不动——废弃；
  2. 无墙 BFS + 双阈值 alpha 渐隐（matte，当前方案）：
     - 核心区：从角落种子 BFS，距种子色 <= tol_hard 的连通域 → alpha=0；
     - 过渡带：从核心边界继续 BFS 距种子 <= tol_soft 的像素 →
       alpha = 255 * (距种子 - tol_hard) / (tol_soft - tol_hard) 线性渐隐；
     本体内部近色区被纹理包围、不连通到背景种子，天然不受影响。
  3. 中心镂空（血条外壳）：中心种子同上处理一次；
  4. 水印涂抹：右下角 ROI 内"低饱和且与板底亮度差 > 30"的像素判为
     白字/字影（金饰/青边/橙灯均高饱和，不会误伤），用 9x9 邻域中位色替换；
  5. 输出规范命名 <theme>_<role>.png（原文件不动）。

用法：python tools/make_ui_alpha.py
判据：以 numpy alpha 统计为准——Read 预览的棋盘格会把纯黑/纯白也渲染成棋盘。
"""
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WOW = os.path.join(ROOT, "assets", "ui", "themes", "wow")
SC2 = os.path.join(ROOT, "assets", "ui", "themes", "sc2")

# (src, dst, tol_hard, tol_soft, hollow_center)
# 白/浅雾底 hard=40 soft=90；黑底 hard=20 soft=35（防吃做旧暗金属）
JOBS = [
    # ---- WoW 主题（白底）----
    ("Fantasy_MMORPG_game_UI_window__2026-10-17T23-15-55.png",
     "wow_panel_large.png", 40.0, 90.0, False),
    ("Fantasy_MMORPG_game_UI_small_w_2026-10-17T23-16-18.png",
     "wow_panel_small.png", 40.0, 90.0, False),
    ("Fantasy_MMORPG_game_UI_button__2026-10-17T23-16-46.png",
     "wow_button_normal.png", 40.0, 90.0, False),
    ("Fantasy_MMORPG_game_UI_primary_2026-10-17T23-17-07.png",
     "wow_button_primary.png", 40.0, 90.0, False),
    ("Fantasy_MMORPG_game_UI_health__2026-10-17T23-17-29.png",
     "wow_bar_frame.png", 40.0, 90.0, True),
    # ---- SC2 主题 ----
    ("StarCraft_II_sci_fi_RTS_game_U_2026-10-17T23-17-54.png",
     "sc2_panel_large.png", 40.0, 110.0, False),   # 雾底+辉光，过渡带加宽
    ("StarCraft_II_sci_fi_RTS_game_U_2026-10-17T23-18-19.png",
     "sc2_panel_small.png", 20.0, 35.0, False),
    ("StarCraft_II_sci_fi_RTS_game_U_2026-10-17T23-19-34.png",
     "sc2_button_normal.png", 40.0, 90.0, False),
    ("StarCraft_II_sci_fi_RTS_game_U_2026-10-17T23-19-50.png",
     "sc2_button_primary.png", 40.0, 90.0, False),
    ("StarCraft_II_sci_fi_RTS_game_U_2026-10-17T23-20-09.png",
     "sc2_bar_frame.png", 20.0, 35.0, True),
]
JOBS = [(os.path.join(WOW, s), os.path.join(WOW, d), th, ts, h) if s[0] == "F"
        else (os.path.join(SC2, s), os.path.join(SC2, d), th, ts, h)
        for (s, d, th, ts, h) in JOBS]


def _bfs_region(near: np.ndarray, sy: int, sx: int) -> np.ndarray:
    """在 near 掩码内从 (sy,sx) BFS 可达域。"""
    h, w = near.shape
    region = np.zeros((h, w), dtype=bool)
    if not near[sy, sx]:
        return region
    vis = np.zeros((h, w), dtype=bool)
    vis[sy, sx] = True
    region[sy, sx] = True
    q = deque([(sy, sx)])
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and near[ny, nx] and not vis[ny, nx]:
                vis[ny, nx] = True
                region[ny, nx] = True
                q.append((ny, nx))
    return region


def _dilate(mask: np.ndarray) -> np.ndarray:
    d = mask.copy()
    d[1:, :] |= mask[:-1, :]
    d[:-1, :] |= mask[1:, :]
    d[:, 1:] |= mask[:, :-1]
    d[:, :-1] |= mask[:, 1:]
    return d


def pick_seed(rgb: np.ndarray, cy: int, cx: int, half: int = 12) -> tuple:
    """在 (cy,cx) 附近 half 半径块内选种子：与块中位色距离最小的像素
    （背景块近似纯色，中位色即背景色；本体延伸到的角则取梯度最小处，
     由调用方结合 near 判据自然处理）。"""
    h, w, _ = rgb.shape
    y0, y1 = max(0, cy - half), min(h, cy + half + 1)
    x0, x1 = max(0, cx - half), min(w, cx + half + 1)
    block = rgb[y0:y1, x0:x1].reshape(-1, 3).astype(np.float32)
    med = np.median(block, axis=0)
    i = int(np.argmin(np.abs(block - med).sum(axis=1)))
    ly, lx = divmod(i, x1 - x0)
    return y0 + ly, x0 + lx


def process(src: str, dst: str, tol_hard: float, tol_soft: float,
            hollow: bool) -> bool:
    if not os.path.exists(src):
        print("  [缺文件] %s" % src, flush=True)
        return False
    im = Image.open(src).convert("RGB")
    rgb = np.asarray(im)
    h, w, _ = rgb.shape
    rgb16 = rgb.astype(np.int16)

    # 输出 alpha 累积图（0=全透明，255=不透明）
    alpha = np.full((h, w), 255, dtype=np.float32)

    # ---- 背景种子：四角 + （血条）中心 ----
    seeds = [(2, 2), (2, w - 3), (h - 3, 2), (h - 3, w - 3)]
    if hollow:
        seeds.append((h // 2, w // 2))

    for (cy, cx) in seeds:
        sy, sx = pick_seed(rgb, cy, cx)
        seed = rgb16[sy, sx]
        dist = np.abs(rgb16 - seed).max(axis=2)   # 与种子最大通道差
        # 核心区
        hard = _bfs_region(dist <= tol_hard, sy, sx)
        # 过渡带：从核心边界出发，距种子 <= tol_soft 的可达域
        soft_near = dist <= tol_soft
        frontier = _dilate(hard) & soft_near & ~hard
        soft = _bfs_region(soft_near, sy, sx) | hard
        soft &= ~hard
        # alpha 渐隐写入：hard=0，过渡带线性，其余 255（取更透明值防多种子冲突）
        band = np.clip((dist - tol_hard) / max(1e-3, tol_soft - tol_hard), 0.0, 1.0)
        a_band = np.where(hard, 0.0, np.where(soft, 255.0 * band, 255.0))
        alpha = np.minimum(alpha, a_band)

    removed = int((alpha < 1).sum())

    # ---- 组装 RGBA ----
    out = np.dstack([rgb, np.clip(alpha, 0, 255).astype(np.uint8)])

    # ---- 水印涂抹（右下角低饱和亮字）----
    wiped = _wipe_watermark(out)

    Image.fromarray(out, "RGBA").save(dst)
    print("  %-24s %dx%d | 抠背景(全透明) %6d px (%4.1f%%) | 涂水印 %5d px"
          % (os.path.basename(dst), w, h, removed, removed * 100.0 / (w * h), wiped),
          flush=True)
    return True


def _wipe_watermark(out: np.ndarray) -> int:
    """涂抹右下角 ROI 内的水印白字/字影。

    判据：ROI 内 饱和度(max-min) < 28 且与 ROI 中位亮度差 > 30 的前景像素
    = 白字或其阴影（金饰/青边/橙灯/红宝石均高饱和，不会误伤）。
    替换：9x9 邻域中位色。
    """
    h, w = out.shape[:2]
    y0, x0 = int(h * 0.84), int(w * 0.80)
    roi = out[y0:, x0:, :].astype(np.int16)
    mx = roi[:, :, :3].max(axis=2)
    mn = roi[:, :, :3].min(axis=2)
    sat = mx - mn
    lum = (roi[:, :, 0] * 299 + roi[:, :, 1] * 587 + roi[:, :, 2] * 114) // 1000
    med_lum = int(np.median(lum))
    fg = roi[:, :, 3] > 0
    cand = fg & (sat < 28) & (np.abs(lum - med_lum) > 30)
    if cand.sum() < 40:
        return 0
    ys, xs = np.nonzero(cand)
    wiped = 0
    rh, rw = roi.shape[:2]
    for yy, xx in zip(ys.tolist(), xs.tolist()):
        a0, a1 = max(0, yy - 4), min(rh, yy + 5)
        b0, b1 = max(0, xx - 4), min(rw, xx + 5)
        nb = roi[a0:a1, b0:b1, :3]
        med = np.median(nb.reshape(-1, 3), axis=0).astype(np.uint8)
        out[y0 + yy, x0 + xx, 0] = med[0]
        out[y0 + yy, x0 + xx, 1] = med[1]
        out[y0 + yy, x0 + xx, 2] = med[2]
        wiped += 1
    return wiped


def main():
    ok_all = True
    for (src, dst, th, ts, hollow) in JOBS:
        print("处理 %s ..." % os.path.basename(src), flush=True)
        if not process(src, dst, th, ts, hollow):
            ok_all = False
    print("=== 全部处理完成 ===" if ok_all else "=== 存在失败项 ===", flush=True)
    sys.exit(0 if ok_all else 1)


if __name__ == "__main__":
    main()
