// Palmera: frondas recortadas con textura propia; el viento las mece (más arriba, más amplitud).
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D frond : source_color, filter_linear_mipmap;
uniform float wind = 1.0;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = w.x * 0.13 + w.z * 0.11;
	float h = max(VERTEX.y - 3.0, 0.0) / 6.0;
	float s = sin(TIME * 0.9 + ph) * 0.6 + sin(TIME * 2.3 + ph * 2.0) * 0.25;
	VERTEX.x += s * h * h * 0.35 * wind;
	VERTEX.z += cos(TIME * 1.1 + ph) * h * h * 0.2 * wind;
	// las frondas (UV.x >= 0) flamean un poco más en la punta
	if (UV.x >= 0.0) {
		VERTEX.y += sin(TIME * 3.0 + ph + UV.y * 4.0) * UV.y * 0.15 * wind;
	}
}

void fragment() {
	vec4 c = UV.x < 0.0 ? vec4(1.0) : texture(frond, UV);
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ROUGHNESS = 0.8;
}
