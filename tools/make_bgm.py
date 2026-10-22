"""
MiniWoW 背景音乐合成器（M43）

为什么要程序化合成而不是找现成素材：
  · 版权：外部曲库没有明确可商用授权，游戏内使用风险大；
  · 无缝循环：现成曲目在循环点必然有呼吸/尾音断裂，合成可以精确做到"尾巴叠回开头"；
  · 可调：想换调式/速度/配器，改常量重跑即可。

风格目标（魔兽世界艾尔文森林 / 暴风城那种）：
  · 大调、缓慢、温暖；弦乐长音铺底 + 竖琴琶音流动 + 长笛式旋律；
  · 大厅混响（Schroeder 梳状+全通）让干音变成"有空间感的管弦"；
  · 每段和弦留 2 小节，避免流行歌式的急促换和弦。

用法：
  python make_bgm.py            # 生成 assets/audio/music/bgm_village.ogg
输出 44.1kHz 立体声 OGG（Vorbis q5），循环长度 = 16 小节。
"""
import os
import subprocess
import wave

import numpy as np

SR = 44100
BPM = 66.0
BEAT = 60.0 / BPM
BAR = 4 * BEAT
BARS = 16
TAIL = 3.2  # 额外渲染的尾巴（秒），最后叠回开头实现无缝循环

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "audio", "music")
WAV_PATH = os.path.join(OUT_DIR, "bgm_village.wav")
OGG_PATH = os.path.join(OUT_DIR, "bgm_village.ogg")


def hz(midi: float) -> float:
	return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def smooth_env(n: int, attack: float, release: float, sustain: float = 1.0) -> np.ndarray:
	env = np.full(n, sustain, dtype=np.float64)
	na = min(max(1, int(attack * SR)), n)
	nr = min(max(1, int(release * SR)), n)
	env[:na] *= 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, na))
	env[n - nr:] *= 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, nr))
	return env


def lowpass_fft(x: np.ndarray, cutoff: float, sr: int = SR) -> np.ndarray:
	"""频域软低通（零相位）。整轨处理，一次性，成本可忽略。"""
	n = x.shape[-1]
	spec = np.fft.rfft(x, axis=-1)
	freqs = np.fft.rfftfreq(n, 1.0 / sr)
	# 一阶软滚降：> cutoff 后按 1/f 衰减
	gain = 1.0 / np.sqrt(1.0 + (freqs / cutoff) ** 4)
	if x.ndim == 2:
		gain = gain[None, :]
	return np.fft.irfft(spec * gain, n=n, axis=-1)


def comb(x: np.ndarray, delay_s: float, g: float, reps: int = 8) -> np.ndarray:
	"""Schroeder 梳状延迟的展开式实现：y[n] = x[n] + g*x[n-D] + g^2*x[n-2D] + ...
	纯向量化叠加，等价于有限次反馈，避免逐采样循环。"""
	d = max(1, int(delay_s * SR))
	y = x.copy()
	for i in range(1, reps + 1):
		off = d * i
		if off >= x.shape[-1]:
			break
		y[..., off:] += (g ** i) * x[..., :-off]
	return y


def allpass(x: np.ndarray, delay_s: float, g: float = 0.7) -> np.ndarray:
	d = max(1, int(delay_s * SR))
	y = -g * x
	y[..., d:] += x[..., :-d] + g * y[..., :-d] * 0.0  # 简化近似（扩散用，不需要严格正确）
	return y


def reverb(stereo: np.ndarray, wet: float = 0.40) -> np.ndarray:
	"""4 梳状并联 + 2 全通串联，模拟音乐厅。左右用不同延迟，产生宽度。"""
	out = np.zeros_like(stereo)
	for ci, (dl, dr) in enumerate([(0.0297, 0.0311), (0.0371, 0.0353), (0.0411, 0.0431), (0.0437, 0.0409)]):
		g = 0.78 - ci * 0.01
		chunk = np.empty_like(stereo)
		chunk[0] = comb(stereo[0], dl, g)
		chunk[1] = comb(stereo[1], dr, g)
		out += chunk * 0.25
	for delay in (0.0053, 0.0017):
		out[0] = allpass(out[0], delay)
		out[1] = allpass(out[1], delay)
	return stereo * (1.0 - wet) + out * wet * 1.9


def saw_ish(freq: float, t: np.ndarray, voices: int, detune: float) -> np.ndarray:
	"""多个微失谐正弦叠加 = 弦乐群（比单正弦厚，比锯齿柔和）。"""
	sig = np.zeros_like(t)
	for v in range(voices):
		k = (v - (voices - 1) / 2.0)
		sig += np.sin(2.0 * np.pi * freq * (1.0 + detune * k) * t + v * 0.7)
	return sig / voices


