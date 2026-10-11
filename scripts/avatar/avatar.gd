class_name Avatar
extends CharacterBody3D
## Un solo avatar para volar y caminar.
##
## - Aire: primera persona, acelerar, girar, subir y bajar (teclado o controles táctiles).
## - Aterrizaje: un rayo al suelo confirma contacto con una superficie CAMINABLE (capa 2:
##   malla + colisión a escala de calle). La velocidad pasa a caminata y la cámara queda a
##   altura de persona. El terreno tosco (capa 1) es sólido pero no caminable.
## - Despegue: invierte el cambio.
## Todas las magnitudes "reales" se multiplican por k (escala de Mercator) al moverse.

signal message(text: String)
signal state_changed(state: int)
signal camera_mode_changed(third_person: bool)

enum State { FLY, LANDING, WALK }

const LAYER_TERRAIN := 1
const LAYER_WALKABLE := 2
const LAYER_BUILDINGS := 8  # capa 4: edificios/muros (sólidos, no caminables)
const EYE_HEIGHT := 1.65
const FLY_EYE := 0.9
const MAX_SPEED := 340.0
const BOOST_SPEED := 1500.0
const WALK_SPEED := 1.6
const RUN_SPEED := 4.5
const YAW_RATE := 55.0
const LAND_RAY := 400.0
const MAX_ALT := 20000.0
const SOUND_SPEED := 343.0
## Vuelo rasante: por debajo de SKIM_ENTER m sobre el agua/suelo con velocidad, el asistente
## sigue el terreno a SKIM_HEIGHT m y un rayo hacia adelante tira para arriba ante obstáculos.
const SKIM_ENTER := 9.0
## Buceo: bajo el nivel del mar el vuelo pasa a nado (velocidad de nado, burbujas).
const SWIM_MAX := 5.0
const SWIM_BOOST := 11.0
const SKIM_HEIGHT := 3.5
const SKIM_MIN_SPEED := 30.0
const TRICK_ACTIONS := {
	"trick_roll_left": "roll_left",
	"trick_roll_right": "roll_right",
	"trick_loop": "loop",
	"trick_flip": "flip",
	"trick_spin": "spin",
	"trick_dodge_left": "dodge_left",
	"trick_dodge_right": "dodge_right",
}

var world: WorldRoot
var state: int = State.FLY
var speed: float = 0.0  # m/s reales (horizontal en vuelo)
var climb: float = 0.0  # m/s reales
var heading_deg: float = 0.0
var look_pitch: float = -8.0
var boost: bool = false
var agl: float = INF  # altura sobre el suelo bajo el avatar (m)
var ground_kind: String = ""  # "caminable" | "terreno" | ""
var head: Node3D
var camera: Camera3D
var body: AvatarBody
var fx: AvatarFx
## Primera persona por defecto; tercera persona opcional (botón táctil / tecla C).
var third_person: bool = false
var base_fov: float = 70.0
## Órbita de la cámara en tercera persona alrededor del avatar (grados; 0 = detrás).
var cam_orbit_deg: float = 0.0

