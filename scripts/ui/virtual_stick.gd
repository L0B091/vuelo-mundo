class_name VirtualStick
extends Control
## Joystick táctil. value: x a la derecha, y hacia arriba, en [-1, 1].

var value: Vector2 = Vector2.ZERO
var _touch: int = -1
var _center: Vector2


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_center = size * 0.5


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch == -1:
			_touch = t.index
			_update(t.position)
		elif not t.pressed and t.index == _touch:
			_touch = -1
			value = Vector2.ZERO
			queue_redraw()
		accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch:
			_update(d.position)
		accept_event()


func _update(p: Vector2) -> void:
	_center = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5
	var v := (p - _center) / r
	if v.length() > 1.0:
		v = v.normalized()
	value = Vector2(v.x, -v.y)
	queue_redraw()


func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5
	draw_circle(size * 0.5, r, Color(1, 1, 1, 0.12))
	draw_arc(size * 0.5, r, 0, TAU, 48, Color(1, 1, 1, 0.5), 2.0)
	draw_circle(size * 0.5 + Vector2(value.x, -value.y) * r, r * 0.35, Color(1, 1, 1, 0.55))
