class_name StreamMath
extends RefCounted
## Reglas puras de streaming (sin estado, testeables).
##
## Estas constantes NO dependen del perfil gráfico: la regla "el vecino está en memoria y en
## GPU antes del cruce" no se negocia por rendimiento.

## Banda mínima de aviso antes de un borde (m).
const MIN_BAND_M: float = 400.0
## Segundos de anticipación: la banda crece con la velocidad (v * LOOKAHEAD_S).
const LOOKAHEAD_S: float = 8.0
const MAX_BAND_M: float = 120000.0
## Histéresis de descarga: se descarga cuando se supera band * UNLOAD_FACTOR + UNLOAD_EXTRA_M.
const UNLOAD_FACTOR: float = 1.5
const UNLOAD_EXTRA_M: float = 1000.0
## Por debajo de esta altitud, entrar a una zona no lista cuenta como "cruce tardío".
const LATE_CROSS_MAX_ALT: float = 3000.0


static func band_width(speed: float) -> float:
	return clampf(MIN_BAND_M + maxf(speed, 0.0) * LOOKAHEAD_S, MIN_BAND_M, MAX_BAND_M)


## Posición prevista (e, n) dentro de `seconds` siguiendo el rumbo.
static func predict(e: float, n: float, heading: Vector2, speed: float, seconds: float) -> PackedFloat64Array:
	var h := heading.normalized() if heading.length_squared() > 0.0 else Vector2.ZERO
	return PackedFloat64Array([Geo.wrap_e(e + h.x * speed * seconds), n + h.y * speed * seconds])


## Zonas (del tipo dado) que deben estar vivas para el avatar en (e, n, up) con ese rumbo
## y velocidad. Incluye: la zona actual, toda zona dentro de la banda (distancia 3D), las
## zonas sobre la trayectoria prevista, vecinos y diagonales del actual dentro de la banda,
## y garantiza al menos dos zonas vivas cuando se está dentro de una zona con vecinos.
static func wanted_zones(
	index: ZoneIndex, e: float, n: float, up: float, heading: Vector2, speed: float, kind: String = "site"
) -> PackedStringArray:
	var band: float = band_width(speed)
	var out := PackedStringArray()
	var current: ZoneInfo = index.zone_at(e, n, kind)
	if current != null and current.available:
		out.append(current.id)
	for z: ZoneInfo in index.list(kind):
		if not z.available or out.has(z.id):
			continue
		if z.distance_3d(e, n, up) <= band:
			out.append(z.id)
			continue
		# trayectoria prevista: muestras a lo largo del rumbo
		for t in [0.25, 0.5, 0.75, 1.0]:
			var p := predict(e, n, heading, speed, LOOKAHEAD_S * float(t))
			if z.distance_3d(p[0], p[1], up) <= MIN_BAND_M:
				out.append(z.id)
				break
	if current != null:
		for nb in current.neighbors:
			var z := index.get_zone(nb)
			if z != null and z.available and not out.has(nb) and z.distance_to(e, n) <= band:
				out.append(nb)  # incluye diagonales: su distancia al punto ya contempla la esquina
		if out.size() < 2:
			var best := best_neighbor_ahead(index, current, e, n, heading)
			if best != "" and not out.has(best):
				out.append(best)
	return out


## Vecino disponible más cercano en la dirección del rumbo (para la regla de dos zonas vivas).
static func best_neighbor_ahead(index: ZoneIndex, current: ZoneInfo, e: float, n: float, heading: Vector2) -> String:
	var best := ""
	var best_score := INF
	for nb in current.neighbors:
		var z := index.get_zone(nb)
		if z == null or not z.available:
			continue
		var c := z.center()
		var dir := Vector2(Geo.delta_e(c.e, e), c.n - n)
		var dist: float = z.distance_to(e, n)
		var align: float = heading.normalized().dot(dir.normalized()) if dir.length() > 0.0 else 0.0
		var score: float = dist * (1.5 - align)
		if score < best_score:
			best_score = score
			best = nb
	return best


static func should_unload(distance: float, speed: float) -> bool:
	return distance > band_width(speed) * UNLOAD_FACTOR + UNLOAD_EXTRA_M
