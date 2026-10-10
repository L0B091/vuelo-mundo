// Cielo HDRI (Poly Haven, CC0) arriba del horizonte; abajo, el color de la bruma (más allá
// del plano lejano se ve el "suelo" del cielo y tiene que coincidir con la niebla).
shader_type sky;

uniform sampler2D panorama : source_color, filter_linear, hint_default_black;
uniform vec3 below_color : source_color = vec3(0.68, 0.79, 0.88);
uniform float exposure = 1.0;
uniform float yaw = 0.0;

void sky() {
	vec3 d = EYEDIR;
	float a = atan(d.x, -d.z) + yaw;
	vec2 uv = vec2(a / (2.0 * PI) + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
	vec3 c = texture(panorama, uv).rgb * exposure;
	float t = smoothstep(-0.02, 0.06, d.y);
	COLOR = mix(below_color, c, t);
}
