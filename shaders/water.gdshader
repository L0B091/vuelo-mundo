// Agua con batimetría real.
// - depth_tex: profundidad (m) horneada desde ETOPO/GEBCO por tesela; d < 0 es tierra.
// - Color según profundidad y latitud (atolón tropical != puerto templado o polar).
// - Espuma en la orilla y sobre arrecifes, transparencia en aguas bajas.
// - Olas: normales animadas periódicas en coordenadas GLOBALES (módulo WAVE_PERIOD) para que
//   el desplazamiento de origen no haga saltar el patrón.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

global uniform vec2 world_origin_mod;

uniform sampler2D depth_tex : filter_linear, repeat_disable;
uniform float tex_n = 65.0;
uniform float abs_lat = 10.0;
uniform float foam_depth = 1.5;
uniform float wave_strength = 1.0;
uniform float time_scale = 1.0;

const float P = 8192.0;
const float TAU_ = 6.28318530718;

varying vec2 g;        // coordenada global periódica (x este, y sur)
varying vec2 uv_d;
varying float view_dist;

vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

void vertex() {
	uv_d = (UV * (tex_n - 1.0) + 0.5) / tex_n;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	g = wp.xz + world_origin_mod;
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

// onda periódica en P: vector de onda (a, b) enteros
vec3 wave(vec2 p, vec2 ab, float amp, float speed, float t) {
	vec2 k = TAU_ * ab / P;
	float ph = dot(k, p) - speed * t;
	float d = amp * cos(ph);
	return vec3(-k.x * d, -k.y * d, amp * sin(ph));
}

void fragment() {
	float d = texture(depth_tex, uv_d).r;
	if (d < -0.6) {
		discard;
	}
	float t = TIME * time_scale;
	vec3 s = vec3(0.0);
	s += wave(g, vec2(97.0, 61.0), 0.35, 1.3, t);
	s += wave(g, vec2(-71.0, 140.0), 0.22, 1.7, t);
	s += wave(g, vec2(260.0, -170.0), 0.10, 2.6, t);
	s += wave(g, vec2(-410.0, -333.0), 0.06, 3.4, t);
	s += wave(g, vec2(800.0, 610.0), 0.03, 4.8, t);
	// las olas se calman en lagunas y se desvanecen a lo lejos (evita aliasing)
	float calm = mix(0.35, 1.0, smoothstep(2.0, 30.0, d));
	float fade = 1.0 - smoothstep(600.0, 6000.0, view_dist);
	vec2 slope = s.xy * wave_strength * calm * fade;
	vec3 nw = normalize(vec3(slope.x, 1.0, slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// paletas por latitud
	float temperate = smoothstep(20.0, 38.0, abs_lat);
	float polar = smoothstep(52.0, 68.0, abs_lat);
	vec3 shallow = mix(srgb(vec3(0.22, 0.85, 0.80)), srgb(vec3(0.32, 0.60, 0.55)), temperate);
	vec3 mid = mix(srgb(vec3(0.02, 0.55, 0.72)), srgb(vec3(0.08, 0.34, 0.42)), temperate);
	vec3 deep = mix(srgb(vec3(0.01, 0.10, 0.30)), srgb(vec3(0.02, 0.12, 0.22)), temperate);
	// laguna de atolón (25-60 m): azul zafiro, distinto del turquesa del arrecife y del azul
	// marino del océano abierto
	vec3 lagoon = mix(srgb(vec3(0.02, 0.33, 0.66)), srgb(vec3(0.05, 0.26, 0.36)), temperate);
	shallow = mix(shallow, srgb(vec3(0.36, 0.52, 0.56)), polar);
	mid = mix(mid, srgb(vec3(0.12, 0.28, 0.34)), polar);
	deep = mix(deep, srgb(vec3(0.04, 0.10, 0.16)), polar);
	lagoon = mix(lagoon, mid, polar);
	vec3 col = mix(shallow, mid, smoothstep(0.5, 8.0, d));
	col = mix(col, lagoon, smoothstep(8.0, 40.0, d));
	col = mix(col, deep, smoothstep(70.0, 600.0, d));

	// espuma: banda de orilla con ruptura animada
	float shore = 1.0 - smoothstep(0.0, foam_depth, d);
	float brk = 0.5 + 0.5 * sin(dot(g, vec2(0.11, 0.07)) + t * 1.8 + s.z * 6.0);
	float foam = shore * mix(0.55, 1.0, brk);

	float alpha = mix(0.45, 0.97, smoothstep(0.0, 12.0, d));
	alpha *= smoothstep(-0.6, 0.0, d);
	ALBEDO = mix(col, srgb(vec3(0.96, 0.98, 1.0)), foam);
	ALPHA = clamp(max(alpha, foam * 0.92), 0.0, 1.0);
	ROUGHNESS = mix(0.04, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
