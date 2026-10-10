// Corales/anémonas: color por instancia, rugosidad alta; las anémonas (sway > 0) ondean con
// la corriente según la altura del vértice. Coordenadas por instancia para desfasar.
shader_type spatial;
render_mode cull_disabled;

uniform float sway = 0.0;

void vertex() {
	if (sway > 0.0) {
		float ph = MODEL_MATRIX[3].x * 0.7 + MODEL_MATRIX[3].z * 0.3;
		float h = max(VERTEX.y - 0.05, 0.0);
		VERTEX.x += sin(TIME * 1.6 + ph + VERTEX.z * 8.0) * sway * h;
		VERTEX.z += cos(TIME * 1.3 + ph + VERTEX.x * 8.0) * sway * h;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
}
