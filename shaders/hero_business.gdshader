// Traje de calle (saco y pantalón oscuros, camisa blanca, corbata, zapatos) pintado sobre el
// cuerpo base (Universal Base Characters "Superhero", Quaternius, CC0). Las regiones salen de la
// posición de reposo del vértice (UV2 = x,y; COLOR.r = z, horneados por AvatarBody) y de la
// máscara UV del traje (R cuerpo, G manos/pies): no dependen de la pose, no se deslizan.
shader_type spatial;
render_mode cull_back;

uniform sampler2D base_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap;
uniform vec4 suit_color : source_color = vec4(0.11, 0.115, 0.13, 1.0);
uniform vec4 tie_color : source_color = vec4(0.12, 0.16, 0.35, 1.0);
uniform vec4 shirt_color : source_color = vec4(0.93, 0.93, 0.95, 1.0);

varying vec3 rp;

void vertex() {
	rp = vec3(UV2.x, UV2.y, COLOR.r * 0.6 - 0.3);
}

void fragment() {
	vec3 skin = texture(base_tex, UV).rgb;
	vec3 m = texture(mask_tex, UV).rgb;
	float body = smoothstep(0.35, 0.65, m.r);
	float ext = smoothstep(0.35, 0.65, m.g);  // guantes/botas de la máscara
	float lum = dot(skin, vec3(0.299, 0.587, 0.114));
	float x = abs(rp.x);
	float y = rp.y;
	float front = smoothstep(0.02, 0.06, rp.z);
	// saco: trama de lana fina; pantalón apenas más oscuro bajo la cadera
	vec2 f = UV * 260.0;
	float weave = 0.5 + 0.5 * sin(f.x * 6.2831) * sin(f.y * 6.2831);
	vec3 cloth = suit_color.rgb * (0.9 + 0.25 * lum) * (0.95 + 0.05 * weave);
	cloth *= mix(0.88, 1.0, step(0.98, y));
	// solapas: bordes del escote del saco algo más brillantes
	float vw = 0.012 + (y - 1.3) * 0.32;
	float shirt = front * step(1.3, y) * step(y, 1.56) * step(x, vw);
	// cuello de camisa: tapa el borde irregular de la máscara en el cuello
	float collar = smoothstep(1.47, 1.48, y) * (1.0 - smoothstep(1.565, 1.575, y)) * step(x, 0.085);
	shirt = max(shirt, collar);
	body = max(body, collar);
	body = max(body, (1.0 - ext) * (1.0 - smoothstep(1.55, 1.565, y)));  // hombros sin el borde de la máscara
	float lapel = front * step(1.15, y) * step(y, 1.52) * step(vw, x) * step(x, vw + 0.03);
	float tie = front * step(1.12, y) * step(y, 1.5) * step(x, mix(0.022, 0.012, smoothstep(1.4, 1.5, y)));
	vec3 col = mix(skin, cloth, body);
	col = mix(col, cloth * 1.25, lapel * body);
	col = mix(col, shirt_color.rgb * (0.8 + 0.3 * lum), shirt * body);
	col = mix(col, tie_color.rgb * (0.7 + 0.6 * lum), tie * body);
	// manos con piel; pies: zapatos negros lustrados
	float shoe = ext * step(y, 0.16);
	col = mix(col, skin, ext * (1.0 - shoe));
	col = mix(col, vec3(0.025, 0.022, 0.02), shoe);
	ALBEDO = col;
	float r = texture(rough_tex, UV).r;
	ROUGHNESS = mix(r, 0.72, body * (1.0 - shoe));
	ROUGHNESS = mix(ROUGHNESS, 0.25, shoe);
	ROUGHNESS = mix(ROUGHNESS, 0.5, tie * body);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.25, body);  // la tela disimula la musculatura del cuerpo base
}
