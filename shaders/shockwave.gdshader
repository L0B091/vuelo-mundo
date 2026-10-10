// Onda expansiva / marca de impacto: anillo en el suelo que crece y se desvanece.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float progress = 0.0;   // 0..1
uniform float strength = 1.0;
uniform vec4 tint : source_color = vec4(0.95, 0.92, 0.85, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring_r = mix(0.05, 0.95, sqrt(progress));
	float w = mix(0.05, 0.18, progress);
	float ring = 1.0 - smoothstep(0.0, w, abs(r - ring_r));
	float dust = (1.0 - smoothstep(0.0, ring_r, r)) * 0.35;
	float a = (ring + dust) * (1.0 - progress) * strength;
	ALBEDO = tint.rgb;
	ALPHA = clamp(a, 0.0, 1.0) * step(r, 1.0);
}
