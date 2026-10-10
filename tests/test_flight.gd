extends GutTest
## Dinámica de vuelo y acrobacias (lógica pura de FlightAcro + avatar sin mundo).


func _run(a: FlightAcro, secs: float, dt: float = 1.0 / 60.0) -> Dictionary:
	var pos := Vector3.ZERO
	var max_roll := 0.0
	var max_pitch := 0.0
	var steps := int(secs / dt)
	for i in steps:
		a.step(dt)
		pos += a.vel_local * dt
		max_roll = maxf(max_roll, absf(a.roll))
		max_pitch = maxf(max_pitch, absf(a.pitch))
	return {"pos": pos, "roll": max_roll, "pitch": max_pitch}


func test_barrel_roll_completes_full_turn() -> void:
	var a := FlightAcro.new()
	assert_true(a.start("roll_right", 120.0))
	var r := _run(a, 1.0)
	assert_false(a.active(), "el tonel terminó")
	assert_eq(a.count, 1)
	assert_gt(r.roll, 300.0, "llega a girar casi 360°")
	assert_eq(a.roll, 0.0, "al terminar vuelve a nivel")


func test_loop_returns_near_start_height() -> void:
	var a := FlightAcro.new()
	assert_true(a.start("loop", 100.0))
	var r := _run(a, 2.6)
	assert_false(a.active())
	assert_gt(r.pitch, 300.0)
	# el círculo vertical se cierra: termina cerca de la altura de entrada
	assert_lt(absf((r.pos as Vector3).y), 25.0, "altura final del rizo cercana a la inicial")


func test_loop_needs_speed_and_no_overlap() -> void:
	var a := FlightAcro.new()
	assert_false(a.start("loop", 10.0), "sin velocidad no hay rizo")
	assert_true(a.start("flip", 0.0))
	assert_false(a.start("spin", 50.0), "no se encadenan dos trucos a la vez")


func test_dodge_moves_sideways() -> void:
	var a := FlightAcro.new()
	a.start("dodge_left", 50.0)
	var r := _run(a, 0.6)
	assert_lt((r.pos as Vector3).x, -5.0, "el esquive desplaza varios metros a la izquierda")


func test_swipe_mapping() -> void:
	assert_eq(FlightAcro.from_swipe(Vector2(200, 10)), "roll_right")
	assert_eq(FlightAcro.from_swipe(Vector2(-200, 10)), "roll_left")
	assert_eq(FlightAcro.from_swipe(Vector2(5, -200)), "loop")
	assert_eq(FlightAcro.from_swipe(Vector2(5, 200)), "flip")
	assert_eq(FlightAcro.from_swipe(Vector2(30, 20)), "", "un toque corto no es gesto")


func _flyer() -> Avatar:
	var av := Avatar.new()
	add_child_autofree(av)
	av.position = Vector3(0, 500, 0)
	av.state = Avatar.State.FLY
	return av


func test_turn_banks_with_inertia() -> void:
	var av := _flyer()
	av.speed = 200.0
	av.pilot_stick = Vector2(1, 0)
	av._physics_process(1.0 / 60.0)
	var early := av.yaw_vel
	for i in 120:
		av._physics_process(1.0 / 60.0)
	assert_lt(early, av.yaw_vel * 0.3, "el giro arranca suave (inercia)")
	assert_gt(av.bank, 20.0, "se inclina hacia la curva")
	av.pilot_stick = Vector2.ZERO
	for i in 120:
		av._physics_process(1.0 / 60.0)
	assert_lt(absf(av.bank), 3.0, "al soltar vuelve a nivel")


func test_sonic_boom_once_when_crossing_mach1() -> void:
	var av := _flyer()
	av.boost = true
	av.speed = 300.0
	av.touch_throttle = 1.0
	for i in 600:
		av._physics_process(1.0 / 60.0)
	assert_gt(av.speed, Avatar.SOUND_SPEED)
	assert_eq(av.supersonic_count, 1, "un solo estampido al cruzar la barrera")
	assert_eq(av.fx.booms, 1)


func test_dive_gains_speed() -> void:
	var av := _flyer()
	av.speed = 100.0
	av.position.y = 3000.0
	av.pilot_climb = -1.0
	for i in 180:
		av._physics_process(1.0 / 60.0)
	assert_gt(av.speed, 110.0, "picar acelera")


func test_trick_only_in_flight_and_draws_trail() -> void:
	var av := _flyer()
	av.speed = 150.0
	assert_true(av.trick("roll_left"))
	assert_eq(av.fx.trails_made, 1)
	av.state = Avatar.State.WALK
	for i in 90:
		av.acro.step(1.0 / 60.0)
	assert_false(av.trick("loop"), "caminando no hay acrobacias")