## Entrada táctil (la escribe el HUD).
var touch_stick: Vector2 = Vector2.ZERO  # x: giro/lateral, y: subir/avanzar (+ arriba)
var touch_throttle: float = -1.0  # 0..1 o -1 si no se usa
var touch_climb: float = 0.0  # -1..1
var auto_land: bool = false  # "Aterrizar" desde lo alto: baja solo y aterriza al llegar
## Entrada programática (piloto automático de pruebas); se suma a la del jugador.
var pilot_stick: Vector2 = Vector2.ZERO
var pilot_climb: float = 0.0
## Dinámica de vuelo: inercia de giro, alabeo en las curvas, turbulencia y acrobacias.
var acro := FlightAcro.new()
var yaw_vel: float = 0.0  # grados/s (con inercia)
var bank: float = 0.0  # alabeo del cuerpo en grados (+ = ala derecha abajo)
## Confort en primera persona: máximo alabeo de la cámara (grados). 0..180; 180 = sin límite.
var fp_roll_limit: float = 12.0
## Escala de las rotaciones de acrobacia en primera persona (1 = completas).
var fp_trick_scale: float = 0.5
var turbulence: Vector2 = Vector2.ZERO  # sacudida suave de la vista (grados)
var supersonic_count: int = 0
## "agua" | "tierra": qué hay debajo (agua = sin suelo o lecho bajo el nivel del mar).
var surface: String = "agua"
## 0..1: qué tan "rasante" se está volando (efectos: espuma, polvo, sacudida, viento).
var skim: float = 0.0
## Asistente de rasante y tirón automático (se puede apagar en opciones).
var skim_assist: bool = true
var pull_ups: int = 0
var swimming: bool = false
var _look_delta: Vector2 = Vector2.ZERO
var _cam_dist: float = 4.0
var _landing_rate: float = 0.0
var _off_walkable_t: float = 0.0
var _takeoff_t: float = 0.0
var _land_target_y: float = 0.0
var _was_supersonic: bool = false
var _turb_t: float = 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = LAYER_TERRAIN | LAYER_WALKABLE | LAYER_BUILDINGS
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, FLY_EYE, 0)
	add_child(head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.1
	camera.far = 100000.0
	camera.fov = 70.0
	camera.current = true
	head.add_child(camera)
	body = AvatarBody.new()
	body.name = "Body"
	add_child(body)
	fx = AvatarFx.new()
	fx.name = "Fx"
	add_child(fx)
	fx.setup(self)


## Cambia el personaje (pantalla de selección o personalización).
func set_character(def: CharacterDef) -> void:
	body.setup(def)
	_apply_camera_mode()


func toggle_camera() -> void:
	third_person = not third_person
	_apply_camera_mode()
	camera_mode_changed.emit(third_person)


func _apply_camera_mode() -> void:
	if body == null or body.model == null:
		return
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		# en primera persona el cuerpo no se ve pero sigue dando sombra
		mi.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if third_person
			else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		)


func scale_k() -> float:
	if world == null:
		return 1.0
	return Geo.scale_k(world.origin_n - position.z)


func global_pos() -> GlobalPos:
	return world.local_to_global(position) if world else GlobalPos.new()


func heading_vec() -> Vector2:
	return Geo.heading_vec(heading_deg)


func add_look(delta_px: Vector2) -> void:
	_look_delta += delta_px


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		add_look((event as InputEventMouseMotion).relative)
	elif event.is_action_pressed("land"):
		request_land()
	elif event.is_action_pressed("takeoff"):
		request_takeoff()
	elif event.is_action_pressed("boost"):
		boost = not boost
	elif event.is_action_pressed("camera_toggle"):
		toggle_camera()
	else:
		for act: String in TRICK_ACTIONS:
			if event.is_action_pressed(act):
				trick(TRICK_ACTIONS[act])


## Lanza una acrobacia (teclado, gesto táctil o pruebas). Solo en vuelo.
func trick(name: String) -> bool:
	if state != State.FLY:
		return false
	var ok := acro.start(name, speed)
	if ok and fx != null:
		fx.trick_started(name)
	return ok


func _physics_process(dt: float) -> void:
	var k := scale_k()
	_probe_ground()
	heading_deg = fposmod(heading_deg + _look_delta.x * 0.15, 360.0)
	look_pitch = clampf(look_pitch - _look_delta.y * 0.15, -80.0, 75.0)
	_look_delta = Vector2.ZERO
	match state:
		State.FLY:
			_fly(dt, k)
		State.LANDING:
			_landing(dt, k)
		State.WALK:
			_walk(dt, k)
	rotation = Vector3(0, -deg_to_rad(heading_deg), 0)
	var eye := EYE_HEIGHT if state == State.WALK else FLY_EYE
	head.position.y = lerpf(head.position.y, eye, clampf(dt * 4.0, 0.0, 1.0))
	var pitch := look_pitch
	var roll_cam := 0.0
	if state == State.FLY:
		pitch += clampf(climb / maxf(speed, 30.0), -0.5, 0.5) * 20.0
		if not third_person:
			pitch += acro.pitch * fp_trick_scale
			roll_cam = clampf(-bank * 0.4 - acro.roll * fp_trick_scale, -fp_roll_limit, fp_roll_limit)
		pitch += turbulence.y
	head.rotation.x = deg_to_rad(pitch)
	head.rotation.z = lerp_angle(head.rotation.z, deg_to_rad(roll_cam), clampf(dt * 8.0, 0.0, 1.0))
	head.rotation.y = deg_to_rad(turbulence.x) + (deg_to_rad(-acro.yaw * fp_trick_scale) if not third_person else 0.0)


