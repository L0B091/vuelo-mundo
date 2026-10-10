// Cáusticas sobre el lecho (pasada aditiva encima del material PBR del fondo). Patrón
// procedural de redes de luz animadas (dos capas de "voronoi" deformado), se apaga con la
// profundidad y fuera del agua. Coordenadas globales periódicas (sin saltos al mover origen).
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;

global uniform vec2 world_origin_mod;
global uniform float caustics_strength;
uniform float strength = 0.55;
varying vec3 wp;

vec2 h2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float cell(vec2 p, float t) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float m = 8.0;
	float m2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = h2(i + o);
			r = 0.5 + 0.45 * sin(t + 6.2831 * r);
			float dd = length(o + r - f);
			m2 = min(m2, max(m, dd));
			m = min(m, dd);
		}
	}
	// red de luz: brilla en los bordes entre celdas (F2 - F1 chico), como las cáusticas reales
	return 1.0 - smoothstep(0.0, 0.07, m2 - m);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = -wp.y;
	if (depth < 0.05) {
		discard;
	}
	vec2 g = mod(wp.xz + world_origin_mod, 4096.0);
	g += 0.35 * vec2(sin(g.y * 0.9 + TIME), cos(g.x * 0.8 + TIME * 1.1));
	float t = TIME * 0.9;
	float c = cell(g * 0.45, t) * 0.8 + cell(g * 0.7 + 3.1, t * 1.3) * 0.5;
	float fade = smoothstep(0.05, 0.6, depth) * (1.0 - smoothstep(4.0, 18.0, depth));
	float far = 1.0 - smoothstep(40.0, 160.0, length(VERTEX));
	ALBEDO = vec3(0.85, 0.97, 1.0) * c * strength * caustics_strength * fade * far;
}
