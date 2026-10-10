// Bandada: cada instancia gira en círculo alrededor de su punto (INSTANCE_CUSTOM: radio, fase,
// velocidad, altura extra) y aletea. Todo en el vértice: cero costo de CPU.
shader_type spatial;
render_mode cull_disabled;

void vertex() {
	vec4 cu = INSTANCE_CUSTOM;
	float t = TIME * (0.25 + cu.z * 0.3) + cu.y * 6.2831;
	float r = 10.0 + cu.x * 30.0;
	vec3 p = VERTEX;
	// aleteo: las puntas de las alas suben y bajan
	float flap = sin(TIME * (7.0 + cu.z * 4.0) + cu.y * 20.0);
	p.y += abs(p.x) * flap * 0.9;
	// orientación tangente al círculo
	float a = t + 1.5708;
	mat2 rot = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
	p.xz = rot * p.xz;
	p += vec3(cos(t) * r, sin(t * 0.7) * 2.0 + cu.w * 10.0, sin(t) * r);
	VERTEX = p;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.8;
}
