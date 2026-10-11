class_name TouchButton
extends Control
## Botón táctil multitáctil: cada dedo se sigue por su índice, así funciona mientras otro dedo
## maneja el joystick (los Button de Godot solo ven el primer dedo emulado como ratón y su
## button_pressed no refleja "mantenido" fuera del modo toggle). En escritorio, el ratón llega
## como toque (emulate_touch_from_mouse).

signal pressed
signal toggled(on: bool)

var text: String = ""
var toggle_mode: bool = false
var held: bool = false  # dedo apoyado ahora
var on: bool = false  # estado del toggle
var _touch: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch == -1:
			_touch = t.index
			held = true
			if toggle_mode:
				set_on(not on)
			pressed.emit()
			queue_redraw()
		elif not t.pressed and t.index == _touch:
			release()
		accept_event()
	elif event is InputEventScreenDrag:
		accept_event()


func release() -> void:
	_touch = -1
	held = false
	queue_redraw()


func set_on(v: bool) -> void:
	if v != on:
		on = v
		toggled.emit(on)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release()


func _draw() -> void:
	var lit := held or on
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.45) if lit else Color(0.05, 0.08, 0.12, 0.45)
	sb.border_color = Color(1, 1, 1, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var f := get_theme_default_font()
	var fs := 22 if text.length() <= 4 else 18
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(
		f,
		Vector2((size.x - w) * 0.5, size.y * 0.5 + fs * 0.35),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs,
		Color.BLACK if lit else Color.WHITE
	)
