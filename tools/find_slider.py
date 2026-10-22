"""M37 取证：在原始像素图上定位音量滑块的亮色圆点（HSlider grabber）。

用途：拿到三个滑块在窗口真实像素坐标下的位置，供 click_volume.py 精确点击。
"""
import ctypes
import ctypes.wintypes as w
import struct
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from snap_windows import capture, list_windows  # noqa: E402


def main():
	hwnds = [h for h in list_windows() if "MiniWoW" in h[1]]
	if not hwnds:
		print("未找到 MiniWoW 窗口")
		return
	hwnd = hwnds[0][0]
	width, height, rgb = capture(hwnd)
	print(f"窗口尺寸 {width}x{height}")

	# 滑块 grabber 是浅色圆点（theme 的 normal grabber 接近白/浅灰）。
	# 在暂停菜单下半部分（y 400~600）找"亮度高且接近灰色"的像素聚簇。
	candidates = []
	for y in range(380, min(620, height)):
		for x in range(400, min(1000, width)):
			i = (y * width + x) * 3
			r, g, b = rgb[i], rgb[i + 1], rgb[i + 2]
			# 浅灰白：各通道都高，且色差小
			if r > 205 and g > 205 and b > 205 and abs(r - g) < 18 and abs(g - b) < 18:
				candidates.append((x, y))
	# 按行聚簇：同一行连续的像素算一个圆点
	points = []
	used = set()
	for (x, y) in candidates:
		if (x, y) in used:
			continue
		cluster = [(x, y)]
		stack = [(x, y)]
		used.add((x, y))
		while stack:
			cx, cy = stack.pop()
			for dx in range(-3, 4):
				for dy in range(-2, 3):
					nx, ny = cx + dx, cy + dy
					if (nx, ny) in used:
						continue
					if 0 <= nx < width and 0 <= ny < height:
						i = (ny * width + nx) * 3
						rr, gg, bb = rgb[i], rgb[i + 1], rgb[i + 2]
						if rr > 205 and gg > 205 and bb > 205 and abs(rr - gg) < 18 and abs(gg - bb) < 18:
							used.add((nx, ny))
							cluster.append((nx, ny))
							stack.append((nx, ny))
		if len(cluster) >= 20:
			cx = sum(p[0] for p in cluster) / len(cluster)
			cy = sum(p[1] for p in cluster) / len(cluster)
			points.append((round(cx), round(cy), len(cluster)))

	points.sort(key=lambda p: p[1])
	print("候选亮色圆点（x, y, 像素数）：")
	for p in points:
		print("   ", p)


if __name__ == "__main__":
	main()
