class_name Geo
extends RefCounted
## Sistema de coordenadas global único del proyecto.
##
## - Proyección Mercator esférica (EPSG:3857, R = 6 378 137 m). Norte siempre = -Z en Godot.
## - Coordenada global = (e, n) en metros de esa proyección + altitud `up` en metros reales.
## - Es conforme: localmente no deforma formas; la escala varía con la latitud por el factor
##   k = 1/cos(lat) = cosh(n/R). Alturas, avatar y modelos se multiplican por k para que
##   las proporciones reales se conserven (en Maldivas k ≈ 1.003).
## - GDScript usa float de 64 bits: las coordenadas globales se guardan siempre en `float`
##   (nunca en Vector2/Vector3, que son de 32 bits). Ver WorldRoot para el desplazamiento de origen.

const R: float = 6378137.0
const HALF: float = PI * R
const WORLD: float = TAU * R
const MAX_LAT: float = 85.0511287798


static func lon_to_e(lon: float) -> float:
	return R * deg_to_rad(lon)


static func lat_to_n(lat: float) -> float:
	var la: float = clampf(lat, -MAX_LAT, MAX_LAT)
	return R * log(tan(PI / 4.0 + deg_to_rad(la) / 2.0))


static func e_to_lon(e: float) -> float:
	return rad_to_deg(wrap_e(e) / R)


static func n_to_lat(n: float) -> float:
	return rad_to_deg(2.0 * atan(exp(n / R)) - PI / 2.0)


## Factor de escala de Mercator en la coordenada norte n (metros globales por metro real).
static func scale_k(n: float) -> float:
	return cosh(n / R)


## Envuelve la coordenada este al rango [-HALF, HALF).
static func wrap_e(e: float) -> float:
	return fposmod(e + HALF, WORLD) - HALF


## Diferencia este más corta a - b, consciente del antimeridiano.
static func delta_e(a: float, b: float) -> float:
	return wrap_e(a - b)


static func tile_count(level: int) -> int:
	return 1 << level


static func tile_size(level: int) -> float:
	return WORLD / float(1 << level)


## Esquina NO (origen) de la tesela (level, i, j).
static func tile_origin_e(level: int, i: int) -> float:
	return -HALF + float(i) * tile_size(level)


static func tile_origin_n(level: int, j: int) -> float:
	return HALF - float(j) * tile_size(level)


static func tile_of(level: int, e: float, n: float) -> Vector2i:
	var s: float = tile_size(level)
	var count: int = 1 << level
	var i: int = posmod(int(floor((wrap_e(e) + HALF) / s)), count)
	var j: int = clampi(int(floor((HALF - n) / s)), 0, count - 1)
	return Vector2i(i, j)


## Distancia horizontal (m globales) del punto (e, n) al rectángulo de una tesela; 0 si está dentro.
static func tile_distance(level: int, i: int, j: int, e: float, n: float) -> float:
	var s: float = tile_size(level)
	return rect_distance(tile_origin_e(level, i), tile_origin_n(level, j), s, s, e, n)


## Distancia del punto al rectángulo con esquina NO (oe, on) y tamaño (se, sn).
static func rect_distance(oe: float, on: float, se: float, sn: float, e: float, n: float) -> float:
	var lx: float = delta_e(e, oe)
	var lz: float = on - n
	var dx: float = maxf(maxf(-lx, 0.0), lx - se)
	var dz: float = maxf(maxf(-lz, 0.0), lz - sn)
	return sqrt(dx * dx + dz * dz)


## Rumbo en grados (0 = norte, 90 = este) -> vector unitario (este, norte).
static func heading_vec(heading_deg: float) -> Vector2:
	var a: float = deg_to_rad(heading_deg)
	return Vector2(sin(a), cos(a))
