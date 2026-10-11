// Props de biblioteca con color por vértice: suciedad, desgaste y variación por instancia
// (ruido en espacio de mundo, sin texturas extra) y balanceo opcional para botes.
shader_type spatial;

uniform float roughness = 0.7;
uniform float metallic = 0.0;
uniform float grime = 0.55;
uniform bool bob = false;

varying vec3 wpos;
varying float lh;
varying float inst;

float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	inst = fract(float(INSTANCE_ID) * 0.6180339);
	if (bob) {
		float ph = float(INSTANCE_ID) * 1.7;
		VERTEX.y += sin(TIME * 1.1 + ph) * 0.08 + VERTEX.x * sin(TIME * 0.9 + ph) * 0.03
			+ VERTEX.z * sin(TIME * 0.7 + ph * 1.3) * 0.012;
	}
	lh = VERTEX.y;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// el color de vértice viene en sRGB (colores de material del glTF)
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	// variación de tono por instancia (pintura distinta, desteñida al sol)
	c *= mix(vec3(0.88), vec3(1.08, 1.04, 0.98), inst);
	float n = noise(wpos * 3.1) * 0.6 + noise(wpos * 11.0) * 0.4;
	// mugre acumulada abajo y en manchas; desgaste claro en relieves
	float dirt = clamp((1.0 - smoothstep(0.0, 0.7, lh)) * 0.7 + (n - 0.45) * 1.2, 0.0, 1.0) * grime;
	c = mix(c, c * vec3(0.55, 0.5, 0.42), dirt);
	c = mix(c, c * 1.15 + 0.04, smoothstep(0.82, 0.95, noise(wpos * 23.0)) * grime * 0.5);
	ALBEDO = c;
	ROUGHNESS = clamp(roughness + dirt * 0.2, 0.0, 1.0);
	METALLIC = metallic * (1.0 - dirt);
}
