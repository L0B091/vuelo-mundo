// Fachadas de Malé: revoque PBR (Poly Haven CC0) teñido por edificio + ventanas y locales
// procedurales (sin texturas de fotos reales). Pensado para el renderer Mobile.
//  UV  = (metros a lo largo del perímetro, altura en metros desde el mar)
//  UV2 = (estilo: 0 revoque, 1 piedra de coral; 1 = planta baja comercial)
//  COLOR = tinte del edificio
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D plaster_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D coral_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D coral_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D coral_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float deck_y = 1.8;
uniform float floor_h = 3.2;
uniform float tex_scale = 0.33;
uniform float window_detail = 1.0; // 0 en perfiles bajos: sin marcos

varying vec2 m;
varying float style;
varying float shop;
varying vec3 tint;
varying float top_y;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	m = UV;
	style = UV2.x;
	shop = UV2.y;
	tint = COLOR.rgb;
}

void fragment() {
	vec2 tuv = m * tex_scale;
	vec3 alb;
	vec3 orm;
	vec3 nrm;
	if (style > 0.5) {
		alb = texture(coral_albedo, tuv).rgb;
		orm = texture(coral_orm, tuv).rgb;
		nrm = texture(coral_normal, tuv).rgb;
	} else {
		alb = texture(plaster_albedo, tuv).rgb * tint * 1.08;
		orm = texture(plaster_orm, tuv).rgb;
		nrm = texture(plaster_normal, tuv).rgb;
	}
	float h = m.y - deck_y;
	float rough = orm.g;
	float metal = 0.0;
	float ao = orm.r;
	vec3 col = alb;
	// zócalo oscurecido (AO falsa de calle) y base gris
	ao *= mix(0.55, 1.0, smoothstep(0.0, 1.2, h));
	if (style < 0.5) {
		float fl = floor(h / floor_h);
		float fy = h - fl * floor_h;
		float cell_w = 3.0;
		float cu = floor(m.x / cell_w);
		float fx = m.x - cu * cell_w;
		float rnd = hash12(vec2(cu, fl) + tint.rg * 31.0);
		bool ground = fl < 0.5;
		bool is_shop = ground && shop > 0.5;
		if (is_shop) {
			// local comercial: vidriera alta con marco, persiana a veces
			float inx = step(0.25, fx) * step(fx, cell_w - 0.25);
			float iny = step(0.35, fy) * step(fy, 2.75);
			float glass = inx * iny;
			float shutter = step(0.72, rnd);
			vec3 g = mix(vec3(0.05, 0.07, 0.09), vec3(0.55, 0.47, 0.32), 0.25 * rnd);
			vec3 sh = vec3(0.55, 0.57, 0.6) * (0.85 + 0.15 * step(0.5, fract(fy * 6.0)));
			col = mix(col, mix(g, sh, shutter), glass);
			rough = mix(rough, mix(0.06, 0.45, shutter), glass);
			metal = mix(metal, 0.6 * shutter, glass);
			// marquesina sobre la vidriera
			float awn = step(2.85, fy) * step(fy, 3.05);
			col = mix(col, vec3(0.2, 0.22, 0.25), awn);
		} else if (!ground || shop < 0.5) {
			float wx0 = 0.75, wx1 = 2.25, wy0 = 0.95, wy1 = 2.45;
			float inside = step(wx0, fx) * step(fx, wx1) * step(wy0, fy) * step(fy, wy1);
			float frame = window_detail * (step(wx0 - 0.08, fx) * step(fx, wx1 + 0.08) * step(wy0 - 0.08, fy)
					* step(fy, wy1 + 0.08) - inside);
			// sin ventanas en la última franja (parapeto) ni donde la fachada es ciega
			float blind = step(0.86, rnd);
			inside *= 1.0 - blind;
			frame *= 1.0 - blind;
			vec3 glass = mix(vec3(0.06, 0.09, 0.12), vec3(0.32, 0.36, 0.38), rnd * 0.5);
			col = mix(col, glass, inside);
			col = mix(col, vec3(0.78, 0.78, 0.76), frame);
			rough = mix(rough, 0.05, inside);
			// alféizar
			float sill = step(wx0 - 0.1, fx) * step(fx, wx1 + 0.1) * step(wy0 - 0.16, fy) * step(fy, wy0 - 0.06);
			ao *= 1.0 - 0.35 * sill * window_detail;
		}
		// moldura entre pisos
		float band = step(floor_h - 0.12, fy);
		col = mix(col, col * 0.82, band);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL_MAP = nrm;
	SPECULAR = 0.5;
}
