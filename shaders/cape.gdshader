// Capa: ondea con el viento relativo (sin simulación de tela: barato para móvil).
shader_type spatial;
render_mode cull_disabled;

uniform vec4 color : source_color = vec4(0.75, 0.08, 0.1, 1.0);
uniform float wind = 0.0;

void vertex() {
	float t = 1.0 - UV.y; // 0 arriba (hombros), 1 abajo
	VERTEX.x *= mix(0.65, 1.15, t);
	float s = sin(TIME * (4.0 + wind * 14.0) + UV.y * 9.0 + UV.x * 2.0);
	// con viento la capa se levanta hacia atrás (+Z local = espalda)
	VERTEX.z -= t * t * 0.12 * (1.0 - 0.6 * wind);
	VERTEX.z += s * 0.05 * t * (0.3 + wind);
}

void fragment() {
	ALBEDO = color.rgb * (0.85 + 0.15 * UV.y);
	ROUGHNESS = 0.7;
	SPECULAR = 0.3;
}
