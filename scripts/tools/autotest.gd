extends Node
## Recorrido automático que verifica las reglas del primer entregable:
##  1. Vuelo largo y rápido entrando a la región de detalle (sin huecos en el terreno).
##  2. Aproximación y aterrizaje en el micro-mapa de prueba A (rayo al suelo caminable).
##  3. Caminata cruzando el borde A -> B (B en memoria antes del cruce, sin escalón).
##  4. Despegue y alejamiento (las zonas se descargan).
## Imprime un resumen JSON y sale con código 0 (PASS) o 1 (FAIL).

var main: Node
var phase: String = "init"
var t: float = 0.0
var total: float = 0.0
var target: GlobalPos
var report: Dictionary = {
	"phases": [],
	"max_step_y": 0.0,
	"walk_cross_ok": false,
	"landed": false,
	"took_off": false,
	"unloaded_after_leave": false
}
var _last_y: float = NAN
var _walk_start: GlobalPos
var _dbg_t: float = 0.0


func _ready() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var a: Avatar = main.avatar
	var za: ZoneInfo = main.index.get_zone("mv_test_male_oeste")
	target = za.landing
	a.message.connect(func(m: String) -> void: print("[avatar] ", m))
	# fase 1: arranca al oeste de la región de detalle, en turbo, rumbo este
	_set_phase("vuelo_largo")
	Engine.time_scale = 6.0
	a.boost = true
	a.speed = 1500.0
	a.heading_deg = 90.0


func _set_phase(p: String) -> void:
	phase = p
	t = 0.0
	report.phases.append({"phase": p, "at_s": snappedf(total, 0.1)})
	print("[autotest] fase: ", p)


func _physics_process(dt: float) -> void:
	if main == null or phase == "init":
		return
	var real_dt: float = dt / maxf(Engine.time_scale, 0.001)
	t += real_dt
	total += real_dt
	var a: Avatar = main.avatar
	var gp: GlobalPos = a.global_pos()
	_dbg_t += real_dt
	if _dbg_t > 5.0:
		_dbg_t = 0.0
		print(
			(
				"[autotest] %s t=%.0f %s agl=%.1f v=%.1f estado=%d dist=%.1f"
				% [phase, total, gp, a.agl, a.speed, a.state, gp.horizontal_distance_to(target)]
			)
		)
	if total > 400.0:
		_finish("tiempo agotado en fase " + phase)
		return
	match phase:
		"vuelo_largo":
			if gp.lon() >= target.lon() - 0.15:
				Engine.time_scale = 1.0
				a.boost = false
				a.speed = 250.0
				_set_phase("aproximacion")
		"aproximacion":
			var dx: float = Geo.delta_e(target.e, gp.e)
			var dn: float = target.n - gp.n
			var dist: float = sqrt(dx * dx + dn * dn)
			a.heading_deg = fposmod(rad_to_deg(atan2(dx, dn)), 360.0)
			a.speed = clampf(dist / 6.0, 0.0, 250.0) if dist > 1.5 else 0.0
			var want_alt: float = 60.0 if dist > 200.0 else 25.0
			a.pilot_climb = clampf((want_alt - a.agl) / 30.0, -1.0, 1.0)
			if dist < 4.0 and a.agl < 40.0:
				a.pilot_climb = 0.0
				print(
					(
						"[autotest] pedir aterrizaje: agl=%.2f suelo=%s zonas=%s"
						% [a.agl, a.ground_kind, main.zones.live_ids()]
					)
				)
				a.request_land()
				_set_phase("aterrizaje")
		"aterrizaje":
			if a.state == Avatar.State.WALK:
				report.landed = true
				report["landing_error_m"] = snappedf(a.global_pos().horizontal_distance_to(target), 0.01)
				a.heading_deg = 90.0
				a.look_pitch = 0.0
				_walk_start = a.global_pos()
				_set_phase("caminata")
			elif a.state == Avatar.State.FLY and t > 1.0:
				_finish("el aterrizaje fue rechazado")
			elif t > 30.0:
				_finish("no tocó el suelo")
		"caminata":
			a.pilot_stick = Vector2(0, 1)
			if not is_nan(_last_y):
				report.max_step_y = maxf(report.max_step_y, absf(a.position.y - _last_y))
			_last_y = a.position.y
			if a.state != Avatar.State.WALK:
				_finish("perdió el suelo al caminar")
				return
			if main.zones.current_id == "mv_test_male_este":
				report.walk_cross_ok = main.zones.stats.late_crossings == 0
				report["walked_m"] = snappedf(a.global_pos().horizontal_distance_to(_walk_start), 0.01)
				a.pilot_stick = Vector2.ZERO
				a.request_takeoff()
				_set_phase("despegue")
			elif t > 60.0:
				_finish("no llegó a la zona B caminando")
		"despegue":
			_last_y = NAN
			if a.state == Avatar.State.FLY:
				report.took_off = true
				a.pilot_climb = 1.0
				if a.agl > 80.0:
					a.pilot_climb = 0.0
					a.heading_deg = 90.0
					a.speed = 300.0
					_set_phase("alejamiento")
		"alejamiento":
			if main.zones.live_ids().size() == 0 and main.zones.stats.unloaded >= 2:
				report.unloaded_after_leave = true
				_finish("")
			elif t > 60.0:
				_finish("las zonas no se descargaron al alejarse")


func _finish(fail_reason: String) -> void:
	Engine.time_scale = 1.0
	report["tile_holes"] = main.tiles.stats.holes
	report["late_crossings"] = main.zones.stats.late_crossings
	report["zone_requests"] = main.zones.stats.requests
	report["tiles_built"] = main.tiles.stats.built
	report["tiles_freed"] = main.tiles.stats.freed
	report["max_tile_build_ms_thread"] = snappedf(main.tiles.stats.max_build_ms, 0.1)
	report["max_frame_ms"] = snappedf(main.frame_ms_max, 0.1)
	report["origin_shifts"] = main.world.shift_count
	report["max_step_y"] = snappedf(report.max_step_y, 0.0001)
	var ok: bool = (
		fail_reason == ""
		and report.tile_holes == 0
		and report.late_crossings == 0
		and report.landed
		and report.walk_cross_ok
		and report.took_off
		and report.max_step_y < 0.05
	)
	report["result"] = "PASS" if ok else "FAIL"
	report["reason"] = fail_reason
	print("[autotest] ", JSON.stringify(report))
	print("AUTOTEST ", report.result)
	phase = "done"
	main.get_tree().quit(0 if ok else 1)
