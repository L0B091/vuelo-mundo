// Rayos de luz submarinos (god rays aparentes) en pantalla: haces oblicuos que ondulan, más
// intensos arriba (hacia la superficie) y que se apagan con la profundidad. Una pasada 2D.
shader_type canvas_item;

uniform float intensity = 0.0;
uniform float depth = 0.0;
uniform float tilt = 0.25;

float h(float x) {
	return fract(sin(x * 91.7) * 43758.5);
}

void fragment() {
	vec2 uv = UV;
	float x = uv.x + uv.y * tilt;
	float r = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float c = h(fi + 1.0) + 0.04 * sin(TIME * (0.3 + 0.2 * fi) + fi);
		float w = 0.015 + 0.03 * h(fi + 7.0);
		r += smoothstep(w, 0.0, abs(fract(x * 1.3 + c) - 0.5)) * (0.5 + 0.5 * h(fi + 3.0));
	}
	float top = 1.0 - smoothstep(0.0, 0.85, uv.y);
	float a = r * top * intensity * (1.0 - smoothstep(4.0, 30.0, depth)) * 0.35;
	COLOR = vec4(0.75, 0.95, 1.0, a);
}
