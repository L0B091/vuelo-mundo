class_name GlobalPos
extends RefCounted
## Posición en el sistema global (doble precisión): este, norte (m Mercator) y altitud (m).

var e: float = 0.0
var n: float = 0.0
var up: float = 0.0


func _init(p_e: float = 0.0, p_n: float = 0.0, p_up: float = 0.0) -> void:
	e = Geo.wrap_e(p_e)
	n = p_n
	up = p_up


static func from_lonlat(lon: float, lat: float, alt: float = 0.0) -> GlobalPos:
	return GlobalPos.new(Geo.lon_to_e(lon), Geo.lat_to_n(lat), alt)


func lon() -> float:
	return Geo.e_to_lon(e)


func lat() -> float:
	return Geo.n_to_lat(n)


func horizontal_distance_to(o: GlobalPos) -> float:
	var dx: float = Geo.delta_e(o.e, e)
	var dz: float = o.n - n
	return sqrt(dx * dx + dz * dz)


func _to_string() -> String:
	return "GlobalPos(lat=%.5f, lon=%.5f, up=%.1f)" % [lat(), lon(), up]