func _process(dt: float) -> void:
	if body != null:
		body.drive(state, speed, climb, boost, dt)
		body.set_attitude(bank, acro.roll, acro.pitch, acro.yaw)
	_update_camera(dt)


func _update_camera(dt: float) -> void:
	# estiramiento de FOV con la velocidad (más fuerte con turbo)
	var stretch := 0.0
	if state == State.FLY:
		stretch = smoothstep(60.0, MAX_SPEED, speed) * 14.0 + smoothstep(MAX_SPEED, BOOST_SPEED, speed) * 16.0
	camera.fov = lerpf(camera.fov, base_fov + stretch, clampf(dt * 3.0, 0.0, 1.0))
	var k := scale_k()
	var sh := Vector3.ZERO
	if fx != null and fx.shake > 0.0:
		var t := Time.get_ticks_msec() * 0.001
		sh = Vector3(sin(t * 53.0), sin(t * 71.0 + 1.3), 0.0) * fx.shake * fx.shake * 0.12 * k
	if not third_person:
		camera.position = sh
		return
	var want := 3.2 if state == State.WALK else 4.5 + smoothstep(50.0, BOOST_SPEED, speed) * 2.5
	_cam_dist = lerpf(_cam_dist, want, clampf(dt * 2.0, 0.0, 1.0))
	var local := Basis(Vector3.UP, deg_to_rad(cam_orbit_deg)) * (Vector3(0.0, 0.45 + 1.8 * skim, _cam_dist) * k)
	# no atravesar paredes: acorta el brazo de la cámara
	var from := head.global_position
	var to := head.global_transform * local
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_BUILDINGS | LAYER_WALKABLE, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var d := from.distance_to(hit.position as Vector3) - 0.25 * k
		local = local.normalized() * maxf(d, 0.4 * k)
	camera.position = local + sh
	if absf(cam_orbit_deg) > 0.5:
		camera.look_at(global_position + Vector3(0, 0.9 * k, 0), Vector3.UP)
	else:
		# en rasante la cámara sube y mira un poco hacia abajo: se ve el agua/suelo pasar
		camera.rotation = Vector3(deg_to_rad(-14.0 * skim), 0.0, 0.0)


