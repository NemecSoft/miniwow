// 星球海洋球壳：略小于陆地表面半径的完整球，只渲染外表面。
// 海面用菲涅尔 + 微波纹，远处变成镜面高光 -> 能看出"这是一颗球的海洋"。
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

uniform float planet_radius = 2200.0;
uniform vec3 deep_color : source_color = vec3(0.020, 0.075, 0.145);
uniform vec3 shallow_color : source_color = vec3(0.055, 0.235, 0.360);
uniform float wave_strength = 0.55;

varying vec3 w_pos;

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

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - w_pos);
	float fres = pow(1.0 - clamp(dot(n, view_dir), 0.0, 1.0), 3.2);

	// 微波纹：两层噪声错向滚动
	float w1 = vnoise(w_pos.xz * 0.09 + vec2(TIME * 0.045, TIME * 0.028));
	float w2 = vnoise(w_pos.xz * 0.021 - vec2(TIME * 0.021, TIME * 0.033));
	float wave = (w1 * 0.6 + w2 * 0.4) * wave_strength;

	vec3 col = mix(deep_color, shallow_color, clamp(wave + fres * 0.55, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = mix(0.14, 0.03, fres);
	METALLIC = 0.32;
	SPECULAR = 0.72;
	EMISSION = shallow_color * fres * 0.16;
}
