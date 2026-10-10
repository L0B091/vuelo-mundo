// Barcos fondeados: cabeceo y balanceo suaves por instancia (en el vértice).
shader_type spatial;

void vertex() {
	float ph = float(INSTANCE_ID) * 1.7;
	float roll = sin(TIME * 0.9 + ph) * 0.05;
	float pitch = sin(TIME * 0.7 + ph * 1.3) * 0.025;
	vec3 p = VERTEX;
	p.y += sin(TIME * 1.1 + ph) * 0.08;
	p.y += p.x * roll + p.z * pitch;
	VERTEX = p;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.5;
}
