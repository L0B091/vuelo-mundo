class_name TimeOfDay
extends Node
## Hora del día y clima. Mueve el sol (elevación/azimut aproximados para latitud tropical),
## tiñe cielo, niebla y luz ambiente, y maneja nubes y lluvia. Barato: unas pocas uniformes
## por cuadro; la lluvia es un emisor alrededor de la cámara cuyo tamaño depende del perfil.
##   --hour=17.5   --day-minutes=24 (ciclo completo; 0 = hora fija)   --weather=clear|cloudy|rain

const WEATHER := {
	"clear": {"cover": 0.22, "fog": 1.0, "light": 1.0, "rain": 0.0},
	"cloudy": {"cover": 0.62, "fog": 1.6, "light": 0.7, "rain": 0.0},
	"rain": {"cover": 0.9, "fog": 3.2, "light": 0.45, "rain": 1.0},
}
const RAIN_BY_PROFILE := {"low": 0, "medium": 300, "high": 900, "ultra": 1600}

var hour: float = 10.5
var day_minutes: float = 0.0
var weather: String = "clear"
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var camera: Camera3D
var fog_base: Color
## Multiplicador de la distancia de niebla (lluvia/nublado la acercan).
var fog_scale: float = 1.0
var _rain: CPUParticles3D
var _t: float = 0.0
var _mix := {"cover": 0.22, "fog": 1.0, "light": 1.0, "rain": 0.0}


func setup(p_sun: DirectionalLight3D, p_env: Environment, p_sky: ShaderMaterial, p_cam: Camera3D, fog: Color) -> void:
	sun = p_sun
	env = p_env
	sky_mat = p_sky
	camera = p_cam
	fog_base = fog
	_mix = (WEATHER[weather] as Dictionary).duplicate()
	apply()


## Elevación del sol en grados (≈ 4°N: casi cenital al mediodía, sale ~6 h, se pone ~18 h).
static func sun_elevation(h: float) -> float:
	return sin((h - 6.0) / 12.0 * PI) * 78.0


func set_weather(w: String) -> void:
	if WEATHER.has(w):
		weather = w


func _process(dt: float) -> void:
	_t += dt
	if day_minutes > 0.0:
		hour = fposmod(hour + dt * 24.0 / (day_minutes * 60.0), 24.0)
	var target: Dictionary = WEATHER[weather]
	for k: String in _mix:
		_mix[k] = lerpf(_mix[k], target[k], clampf(dt * 0.3, 0.0, 1.0))
	apply()


func apply() -> void:
	if sun == null:
		return
	var elev := sun_elevation(hour)
	var az := lerpf(100.0, 260.0, clampf((hour - 6.0) / 12.0, 0.0, 1.0))  # este → oeste
	sun.rotation_degrees = Vector3(-maxf(elev, -5.0), 180.0 - az, 0.0)
	var low := 1.0 - smoothstep(4.0, 30.0, elev)  # amanecer/atardecer
	var night := 1.0 - smoothstep(-6.0, 3.0, elev)
	var warm := Color(1.0, 0.62, 0.38).lerp(Color(1.0, 0.97, 0.92), 1.0 - low)
	var lightf: float = _mix["light"]
	sun.light_color = warm
	sun.light_energy = (1.0 - night) * lerpf(1.0, 0.55, low) * lightf
	sun.visible = night < 0.98
	var tint := Color(1, 1, 1).lerp(Color(1.0, 0.72, 0.55), low * 0.8) * lerpf(1.0, 0.75, 1.0 - lightf)
	env.ambient_light_energy = lerpf(0.8, 0.12, night) * lerpf(1.0, 0.8, low)
	var fogc := Color(fog_base.r * tint.r, fog_base.g * tint.g, fog_base.b * tint.b).lerp(
		Color(0.02, 0.03, 0.06), night
	)
	fogc = fogc.lerp(Color(0.55, 0.58, 0.62), (1.0 - lightf) * 0.6)
	env.fog_light_color = fogc
	fog_scale = 1.0 / float(_mix["fog"])  # main acorta la niebla de profundidad con esto
	if sky_mat != null:
		sky_mat.set_shader_parameter(&"sky_tint", Vector3(tint.r, tint.g, tint.b))
		sky_mat.set_shader_parameter(&"night", night)
		sky_mat.set_shader_parameter(&"below_color", Vector3(fogc.r, fogc.g, fogc.b))
		sky_mat.set_shader_parameter(&"cloud_cover", _mix["cover"])
		sky_mat.set_shader_parameter(&"cloud_time", _t)
		var cl := warm.lerp(Color(1, 1, 1), 0.5) * lerpf(1.0, 0.25, night)
		sky_mat.set_shader_parameter(&"cloud_light", Vector3(cl.r, cl.g, cl.b))
		var oct := {"low": 2, "medium": 3, "high": 4, "ultra": 5}.get(str(Quality.current_name), 3) as int
		sky_mat.set_shader_parameter(&"cloud_octaves", oct)
	_update_rain()


func _update_rain() -> void:
	var amount := RAIN_BY_PROFILE.get(str(Quality.current_name), 300) as int
	var on: bool = _mix["rain"] > 0.3 and amount > 0 and camera != null
	if not on:
		if _rain != null:
			_rain.emitting = false
		return
	if _rain == null:
		_rain = CPUParticles3D.new()
		_rain.amount = amount
		_rain.lifetime = 0.8
		_rain.local_coords = false
		_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_rain.emission_box_extents = Vector3(25, 2, 25)
		_rain.direction = Vector3(0.1, -1, 0)
		_rain.spread = 3.0
		_rain.initial_velocity_min = 22.0
		_rain.initial_velocity_max = 28.0
		_rain.gravity = Vector3(0, -9.8, 0)
		var q := QuadMesh.new()
		q.size = Vector2(0.02, 0.6)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.8, 0.85, 0.95, 0.35)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		q.material = m
		_rain.mesh = q
		camera.get_tree().current_scene.add_child(_rain)
	_rain.emitting = true
	_rain.global_position = camera.global_position + Vector3(0, 12, 0) - camera.global_transform.basis.z * 10.0
