// Gente de la multitud estática: cuerpo base texturizado (Universal Base Characters, CC0)
// con ropa de calle pintada por máscara UV + altura (UV2.y) / distancia al eje (UV2.x).
// Por instancia: color de la remera en INSTANCE_CUSTOM.rgb, largo del pantalón en .a,
// color del pantalón en el color de instancia (COLOR).
shader_type spatial;
render_mode cull_back;

uniform sampler2D base_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap;
uniform float hip = 0.52;

varying vec3 shirt;
varying vec3 pants;
varying float plen;

void vertex() {
	shirt = INSTANCE_CUSTOM.rgb;
	plen = INSTANCE_CUSTOM.a;
	pants = COLOR.rgb;
}

void fragment() {
	vec3 skin = texture(base_tex, UV).rgb;
	float suit = smoothstep(0.35, 0.65, texture(mask_tex, UV).r);
	float lum = dot(skin, vec3(0.299, 0.587, 0.114));
	float h = UV2.y;
	float ax = UV2.x;
	float top = step(hip, h) * step(h, 0.83) * max(step(ax, 0.2), step(0.66, h));
	float bottom = step(h, hip + 0.01) * step(mix(0.08, 0.3, plen), h);
	float shoe = step(h, 0.06);
	vec3 col = skin;
	col = mix(col, shirt * (0.6 + 0.8 * lum), top * max(suit, 0.6));
	col = mix(col, pants * (0.6 + 0.8 * lum), bottom * max(suit, 0.6));
	col = mix(col, vec3(0.08, 0.07, 0.07), shoe);
	ALBEDO = col;
	ROUGHNESS = mix(texture(rough_tex, UV).r, 0.85, max(top, bottom));
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}
