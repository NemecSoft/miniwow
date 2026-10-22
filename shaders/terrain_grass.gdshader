// M41 自建地形网格的草地 shader（不依赖 Terrain3D 的任何 uniform）。
// 背景：Terrain3D 1.1.0-rc1 在 Godot 4.7.2 下 GPU 侧高度图采样损坏，
// 渲染结果固定是"1m 棋盘格 + 规则尖刺"；CPU 的 data.get_height() 正常。
// 因此改为：隐藏 Terrain3D 渲染 → 用 get_height 生成 ArrayMesh → 本 shader 上色。

shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms surf_colors;
uniform vec3 grass_color_a : source_color = vec3(0.20, 0.31, 0.12);
uniform vec3 grass_color_b : source_color = vec3(0.31, 0.42, 0.16);
uniform vec3 dirt_color : source_color = vec3(0.38, 0.29, 0.17);
uniform vec3 rock_color : source_color = vec3(0.34, 0.33, 0.31);
uniform float patch_scale : hint_range(0.001, 0.2) = 0.022;
uniform float detail_scale : hint_range(0.5, 12.0) = 2.2;
group_uniforms;

// M43 天气：地面积雪覆盖度（0 = 无雪，1 = 全白）。
// 由 WeatherSystem 在切换雪天时写入；平地积雪厚、陡坡露出泥土岩面，符合直觉。
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;

varying vec3 w_pos;
varying vec3 w_norm;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_norm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV; // Godot 4.7 内部采样需要该标识符
	float slope = 1.0 - clamp(w_norm.y, 0.0, 1.0);

	float n1 = sin(w_pos.x * patch_scale + sin(w_pos.z * patch_scale * 0.72) * 1.7) * 0.5 + 0.5;
	float n2 = sin(w_pos.z * patch_scale * 1.5 + sin(w_pos.x * patch_scale * 0.61) * 2.1) * 0.5 + 0.5;
	float macro = n1 * 0.62 + n2 * 0.38;

	float detail = hash21(floor(w_pos.xz * detail_scale));

	vec3 col = mix(grass_color_a, grass_color_b, macro);
	col = mix(col, dirt_color, smoothstep(0.55, 0.82, n2) * 0.5);
	col = mix(col, rock_color, smoothstep(0.32, 0.62, slope));
	col *= 0.90 + 0.20 * detail;

	// 积雪：越平越厚（slope=0 平地全盖，陡坡留出岩土）
	float snow_mask = snow_amount * clamp(1.0 - slope * 1.35, 0.0, 1.0);
	// 用 macro 噪声让雪边不规则，避免"整块白布"
	snow_mask *= 0.82 + 0.18 * macro;
	col = mix(col, vec3(0.94, 0.96, 1.0), snow_mask);

	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.62, snow_mask);
	SPECULAR = mix(0.08, 0.22, snow_mask);
}
