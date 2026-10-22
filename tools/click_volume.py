"""M37 取证：模拟真实鼠标点击，验证音量滑块能拉到 0 且总线真的静音。

用法：python tools/click_volume.py <slider_index> <target_percent>
- slider_index: 0=总音量 1=音效 2=环境音
- target_percent: 0~100
"""
import ctypes
import ctypes.wintypes as w
import subprocess
import sys
import time

user32 = ctypes.windll.user32

# snap_windows 抓到的是窗口真实像素 1296x759。
# 暂停菜单三条滑块的 grabber（100% 位置）实测坐标见 find_slider.py 输出：
#   总音量 (756, 501)  音效 (756, 538)  环境音 (756, 576)
# 轨道左端 x=601（HSlider 宽度 160 + 边距），grabber 直径约 16px，
# 100% 时 grabber 中心 = 轨道右端 - 8。
GRABBER_100_X = 756
TRACK_LEFT_X = 601
GRABBER_Y = {0: 501, 1: 538, 2: 576}


def find_window():
	hwnd = None

	def cb(h, l):
		nonlocal hwnd
		if user32.IsWindowVisible(h):
			n = ctypes.create_unicode_buffer(256)
			user32.GetWindowTextW(h, n, 256)
			if "MiniWoW" in n.value:
				hwnd = h
		return True

	user32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, w.HWND, w.LPARAM)(cb), 0)
	return hwnd


def main():
	idx = int(sys.argv[1]) if len(sys.argv) > 1 else 0
	pct = int(sys.argv[2]) if len(sys.argv) > 2 else 0
	hwnd = find_window()
	if not hwnd:
		print("未找到窗口")
		return
	r = w.RECT()
	user32.GetWindowRect(hwnd, ctypes.byref(r))
	# 客户区尺寸
	client_w = ctypes.c_ulong()
	client_h = ctypes.c_ulong()
	user32.GetClientRect(hwnd, ctypes.byref(w.RECT()))
	user32.GetClientRect(hwnd, ctypes.byref(w.RECT(0, 0, 0, 0)))
	# 用 GetClientRect 正确获取
	cr = w.RECT()
	user32.GetClientRect(hwnd, ctypes.byref(cr))
	# 目标百分比 → grabber 中心 x（100% 时 grabber 中心 = GRABBER_100_X）
	span = GRABBER_100_X - TRACK_LEFT_X
	tx = GRABBER_100_X - span * (100.0 - pct) / 100.0
	real_x = int(tx)
	real_y = GRABBER_Y[idx]
	screen_x = r.left + real_x
	screen_y = r.top + real_y
	print(f"滑块{idx} 目标 {pct}% -> 屏幕 ({screen_x}, {screen_y})")
	user32.SetCursorPos(screen_x, screen_y)
	time.sleep(0.2)
	# 左键点击
	MOUSEEVENTF_LEFTDOWN = 0x0002
	MOUSEEVENTF_LEFTUP = 0x0004
	user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
	time.sleep(0.05)
	user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
	time.sleep(0.5)
	print("已点击")


if __name__ == "__main__":
	main()
