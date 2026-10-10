extends Node3D
## Escena principal: mundo global, streaming, avatar y HUD.
##
## Argumentos opcionales (después de `--`):
##   --start=lat,lon,alt,rumbo   posición inicial (por defecto: aproximación a Malé, Maldivas)
##   --speed=m/s                 velocidad inicial
##   --screenshot=ruta.png       guarda una captura cuando el streaming termina y sale
##   --walk                     (con --screenshot) aterriza antes de capturar (vista de peatón)
##   --character=male|female    personaje (si no, el guardado en user://character.tres)
##   --third-person             cámara en tercera persona
##   --event=wait               (con --screenshot y --event-delay=s) espera antes de capturar
##   --event=takeoff|impact     (con --screenshot) captura el despegue o el impacto del aterrizaje
##   --event=trick:<nombre>     acrobacia (roll_left, loop, flip, spin, dodge_left...)
##   --event=boom               cruza la barrera del sonido
##   --event-delay=s            segundos después del evento (0.2)
##   --pitch=grados             inclinación inicial de la mirada (negativo = abajo)
##   --profile=low|medium|high|ultra  fuerza un perfil sin guardarlo
##   --hide-hud                  oculta el HUD (capturas limpias)
##   --hour=H --day-minutes=M --weather=clear|cloudy|rain   hora del día y clima
##   --autotest                  recorrido automático de prueba (ver scripts/tools/autotest.gd)
##   --quit-after=segundos       sale después de N segundos

const ZONE_INDEX := "res://data/zone_index.json"
const DEFAULT_START := [4.02, 73.36, 1400.0, 40.0]
const FOG_COLOR := Color(0.66, 0.78, 0.90)

var world: WorldRoot
var tiles: TileStreamer
var zones: ZoneStreamer
var crowd: NpcCrowd
var index: ZoneIndex
var avatar: Avatar
var hud: Hud
var env: Environment
var sun: DirectionalLight3D
var tod: TimeOfDay
var args: Dictionary = {}
var sealife: Node3D = null
var frame_ms_max: float = 0.0
## Cuadros de más de 50 ms (para investigar tirones).
var spikes: Array = []
## Peor cuadro en el que hubo un cambio tosco<->detalle (lo mide la prueba automática).
var swap_frame_ms_max: float = 0.0
var swap_cpu_ms_max: float = 0.0
var cpu_ms_max: float = 0.0
var _perf: PerfOverlay = null
var _prev_tiles_ms: float = 0.0
var _prev_zones_ms: float = 0.0
var _prev_swapped: bool = false

