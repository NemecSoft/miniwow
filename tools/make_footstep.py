# -*- coding: utf-8 -*-
"""
M13 脚步声生成脚本（可复跑）。

素材来源：Sound FX Starter Pack Vol. 1（本地资源包）
  Motions and Impacts/Impact Vox Hammer.wav（44.1kHz/16bit/立体声/3.5s 捶击）
变通处理（音效包无脚步素材，用户选定方案 B）：
  取起始瞬态 0.35s -> 重采样降调 0.6 倍（低沉）-> 截 0.28s + 末端淡出
  -> 音量 35% -> 单声道
输出：assets/sfx/movement/footstep.wav

纯 Python 标准库实现（wave + struct），无 ffmpeg/numpy 依赖。
用法：python tools/make_footstep.py
"""
import wave
import struct
import os

SRC = r"D:/AI/GodotProject/MiniWoW/资源/Sound_FX_Starter_Pack_Vol._1/Sound FX Starter Pack Vol. 1/Motions and Impacts/Impact Vox Hammer.wav"
DST = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx", "movement", "footstep.wav")

SNAPSHOT_SEC = 0.35   # 取起始瞬态时长
PITCH_RATIO = 0.6     # 降调系数（<1 更低沉）
TARGET_SEC = 0.28     # 输出时长
GAIN = 0.35           # 输出音量
FADE_SEC = 0.06       # 末端淡出时长，避免截断爆音


def main() -> None:
    src = wave.open(SRC, "rb")
    rate = src.getframerate()
    channels = src.getnchannels()
    width = src.getsampwidth()
    assert rate == 44100 and width == 2, "预期 44.1kHz/16bit，实际 %dHz/%dbit" % (rate, width * 8)

    # 读前 0.35s，混成单声道
    frames = src.readframes(int(rate * SNAPSHOT_SEC))
    src.close()
    count = len(frames) // (channels * width)
    mono = []
    for i in range(count):
        offset = i * channels * width
        acc = 0
        for c in range(channels):
            (sample,) = struct.unpack_from("<h", frames, offset + c * width)
            acc += sample
        mono.append(acc / channels)

    # 重采样降调：按 pitch_ratio 拉长（线性插值），频率整体降低
    new_len = int(count / PITCH_RATIO)
    resampled = []
    for j in range(new_len):
        pos = j * PITCH_RATIO
        i0 = int(pos)
        frac = pos - i0
        a = mono[i0]
        b = mono[i0 + 1] if i0 + 1 < count else a
        resampled.append(a + (b - a) * frac)

    # 截到目标时长 + 音量 + 淡出
    final_len = min(int(rate * TARGET_SEC), new_len)
    fade_samples = int(rate * FADE_SEC)
    out = []
    for j in range(final_len):
        v = resampled[j] * GAIN
        remain = final_len - j
        if remain < fade_samples:
            v *= remain / fade_samples
        out.append(max(-32768, min(32767, int(v))))

    os.makedirs(os.path.dirname(DST), exist_ok=True)
    dst = wave.open(DST, "wb")
    dst.setnchannels(1)
    dst.setsampwidth(2)
    dst.setframerate(rate)
    dst.writeframes(struct.pack("<%dh" % len(out), *out))
    dst.close()
    print("生成 %s（%.2fs，单声道，降调 %.1f 倍）" % (os.path.abspath(DST), len(out) / rate, PITCH_RATIO))


if __name__ == "__main__":
    main()
