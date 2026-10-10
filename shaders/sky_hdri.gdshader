// Cielo HDRI (Poly Haven, CC0) arriba del horizonte; abajo, el color de la bruma (más allá
// del plano lejano se ve el "suelo" del cielo y tiene que coincidir con la niebla).
// Hora del día: el HDRI de mediodía se tiñe/oscurece según el sol (sky_tint, night) y se
// agrega disco solar con halo. Nubes procedurales (fbm 2D proyectado) con cobertura por clima;
// las octavas bajan en perfiles bajos (cloud_octaves).
shader_type sky;

uniform sampler2D panorama : source_color, filter_linear, hint_default_black;
uniform vec3 below_color : source_color = vec3(0.68, 0.79, 0.88);
uniform float exposure = 1.0;
uniform float yaw = 0.0;
uniform vec3 sky_tint : source_color = vec3(1.0);
uniform float night = 0.0;
uniform float cloud_cover = 0.25;
uniform int cloud_octaves = 4;
uniform float cloud_time = 0.0;
uniform vec3 cloud_light : source_color = vec3(1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		if (i >= cloud_octaves) {
			break;
		}
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float a = atan(d.x, -d.z) + yaw;
	vec2 uv = vec2(a / (2.0 * PI) + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
	vec3 c = texture(panorama, uv).rgb * exposure * sky_tint;
	// noche: azul profundo con estrellas tenues
	vec3 nightc = vec3(0.012, 0.02, 0.05) + step(0.9975, hash(floor(d.xz / max(d.y, 0.05) * 300.0))) * 0.6 * step(0.05, d.y);
	c = mix(c, nightc, night);
	// sol
	vec3 sd = LIGHT0_DIRECTION;
	float cs = max(dot(d, sd), 0.0);
	c += LIGHT0_COLOR * LIGHT0_ENERGY * (pow(cs, 2000.0) * 18.0 + pow(cs, 12.0) * 0.18) * (1.0 - night);
	// nubes: plano a "altura" fija, proyectado
	if (d.y > 0.0 && cloud_cover > 0.01) {
		vec2 cp = d.xz / (d.y + 0.08) * 1.6 + vec2(cloud_time * 0.004, cloud_time * 0.0015);
		float n = fbm(cp);
		float cov = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.25, n);
		float shade = 0.75 + 0.25 * smoothstep(0.3, 0.8, fbm(cp * 1.7 + 3.1));
		vec3 cc = cloud_light * shade * mix(1.0, 0.55, smoothstep(0.6, 1.0, cloud_cover));
		c = mix(c, cc * (1.0 - 0.9 * night), cov * smoothstep(0.0, 0.12, d.y));
	}
	// resplandor del ocaso: banda cálida en el horizonte hacia el sol (Rayleigh/Mie aproximado)
	float sunlow = 1.0 - smoothstep(0.05, 0.4, sd.y);
	float toward = pow(max(dot(normalize(d.xz + 1e-4), normalize(sd.xz + 1e-4)), 0.0), 2.0);
	float band = exp(-max(d.y, 0.0) * 9.0);
	c = mix(c, vec3(1.0, 0.42, 0.16) * 1.3, sunlow * band * (0.25 + 0.6 * toward) * (1.0 - night));
	float t = smoothstep(-0.02, 0.06, d.y);
	COLOR = mix(below_color, c, t);
}
