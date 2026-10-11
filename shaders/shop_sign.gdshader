// Letreros de comercio: una celda del atlas (2x8) por instancia (INSTANCE_CUSTOM.x = índice).
shader_type spatial;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;

varying float idx;

void vertex() {
	idx = INSTANCE_CUSTOM.x;
}

void fragment() {
	float i = floor(idx + 0.5);
	vec2 cell = vec2(mod(i, 2.0), floor(i / 2.0));
	vec2 uv = (cell + UV) / vec2(2.0, 8.0);
	vec3 c = texture(atlas, uv).rgb;
	// sol y polvo: un poco desteñido y con mugre abajo
	c = mix(c, c * vec3(0.8, 0.76, 0.7), (1.0 - UV.y) * 0.25);
	ALBEDO = c;
	ROUGHNESS = 0.55;
}
