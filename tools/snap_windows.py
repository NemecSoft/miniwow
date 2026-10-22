# MiniWoW M26：双端一致性截图取证工具（纯 ctypes，无第三方依赖）。
# 用法：python snap_windows.py <输出前缀>
# 枚举所有可见窗口，过滤标题含 MiniWoW 的（两个 Godot 窗口），
# 用 PrintWindow(PW_RENDERFULLCONTENT) 捕获（不受窗口遮挡/最小化影响），
# 手写 PNG 编码（zlib）保存为 <前缀>_1.png / <前缀>_2.png（按屏幕 x 坐标排序）。
import ctypes
import ctypes.wintypes as w
import struct
import sys
import zlib

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32

PW_RENDERFULLCONTENT = 2
DIB_RGB_COLORS = 0
BI_RGB = 0


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", ctypes.c_uint32),
        ("biWidth", ctypes.c_int32),
        ("biHeight", ctypes.c_int32),
        ("biPlanes", ctypes.c_uint16),
        ("biBitCount", ctypes.c_uint16),
        ("biCompression", ctypes.c_uint32),
        ("biSizeImage", ctypes.c_uint32),
        ("biXPelsPerMeter", ctypes.c_int32),
        ("biYPelsPerMeter", ctypes.c_int32),
        ("biClrUsed", ctypes.c_uint32),
        ("biClrImportant", ctypes.c_uint32),
    ]


class BITMAPINFO(ctypes.Structure):
    _fields_ = [("bmiHeader", BITMAPINFOHEADER), ("bmiColors", ctypes.c_uint32 * 3)]


EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, w.HWND, w.LPARAM)


def list_windows():
    res = []
    def cb(hwnd, _l):
        if user32.IsWindowVisible(hwnd):
            n = user32.GetWindowTextLengthW(hwnd)
            if n > 0:
                buf = ctypes.create_unicode_buffer(n + 1)
                user32.GetWindowTextW(hwnd, buf, n + 1)
                res.append((hwnd, buf.value))
        return True
    user32.EnumWindows(EnumWindowsProc(cb), 0)
    return res


def capture(hwnd):
    # 最小化窗口先恢复（SW_RESTORE=9），否则拿到的是最小化占位矩形
    user32.ShowWindow(hwnd, 9)
    r = w.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(r))
    width = r.right - r.left
    height = r.bottom - r.top
    if width <= 0 or height <= 0:
        return None
    hdc = user32.GetWindowDC(hwnd)
    try:
        memdc = gdi32.CreateCompatibleDC(hdc)
        bi = BITMAPINFO()
        ctypes.memset(ctypes.byref(bi), 0, ctypes.sizeof(bi))
        bi.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
        bi.bmiHeader.biWidth = width
        bi.bmiHeader.biHeight = -height  # 自顶向下
        bi.bmiHeader.biPlanes = 1
        bi.bmiHeader.biBitCount = 32
        bi.bmiHeader.biCompression = BI_RGB
        ppv = ctypes.c_void_p()
        bmp = gdi32.CreateDIBSection(memdc, ctypes.byref(bi), DIB_RGB_COLORS, ctypes.byref(ppv), None, 0)
        if not bmp or not ppv.value:
            return None
        gdi32.SelectObject(memdc, bmp)
        ok = user32.PrintWindow(hwnd, memdc, PW_RENDERFULLCONTENT)
        if not ok:
            return None
        raw = ctypes.string_at(ppv.value, width * height * 4)
        # BGRA -> RGB
        out = bytearray(width * height * 3)
        for i in range(width * height):
            out[i * 3] = raw[i * 4 + 2]
            out[i * 3 + 1] = raw[i * 4 + 1]
            out[i * 3 + 2] = raw[i * 4]
        return (width, height, bytes(out))
    finally:
        user32.ReleaseDC(hwnd, hdc)


def png_chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def save_png(path, width, height, rgb):
    raw = b"".join(b"\x00" + rgb[y * width * 3:(y + 1) * width * 3] for y in range(height))
    png = b"\x89PNG\r\n\x1a\n"
    png += png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += png_chunk(b"IDAT", zlib.compress(raw, 6))
    png += png_chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main():
    prefix = sys.argv[1] if len(sys.argv) > 1 else "snap"
    wins = [(h, t) for h, t in list_windows() if "MiniWoW" in t or "Godot" in t]
    wins.sort(key=lambda ht: user32.GetWindowRect and _rect_x(ht[0]))
    print("捕获窗口：", [t for _, t in wins])
    for i, (hwnd, title) in enumerate(wins, 1):
        img = capture(hwnd)
        if img is None:
            print(f"[{i}] {title}: 捕获失败")
            continue
        wd, ht, rgb = img
        path = f"{prefix}_{i}.png"
        save_png(path, wd, ht, rgb)
        print(f"[{i}] {title}: {wd}x{ht} -> {path}")


def _rect_x(hwnd):
    r = w.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(r))
    return r.left


if __name__ == "__main__":
    main()