func _fly(dt: float, k: float) -> void:
	swimming = position.y < -0.6 * k_now()
	var vmax := (SWIM_BOOST if boost else SWIM_MAX) if swimming else (BOOST_SPEED if boost else MAX_SPEED)
	var thr := Input.get_action_strength("throttle_up") - Input.get_action_strength("throttle_down")
	# curva de aceleración: fuerte al arrancar, se suaviza cerca del máximo; el turbo empuja más
	var near := clampf(speed / vmax, 0.0, 1.0)
	var accel := (25.0 + speed * 0.6) * (1.0 - 0.55 * near * near) * (2.2 if boost else 1.0)
	if touch_throttle >= 0.0:
		speed = move_toward(speed, touch_throttle * vmax, accel * dt)
	elif thr < 0.0 and speed < 40.0:
		# freno de vuelo estacionario: se detiene firme pero sin golpe
		speed = lerpf(speed, 0.0, clampf(dt * 2.5, 0.0, 1.0))
	else:
		speed = clampf(speed + thr * accel * dt, 0.0, vmax * 1.1)
	if speed > vmax:
		speed = move_toward(speed, vmax, accel * 1.5 * dt)
	var yaw := (
		Input.get_action_strength("yaw_right") - Input.get_action_strength("yaw_left") + touch_stick.x + pilot_stick.x
	)
	# giro con inercia: la velocidad angular se acerca a la pedida (más lenta a gran velocidad)
	var yaw_rate := YAW_RATE * (1.15 - 0.55 * smoothstep(150.0, BOOST_SPEED, speed))
	var resp := 3.5 if absf(yaw) > 0.05 else 5.5  # al soltar se endereza un poco más rápido
	yaw_vel = lerpf(yaw_vel, clampf(yaw, -1.0, 1.0) * yaw_rate, clampf(dt * resp, 0.0, 1.0))
	heading_deg = fposmod(heading_deg + yaw_vel * dt, 360.0)
	# alabeo coordinado: tan(bank) = v·ω/g, limitado; en vuelo lento casi no se inclina
	var want_bank := rad_to_deg(atan(maxf(speed, 0.0) * deg_to_rad(yaw_vel) / 9.81))
	bank = lerpf(bank, clampf(want_bank, -70.0, 70.0), clampf(dt * 4.0, 0.0, 1.0))
	var c := (
		Input.get_action_strength("climb")
		- Input.get_action_strength("descend")
		+ touch_climb
		+ pilot_climb
		+ touch_stick.y
		+ pilot_stick.y
	)
	if auto_land:
		if absf(c) > 0.3:
			auto_land = false  # el jugador retoma el control
		else:
			c = -1.0
			speed = move_toward(speed, 40.0, 60.0 * dt)
			request_land()
	var climb_max := clampf(maxf(8.0, speed * 0.4), 8.0, 300.0)
	if swimming:
		climb_max = 4.0  # nado: subir/bajar lento
	var target_climb := clampf(c, -1.0, 1.0) * climb_max
	target_climb = _skim_assist(target_climb, c, climb_max, k)
	if _takeoff_t > 0.0:
		_takeoff_t -= dt
		target_climb = maxf(target_climb, 22.0)
	climb = move_toward(climb, target_climb, climb_max * 1.5 * dt)
	# picada: bajar suma velocidad; trepar fuerte cuesta un poco
	if climb < -5.0:
		speed = minf(speed + -climb * 0.22 * dt, vmax * 1.1)
	elif climb > 20.0 and speed > 60.0:
		speed -= climb * 0.05 * dt
	_supersonic_check()
	_turbulence(dt)
	acro.step(dt)
	var h := heading_vec()
	velocity = Vector3(h.x * speed, climb, -h.y * speed) * k
	if acro.active():
		# velocidad extra del truco en ejes locales del avatar (x derecha, z adelante)
		var fwd := Vector3(h.x, 0.0, -h.y)
		var right := Vector3(h.y, 0.0, h.x)
		velocity += (right * acro.vel_local.x + Vector3.UP * acro.vel_local.y + fwd * acro.vel_local.z) * k
	move_and_slide()
	# no hundirse en el mar por accidente a alta velocidad; lento sobre el agua se puede bucear
	var can_dive := surface == "agua" and (speed < 40.0 or swimming)
	if position.y < 2.0 * k and not can_dive:
		position.y = 2.0 * k
		climb = maxf(climb, 0.0)
	if position.y > MAX_ALT:
		position.y = MAX_ALT
		climb = minf(climb, 0.0)
	# aterrizaje automático suave: lento y a punto de tocar una superficie caminable
	if ground_kind == "caminable" and agl < 1.2 and speed < 20.0 and climb <= 0.0:
		_enter_walk()


