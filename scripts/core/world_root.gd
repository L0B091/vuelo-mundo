class_name WorldRoot
extends Node3D
## Raíz de todo lo que vive en el espacio global.
##
## Guarda el "origen de render" en doble precisión. Todo nodo hijo directo se posiciona
## relativo a ese origen, así las coordenadas que ve el motor (float32) quedan siempre cerca
## de cero. Cuando el foco (avatar) se aleja más de SHIFT_THRESHOLD, el origen se desplaza:
## se mueve el origen y se restan las mismas coordenadas a todos los hijos. Es invisible.

signal origin_shifted(delta: Vector3)

const SHIFT_THRESHOLD: float = 2048.0
## Período (m) del patrón de olas; las olas usan coordenadas globales módulo este valor.
const WAVE_PERIOD: float = 8192.0

var origin_e: float = 0.0
var origin_n: float = 0.0
var shift_count: int = 0


func set_origin(e: float, n: float) -> void:
	origin_e = Geo.wrap_e(e)
	origin_n = n
	_update_shader_globals()


func global_to_local(e: float, n: float, up: float = 0.0) -> Vector3:
	return Vector3(Geo.delta_e(e, origin_e), up, -(n - origin_n))


func local_to_global(p: Vector3) -> GlobalPos:
	return GlobalPos.new(origin_e + p.x, origin_n - p.z, p.y)


func place(node: Node3D, e: float, n: float, up: float = 0.0) -> void:
	node.position = global_to_local(e, n, up)


func maybe_shift(focus: Node3D) -> bool:
	var p: Vector3 = focus.position
	if absf(p.x) < SHIFT_THRESHOLD and absf(p.z) < SHIFT_THRESHOLD:
		return false
	shift_by(p.x, p.z)
	return true


func shift_by(dx: float, dz: float) -> void:
	var d := Vector3(dx, 0.0, dz)
	for c in get_children():
		if c is Node3D:
			(c as Node3D).position -= d
	origin_e = Geo.wrap_e(origin_e + dx)
	origin_n -= dz
	shift_count += 1
	_update_shader_globals()
	origin_shifted.emit(d)


func _update_shader_globals() -> void:
	var mod := Vector2(fposmod(origin_e, WAVE_PERIOD), fposmod(-origin_n, WAVE_PERIOD))
	RenderingServer.global_shader_parameter_set(&"world_origin_mod", mod)
