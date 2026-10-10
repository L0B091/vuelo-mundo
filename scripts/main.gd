extends Node3D
## Escena principal: mundo global, streaming, avatar y HUD.
##
## Argumentos opcionales (después de `--`):
##   --start=lat,lon,alt,rumbo   posición inicial (por defecto: aproximación a Malé, Maldivas)
##   --speed=m/s                 velocidad inicial
##   --screenshot=ruta.png       guarda una captura cuando el streaming termina y sale
##   --pitch=grados             inclinación inicial de la mirada (negativo = abajo)
##   --profile=low|medium|high|ultra  fuerza un perfil sin guardarlo
##   --hide-hud                  oculta el HUD (capturas limpias)
##   --autotest                  recorrido automático de prueba (ver scripts/tools/autotest.gd)
##   --quit-after=segundos       sale después de N segundos

const ZONE_INDEX := "res://data/zone_index.json"
const DEFAULT_START := [4.02, 73.36, 1400.0, 40.0]
const FOG_COLOR := Color(0.66, 0.78, 0.90)

var world: WorldRoot
var tiles: TileStreamer
var zones: ZoneStreamer
var index: ZoneIndex
var avatar: Avatar
var hud: Hud
var env: Environment
var sun: DirectionalLight3D
var args: Dictionary = {}
var frame_ms_max: float = 0.0
## Cuadros de más de 50 ms (para investigar tirones).
var spikes: Array = []
## Peor cuadro en el que hubo un cambio tosco<->detalle (lo mide la prueba automática).
var swap_frame_ms_max: float = 0.0
var _prev_tiles_ms: float = 0.0
var _prev_zones_ms: float = 0.0
var _prev_swapped: bool = false

var _idle_frames: int = 0
var _elapsed: float = 0.0


static func parse_args(list: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for a in list:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


func _ready() -> void:
	args = parse_args(OS.get_cmdline_user_args())
	if args.has("profile"):
		Quality.force_profile(str(args.profile))
	_build_environment()
	world = WorldRoot.new()
	world.name = "World"
	add_child(world)

	var st: Array = DEFAULT_START.duplicate()
	if args.has("start"):
		var parts: PackedStringArray = str(args.start).split(",")
		for i in mini(parts.size(), 4):
			st[i] = float(parts[i])
	var gp := GlobalPos.from_lonlat(float(st[1]), float(st[0]), float(st[2]))
	world.set_origin(gp.e, gp.n)

	avatar = Avatar.new()
	avatar.name = "Avatar"
	avatar.world = world
	world.add_child(avatar)
	avatar.position = Vector3(0.0, float(st[2]) * Geo.scale_k(gp.n), 0.0)
	avatar.heading_deg = float(st[3])
	avatar.speed = float(args.get("speed", "90"))
	if args.has("pitch"):
		avatar.look_pitch = float(args.pitch)

	tiles = TileStreamer.new()
	tiles.name = "TileStreamer"
	add_child(tiles)
	tiles.setup(world)

	index = ZoneIndex.load_from(ZONE_INDEX)
	for e in index.validate():
		push_error("Índice de zonas: " + e)
	zones = ZoneStreamer.new()
	zones.name = "ZoneStreamer"
	add_child(zones)
	zones.setup(world, index)

	hud = Hud.new()
	hud.avatar = avatar
	hud.main = self
	add_child(hud)
	hud.visible = not args.has("hide-hud")
	avatar.message.connect(hud.show_message)
	zones.zone_entered.connect(
		func(id: String) -> void:
			if id != "":
				hud.show_message("Entrando a " + index.get_zone(id).name)
	)

	Quality.apply_to(get_viewport(), env, sun, avatar.camera)
	Quality.profile_changed.connect(func(_n: String) -> void: Quality.apply_to(get_viewport(), env, sun, avatar.camera))

	if args.has("autotest"):
		var at: Node = load("res://scripts/tools/autotest.gd").new()
		at.set("main", self)
		add_child(at)
	print("Vuelo Mundo: inicio en %s, perfil %s (%s)" % [gp, Quality.current_name, Quality.detected_by])


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.20, 0.45, 0.85)
	psm.sky_horizon_color = Color(0.70, 0.82, 0.92)
	# más allá del plano lejano se ve el "suelo" del cielo: que sea igual a la bruma
	psm.ground_horizon_color = FOG_COLOR
	psm.ground_bottom_color = FOG_COLOR
	psm.ground_curve = 0.02
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = FOG_COLOR
	env.fog_density = 1.0
	env.fog_sky_affect = 0.0
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	sun.light_energy = 1.0
	sun.directional_shadow_max_distance = 300.0
	add_child(sun)


