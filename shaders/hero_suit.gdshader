// Traje de superhéroe sobre el cuerpo base (Universal Base Characters, CC0): la máscara UV
// (R traje, G guantes/botas, B franja del pecho) mezcla la piel original con tela teñida.
shader_type spatial;
render_mode cull_back;

uniform sampler2D base_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap;
uniform vec4 suit_color : source_color = vec4(0.1, 0.12, 0.25, 1.0);
uniform vec4 accent_color : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform float metal = 0.0;
uniform float fabric_scale = 180.0;

void fragment() {
	vec3 skin = texture(base_tex, UV).rgb;
	vec3 m = texture(mask_tex, UV).rgb;
	float suit = smoothstep(0.35, 0.65, m.r);
	float acc = smoothstep(0.35, 0.65, max(m.g, m.b));
	// tela: trama fina procedural (se pierde a distancia por el filtrado, sin costo de textura)
	vec2 f = UV * fabric_scale;
	float weave = 0.5 + 0.5 * sin(f.x * 6.2831) * sin(f.y * 6.2831);
	// se conserva el relieve (músculos) de la textura original como luminancia
	float lum = dot(skin, vec3(0.299, 0.587, 0.114));
	vec3 cloth = suit_color.rgb * (0.55 + 0.9 * lum) * (0.94 + 0.06 * weave);
	vec3 trim = accent_color.rgb * (0.6 + 0.8 * lum);
	vec3 col = mix(skin, cloth, suit);
	col = mix(col, trim, acc * max(suit, m.g));
	ALBEDO = col;
	float r = texture(rough_tex, UV).r;
	ROUGHNESS = mix(r, mix(0.55, 0.28, metal), max(suit, acc));
	METALLIC = metal * max(suit, acc);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	RIM = 0.2 * suit;
	RIM_TINT = 0.4;
}
