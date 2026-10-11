extends GutTest
## Controles táctiles simulados con eventos de pantalla (multitáctil: joystick + botones).


func _touch(c: Control, idx: int, down: bool, pos := Vector2(10, 10)) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.pressed = down
	e.position = pos
	c._gui_input(e)


func _drag(c: Control, idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	c._gui_input(e)


func _setup() -> Hud:
	var av := Avatar.new()
	add_child_autofree(av)
	av.position = Vector3(0, 300, 0)
	av.state = Avatar.State.FLY
	av.speed = 100.0
	var hud := Hud.new()
	hud.avatar = av
	add_child_autofree(hud)
	return hud


func test_descend_hold_while_steering() -> void:
	var hud := _setup()
	_touch(hud.stick, 0, true, Vector2(110, 110))
	_drag(hud.stick, 0, Vector2(200, 110))  # dedo 0 gira a la derecha
	_touch(hud.btn_down, 1, true)  # dedo 1 mantiene "bajar"
	hud._process(0.016)
	assert_almost_eq(hud.avatar.touch_climb, -1.0, 0.001)
	assert_gt(hud.avatar.touch_stick.x, 0.5)
	_touch(hud.btn_down, 1, false)
	hud._process(0.016)
	assert_almost_eq(hud.avatar.touch_climb, 0.0, 0.001)
	assert_gt(hud.avatar.touch_stick.x, 0.5, "soltar el botón no suelta el joystick")


func test_ascend_and_throttle_multitouch() -> void:
	var hud := _setup()
	_touch(hud.btn_up, 2, true)
	_touch(hud.throttle, 3, true, Vector2(30, hud.throttle.size.y * 0.1))
	hud._process(0.016)
	assert_almost_eq(hud.avatar.touch_climb, 1.0, 0.001)
	assert_gt(hud.avatar.touch_throttle, 0.8)


func test_boost_camera_land_buttons() -> void:
	var hud := _setup()
	_touch(hud.btn_boost, 0, true)
	_touch(hud.btn_boost, 0, false)
	assert_true(hud.avatar.boost)
	var tp: bool = hud.avatar.third_person
	_touch(hud.btn_cam, 0, true)
	assert_ne(hud.avatar.third_person, tp)
	_touch(hud.btn_land, 0, true)  # alto y sin suelo: activa el descenso automático
	assert_true(hud.avatar.auto_land)


func test_auto_land_descends_and_cancels() -> void:
	var hud := _setup()
	hud.avatar.request_land()
	var y0: float = hud.avatar.position.y
	for i in 60:
		hud.avatar._physics_process(1.0 / 60.0)
	assert_lt(hud.avatar.position.y, y0 - 3.0)
	_touch(hud.btn_up, 0, true)
	hud._process(0.016)
	hud.avatar._physics_process(1.0 / 60.0)
	assert_false(hud.avatar.auto_land, "subir cancela el aterrizaje automático")


func test_swipe_trick_gesture() -> void:
	var hud := _setup()
	var w: float = hud.look_pad.size.x
	var sw: float = 200.0 * hud.get_viewport().get_visible_rect().size.y / 720.0
	var e := InputEventScreenTouch.new()
	e.index = 4
	e.pressed = true
	e.position = Vector2(w * 0.5, 40)
	hud._on_look_input(e)
	e = InputEventScreenTouch.new()
	e.index = 4
	e.pressed = false
	e.position = Vector2(w * 0.5 + sw, 40)
	hud._on_look_input(e)
	assert_true(hud.avatar.acro.active(), "deslizar rápido a la derecha hace un tonel")
