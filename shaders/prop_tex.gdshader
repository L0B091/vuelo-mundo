// Props texturizados (modelos Meshy): textura propia + variación por instancia.
// recolor: tiñe la ropa con el color de instancia y respeta la piel (detección por tono).
// bob: balanceo en el agua (botes).
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform bool recolor = false;
uniform bool bob = false;
uniform float roughness = 0.75;

varying vec3 tint;

void vertex() {
	tint = COLOR.rgb;
	if (bob) {
		float ph = float(INSTANCE_ID) * 1.7;
		VERTEX.y += sin(TIME * 1.1 + ph) * 0.08 + VERTEX.x * sin(TIME * 0.9 + ph) * 0.03
			+ VERTEX.z * sin(TIME * 0.7 + ph * 1.3) * 0.012;
	}
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	if (recolor) {
		// piel: rojo > verde > azul con saturación media; el resto (ropa) se tiñe
		float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
		float skin = step(c.b, c.g) * step(c.g, c.r) * smoothstep(0.08, 0.18, sat) * (1.0 - smoothstep(0.45, 0.6, sat))
			* smoothstep(0.03, 0.08, c.r - c.g);
		float lum = dot(c, vec3(0.299, 0.587, 0.114));
		vec3 cloth = tint * (0.35 + 1.1 * lum);
		c = mix(c, cloth, (1.0 - skin) * 0.75 * step(0.001, distance(tint, vec3(1.0))));
	}
	ALBEDO = c;
	ROUGHNESS = roughness;
}
