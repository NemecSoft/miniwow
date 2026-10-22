// 虚空球壳（M46：外域的"海"）
//
// 外域是星球残骸，没有海洋。这块球壳铺在 SEA_FLOOR（比陆地低 300 米），
// 作用是给边缘断崖一个"底"——让断崖看起来插进虚空，而不是插进空气。
//
// 必须不透明（depth_draw_opaque + 不写 ALPHA）：半透明球壳会把整颗星球
// 扣成一个玻璃罩（M45 海洋已经踩过这个坑）。

shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform float planet_radius = 1500.0;
uniform vec3 void_color : source_color = vec3(0.07, 0.04, 0.13);
uniform vec3 glow_color : source_color = vec3(0.48, 0.18, 0.78);

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

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += vnoise(p) * a;
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_norm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 用三个轴向投影混合，避免单投影在两极被拉伸成条纹
	vec2 p1 = w_pos.xz * 0.0022;
	vec2 p2 = w_pos.xy * 0.0022;
	vec2 p3 = w_pos.zy * 0.0022;
	float drift = TIME * 0.013;
	float n1 = fbm(p1 + vec2(drift, -drift * 0.7));
	float n2 = fbm(p2 + vec2(-drift * 0.6, drift));
	float n3 = fbm(p3 + vec2(drift * 0.5, drift * 0.8));
	float n = (n1 + n2 + n3) / 3.0;

	// 能量脉络：把噪声做脊状处理，取窄带发亮
	float vein = 1.0 - abs(n * 2.0 - 1.0);
	vein = pow(clamp(vein, 0.0, 1.0), 7.0);

	vec3 col = mix(void_color, void_color * 2.1, smoothstep(0.35, 0.85, n));
	col = mix(col, glow_color, vein * 0.85);

	ALBEDO = col;
	ROUGHNESS = 0.86;
	SPECULAR = 0.10;
	EMISSION = glow_color * vein * 1.35 + void_color * 0.35;
}
