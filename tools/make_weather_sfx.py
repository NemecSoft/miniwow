"""
MiniWoW 天气环境音合成器（M43）

生成两个可无缝循环的环境音：
  · weather_rain.ogg —— 雨声：带通噪声（沙沙底） + 低频隆隆 + 随机雨点颗粒
  · weather_wind.ogg —— 风声：低中频噪声 + 极慢幅度调制（呼吸感） + 窄带呼啸

为什么合成而不是找素材：和 BGM 同理——版权干净、循环点可控、参数可调。
雨声/风声本质就是"滤波后的噪声 + 调制"，程序合成听起来比很多免费素材还真。

用法：python make_weather_sfx.py
"""
import os
import subprocess
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "audio", "weather")
FFMPEG = r"C:\Program Files\ffmpeg\bin\ffmpeg.exe"


def bandpass(x: np.ndarray, lo: float, hi: float, order: float = 2.0) -> np.ndarray:
	"""频域带通（软边缘）。整段一次处理，无相位问题。"""
	n = x.shape[-1]
	spec = np.fft.rfft(x, axis=-1)
	f = np.fft.rfftfreq(n, 1.0 / SR)
	with np.errstate(divide="ignore"):
		hp = 1.0 / np.sqrt(1.0 + (lo / np.maximum(f, 1e-6)) ** (2 * order))
		lp = 1.0 / np.sqrt(1.0 + (f / hi) ** (2 * order))
	gain = hp * lp
	if x.ndim == 2:
		gain = gain[None, :]
	return np.fft.irfft(spec * gain, n=n, axis=-1)


def loop_fade(x: np.ndarray, ms: float = 30.0) -> np.ndarray:
	"""首尾等长交叉淡化，保证循环点无爆音。"""
	n = int(SR * ms / 1000.0)
	fade = np.linspace(0.0, 1.0, n)
	y = x.copy()
	y[..., :n] *= fade
	y[..., -n:] *= fade[::-1]
	return y


def normalize(x: np.ndarray, peak: float = 0.86) -> np.ndarray:
	m = float(np.max(np.abs(x)))
	return x * (peak / m) if m > 1e-9 else x


def write_ogg(name: str, stereo: np.ndarray) -> None:
	os.makedirs(OUT_DIR, exist_ok=True)
	wav_path = os.path.join(OUT_DIR, name + ".wav")
	ogg_path = os.path.join(OUT_DIR, name + ".ogg")
	pcm = (np.clip(stereo.T, -1.0, 1.0) * 32767.0).astype("<i2")
	with wave.open(wav_path, "wb") as wf:
		wf.setnchannels(2)
		wf.setsampwidth(2)
		wf.setframerate(SR)
		wf.writeframes(pcm.tobytes())
	subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", wav_path,
					"-c:a", "libvorbis", "-q:a", "4", ogg_path], check=True)
	print(name, "->", os.path.getsize(ogg_path) // 1024, "KB,", round(len(stereo[0]) / SR, 2), "s")
	os.remove(wav_path)


def make_rain(seconds: float = 8.0) -> np.ndarray:
	n = int(SR * seconds)
	rng = np.random.default_rng(20261022)
	out = np.zeros((2, n))
	for ch in range(2):
		noise = rng.standard_normal(n)
		# ① 雨幕：中高频带通噪声（主体"沙沙"）
		hiss = bandpass(noise, 700.0, 9500.0, order=1.5) * 0.55
		# ② 远处雨声的低频隆隆
		rumble = bandpass(rng.standard_normal(n), 60.0, 320.0, order=2.0) * 0.16
		# ③ 雨点颗粒：随机短脉冲（打在屋顶/地面上的"嗒"）
		drops = np.zeros(n)
		count = int(seconds * 55)
		for _ in range(count):
			pos = rng.integers(0, n - 2000)
			length = int(rng.integers(300, 1600))
			t = np.arange(length) / SR
			freq = rng.uniform(1200.0, 5200.0)
			amp = rng.uniform(0.04, 0.16)
			env = np.exp(-t * rng.uniform(55.0, 130.0))
			drops[pos:pos + length] += amp * env * np.sin(2 * np.pi * freq * t)
		# 极缓慢的整体起伏，避免 8 秒里"一直一个音量"
		t_all = np.arange(n) / SR
		swell = 1.0 + 0.10 * np.sin(2 * np.pi * 0.09 * t_all + ch * 1.1)
		out[ch] = (hiss + rumble + drops) * swell
	return loop_fade(normalize(out, 0.80))


def make_wind(seconds: float = 10.0) -> np.ndarray:
	n = int(SR * seconds)
	rng = np.random.default_rng(77123)
	out = np.zeros((2, n))
	t_all = np.arange(n) / SR
	for ch in range(2):
		base = bandpass(rng.standard_normal(n), 90.0, 1500.0, order=1.8) * 0.5
		# 呼啸层：窄带高一点的中频，音量被极慢的正弦推来推去 → "一阵一阵的风"
		whistle = bandpass(rng.standard_normal(n), 600.0, 2600.0, order=2.2) * 0.22
		mod = 0.45 + 0.55 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.07 * t_all + ch * 2.0))
		mod *= 0.75 + 0.25 * np.sin(2 * np.pi * 0.19 * t_all + 0.7)
		# 低频压力感
		low = bandpass(rng.standard_normal(n), 40.0, 140.0, order=2.0) * 0.20
		out[ch] = base * mod + whistle * (mod ** 2) + low
	return loop_fade(normalize(out, 0.82))


if __name__ == "__main__":
	write_ogg("weather_rain", make_rain())
	write_ogg("weather_wind", make_wind())
