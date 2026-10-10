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

## Entrada táctil (la escribe el HUD).
var touch_stick: Vector2 = Vector2.ZERO  # x: giro/lateral, y: subir/avanzar (+ arriba)
var touch_throttle: float = -1.0  # 0..1 o -1 si no se usa
var touch_climb: float = 0.0  # -1..1
## Entrada programática (piloto automático de pruebas); se suma a la del jugador.
var pilot_stick: Vector2 = Vector2.ZERO
var pilot_climb: float = 0.0
var _look_delta: Vector2 = Vector2.ZERO
var _off_walkable_t: float = 0.0
var _takeoff_t: float = 0.0
var _land_target_y: float = 0.0


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
	if state == State.FLY:
		pitch += clampf(climb / maxf(speed, 30.0), -0.5, 0.5) * 20.0
	head.rotation.x = deg_to_rad(pitch)


func _fly(dt: float, k: float) -> void:
	var vmax := BOOST_SPEED if boost else MAX_SPEED
	var thr := Input.get_action_strength("throttle_up") - Input.get_action_strength("throttle_down")
	var accel := 25.0 + speed * 0.6
	if touch_throttle >= 0.0:
		speed = move_toward(speed, touch_throttle * vmax, accel * dt)
	else:
		speed = clampf(speed + thr * accel * dt, 0.0, vmax)
	if speed > vmax:
		speed = move_toward(speed, vmax, accel * 2.0 * dt)
	var yaw := (
		Input.get_action_strength("yaw_right") - Input.get_action_strength("yaw_left") + touch_stick.x + pilot_stick.x
	)
	heading_deg = fposmod(heading_deg + clampf(yaw, -1.0, 1.0) * YAW_RATE * dt, 360.0)
	var c := (
		Input.get_action_strength("climb")
		- Input.get_action_strength("descend")
		+ touch_climb
		+ pilot_climb
		+ touch_stick.y
		+ pilot_stick.y
	)
	var climb_max := clampf(maxf(8.0, speed * 0.4), 8.0, 300.0)
	var target_climb := clampf(c, -1.0, 1.0) * climb_max
	if _takeoff_t > 0.0:
		_takeoff_t -= dt
		target_climb = maxf(target_climb, 4.0)
	climb = move_toward(climb, target_climb, climb_max * 1.5 * dt)
	var h := heading_vec()
	velocity = Vector3(h.x * speed, climb, -h.y * speed) * k
	move_and_slide()
	# no hundirse en el mar ni salir del techo
	if position.y < 2.0 * k:
		position.y = 2.0 * k
		climb = maxf(climb, 0.0)
	if position.y > MAX_ALT:
		position.y = MAX_ALT
		climb = minf(climb, 0.0)
	# aterrizaje automático suave: lento y a punto de tocar una superficie caminable
	if ground_kind == "caminable" and agl < 1.2 and speed < 20.0 and climb <= 0.0:
		_enter_walk()


func _landing(dt: float, k: float) -> void:
	speed = move_toward(speed, 0.0, maxf(speed, 10.0) * 1.2 * dt)
	var h := heading_vec()
	var rate := clampf(agl * 0.8, 2.0, 60.0)
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
		message.emit("Demasiado alto para aterrizar: bajá a menos de %d m" % int(LAND_RAY))
		return
	var col: CollisionObject3D = hit.collider
	if col == null or (col.collision_layer & LAYER_WALKABLE) == 0:
		message.emit("Acá no hay calles modeladas: solo se aterriza en micro-mapas")
		return
	_land_target_y = (hit.position as Vector3).y
	state = State.LANDING
	message.emit("Aterrizando…")
	state_changed.emit(state)


func request_takeoff() -> void:
	if state == State.FLY:
		return
	state = State.FLY
	speed = 0.0
	climb = 4.0
	_takeoff_t = 1.5
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
		return
	agl = (global_position.y - (hit.position as Vector3).y) / scale_k()
	var col: CollisionObject3D = hit.collider
	ground_kind = "caminable" if col != null and (col.collision_layer & LAYER_WALKABLE) != 0 else "terreno"
	if ground_kind == "terreno":
		agl = minf(agl, maxf(position.y, 0.0) / scale_k())  # sobre el agua cuenta el nivel del mar