func _process(dt: float) -> void:
	_elapsed += dt
	var real_ms: float = dt * 1000.0 / maxf(Engine.time_scale, 0.001)  # delta viene escalado
	frame_ms_max = maxf(frame_ms_max, real_ms) if _elapsed > 3.0 else 0.0
	world.maybe_shift(avatar)
	var gp := avatar.global_pos()
	var k := Geo.scale_k(gp.n)
	var hv := avatar.heading_vec()
	var spd := avatar.speed * k
	_update_fog()
	var t0 := Time.get_ticks_usec()
	tiles.update(gp, hv, spd)
	var t1 := Time.get_ticks_usec()
	zones.update(gp, hv, spd)
	var t2 := Time.get_ticks_usec()
	# el dt de este cuadro mide el trabajo del cuadro anterior
	if _prev_swapped and _elapsed > 3.0:
		swap_frame_ms_max = maxf(swap_frame_ms_max, real_ms)
	if _elapsed > 3.0 and real_ms > 50.0:
		spikes.append(
			{
				"t": snappedf(_elapsed, 0.01),
				"ms": snappedf(real_ms, 0.1),
				"prev_tiles_ms": snappedf(_prev_tiles_ms, 0.1),
				"prev_zones_ms": snappedf(_prev_zones_ms, 0.1),
				"time_scale": Engine.time_scale,
				"swap": _prev_swapped
			}
		)
	_prev_tiles_ms = (t1 - t0) / 1000.0
	_prev_zones_ms = (t2 - t1) / 1000.0
	_prev_swapped = bool(tiles.stats.swapped_this_frame)
	if OS.is_debug_build() and (t2 - t0) > 25000:
		print(
			(
				"[perf] cuadro lento: teselas %.1f ms, zonas %.1f ms, dt %.1f ms"
				% [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, real_ms]
			)
		)
	_handle_cli(dt)


## La niebla se aleja con la altitud (desde arriba se ve más lejos); la base sale del perfil.
func _update_fog() -> void:
	var base: float = float(Quality.current.get("fog_end_m", 90000.0))
	var end: float = base * clampf(1.0 + avatar.agl / 2500.0, 1.0, 4.0)
	env.fog_depth_end = end
	env.fog_depth_begin = end * 0.2
	avatar.camera.far = end * 1.1


func _handle_cli(_dt: float) -> void:
	if args.has("quit-after") and _elapsed > float(args["quit-after"]):
		print(telemetry())
		get_tree().quit()
	if args.has("screenshot"):
		_idle_frames = _idle_frames + 1 if tiles.is_idle() and _elapsed > 1.0 else 0
		if _idle_frames == 90:
			var img := get_viewport().get_texture().get_image()
			var path := str(args.screenshot)
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			img.save_png(path)
			print("captura guardada: ", path)
			print(telemetry())
			get_tree().quit()


func telemetry() -> String:
	var gp := avatar.global_pos()
	var site: ZoneInfo = index.zone_at(gp.e, gp.n, "site")
	var country: ZoneInfo = index.zone_at(gp.e, gp.n, "country")
	var zname := site.name if site else (country.name if country else "—")
	var state_names := ["Vuelo", "Aterrizando", "Caminando"]
	return (
		(
			"%s | %s\nLat %.4f  Lon %.4f  Alt %.0f m  AGL %.0f m\nVel %.0f km/h  Rumbo %03.0f°%s\n"
			+ "Perfil %s  FPS %d\nTeselas %d vivas, %d pendientes, huecos %d | Zonas %s, tardías %d | orígenes %d"
		)
		% [
			state_names[avatar.state],
			zname,
			gp.lat(),
			gp.lon(),
			gp.up / Geo.scale_k(gp.n),
			avatar.agl,
			avatar.speed * 3.6,
			avatar.heading_deg,
			"  TURBO" if avatar.boost else "",
			Quality.label(),
			Engine.get_frames_per_second(),
			tiles.stats.live,
			tiles.stats.pending,
			tiles.stats.holes,
			",".join(zones.live_ids()) if zones.live_ids().size() > 0 else "—",
			zones.stats.late_crossings,
			world.shift_count
		]
	)
