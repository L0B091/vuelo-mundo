extends Node
## Perfiles gráficos (autoload "Quality").
##
## Detecta el equipo con OS.get_model_name(), RenderingServer.get_video_adapter_name() y la
## memoria; busca en data/device_profiles.json. Si no hay coincidencia, la pantalla de inicio
## corre una prueba corta de rendimiento. El jugador puede forzar otro perfil.
## Los perfiles cambian niebla, resolución de texturas/mallas, sombras, escala de render y
## radio de carga, pero NUNCA las reglas de StreamMath (vecino precargado antes del cruce).

signal profile_changed(name: String)

const ORDER: Array[String] = ["low", "medium", "high", "ultra"]
const LABELS: Dictionary = {"low": "Bajo", "medium": "Medio", "high": "Alto", "ultra": "Ultra"}
const PROFILES: Dictionary = {
	"low":
	{
		"fog_end_m": 45000.0,
		"render_scale": 0.75,
		"shadows": true,
		"shadow_size": 1024,
		"msaa": 0,
		"detail_mesh_step": 8,
		"water_tex_div": 4,
		"coarse_radius": 1,
		"detail_radius_m": 80000.0,
		"max_finalize_per_frame": 2,
		"npc_pedestrians": 10,
		"npc_riders": 4,
		"max_inflight": 2,
		"finalize_budget_usec": 3000,
		"collision_budget_usec": 2500
	},
	"medium":
	{
		"fog_end_m": 90000.0,
		"render_scale": 0.85,
		"shadows": true,
		"shadow_size": 2048,
		"msaa": 1,
		"detail_mesh_step": 4,
		"water_tex_div": 2,
		"coarse_radius": 1,
		"detail_radius_m": 140000.0,
		"max_finalize_per_frame": 3,
		"npc_pedestrians": 20,
		"npc_riders": 8,
		"max_inflight": 3,
		"finalize_budget_usec": 3000,
		"collision_budget_usec": 2500
	},
	"high":
	{
		"fog_end_m": 160000.0,
		"render_scale": 1.0,
		"shadows": true,
		"shadow_size": 2048,
		"msaa": 1,
		"detail_mesh_step": 2,  # 4.8 m: el atolón es casi plano y los micro-mapas cubren el detalle
		"water_tex_div": 1,
		"coarse_radius": 2,
		"detail_radius_m": 220000.0,
		"max_finalize_per_frame": 4,
		"npc_pedestrians": 40,
		"npc_riders": 16,
		"max_inflight": 4,
		"finalize_budget_usec": 3000,
		"collision_budget_usec": 2500
	},
	"ultra":
	{
		"fog_end_m": 260000.0,
		"render_scale": 1.0,
		"shadows": true,
		"shadow_size": 4096,
		"msaa": 2,
		"detail_mesh_step": 1,
		"water_tex_div": 1,
		"coarse_radius": 2,
		"detail_radius_m": 320000.0,
		"max_finalize_per_frame": 6,
		"npc_pedestrians": 60,
		"npc_riders": 24,
		"max_inflight": 4,
		"finalize_budget_usec": 3000,
		"collision_budget_usec": 2500
	},
}
const SETTINGS_PATH := "user://settings.cfg"

var current_name: String = "medium"
var current: Dictionary = PROFILES["medium"]
var detected_name: String = "medium"
var detected_by: String = "default"  # "table" | "benchmark" | "default"
var override_name: String = ""  # "" = automático
var device: Dictionary = {}


func _ready() -> void:
	detect()
	_load_settings()
	_apply_choice()


func detect() -> void:
	var mem: Dictionary = OS.get_memory_info()
	var phys: int = int(mem.get("physical", -1))
	device = {
		"model": OS.get_model_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"os": OS.get_name(),
		"ram_gb": float(phys) / 1073741824.0 if phys > 0 else -1.0,
	}
	var res := match_table(device, _load_table())
	if res != "":
		detected_name = res
		detected_by = "table"
	else:
		detected_name = "medium"
		detected_by = "default"
	detected_name = cap_by_ram(detected_name, float(device.ram_gb), _load_table())


func needs_benchmark() -> bool:
	return detected_by == "default" and override_name == ""


