// Lecho marino guiado por el Allen Coral Atlas (CC BY 4.0): la textura de clases bentónicas
// (benthic.png, R = clase*1/255) elige el material: arena, pasto marino, coral/alga, escombro,
// roca, microalgas. Base: arena PBR de Poly Haven (CC0); el resto son tintes y patrones
// procedurales. Bordes entre clases suavizados con ruido (no pixelados).
shader_type spatial;

uniform sampler2D benthic : filter_nearest, repeat_disable;
uniform vec2 zone_size = vec2(2000.0, 2500.0);
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.9, 0.9, 0.85);
uniform float uv_scale = 0.05;
varying vec3 lp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

int cls_at(vec2 p) {
	return int(texture(benthic, p / zone_size).r * 255.0 + 0.5);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 p = lp.xz;
	// jitter del muestreo: los bordes de clase se ven orgánicos
	vec2 j = (vec2(noise(p * 0.08), noise(p * 0.08 + 7.0)) - 0.5) * 9.0;
	int c = cls_at(p + j);
	vec2 uv = p * uv_scale;
	vec3 sand = texture(sand_albedo, uv).rgb * tint;
	vec3 col = sand;
	float rough = 0.9;
	float n1 = noise(p * 0.7);
	float n2 = noise(p * 3.1);
	if (c == 2) {  // pasto marino: verde oliva oscuro, hojas en manchones
		col = mix(sand * 0.6, vec3(0.10, 0.20, 0.07), smoothstep(0.3, 0.6, n1 * 0.6 + n2 * 0.4));
	} else if (c == 3) {  // coral/alga: ocre/marrón/violáceo moteado
		vec3 a = vec3(0.42, 0.30, 0.18);
		vec3 b = vec3(0.36, 0.22, 0.30);
		col = mix(mix(a, b, n1), sand * 0.8, smoothstep(0.65, 0.85, n2) * 0.6);
		rough = 0.8;
	} else if (c == 4) {  // escombro de coral: gris claro granulado
		col = mix(sand * 0.95, vec3(0.62, 0.60, 0.55), 0.5 + 0.5 * step(0.55, n2));
	} else if (c == 5) {  // roca/plataforma: gris parduzco
		col = mix(vec3(0.33, 0.31, 0.27), vec3(0.45, 0.42, 0.36), n1);
	} else if (c == 6) {  // tapetes de microalgas
		col = mix(sand, vec3(0.33, 0.32, 0.16), 0.55);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	NORMAL_MAP = texture(sand_normal, uv).rgb;
}
