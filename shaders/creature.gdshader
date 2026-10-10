// Animales marinos procedurales: ondulación de natación en el vértice (sin esqueleto).
// mode 0 = pez/tiburón/delfín (ondulación lateral creciente hacia la cola; delfín: vertical),
// mode 1 = raya/manta (aleteo de las alas según |x|), mode 2 = tortuga (aletas).
// Color por vértice (lomo oscuro/vientre claro) + manchas procedurales opcionales.
shader_type spatial;
render_mode cull_disabled;

uniform int mode = 0;
uniform float length_m = 1.0;
uniform float amp = 0.08;
uniform float freq = 1.0;
uniform float speed = 1.0;
uniform bool vertical = false;
uniform float spots = 0.0;
uniform float phase = 0.0;
instance uniform float inst_phase = 0.0;
varying vec3 lp;

void vertex() {
	lp = VERTEX;
	float t = TIME * speed + phase + inst_phase + float(INSTANCE_ID) * 1.37;
	// z: +adelante (cabeza) … −atrás (cola), normalizado a 0..1 desde la cabeza
	float u = clamp(0.5 - VERTEX.z / length_m, 0.0, 1.0);
	if (mode == 0) {
		float d = sin(u * 6.2831 * freq - t * 6.0) * amp * length_m * u * u;
		if (vertical) {
			VERTEX.y += d;
		} else {
			VERTEX.x += d;
		}
	} else if (mode == 1) {
		float w = abs(VERTEX.x) / (length_m * 0.6);
		VERTEX.y += sin(t * 2.2 - w * 2.0) * amp * length_m * w * w;
	} else {
		float w = smoothstep(0.25, 0.6, abs(VERTEX.x) / length_m);
		VERTEX.y += sin(t * 2.0 + sign(VERTEX.x)) * amp * length_m * w;
	}
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 c = COLOR.rgb;
	if (spots > 0.0) {
		vec2 g = lp.xz * spots;
		vec2 f = fract(g) - 0.5;
		float s = step(length(f), 0.18 + 0.1 * hash(floor(g))) * step(0.2, COLOR.g);
		c = mix(c, vec3(0.92, 0.94, 0.95), s * step(0.0, lp.y));
	}
	ALBEDO = c;
	ROUGHNESS = 0.45;
	SPECULAR = 0.4;
}
