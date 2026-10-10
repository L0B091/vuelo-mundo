// Marca de impacto del aterrizaje pesado (grietas radiales procedurales que se desvanecen).
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never;

uniform float fade = 1.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float k = floor((a + PI) / (2.0 * PI) * 23.0);
	float crack = 1.0 - smoothstep(0.0, 0.035, abs(fract((a + PI) / (2.0 * PI) * 23.0) - 0.5 - (hash(k) - 0.5) * 0.4 * r));
	crack *= step(r, 0.35 + 0.6 * hash(k + 7.0));
	float center = 1.0 - smoothstep(0.0, 0.32, r);
	float m = max(crack * 0.8, center * 0.75) * (1.0 - smoothstep(0.7, 1.0, r));
	ALBEDO = vec3(0.08, 0.07, 0.06);
	ALPHA = m * fade;
	ROUGHNESS = 1.0;
}
