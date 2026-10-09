// Terreno del conector y del detalle regional.
// Color por altura real (UV2.x, metros), máscara de tierra (UV2.y), pendiente y latitud.
// Bajo el agua: fondo marino (arena de coral clara en lo bajo, oscuro en lo profundo).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

instance uniform float abs_lat = 10.0;

varying float h_real;
varying float land;
varying vec3 n_world;

vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

void vertex() {
	h_real = UV2.x;
	land = UV2.y;
	n_world = NORMAL;
}

vec3 land_color(float h, float slope, float lat) {
	float tropic = 1.0 - smoothstep(18.0, 35.0, lat);
	float boreal = smoothstep(45.0, 62.0, lat);
	vec3 sand = srgb(vec3(0.86, 0.80, 0.62));
	vec3 green = mix(srgb(vec3(0.33, 0.45, 0.22)), srgb(vec3(0.16, 0.42, 0.15)), tropic);
	green = mix(green, srgb(vec3(0.24, 0.32, 0.20)), boreal);
	vec3 dry = srgb(vec3(0.55, 0.47, 0.33));
	vec3 rock = srgb(vec3(0.45, 0.42, 0.40));
	vec3 snow = srgb(vec3(0.95, 0.96, 0.98));
	vec3 c = mix(sand, green, smoothstep(1.2, 2.6, h));
	c = mix(c, dry, smoothstep(600.0, 2200.0, h));
	c = mix(c, rock, smoothstep(0.35, 0.7, slope));
	float snowline = mix(5200.0, 0.0, smoothstep(25.0, 72.0, lat));
	c = mix(c, snow, smoothstep(snowline - 300.0, snowline + 300.0, h));
	return c;
}

vec3 seabed_color(float depth) {
	vec3 coral_sand = srgb(vec3(0.85, 0.82, 0.70));
	vec3 mid = srgb(vec3(0.45, 0.52, 0.50));
	vec3 deep = srgb(vec3(0.10, 0.14, 0.20));
	vec3 c = mix(coral_sand, mid, smoothstep(0.5, 20.0, depth));
	return mix(c, deep, smoothstep(40.0, 1500.0, depth));
}

void fragment() {
	float slope = 1.0 - clamp(normalize(n_world).y, 0.0, 1.0);
	float is_land = max(step(0.5, land), step(0.5, h_real));
	vec3 c = mix(seabed_color(max(-h_real, 0.0)), land_color(h_real, slope, abs_lat), is_land);
	ALBEDO = c;
	ROUGHNESS = mix(0.85, 0.95, is_land);
	SPECULAR = 0.2;
}