def add(buf: np.ndarray, start: int, mono: np.ndarray, pan: float = 0.0) -> None:
	"""把单声道音符按等功率声像写入立体声缓冲。pan: -1 左 .. +1 右"""
	end = start + mono.shape[0]
	if start >= buf.shape[1]:
		return
	if end > buf.shape[1]:
		mono = mono[: buf.shape[1] - start]
		end = buf.shape[1]
	ang = (pan + 1.0) * 0.25 * np.pi
	buf[0, start:end] += mono * np.cos(ang) * 1.35
	buf[1, start:end] += mono * np.sin(ang) * 1.35


# ===== 十六小节和声 =====
# 调性 D 大调；每 2 小节一个和弦（比每小节换更"开阔"）
CHORDS = [
	("D", 38, [50, 54, 57]),    # 1-2   D  : D3 F#3 A3
	("G", 43, [50, 55, 59]),    # 3-4   G  : D3 G3 B3
	("Bm", 47, [50, 54, 59]),   # 5-6   Bm : D3 F#3 B3
	("A", 45, [52, 57, 61]),    # 7-8   A  : E3 A3 C#4
	("D", 38, [50, 54, 57]),    # 9-10
	("G", 43, [50, 55, 59]),    # 11-12
	("A", 45, [52, 57, 61]),    # 13-14
	("D", 38, [50, 54, 57]),    # 15-16
]

# 长笛旋律：(起始拍, MIDI, 长度拍)
MELODY = [
	(0, 69, 2), (2, 74, 3), (5, 76, 1), (6, 78, 2),
	(8, 76, 2), (10, 74, 4), (14, 71, 2),
	(16, 71, 2), (18, 74, 2), (20, 79, 3), (23, 78, 1),
	(24, 76, 2), (26, 74, 2), (28, 71, 4),
	(32, 78, 3), (35, 76, 1), (36, 74, 2), (38, 71, 2),
	(40, 69, 4), (44, 71, 2), (46, 74, 2),
	(48, 73, 2), (50, 76, 2), (52, 81, 4),
	(56, 78, 4), (60, 76, 2), (62, 74, 2),
	# 第二遍升高八度情绪上扬
	(64, 74, 2), (66, 78, 2), (68, 81, 4),
	(72, 79, 4), (76, 78, 2), (78, 76, 2),
	(80, 81, 2), (82, 84, 2), (84, 86, 4),
	(88, 84, 4), (92, 81, 2), (94, 79, 2),
	(96, 78, 4), (100, 76, 2), (102, 74, 2),
	(104, 76, 2), (106, 74, 2), (108, 71, 4),
	(112, 74, 8),
]

total = BARS * BAR + TAIL
n_total = int(total * SR)
mix = np.zeros((2, n_total), dtype=np.float64)

# ---------- ① 弦乐铺底（pad）：每个和弦两小节长音，加九度让色彩更"奇幻" ----------
for ci, (name, bass, triad) in enumerate(CHORDS):
	start = int(ci * 2 * BAR * SR)
	dur = 2 * BAR + 0.9
	n = int(dur * SR)
	t = np.arange(n) / SR
	env = smooth_env(n, attack=1.1, release=1.6, sustain=1.0)
	for ni, midi in enumerate(triad):
		f = hz(midi + 12)  # 中音区
		sig = saw_ish(f, t, voices=5, detune=0.0022) * 0.30
		sig += 0.10 * np.sin(2 * np.pi * f * 2 * t)          # 2 次谐波
		sig += 0.045 * np.sin(2 * np.pi * f * 3 * t)         # 3 次谐波
		pan = [-0.55, 0.0, 0.55][ni % 3]
		add(mix, start, sig * env, pan)
	# 九度（add9）：D 加 E、G 加 A、A 加 B —— 这是"神圣/辽阔"感的关键
	nine = {38: 64, 43: 69, 47: 66, 45: 71}[bass]
	f9 = hz(nine)
	add(mix, start, 0.16 * np.sin(2 * np.pi * f9 * t) * env, 0.0)

# ---------- ② 低音弦 ----------
for ci, (name, bass, triad) in enumerate(CHORDS):
	start = int(ci * 2 * BAR * SR)
	dur = 2 * BAR + 0.5
	n = int(dur * SR)
	t = np.arange(n) / SR
	env = smooth_env(n, attack=0.35, release=1.1)
	f = hz(bass)
	sig = 0.52 * np.sin(2 * np.pi * f * t)
	sig += 0.16 * np.sin(2 * np.pi * f * 2 * t)
	sig += 0.07 * np.sin(2 * np.pi * f * 3 * t)
	add(mix, start, sig * env, 0.0)

