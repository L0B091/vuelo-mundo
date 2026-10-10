// Líneas de velocidad + distorsión radial en pantalla (barato: un solo pase 2D).
shader_type canvas_item;

uniform float intensity = 0.0;  // 0..1
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform bool distort = true;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	float r = length(c * vec2(1.6, 1.0));
	float a = atan(c.y, c.x);
	float id = floor(a * 70.0 / 6.2831);
	float flick = step(0.55, hash(id + floor(TIME * 18.0)));
	float line = (1.0 - smoothstep(0.0, 0.09, abs(fract(a * 70.0 / 6.2831) - 0.5))) * flick;
	float edge = smoothstep(0.25, 0.75, r);
	float lines = line * edge * intensity;
	vec3 col = vec3(0.0);
	if (distort) {
		vec2 uv = SCREEN_UV - c * 0.035 * intensity * edge * (0.6 + 0.4 * sin(TIME * 40.0 + r * 30.0));
		col = textureLod(screen_tex, uv, 0.0).rgb;
		COLOR = vec4(mix(col, vec3(1.0), lines * 0.55), 1.0);
	} else {
		COLOR = vec4(1.0, 1.0, 1.0, lines * 0.5);
	}
}
