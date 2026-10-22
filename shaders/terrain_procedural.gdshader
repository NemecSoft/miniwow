// M41 程序化地表 shader（基于 Terrain3D 官方 extras/shaders/lightweight.gdshader 改造）
//
// 为什么不用官方内置 shader / lightweight 原版：
//   本项目地形是「RF 单通道高度 + null control map」，control 采样恒为 0，
//   官方 shader 的混合权重算法是
//       float id_weight = exp2(sharpness * log2(id_w + alb.a * world_normal));
//   当 id_w == 0 时 log2(0) = -inf → id_weight = 0 → albedo_height 累加为 0
//   → ALBEDO = 0 → **地形整片纯黑**（M41 事故：一加纹理就黑，清空纹理反而能看见）。
// 本 shader 保留 lightweight 的顶点高度/法线/clipmap 位移逻辑（必须，否则地形塌平），
// 只把 fragment 的着色换成按世界坐标 + 坡度 + 噪声的程序化地表色，完全不碰
// _control_maps / _texture_array_albedo。

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, skip_vertex_transform;

#define MAX_REGIONS 1024

#define DECODE_HOLE(control) bool(control >> 2u & 0x1u)

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	#define fma(a, b, c) ((a) * (b) + (c))
	#define dFdxCoarse(a) dFdx(a)
	#define dFdyCoarse(a) dFdy(a)
#endif

// ===== 私有 uniform（名字必须与 Terrain3D 内部一致，否则 C++ 填不进来）=====
group_uniforms private;
uniform vec3 _target_pos = vec3(0.f);
uniform float _mesh_size = 48.f;
uniform uint _background_mode = 1u;
uniform uint _mouse_layer = 0x80000000u;
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0;
uniform float _subdiv = 1.0;
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625;
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform vec2 _region_locations[MAX_REGIONS];
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;
group_uniforms;

// ===== 公开 uniform（地表配色，可在材质里微调）=====
group_uniforms general_uniforms;
uniform float ground_level : hint_range(-1000., 1000.) = -200.0;
uniform float region_blend : hint_range(.001, 1., 0.001) = 0.25;
uniform bool flat_terrain_normals = false;
group_uniforms;

group_uniforms surf_colors;
uniform vec3 grass_color_a : source_color = vec3(0.24, 0.36, 0.14);
uniform vec3 grass_color_b : source_color = vec3(0.34, 0.44, 0.18);
uniform vec3 dirt_color : source_color = vec3(0.40, 0.31, 0.19);
uniform vec3 rock_color : source_color = vec3(0.36, 0.35, 0.33);
uniform float patch_scale : hint_range(0.001, 0.1) = 0.018;
uniform float detail_scale : hint_range(0.5, 8.0) = 1.7;
group_uniforms;

varying vec3 v_vertex;
varying float v_vertex_xz_dist;
varying vec3 v_normal;
varying vec3 v_camera_pos;
varying mat3 TBN;


ivec3 get_index_coord(const vec2 p_uv) {
	vec2 r_uv = round(p_uv);
	ivec2 pos = ivec2(floor(r_uv * _region_texel_size)) + (_region_map_size / 2);
	int bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
	int map_val = _region_map[pos.y * _region_map_size + pos.x];
	int raw_index = map_val - 1;
	int is_region = bounds * int(raw_index >= 0) * int(raw_index < MAX_REGIONS);
	int is_dummy = bounds * int(map_val < 0);
	int layer_index = is_region * raw_index + is_dummy * (map_val - 1) - (1 - is_region - is_dummy);
	return ivec3(ivec2(mod(r_uv, _region_size)), layer_index);
}

bool is_none_bg(const vec2 p_uv) {
	ivec4 regions = ivec4(
		get_index_coord(p_uv - vec2(0.5, 0.0)).z,
		get_index_coord(p_uv - vec2(0.0, 0.5)).z,
		get_index_coord(p_uv + vec2(1.0, 0.0)).z,
		get_index_coord(p_uv + vec2(0.0, 1.0)).z);
	return any(equal(regions, ivec4(-1)));
}

