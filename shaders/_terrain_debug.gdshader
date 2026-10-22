// M41 临时调试 shader：验证 Terrain3D 的 _region_map / _height_maps 是否被填充。
// 绿色 = 该顶点在 region 内（高度正确采样）；红色 = 判定无 region（_region_map 未填充）。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded, skip_vertex_transform;

#define MAX_REGIONS 1024

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
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;
group_uniforms;

varying float v_rz;
varying float v_h;

ivec3 get_index_coord(const vec2 uv) {
	vec2 r_uv = round(uv);
	ivec2 pos = ivec2(floor(r_uv * _region_texel_size)) + (_region_map_size / 2);
	int bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
	int map_val = _region_map[pos.y * _region_map_size + pos.x];
	int raw_index = map_val - 1;
	int is_region = bounds * int(raw_index >= 0) * int(raw_index < MAX_REGIONS);
	int is_dummy = bounds * int(map_val < 0);
	int layer_index = is_region * raw_index + is_dummy * (map_val - 1) - (1 - is_region - is_dummy);
	return ivec3(ivec2(mod(r_uv, _region_size)), layer_index);
}

void vertex() {
	vec3 wv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 start_pos = wv.xz * _vertex_density;
	ivec3 idx = get_index_coord(start_pos);
	v_rz = float(idx.z);
	float h = 0.0;
	if (idx.z >= 0 && idx.z < MAX_REGIONS) {
		h = texelFetch(_height_maps, idx, 0).r;
	}
	v_h = h;
	wv.y = h;
	VERTEX = (VIEW_MATRIX * vec4(wv, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	if (v_rz < 0.0) {
		ALBEDO = vec3(0.85, 0.12, 0.12);   // 红：无 region
	} else {
		ALBEDO = vec3(0.12, 0.72, 0.24);   // 绿：有 region
	}
}
