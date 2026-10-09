class_name Hud
extends CanvasLayer
## HUD con controles táctiles (vuelo y caminata) y datos de telemetría/streaming.

var avatar: Avatar
var main: Node

var info: Label
var msg: Label
var stick: VirtualStick
var throttle: VSlider
var btn_land: Button
var btn_boost: Button
var btn_up: Button
var btn_down: Button
var look_pad: Control
var _msg_t: float = 0.0
var _look_touch: int = -1


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	look_pad = Control.new()
	look_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	look_pad.mouse_filter = Control.MOUSE_FILTER_PASS
	look_pad.gui_input.connect(_on_look_input)
	root.add_child(look_pad)

	info = Label.new()
	info.position = Vector2(12, 8)
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	info.add_theme_constant_override("outline_size", 4)
	root.add_child(info)

	msg = Label.new()
	msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msg.position = Vector2(-300, 60)
	msg.size = Vector2(600, 40)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 22)
	msg.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	msg.add_theme_constant_override("outline_size", 6)
	root.add_child(msg)

	stick = VirtualStick.new()
	stick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stick.position = Vector2(30, -250)
	stick.size = Vector2(220, 220)
	root.add_child(stick)

	throttle = VSlider.new()
	throttle.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	throttle.position = Vector2(-80, -300)
	throttle.size = Vector2(50, 260)
	throttle.min_value = 0.0
	throttle.max_value = 1.0
	throttle.step = 0.01
	throttle.tooltip_text = "Acelerador"
	root.add_child(throttle)

	btn_up = _button(root, "▲", Vector2(-200, -300))
	btn_down = _button(root, "▼", Vector2(-200, -200))
	btn_land = _button(root, "Aterrizar", Vector2(-330, -100))
	btn_land.size = Vector2(150, 70)
	btn_land.pressed.connect(_on_land_pressed)
	btn_boost = _button(root, "Turbo", Vector2(-330, -300))
	btn_boost.toggle_mode = true
	btn_boost.toggled.connect(func(on: bool) -> void: avatar.boost = on)


func _button(parent: Control, text: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	b.position = pos
	b.size = Vector2(90, 80)
	b.add_theme_font_size_override("font_size", 22)
	parent.add_child(b)
	return b


func _on_land_pressed() -> void:
	if avatar.state == Avatar.State.FLY:
		avatar.request_land()
	else:
		avatar.request_takeoff()


func _on_look_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _look_touch == -1 and t.position.x > look_pad.size.x * 0.35:
			_look_touch = t.index
		elif not t.pressed and t.index == _look_touch:
			_look_touch = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _look_touch:
			avatar.add_look(d.relative)


func show_message(text: String) -> void:
	msg.text = text
	_msg_t = 3.0


func _process(dt: float) -> void:
	if avatar == null:
		return
	var flying := avatar.state != Avatar.State.WALK
	avatar.touch_stick = stick.value
	avatar.touch_climb = (1.0 if btn_up.button_pressed else 0.0) - (1.0 if btn_down.button_pressed else 0.0)
	throttle.visible = flying
	btn_up.visible = flying
	btn_down.visible = flying
	btn_boost.visible = flying
	btn_land.text = "Aterrizar" if flying else "Despegar"
	if flying and throttle.has_focus() or _throttle_touched():
		avatar.touch_throttle = throttle.value
	else:
		throttle.set_value_no_signal(avatar.speed / (Avatar.BOOST_SPEED if avatar.boost else Avatar.MAX_SPEED))
		avatar.touch_throttle = -1.0
	_msg_t -= dt
	msg.modulate.a = clampf(_msg_t, 0.0, 1.0)
	if main and main.has_method("telemetry"):
		info.text = main.telemetry()


func _throttle_touched() -> bool:
	return (
		throttle.get_global_rect().has_point(throttle.get_viewport().get_mouse_position())
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	)
