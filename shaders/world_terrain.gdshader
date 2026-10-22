// 星球地表 shader（M46：多星球通用）
//
// 与 M45 的区别：6 套硬编码配色改成 uniform 数组，由 PlanetProfile 灌入，
// 因此同一份 shader 既能画艾泽拉斯（6 块大陆 + 海洋）也能画外域（6 块区域 + 虚空）。
//
// 通道约定：
//   · 顶点色 R 通道 = 面 ID（0..5）→ 取 face_col[ID] / face_var[ID]
//   · 面内 UV (u,v) → 只有面 0 且 uses_zone_mask=1 时采平面遮罩（道路/草原/红土/熔岩）
//   · 高度 = length(世界坐标) - planet_radius，用于雪线/岩石/断崖/虚空分层

shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform float planet_radius = 2200.0;
uniform float sea_level = -40.0;

// 1 = 有海洋（边缘是沙滩），0 = 无海洋（边缘是断崖坠入虚空）
uniform float has_ocean = 1.0;
uniform float has_lava = 1.0;
// 1 = 面 0 用平面世界遮罩（艾泽拉斯的卡利姆多）
uniform float uses_zone_mask = 1.0;

group_uniforms planet;
uniform vec3 face_col[6];
uniform float face_var[6];
uniform vec3 sand_color : source_color = vec3(0.78, 0.70, 0.50);
uniform vec3 rock_color : source_color = vec3(0.42, 0.40, 0.37);
uniform vec3 rock_dark : source_color = vec3(0.26, 0.25, 0.24);
uniform vec3 snow_color : source_color = vec3(0.93, 0.95, 1.0);
uniform vec3 lava_color : source_color = vec3(1.0, 0.34, 0.05);
uniform vec3 lava_color_b : source_color = vec3(0.35, 1.0, 0.22);
uniform vec3 void_color : source_color = vec3(0.10, 0.06, 0.16);
group_uniforms;

// 卡利姆多遮罩专用的分区配色（仅 uses_zone_mask=1 时生效）
group_uniforms kalimdor;
uniform vec3 grass_lush : source_color = vec3(0.24, 0.38, 0.13);
uniform vec3 grass_gold : source_color = vec3(0.58, 0.55, 0.21);
uniform vec3 savanna : source_color = vec3(0.66, 0.61, 0.34);
uniform vec3 road_dirt : source_color = vec3(0.56, 0.47, 0.33);
uniform vec3 red_dirt : source_color = vec3(0.50, 0.22, 0.13);
uniform vec3 red_rock : source_color = vec3(0.42, 0.16, 0.10);
uniform vec3 ash_color : source_color = vec3(0.24, 0.20, 0.19);
group_uniforms;

uniform float snow_line = 150.0;
uniform float rock_line = 44.0;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;
uniform float lava_emission = 1.9;

varying vec2 v_uv;
varying float v_face;
varying vec3 w_pos;
varying vec3 w_norm;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 43.21);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ===== 3D 值噪声（M47 地面质感）=====
// 【为什么必须用 3D】旧版用 w_pos.xz 当噪声坐标：球面上 -X/+X 面的 x 接近 0、
// -Z/+Z 面的 z 接近 0，那两个方向的整片大陆会退化成一条缝 → 完全没纹理。
// 3D 噪声在球面上各向同性，六面均匀。
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

// 4 层分形噪声（频率每层 ×2.03，避免格点对齐产生规律纹）
float fbm3(vec3 p, int oct) {
	float a = 0.5;
	float s = 0.0;
	float norm = 0.0;
	vec3 q = p;
	for (int i = 0; i < 4; i++) {
		if (i >= oct) {
			break;
		}
		s += vnoise3(q) * a;
		norm += a;
		q *= 2.03;
		a *= 0.5;
	}
	return s / max(norm, 0.0001);
}

float BigNoise(float a, float b) {
	return clamp(a * 0.6 + b * 0.4, 0.0, 1.0);
}

int face_id() {
	return int(clamp(v_face + 0.5, 0.0, 5.0));
}

