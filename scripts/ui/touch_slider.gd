class_name TouchSlider
extends Control
## Acelerador vertical multitáctil (0 abajo .. 1 arriba). `active` mientras un dedo lo mueve.

var value: float = 0.0
var active: bool = false
var _touch: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch == -1:
			_touch = t.index
			active = true
			_set_from(t.position)
		elif not t.pressed and t.index == _touch:
			_touch = -1
			active = false
		accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch:
			_set_from(d.position)
		accept_event()


func _set_from(p: Vector2) -> void:
	value = clampf(1.0 - p.y / maxf(size.y, 1.0), 0.0, 1.0)
	queue_redraw()


func show_value(v: float) -> void:
	if not active:
		value = clampf(v, 0.0, 1.0)
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2(size.x * 0.3, 0), Vector2(size.x * 0.4, size.y)), Color(0.05, 0.08, 0.12, 0.45))
	var y := (1.0 - value) * size.y
	draw_rect(Rect2(Vector2(size.x * 0.3, y), Vector2(size.x * 0.4, size.y - y)), Color(1, 0.8, 0.3, 0.55))
	draw_rect(Rect2(Vector2(0, y - 10), Vector2(size.x, 20)), Color(1, 1, 1, 0.8))
