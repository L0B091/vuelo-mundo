class_name ZoneInfo
extends RefCounted
## Una zona del espacio global: guarda SOLO su origen (esquina NO) y su tamaño, en metros
## globales, y traduce la posición global del avatar a su espacio local.
## Espacio local: x = este desde el origen, z = sur desde el origen, y = altitud.

var id: String = ""
var name: String = ""
var kind: String = "site"  # "country" | "site"
var parent: String = ""
var origin_e: float = 0.0
var origin_n: float = 0.0
var size_e: float = 0.0
var size_n: float = 0.0
var neighbors: PackedStringArray = PackedStringArray()
var landing: GlobalPos = null
var scene: String = ""
var available: bool = false
## Escala uniforme aplicada a la escena (metros globales por metro real), fija por país.
var local_scale: float = 1.0


static func from_dict(d: Dictionary) -> ZoneInfo:
	var z := ZoneInfo.new()
	z.id = str(d.get("id", ""))
	z.name = str(d.get("name", z.id))
	z.kind = str(d.get("kind", "site"))
	z.parent = str(d.get("parent", ""))
	var o: Array = d.get("origin", [0.0, 0.0])
	var s: Array = d.get("size", [0.0, 0.0])
	z.origin_e = float(o[0])
	z.origin_n = float(o[1])
	z.size_e = float(s[0])
	z.size_n = float(s[1])
	z.neighbors = PackedStringArray(d.get("neighbors", []))
	var lp: Variant = d.get("landing", null)
	if lp is Array and (lp as Array).size() >= 3:
		z.landing = GlobalPos.new(float(lp[0]), float(lp[1]), float(lp[2]))
	z.scene = str(d.get("scene", ""))
	z.available = bool(d.get("available", false))
	z.local_scale = float(d.get("local_scale", 1.0))
	return z


func global_to_local(e: float, n: float, up: float = 0.0) -> Vector3:
	return Vector3(Geo.delta_e(e, origin_e), up, origin_n - n)


func local_to_global(p: Vector3) -> GlobalPos:
	return GlobalPos.new(origin_e + p.x, origin_n - p.z, p.y)


func contains(e: float, n: float) -> bool:
	var l := global_to_local(e, n)
	return l.x >= 0.0 and l.x < size_e and l.z >= 0.0 and l.z < size_n


func distance_to(e: float, n: float) -> float:
	return Geo.rect_distance(origin_e, origin_n, size_e, size_n, e, n)


## Distancia 3D aproximada (rectángulo a nivel del mar + altitud).
func distance_3d(e: float, n: float, up: float) -> float:
	var d: float = distance_to(e, n)
	var h: float = maxf(up, 0.0)
	return sqrt(d * d + h * h)


func area() -> float:
	return size_e * size_n


func center() -> GlobalPos:
	return GlobalPos.new(origin_e + size_e * 0.5, origin_n - size_n * 0.5, 0.0)