## Asistente de vuelo rasante: mantiene unos metros sobre agua, suelo, techos y muelles si
## el jugador no pide subir/bajar, y tira hacia arriba ante un choque inminente (mirando
## hacia adelante el tiempo de reacción: ~1.1 s a la velocidad actual).
func _skim_assist(target_climb: float, c: float, climb_max: float, k: float) -> float:
	var near := agl < SKIM_ENTER * 1.6 and speed > SKIM_MIN_SPEED
	skim = lerpf(skim, (1.0 - clampf((agl - 1.0) / SKIM_ENTER, 0.0, 1.0)) if near else 0.0, 0.15)
	if not skim_assist or acro.active() or swimming or position.y < 0.5:
		return target_climb
	if agl < SKIM_ENTER and speed > SKIM_MIN_SPEED and absf(c) < 0.2:
		target_climb = clampf((SKIM_HEIGHT - agl) * 2.5, -12.0, climb_max)
	# tirón automático: rayo hacia adelante y abajo a la altura del cuerpo
	if speed > 15.0:
		var h := heading_vec()
		var fwd := Vector3(h.x, 0.0, -h.y)
		var look := clampf(speed * 1.1, 8.0, 400.0) * k
		var from := global_position + Vector3(0, 0.6 * k, 0)
		var q := PhysicsRayQueryParameters3D.create(
			from, from + fwd * look + Vector3(0, climb * 1.1 * k, 0), collision_mask, [get_rid()]
		)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var danger := not hit.is_empty() or (agl < 1.2 and climb < 0.0)
		if danger:
			var need := 0.0
			if not hit.is_empty():
				# subir lo suficiente para pasar por encima (con margen) antes de llegar
				var top := (hit.position as Vector3).y / k + 4.0
				var t := maxf(from.distance_to(hit.position as Vector3) / k / maxf(speed, 1.0), 0.15)
				need = (top - position.y / k) / t
			else:
				need = 6.0
			if need > target_climb:
				if need > 2.0 and target_climb < need - 5.0 and climb < need * 0.5:
					pull_ups += 1
					message.emit("¡Arriba!")
				target_climb = minf(maxf(need, target_climb), 300.0)
				climb = maxf(climb, minf(need, climb + climb_max * 0.5))
	return target_climb


func k_now() -> float:
	return scale_k()


func _supersonic_check() -> void:
	var sup := speed >= SOUND_SPEED
	if sup and not _was_supersonic:
		supersonic_count += 1
		if fx != null:
			fx.sonic_boom()
		message.emit("¡Barrera del sonido!")
	_was_supersonic = speed >= SOUND_SPEED * 0.97 if _was_supersonic else sup


## Viento/turbulencia: sacudida suave (ruido de senos) que crece con la velocidad y cerca del
## suelo; muy chica para no marear.
func _turbulence(dt: float) -> void:
	_turb_t += dt
	var amp := smoothstep(40.0, 900.0, speed) * 0.55 + (0.25 if agl < 60.0 and speed > 80.0 else 0.0)
	amp += skim * smoothstep(30.0, 300.0, speed) * 0.9  # rasante: el suelo "pasa" cerca
	var tt := _turb_t
	var want := Vector2(sin(tt * 1.7) + sin(tt * 3.1 + 1.0) * 0.5, sin(tt * 2.3 + 0.4) + sin(tt * 4.7) * 0.4) * amp
	turbulence = turbulence.lerp(want, clampf(dt * 4.0, 0.0, 1.0))


func _landing(dt: float, k: float) -> void:
	speed = move_toward(speed, 0.0, maxf(speed, 10.0) * 1.2 * dt)
	var h := heading_vec()
	# aterrizaje pesado: baja rápido hasta el final (impacto con onda y polvo)
	var rate := clampf(agl * 1.2, 9.0, 70.0)
	_landing_rate = rate
	velocity = Vector3(h.x * speed, -rate, -h.y * speed) * k
	move_and_slide()
	if ground_kind != "caminable" and agl > 2.0 and agl != INF:
		# el suelo bajo el avatar dejó de ser caminable: abortar
		state = State.FLY
		message.emit("Aterrizaje cancelado: no hay calle debajo")
		state_changed.emit(state)
		return
	if is_on_floor() or agl < 0.08:
		_enter_walk()