# ---------- ③ 竖琴琶音：每小节 8 个八分音符，奇偶小节上下行交替 ----------
def arp_notes(triad, bass: int, pattern: list) -> list:
	"""把三和弦铺到两个八度，按 pattern 索引取音。"""
	pool = []
	for octv in (0, 12, 24):
		for m in triad:
			pool.append(m + octv)
	pool = sorted(set(pool))
	# 保证至少 8 个可用音，不够则循环扩展
	while len(pool) < 8:
		pool.append(pool[-1] + 12)
	if pattern == "up":
		return [pool[i] for i in range(min(8, len(pool)))]
	return [pool[min(len(pool) - 1, 7 - i)] for i in range(min(8, len(pool)))]


for ci, (name, bass, triad) in enumerate(CHORDS):
	for bar in range(2):
		bar_index = ci * 2 + bar
		notes = arp_notes(triad, bass, "up" if bar_index % 2 == 0 else "down")
		for k, midi in enumerate(notes):
			start = int((bar_index * BAR + k * BEAT * 0.5) * SR)
			dur = 1.35
			n = int(dur * SR)
			t = np.arange(n) / SR
			f = hz(midi + 12)
			# 拨弦：快速起音 + 指数衰减 + 明亮泛音
			sig = np.sin(2 * np.pi * f * t)
			sig += 0.48 * np.sin(2 * np.pi * f * 2 * t)
			sig += 0.26 * np.sin(2 * np.pi * f * 3 * t)
			sig += 0.13 * np.sin(2 * np.pi * f * 4 * t)
			sig += 0.06 * np.sin(2 * np.pi * f * 6 * t)
			env = np.exp(-t * 3.1) * smooth_env(n, 0.004, 0.05)
			pan = -0.35 if k % 2 == 0 else 0.35
			add(mix, start, sig * env * 0.115, pan)

# ---------- ④ 长笛旋律 ----------
for (beat, midi, length) in MELODY:
	start = int(beat * BEAT * SR)
	dur = length * BEAT + 0.45
	n = int(dur * SR)
	t = np.arange(n) / SR
	f = hz(midi)
	# 轻微颤音（5.2Hz，深度 0.55%）——人耳靠它分辨"吹奏"而不是"电子音"
	vib = 1.0 + 0.0055 * np.sin(2 * np.pi * 5.2 * t + 0.3)
	phase = 2 * np.pi * f * np.cumsum(vib) / SR
	sig = np.sin(phase) + 0.055 * np.sin(2 * phase) + 0.018 * np.sin(3 * phase)
	# 气声：极轻的白噪声经低通，只为增"肉"不为可闻
	rng = np.random.default_rng(int(midi * 31 + beat))
	breath = rng.standard_normal(n) * 0.006
	env = smooth_env(n, attack=0.13, release=0.42)
	add(mix, start, (sig + breath) * env * 0.13, 0.05)

# ---------- ⑤ 后期：分轨低通 + 混响 + 无缝循环 ----------
mix[0] = lowpass_fft(mix[0], 3800.0)
mix[1] = lowpass_fft(mix[1], 3800.0)
mix = reverb(mix, wet=0.42)

loop_n = int(BARS * BAR * SR)
# 把超出循环点的尾巴（混响余音、长音释放）折回开头，循环处就不会"啪"地断掉
tail = mix[:, loop_n:]
mix = mix[:, :loop_n].copy()
if tail.shape[1] > 0:
	mix[:, : tail.shape[1]] += tail

# 归一化 + 轻微软削波（防个别峰值爆音）
peak = float(np.max(np.abs(mix)))
if peak > 0:
	mix /= peak
mix = np.tanh(mix * 1.06) * 0.92

# 首尾 8ms 微交叉淡化，消除相位不连续造成的爆点
xf = int(0.008 * SR)
fade = np.linspace(0.0, 1.0, xf)
mix[:, :xf] *= fade
mix[:, -xf:] *= fade[::-1]

os.makedirs(OUT_DIR, exist_ok=True)
pcm = (np.clip(mix.T, -1.0, 1.0) * 32767.0).astype("<i2")
with wave.open(WAV_PATH, "wb") as wf:
	wf.setnchannels(2)
	wf.setsampwidth(2)
	wf.setframerate(SR)
	wf.writeframes(pcm.tobytes())

print("WAV:", WAV_PATH, os.path.getsize(WAV_PATH) // 1024, "KB,", round(loop_n / SR, 2), "s")

ffmpeg = r"C:\Program Files\ffmpeg\bin\ffmpeg.exe"
subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-i", WAV_PATH,
				"-c:a", "libvorbis", "-q:a", "5", OGG_PATH], check=True)
print("OGG:", OGG_PATH, os.path.getsize(OGG_PATH) // 1024, "KB")
os.remove(WAV_PATH)