var _idle_frames: int = 0
var _event_t: float = -1.0
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
	var cdef := CharacterDef.load_or_default()
	if args.has("character"):
		cdef = CharacterDef.preset(str(args.character))
	avatar.set_character(cdef)
	if args.has("third-person"):
		avatar.toggle_camera()
	avatar.cam_orbit_deg = float(args.get("cam-orbit", "0"))

	tiles = TileStreamer.new()
	tiles.name = "TileStreamer"
	add_child(tiles)
	tiles.setup(world)

	index = ZoneIndex.load_from(ZONE_INDEX)
	for e in index.validate():
		push_error("Índice de zonas: " + e)
	for z: ZoneInfo in index.zones.values():
		if z.kind == "site":
			tiles.site_rects.append(Rect2(z.origin_e, z.origin_n - z.size_n, z.size_e, z.size_n))
	zones = ZoneStreamer.new()
	zones.name = "ZoneStreamer"
	add_child(zones)
	zones.setup(world, index)

	crowd = NpcCrowd.new()
	crowd.name = "NpcCrowd"
	add_child(crowd)
	crowd.setup(avatar, zones, Quality.current)

	hud = Hud.new()
	hud.avatar = avatar
	hud.main = self
	add_child(hud)
	hud.visible = not args.has("hide-hud")
	avatar.message.connect(hud.show_message)
	hud.perf_toggled.connect(_set_perf)
	if args.has("perf"):
		_set_perf(true)
	zones.zone_entered.connect(
		func(id: String) -> void:
			if id != "":
				hud.show_message("Entrando a " + index.get_zone(id).name)
	)

	Quality.apply_to(get_viewport(), env, sun, avatar.camera)
	tod = TimeOfDay.new()
	tod.name = "TimeOfDay"
	tod.hour = float(args.get("hour", "10.5"))
	tod.day_minutes = float(args.get("day-minutes", "0"))
	tod.set_weather(str(args.get("weather", "clear")))
	add_child(tod)
	tod.setup(sun, env, env.sky.sky_material as ShaderMaterial, avatar.camera, FOG_COLOR)
	var amb := AmbientAudio.new()
	amb.name = "AmbientAudio"
	add_child(amb)
	amb.setup(avatar, tod)
	var uwfx := UnderwaterFx.new()
	uwfx.name = "UnderwaterFx"
	add_child(uwfx)
	uwfx.setup(avatar, tod)
	var life := SeaLife.new()
	sealife = life
	life.name = "SeaLife"
	add_child(life)
	life.setup(world, avatar)
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
	# cielo HDRI CC0 (Poly Haven "Qwantani Noon (Pure Sky)"); bajo el horizonte = bruma
	var psm := ShaderMaterial.new()
	psm.shader = load("res://shaders/sky_hdri.gdshader")
	psm.set_shader_parameter(&"panorama", load("res://assets/hdri/qwantani_noon_puresky_2k.hdr"))
	psm.set_shader_parameter(&"below_color", FOG_COLOR)
	psm.set_shader_parameter(&"exposure", 0.9)
	sky.sky_material = psm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
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