func _load_table() -> Dictionary:
	var f := FileAccess.open("res://data/device_profiles.json", FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## Primera regla que coincide con el modelo o la GPU; "" si ninguna.
static func match_table(dev: Dictionary, table: Dictionary) -> String:
	for rule: Dictionary in table.get("rules", []):
		var field := "gpu" if rule.has("gpu") else "model"
		var re := RegEx.new()
		if re.compile("(?i)" + str(rule[field])) != OK:
			continue
		if re.search(str(dev.get(field, ""))) != null:
			return str(rule.profile)
	return ""


static func cap_by_ram(profile: String, ram_gb: float, table: Dictionary) -> String:
	if ram_gb <= 0.0:
		return profile
	for cap: Dictionary in table.get("ram_caps", []):
		if ram_gb <= float(cap.max_gb):
			var cap_name := str(cap.profile)
			if ORDER.find(profile) > ORDER.find(cap_name):
				return cap_name
			return profile
	return profile


## Resultado de la prueba de rendimiento (cuadros por segundo sin vsync).
func set_benchmark_result(avg_fps: float) -> void:
	var p := "low"
	if avg_fps >= 110.0:
		p = "ultra"
	elif avg_fps >= 70.0:
		p = "high"
	elif avg_fps >= 40.0:
		p = "medium"
	detected_name = cap_by_ram(p, float(device.get("ram_gb", -1.0)), _load_table())
	detected_by = "benchmark"
	_save_settings()
	_apply_choice()


func set_override(name: String) -> void:
	override_name = name if PROFILES.has(name) else ""
	_save_settings()
	_apply_choice()


## Fuerza un perfil para esta sesión sin guardarlo (capturas y pruebas).
func force_profile(name: String) -> void:
	if PROFILES.has(name):
		current_name = name
		current = PROFILES[name]
		profile_changed.emit(name)


func _apply_choice() -> void:
	current_name = override_name if override_name != "" else detected_name
	current = PROFILES[current_name]
	profile_changed.emit(current_name)


func label() -> String:
	return LABELS.get(current_name, current_name)


## Aplica el perfil a la ventana, entorno, sol y cámara.
func apply_to(viewport: Viewport, env: Environment, sun: DirectionalLight3D, cam: Camera3D) -> void:
	var p := current
	var wd := {"low": 0, "medium": 3, "high": 8, "ultra": 12}.get(current_name, 3) as int
	RenderingServer.global_shader_parameter_set(&"water_detail", wd)
	RenderingServer.global_shader_parameter_set(&"caustics_strength", 0.0 if current_name == "low" else 1.0)
	viewport.scaling_3d_scale = float(p.render_scale)
	# FSR 1 al escalar (más nítido que bilineal); FXAA donde no hay MSAA
	viewport.scaling_3d_mode = (
		Viewport.SCALING_3D_MODE_FSR if float(p.render_scale) < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	)
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if int(p.msaa) == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][int(p.msaa)]
	RenderingServer.directional_shadow_atlas_set_size(int(p.shadow_size), true)
	if sun:
		sun.shadow_enabled = bool(p.shadows)
	if sun:
		sun.directional_shadow_max_distance = {"low": 90.0, "medium": 200.0}.get(current_name, 350.0)
		sun.shadow_blur = 1.5
	if env:
		# imagen: ACES, brillo suave (glow sí existe en Mobile), algo de saturación/contraste.
		# Mobile no tiene SSAO/SSIL/SSR: la oclusión viene de las texturas AO/ORM.
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.05
		env.tonemap_white = 6.0
		env.glow_enabled = current_name != "low"
		env.glow_intensity = 0.35
		env.glow_bloom = 0.03
		env.glow_hdr_threshold = 1.1
		env.adjustment_enabled = true
		env.adjustment_saturation = 1.12
		env.adjustment_contrast = 1.06
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = float(p.fog_end_m) * 0.15
		env.fog_depth_end = float(p.fog_end_m)
	if cam:
		cam.far = float(p.fog_end_m) * 1.1


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	override_name = str(cfg.get_value("graphics", "override", ""))
	if not PROFILES.has(override_name):
		override_name = ""
	var bench := str(cfg.get_value("graphics", "benchmark_profile", ""))
	var bench_model := str(cfg.get_value("graphics", "benchmark_model", ""))
	if detected_by == "default" and PROFILES.has(bench) and bench_model == str(device.model):
		detected_name = bench
		detected_by = "benchmark"


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "override", override_name)
	if detected_by == "benchmark":
		cfg.set_value("graphics", "benchmark_profile", detected_name)
		cfg.set_value("graphics", "benchmark_model", str(device.get("model", "")))
	cfg.save(SETTINGS_PATH)