func _walk(dt: float, k: float) -> void:
	var fwd := (
		Input.get_action_strength("throttle_up")
		- Input.get_action_strength("throttle_down")
		+ touch_stick.y
		+ pilot_stick.y
	)
	var side := (
		Input.get_action_strength("yaw_right") - Input.get_action_strength("yaw_left") + touch_stick.x + pilot_stick.x
	)
	var mv := Vector2(side, fwd)
	if mv.length() > 1.0:
		mv = mv.normalized()
	var spd := RUN_SPEED if Input.is_action_pressed("run") else WALK_SPEED
	var h := heading_vec()
	var right := Vector2(h.y, -h.x)
	var dir2 := h * mv.y + right * mv.x
	velocity.x = dir2.x * spd * k
	velocity.z = -dir2.y * spd * k
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 9.81 * k * dt
	move_and_slide()
	speed = Vector2(velocity.x, velocity.z).length() / k
	# solo se camina donde hay malla caminable
	if ground_kind != "caminable" or agl > 2.5:
		_off_walkable_t += dt
		if _off_walkable_t > 0.4:
			request_takeoff()
			message.emit("Fin de la calle modelada: volvés al aire")
	else:
		_off_walkable_t = 0.0


func _enter_walk() -> void:
	if state == State.LANDING or (state == State.FLY and speed > 5.0):
		var strength := clampf(_landing_rate / 40.0 + 0.35, 0.0, 1.0)
		if fx != null:
			fx.burst(global_position, strength, true)
		if body != null:
			body.impact()
	state = State.WALK
	speed = 0.0
	climb = 0.0
	velocity = Vector3.ZERO
	look_pitch = 0.0
	_off_walkable_t = 0.0
	message.emit("En tierra: caminando")
	state_changed.emit(state)


func request_land() -> void:
	if state != State.FLY:
		return
	var hit := _ray_down(LAND_RAY * scale_k(), ground_mask())
	if hit.is_empty():
		if not auto_land:
			message.emit("Descendiendo para aterrizar…")
		auto_land = true
		return
	var col: CollisionObject3D = hit.collider
	if col == null or (col.collision_layer & LAYER_WALKABLE) == 0:
		auto_land = false
		message.emit("Acá no hay calles modeladas: solo se aterriza en micro-mapas")
		return
	auto_land = false
	_land_target_y = (hit.position as Vector3).y
	state = State.LANDING
	message.emit("Aterrizando…")
	state_changed.emit(state)


func request_takeoff() -> void:
	if state == State.FLY:
		return
	state = State.FLY
	speed = 0.0
	# despegue explosivo: salida vertical fuerte, onda expansiva y polvo
	climb = 26.0
	_takeoff_t = 1.2
	if fx != null:
		fx.burst(global_position, 0.8, false)
	if body != null:
		body.launch()
	look_pitch = -8.0
	message.emit("Despegue")
	state_changed.emit(state)


## Dentro de un micro-mapa cargado el conector (terreno tosco) no cuenta: el micro-mapa
## trae su propio suelo y el relieve de 611 m podría asomar por encima de calles y playas.
func set_inside_site(inside: bool) -> void:
	var m := LAYER_WALKABLE | LAYER_BUILDINGS
	if not inside:
		m |= LAYER_TERRAIN
	if collision_mask != m:
		collision_mask = m


func ground_mask() -> int:
	return collision_mask


func _ray_down(length: float, mask: int) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, length, 0), mask, [get_rid()])
	return space.intersect_ray(q)


func _probe_ground() -> void:
	var hit := _ray_down(30000.0, ground_mask())
	if hit.is_empty():
		agl = maxf(position.y, 0.0) / scale_k()  # sobre el mar
		ground_kind = ""
		surface = "agua"
		return
	surface = "agua" if (hit.position as Vector3).y < 0.15 * scale_k() else "tierra"
	agl = (global_position.y - (hit.position as Vector3).y) / scale_k()
	var col: CollisionObject3D = hit.collider
	ground_kind = "caminable" if col != null and (col.collision_layer & LAYER_WALKABLE) != 0 else "terreno"
	if ground_kind == "terreno":
		agl = minf(agl, maxf(position.y, 0.0) / scale_k())  # sobre el agua cuenta el nivel del mar