## --dump-geo: triángulos de lo visible (dentro de rango) agrupados por tipo de nodo, para perfilar.
func _dump_geo() -> void:
	var cam := get_viewport().get_camera_3d().global_position
	var tot := {}
	for n: GeometryInstance3D in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		if not n.is_visible_in_tree():
			continue
		var r := n.visibility_range_end
		if r > 0.0 and (n.global_transform * n.get_aabb().get_center()).distance_to(cam) > r:
			continue
		var mesh: Mesh = null
		var mult := 1
		if n is MeshInstance3D:
			mesh = n.mesh
		elif n is MultiMeshInstance3D and n.multimesh != null:
			mesh = n.multimesh.mesh
			mult = (
				n.multimesh.visible_instance_count
				if n.multimesh.visible_instance_count >= 0
				else n.multimesh.instance_count
			)
		if mesh == null:
			continue
		var tris := 0
		for i in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(i)
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			tris += (idx.size() if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var key := "%s/%s" % [n.get_parent().name, str(n.name).get_slice("_", 0)]
		tot[key] = int(tot.get(key, 0)) + tris * mult
	var ks := tot.keys()
	ks.sort_custom(func(a: String, b: String) -> bool: return tot[a] > tot[b])
	for k: String in ks.slice(0, 20):
		print("GEO ", k, " ", tot[k])


## Medidor FPS/ms + registro CSV (pruebas en teléfono).
func _set_perf(on: bool) -> void:
	if on and _perf == null:
		_perf = PerfOverlay.new()
		_perf.context = func() -> String:
			var gp := avatar.global_pos()
			return "%s %s alt=%.0f" % [Quality.current_name, avatar.State.keys()[avatar.state], gp.up]
		add_child(_perf)
	elif not on and _perf != null:
		_perf.queue_free()
		_perf = null


## --hide=props,reef,sealife,water,npc: apaga sistemas para medir su coste por separado.
func _apply_hide() -> void:
	if not args.has("hide"):
		return
	var parts: Array = Array(str(args.hide).split(","))
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var nm := str(n.name)
		var off: bool = (
			(
				"props" in parts
				and n is MultiMeshInstance3D
				and n.has_meta(&"detail_kind")
				and not nm.begins_with("coral")
			)
			or ("reef" in parts and nm.begins_with("coral_"))
			or ("water" in parts and nm == "Agua")
			or ("palms" in parts and nm.begins_with("Palm"))
			or parts.any(func(x: String) -> bool: return x.begins_with("name:") and nm.begins_with(x.substr(5)))
		)
		if off:
			n.visible = false
	if "sealife" in parts and sealife != null:
		sealife.process_mode = Node.PROCESS_MODE_DISABLED
		sealife.visible = false
	if "npc" in parts:
		for n in get_tree().get_nodes_in_group(&"npc"):
			n.visible = false


func _process(dt: float) -> void:
	if args.has("hide") and Engine.get_process_frames() % 30 == 0:
		_apply_hide()
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
	avatar.set_inside_site(zones.inside_ready_site)
	var t2 := Time.get_ticks_usec()
	# el dt de este cuadro mide el trabajo del cuadro anterior
	# coste medido de nuestro streaming (teselas + zonas) en el cuadro anterior. TIME_PROCESS de
	# Godot no sirve: incluye la espera al render (con lavapipe superaba al propio cuadro).
	var cpu_ms := _prev_tiles_ms + _prev_zones_ms
	if _elapsed > 3.0:
		cpu_ms_max = maxf(cpu_ms_max, cpu_ms)
	if _prev_swapped and _elapsed > 3.0:
		swap_frame_ms_max = maxf(swap_frame_ms_max, real_ms)
		swap_cpu_ms_max = maxf(swap_cpu_ms_max, cpu_ms)
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
	if tod != null:
		end *= tod.fog_scale
		if tod.underwater:
			end = 60.0  # bajo el agua la visibilidad es de decenas de metros
	env.fog_depth_end = end
	env.fog_depth_begin = end * 0.2
	avatar.camera.far = end * 1.1


func _handle_cli(dt: float) -> void:
	if args.has("quit-after") and _elapsed > float(args["quit-after"]):
		print(telemetry())
		get_tree().quit()
	if args.has("screenshot"):
		var zones_idle := zones.pending_collisions() == 0
		var here := avatar.global_pos()
		var site_here: ZoneInfo = index.zone_at(here.e, here.n, "site")
		if site_here != null and site_here.available and not zones.is_ready(site_here.id):
			zones_idle = false
		for id: String in zones.live:
			if zones.live[id].state == "loading":
				zones_idle = false
		var ev := str(args.get("event", ""))
		if (
			(args.has("walk") or ev == "impact")
			and avatar.state == Avatar.State.FLY
			and zones_idle
			and _elapsed > 1.0
			and _event_t < 0.0
		):
			avatar.request_land()
			if ev == "impact":
				_event_t = 0.0
		if _event_t >= 0.0:
			# captura de un instante (despegue / impacto): se toma unos cuadros después del evento
			if ev == "impact" and avatar.state != Avatar.State.WALK:
				return
			_event_t += dt
			if _event_t >= float(args.get("event-delay", "0.2")):
				_save_shot()
			return
		_idle_frames = _idle_frames + 1 if tiles.is_idle() and zones_idle and _elapsed > 1.0 else 0
		if _idle_frames == 90:
			if ev == "takeoff":
				avatar.request_takeoff()
				_event_t = 0.0
				return
			if ev.begins_with("trick:"):
				avatar.trick(ev.substr(6))
				_event_t = 0.0
				return
			if ev == "wait":  # deja pasar --event-delay segundos (fauna que se acerca, etc.)
				_event_t = 0.0
				return
			if ev == "boom":
				avatar.boost = true
				avatar.speed = Avatar.SOUND_SPEED + 5.0
				_event_t = 0.0
				return
			_save_shot()


func _save_shot() -> void:
	if args.has("dump-geo"):
		_dump_geo()
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