float check_region(const vec2 uv2) {
	ivec2 pos = ivec2(floor(uv2)) + (_region_map_size / 2);
	int bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
	int raw_index = _region_map[pos.y * _region_map_size + pos.x] - 1;
	int is_valid = bounds * int(raw_index >= 0) * int(raw_index < MAX_REGIONS);
	return float(is_valid);
}

float get_region_blend(vec2 uv2) {
	uv2 -= 0.5011;
	const vec2 offset = vec2(0.0, 1.0);
	float a = check_region(uv2 + offset.xy);
	float b = check_region(uv2 + offset.yy);
	float c = check_region(uv2 + offset.yx);
	float d = check_region(uv2 + offset.xx);
	vec2 blend_factor = vec2(2.0 + 126.0 * (1.0 - region_blend));
	vec2 f = fract(uv2);
	vec2 w = 1.0 / (1.0 + exp(blend_factor * log((1.0 - f) / f)));
	float blend = mix(mix(d, c, w.x), mix(a, b, w.x), w.y);
	return (1.0 - blend) * 2.0;
}

float interpolated_height(vec2 pos) {
	const vec2 offsets = vec2(0, 1);
	vec2 index_id = floor(pos);
	ivec3 index[4];
	index[0] = get_index_coord(index_id + offsets.xy);
	index[1] = get_index_coord(index_id + offsets.yy);
	index[2] = get_index_coord(index_id + offsets.yx);
	index[3] = get_index_coord(index_id + offsets.xx);
	float h0 = texelFetch(_height_maps, index[0], 0).r;
	float h1 = texelFetch(_height_maps, index[1], 0).r;
	float h2 = texelFetch(_height_maps, index[2], 0).r;
	float h3 = texelFetch(_height_maps, index[3], 0).r;
	vec2 f = fract(pos);
	vec2 i = 1.0 - f;
	vec4 w = vec4(i.x * f.y, f.x * f.y, f.x * i.y, i.x * i.y);
	return h0 * w[0] + h1 * w[1] + h2 * w[2] + h3 * w[3];
}


