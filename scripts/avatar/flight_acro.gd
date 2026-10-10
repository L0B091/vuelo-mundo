class_name FlightAcro
extends RefCounted
## Acrobacias de vuelo: tonel (barrel roll), rizo (loop), mortal (flip), giro sobre sí mismo
## (spin) y esquive lateral (dodge). Lógica pura y determinista (se prueba sin escena):
## cada truco da, en función del tiempo, rotaciones extra del cuerpo/cámara (grados) y una
## velocidad adicional en ejes locales (x derecha, y arriba, z adelante) en m/s.

const TRICKS := {
	"roll_left": {"dur": 0.85, "min_speed": 15.0},
	"roll_right": {"dur": 0.85, "min_speed": 15.0},
	"loop": {"dur": 2.4, "min_speed": 40.0},
	"flip": {"dur": 0.9, "min_speed": 0.0},
	"spin": {"dur": 1.0, "min_speed": 0.0},
	"dodge_left": {"dur": 0.45, "min_speed": 0.0},
	"dodge_right": {"dur": 0.45, "min_speed": 0.0},
}

var kind: String = ""
var t: float = 0.0
var dur: float = 0.0
var count: int = 0  # trucos completados (estadística / pruebas)
## salidas del último paso
var roll: float = 0.0
var pitch: float = 0.0
var yaw: float = 0.0
var vel_local: Vector3 = Vector3.ZERO
var _speed: float = 0.0


func active() -> bool:
	return kind != ""


## Intenta empezar un truco. Devuelve false si ya hay uno en curso o falta velocidad.
func start(name: String, speed: float) -> bool:
	if active() or not TRICKS.has(name):
		return false
	if speed < float(TRICKS[name].min_speed):
		return false
	kind = name
	t = 0.0
	dur = float(TRICKS[name].dur)
	_speed = speed
	return true


static func ease_io(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func step(dt: float) -> void:
	roll = 0.0
	pitch = 0.0
	yaw = 0.0
	vel_local = Vector3.ZERO
	if not active():
		return
	t += dt
	var u := clampf(t / dur, 0.0, 1.0)
	var e := ease_io(u)
	match kind:
		"roll_left", "roll_right":
			var s := -1.0 if kind == "roll_left" else 1.0
			roll = 360.0 * e * s
			# el tonel desplaza en espiral: un poco al costado y arriba
			vel_local = Vector3(s * sin(u * PI) * 9.0, sin(u * TAU) * 4.0, 0.0)
		"loop":
			pitch = 360.0 * e
			# círculo vertical de radio ~ v/ω: la velocidad hacia adelante se rota hacia arriba
			var a := e * TAU
			var v := maxf(_speed, 40.0)
			vel_local = Vector3(0.0, sin(a) * v, (cos(a) - 1.0) * v)
		"flip":
			pitch = -360.0 * e
			vel_local = Vector3(0.0, sin(u * PI) * 6.0, 0.0)
		"spin":
			yaw = 360.0 * e
		"dodge_left", "dodge_right":
			var s2 := -1.0 if kind == "dodge_left" else 1.0
			vel_local = Vector3(s2 * 32.0 * (1.0 - u) * (1.0 - u) * 2.2, 0.0, 0.0)
			roll = s2 * 50.0 * sin(u * PI)
	if u >= 1.0:
		kind = ""
		count += 1
		roll = 0.0
		pitch = 0.0
		yaw = 0.0
		vel_local = Vector3.ZERO


## Gesto táctil -> truco: deslizar izq/der = tonel, arriba = rizo, abajo = mortal,
## doble toque = esquive hacia el lado tocado, deslizar en círculo no (se usa spin con 2 dedos).
static func from_swipe(delta: Vector2, min_px: float = 90.0) -> String:
	if delta.length() < min_px:
		return ""
	if absf(delta.x) > absf(delta.y) * 1.3:
		return "roll_right" if delta.x > 0.0 else "roll_left"
	if absf(delta.y) > absf(delta.x) * 1.3:
		return "flip" if delta.y > 0.0 else "loop"
	return ""
