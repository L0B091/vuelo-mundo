// Agua con batimetría real.
// - depth_tex: profundidad (m) horneada desde ETOPO/GEBCO por tesela; d < 0 es tierra.
// - Color según profundidad y latitud (atolón tropical != puerto templado o polar).
// - Espuma en la orilla y sobre arrecifes, transparencia en aguas bajas.
// - Olas: normales animadas periódicas en coordenadas GLOBALES (módulo WAVE_PERIOD) para que
//   el desplazamiento de origen no haga saltar el patrón.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

global uniform vec2 world_origin_mod;

// Recorte del conector bajo los micro-mapas cargados (ellos traen su propio suelo/agua).
// site_cut_* = (x0, z0, x1, z1) en coordenadas locales del mundo; x1 <= x0 = sin recorte.
global uniform vec4 site_cut_a;
global uniform vec4 site_cut_b;

bool in_cut(vec2 p) {
	bool a = site_cut_a.z > site_cut_a.x && p.x > site_cut_a.x && p.x < site_cut_a.z && p.y > site_cut_a.y
			&& p.y < site_cut_a.w;
	bool b = site_cut_b.z > site_cut_b.x && p.x > site_cut_b.x && p.x < site_cut_b.z && p.y > site_cut_b.y
			&& p.y < site_cut_b.w;
	return a || b;
}
uniform bool use_cut = true;
// Detalle de oleaje por perfil (0 bajo … 12 ultra): espectro "tipo FFT" de ondas extra con
// dispersión de aguas profundas (ω = √(g·k)), sesgado al viento. Lo fija Quality.
global uniform int water_detail;

uniform sampler2D depth_tex : filter_linear, repeat_disable;
uniform float tex_n = 65.0;
uniform float abs_lat = 10.0;
uniform float foam_depth = 1.5;
uniform float wave_strength = 1.0;
uniform float time_scale = 1.0;
// Geomorfología del Allen Coral Atlas (solo micro-mapas): 1 = cresta de arrecife → rompiente
// con espuma que pulsa con la ola; 2/3 = planicie arrecifal → turquesa claro; 6 = laguna
// somera/bancos de arena → aguamarina brillante.
uniform sampler2D geo_tex : filter_nearest, repeat_disable;
uniform bool use_geo = false;

const float P = 8192.0;
const float TAU_ = 6.28318530718;

varying vec2 g;
varying vec2 wxz;        // coordenada global periódica (x este, y sur)
varying vec2 uv_d;
varying float view_dist;

vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

void vertex() {
	uv_d = (UV * (tex_n - 1.0) + 0.5) / tex_n;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	g = wp.xz + world_origin_mod;
	wxz = wp.xz;
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
	if (d < -0.6 || (use_cut && in_cut(wxz))) {
		discard;
	}
	float t = TIME * time_scale;
	vec3 s = vec3(0.0);
	s += wave(g, vec2(97.0, 61.0), 0.35, 1.3, t);
	s += wave(g, vec2(-71.0, 140.0), 0.22, 1.7, t);
	s += wave(g, vec2(260.0, -170.0), 0.10, 2.6, t);
	s += wave(g, vec2(-410.0, -333.0), 0.06, 3.4, t);
	s += wave(g, vec2(800.0, 610.0), 0.03, 4.8, t);
	// espectro adicional: longitudes de 40 m a 0.6 m, amplitud ∝ λ (pendiente constante),
	// direcciones repartidas ±70° alrededor del viento (NE monzón ≈ (0.8, -0.6))
	for (int i = 0; i < 12; i++) {
		if (i >= water_detail) {
			break;
		}
		float fi = float(i);
		float lam = 40.0 * pow(0.68, fi);
		float ang = 0.64 + sin(fi * 2.399) * 1.2;
		vec2 dir = vec2(cos(ang), -sin(ang));
		vec2 ab = round(dir * P / lam);
		float kk = TAU_ / lam;
		// sin moiré: cada onda se apaga cuando su longitud ya no se resuelve en pantalla
		float vis = 1.0 - smoothstep(lam * 12.0, lam * 40.0, view_dist);
		s += wave(g, ab, lam * 0.012 * vis, sqrt(9.81 * kk), t);
	}
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
	if (use_geo) {
		vec2 jg = (vec2(sin(g.y * 0.21), cos(g.x * 0.19))) * 0.004;
		int gc = int(texture(geo_tex, UV + jg).r * 255.0 + 0.5);
		// cerca del borde del micro-mapa los efectos se apagan: empalma con el agua de las teselas
		vec2 eu = min(UV, 1.0 - UV);
		float edge = smoothstep(0.0, 0.08, min(eu.x, eu.y));
		if (gc == 1) {
			// rompiente: series de olas (período ~9 s) que llegan del océano y estallan en espuma
			float set_ = 0.5 + 0.5 * sin(t * 0.7 + dot(g, vec2(0.013, 0.009)));
			float lines = smoothstep(0.55, 1.0, sin(dot(g, vec2(0.35, 0.22)) - t * 2.2 + s.z * 4.0));
			foam = max(foam, clamp(0.45 + 0.55 * lines, 0.0, 1.0) * mix(0.55, 1.0, set_) * edge);
		} else if (gc == 2 || gc == 3) {
			col = mix(col, srgb(vec3(0.42, 0.90, 0.84)), 0.45 * edge);
		} else if (gc == 6) {
			col = mix(col, srgb(vec3(0.50, 0.93, 0.88)), 0.3 * edge);
		}
	}

	float alpha = mix(0.45, 0.97, smoothstep(0.0, 12.0, d));
	alpha *= smoothstep(-0.6, 0.0, d);
	ALBEDO = mix(col, srgb(vec3(0.96, 0.98, 1.0)), foam);
	if (!FRONT_FACING) {
		// visto desde abajo: superficie plateada/turquesa opaca (reflexión total interna)
		ALBEDO = mix(srgb(vec3(0.10, 0.55, 0.62)), srgb(vec3(0.75, 0.92, 0.95)), 0.3 + 0.4 * foam);
		NORMAL = -NORMAL;
	}
	ALPHA = FRONT_FACING ? clamp(max(alpha, foam * 0.92), 0.0, 1.0) : 0.92;
	ROUGHNESS = mix(0.04, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