void vertex() {
	v_camera_pos = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_vertex_xz_dist = length(v_vertex.xz - _target_pos.xz);

	float scale = MODEL_MATRIX[0][0];
	float inv_scale = 1.0 / scale;
	float max_xz = max(abs(v_vertex.x - _target_pos.x), abs(v_vertex.z - _target_pos.z));
	float vertex_lerp = smoothstep(0.0, 1.0, (max_xz * inv_scale - _mesh_size - 4.0) / (_mesh_size - 4.0));
	vec2 vertex_fract = fract(VERTEX.xz * 0.5) * 2.0;
	vec2 shift = (scale < _vertex_spacing / _subdiv + 1e-6) ?
		mix(vertex_fract, vec2(vertex_fract.x, -vertex_fract.y),
			round(fract(round(mod(v_vertex.z * inv_scale, 4.0)) *
			round(mod(v_vertex.x * inv_scale, 4.0)) * 0.25))) :
		vertex_fract * round((fract(v_vertex.xz * 0.25 * inv_scale) - 0.5) * 4.0);
	vec2 start_pos = v_vertex.xz * _vertex_density;
	vec2 end_pos = (v_vertex.xz - shift * scale) * _vertex_density;
	v_vertex.xz -= shift * scale * vertex_lerp;

	UV = v_vertex.xz * _vertex_density;
	UV2 = fma(UV, vec2(_region_texel_size), vec2(0.5 * _region_texel_size));

	// 挖洞：只认 control map 的 hole 位（无 control 时恒 false）。
	// 注意：M41 特意**不**沿用 _background_mode==NONE 时丢弃无 region 顶点的逻辑——
	// 那会让数据区边缘/空洞直接露出黑色天空下半球（用户看到的"黑咕隆咚"）。
	// 无 region 的顶点改用 ground_level 兜底，保证任何角度都看不到黑洞。
	ivec3 v_region = get_index_coord(start_pos);
	uint control = floatBitsToUint(texelFetch(_control_maps, v_region, 0).r);
	bool hole = DECODE_HOLE(control);

	if (!(CAMERA_VISIBLE_LAYERS == _mouse_layer) && hole) {
		v_vertex.x = 0. / 0.;
	} else {
		float h, u, v;
		if (v_region.z < 0) {
			// 无 region：用 ground_level 兜底（不丢弃）
			h = ground_level;
			u = ground_level;
			v = ground_level;
		} else if (scale < _vertex_spacing) {
			h = interpolated_height(UV);
			u = interpolated_height(UV + vec2(1, 0));
			v = interpolated_height(UV + vec2(0, 1));
		} else {
			ivec3 coord_a = get_index_coord(start_pos);
			ivec3 coord_b = get_index_coord(end_pos);
			ivec3 coord_ua = get_index_coord(start_pos + vec2(1, 0));
			ivec3 coord_ub = get_index_coord(end_pos + vec2(1, 0));
			ivec3 coord_va = get_index_coord(start_pos + vec2(0, 1));
			ivec3 coord_vb = get_index_coord(end_pos + vec2(0, 1));
			h = mix(texelFetch(_height_maps, coord_a, 0).r, texelFetch(_height_maps, coord_b, 0).r, vertex_lerp);
			u = mix(texelFetch(_height_maps, coord_ua, 0).r, texelFetch(_height_maps, coord_ub, 0).r, vertex_lerp);
			v = mix(texelFetch(_height_maps, coord_va, 0).r, texelFetch(_height_maps, coord_vb, 0).r, vertex_lerp);
		}

		// region 边界平滑过渡到 ground_level，避免数据区边缘出现断崖
		vec2 ruv = UV * _region_texel_size;
		h = mix(h, ground_level, smoothstep(0.0, 1.0, get_region_blend(ruv)));
		u = mix(u, ground_level, smoothstep(0.0, 1.0, get_region_blend(ruv + vec2(_region_texel_size, 0.0))));
		v = mix(v, ground_level, smoothstep(0.0, 1.0, get_region_blend(ruv + vec2(0.0, _region_texel_size))));

		v_vertex.y = h;
		v_normal = normalize(vec3(h - u, _vertex_spacing, h - v));
	}

	VERTEX = (VIEW_MATRIX * vec4(v_vertex, 1.0)).xyz;

	vec3 w_tangent = normalize(cross(v_normal, vec3(0.0, 0.0, 1.0)));
	vec3 w_binormal = normalize(cross(v_normal, w_tangent));
	TBN = mat3(w_tangent, w_binormal, v_normal);

	NORMAL = normalize((VIEW_MATRIX * vec4(v_normal, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(w_binormal, 0.0)).xyz);
	TANGENT = normalize((VIEW_MATRIX * vec4(w_tangent, 0.0)).xyz);
}


// 便宜的确定性 hash（不需要纹理）
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	// Godot 4.7 会为内部采样生成 `vec2 __p = uv * 1.0;`，此变量必须存在
	vec2 uv = UV;
	vec3 wp = v_vertex;
	float slope = 1.0 - clamp(v_normal.y, 0.0, 1.0);

	// 大尺度斑块（草地深浅 / 土斑）
	float n1 = sin(wp.x * patch_scale + sin(wp.z * patch_scale * 0.72) * 1.7) * 0.5 + 0.5;
	float n2 = sin(wp.z * patch_scale * 1.5 + sin(wp.x * patch_scale * 0.61) * 2.1) * 0.5 + 0.5;
	float macro = n1 * 0.62 + n2 * 0.38;

	// 细节颗粒
	float detail = hash21(floor(wp.xz * detail_scale));

	vec3 col = mix(grass_color_a, grass_color_b, macro);
	col = mix(col, dirt_color, smoothstep(0.52, 0.80, n2) * 0.55);
	col = mix(col, rock_color, smoothstep(0.30, 0.62, slope));
	col *= 0.88 + 0.24 * detail;

	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.08;
}