void vertex() {
	v_uv = UV;
	v_face = COLOR.r * 5.0;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_norm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV; // Godot 4.7 内部采样需要该标识符
	float h = length(w_pos) - planet_radius;
	// 坡度：地形法线偏离径向越多 = 越陡
	float radial_dot = clamp(dot(normalize(w_norm), normalize(w_pos)), 0.0, 1.0);
	float slope = 1.0 - radial_dot;

	// 【M47 地面质感】四层 3D 噪声，单位就是米：
	//   macro ≈ 170m 地貌级色斑 / meso ≈ 18m 土块 / dust ≈ 1.3m 沙砾 / fine ≈ 0.32m 颗粒
	// 旧版只用 2D 的 w_pos.xz，且颗粒对比只有 ±6% —— 视觉上就是一片打蜡的塑料。
	vec3 sp = w_pos;
	float big = fbm3(sp * 0.006, 3);
	float mid = fbm3(sp * 0.055, 3);
	float dust = fbm3(sp * 0.75, 2);
	float fine = vnoise3(sp * 3.1);
	// 干裂纹路：两层 ridged 噪声叠，单层会退化成一个个孤立的圆圈
	// （像地上的水渍圈，实测很难看），两层才有网状碎裂感
	float rid1 = 1.0 - abs(vnoise3(sp * 0.28) * 2.0 - 1.0);
	float rid2 = 1.0 - abs(vnoise3(sp * 0.95) * 2.0 - 1.0);
	float crack = smoothstep(0.91, 1.0, rid1) * 0.62 + smoothstep(0.95, 1.0, rid2) * 0.38;

	int fid = face_id();
	vec3 base = face_col[fid];
	float fv = face_var[fid];

	vec3 col = base;
	float road = 0.0;
	float lava = 0.0;

	if (uses_zone_mask > 0.5 && fid == 0) {
		// ===== 艾泽拉斯面 0：草原 + 地狱火红土 + 道路 + 熔岩（平面遮罩驱动）=====
		vec4 mask = texture(mask_tex, clamp(v_uv * 0.5 + 0.5, vec2(0.001), vec2(0.999)));
		vec3 grass = mix(grass_lush, grass_gold, smoothstep(0.30, 0.78, big));
		grass = mix(grass, savanna, smoothstep(0.45, 0.90, mid) * 0.55);
		grass *= 0.88 + 0.24 * dust;
		vec3 hell = mix(red_dirt, red_rock, smoothstep(0.35, 0.75, big));
		hell = mix(hell, ash_color, smoothstep(0.52, 0.92, mid) * 0.5);
		hell *= 0.88 + 0.24 * dust;
		float ws = max(mask.g + mask.b, 0.0001);
		col = (grass * mask.g + hell * mask.b) / ws;
		road = smoothstep(0.18, 0.85, mask.r);
		lava = smoothstep(0.05, 0.75, mask.a);
		col = mix(col, road_dirt * (0.82 + 0.36 * dust), road * 0.94);
	} else {
		// ===== 通用：面主色 + 四层噪声调制 =====
		col = base * mix(1.0 - fv * 0.62, 1.0 + fv * 0.52, smoothstep(0.16, 0.86, big));
		col = mix(col, base * (1.0 + fv * 0.85), smoothstep(0.42, 0.92, mid) * 0.72);
		// 中观土块：明暗都拉开，否则远处看还是塑料板
		col *= 0.74 + 0.52 * dust;
		// 微观颗粒 + 干裂
		col *= 0.84 + 0.32 * fine;
		float crack_amt = crack * clamp(1.0 - slope * 1.6, 0.0, 1.0);
		col *= 1.0 - crack_amt * 0.26;
	}

	// 无海洋星球（外域）：低地不铺沙滩，而是焦土/岩屑
	if (has_ocean > 0.5) {
		float beach = smoothstep(sea_level + 12.0, sea_level + 1.0, h);
		col = mix(col, sand_color, beach * 0.85);
	} else {
		float scorch = smoothstep(sea_level + 90.0, sea_level + 6.0, h);
		col = mix(col, rock_dark * 0.72, scorch * 0.72);
	}

	// 岩石：高度 + 坡度
	float rock_amt = smoothstep(rock_line, rock_line + 26.0, h);
	rock_amt = max(rock_amt, smoothstep(0.28, 0.58, slope));
	vec3 rock = mix(rock_color, rock_dark, smoothstep(0.30, 0.82, big));
	rock *= 0.78 + 0.44 * dust;
	// 岩层条带：沿高度的水平层理，让坡面有"石头"感而不是糊墙
	float strata = sin(h * 0.62 + fbm3(sp * 0.018, 2) * 9.0) * 0.5 + 0.5;
	rock *= 0.80 + 0.36 * strata;
	col = mix(col, rock, clamp(rock_amt, 0.0, 1.0));

	// 陡壁裂纹（无海洋星球边缘断崖更明显）
	float cliff = smoothstep(0.52, 0.86, slope);
	col = mix(col, rock_dark * 0.7, cliff * 0.55);

	// 雪线（陡壁挂不住雪）
	float snow_h = smoothstep(snow_line - 34.0, snow_line + 26.0, h);
	snow_h *= clamp(1.0 - slope * 1.45, 0.0, 1.0);
	snow_h = max(snow_h, snow_amount * clamp(1.0 - slope * 1.3, 0.0, 1.0) * 0.96);
	snow_h *= 0.84 + 0.16 * mid;
	col = mix(col, snow_color, clamp(snow_h, 0.0, 1.0));

	// 熔岩配色：影月谷（面 4）用邪能绿，其余用橙红
	vec3 lc = (fid == 4) ? lava_color_b : lava_color;
	vec3 lava_rgb = lc * (0.82 + 0.18 * sin(TIME * 1.7 + w_pos.x * 0.08 + w_pos.z * 0.06));
	lava *= has_lava;
	col = mix(col, lava_rgb * 0.55, lava * 0.7);

	// 虚空：低于 sea_level 的部分吞进紫色迷雾（外域断崖底部）
	float vd = smoothstep(sea_level + 40.0, sea_level, h);
	if (has_ocean < 0.5) {
		col = mix(col, void_color, vd * 0.92);
	}

	ALBEDO = col;
	ROUGHNESS = clamp(mix(0.94, 0.70, road) - snow_h * 0.18 - lava * 0.3, 0.12, 1.0);
	SPECULAR = 0.06 + snow_h * 0.16 + road * 0.05;
	EMISSION = lava_rgb * lava * lava_emission;
	if (has_ocean < 0.5) {
		// 虚空边缘透出一点紫光，避免整块死黑
		EMISSION += void_color * vd * 0.55;
	}
}
