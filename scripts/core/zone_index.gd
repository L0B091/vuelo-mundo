class_name ZoneIndex
extends RefCounted
## Índice mínimo de zonas: id, origen, tamaño, vecinos, punto de aterrizaje.
## Se genera con pipeline/make_zone_index.py en data/zone_index.json.

var zones: Dictionary = {}  # id -> ZoneInfo
var version: int = 0


static func load_from(path: String) -> ZoneIndex:
	var idx := ZoneIndex.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("ZoneIndex: no se pudo abrir %s" % path)
		return idx
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		push_error("ZoneIndex: JSON inválido en %s" % path)
		return idx
	idx.version = int((data as Dictionary).get("version", 0))
	for zd: Variant in (data as Dictionary).get("zones", []):
		var z := ZoneInfo.from_dict(zd as Dictionary)
		idx.zones[z.id] = z
	return idx


func get_zone(id: String) -> ZoneInfo:
	return zones.get(id, null)


func list(kind: String = "") -> Array[ZoneInfo]:
	var out: Array[ZoneInfo] = []
	for z: ZoneInfo in zones.values():
		if kind == "" or z.kind == kind:
			out.append(z)
	return out


## Zona más chica que contiene (e, n), opcionalmente filtrando por tipo.
func zone_at(e: float, n: float, kind: String = "") -> ZoneInfo:
	var best: ZoneInfo = null
	for z: ZoneInfo in zones.values():
		if kind != "" and z.kind != kind:
			continue
		if z.contains(e, n) and (best == null or z.area() < best.area()):
			best = z
	return best


## Devuelve una lista de problemas (vacía si el índice es coherente).
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	for z: ZoneInfo in zones.values():
		if z.size_e <= 0.0 or z.size_n <= 0.0:
			errs.append("%s: tamaño inválido" % z.id)
		if z.available and z.landing == null:
			errs.append("%s: sin punto de aterrizaje" % z.id)
		if z.landing != null and not z.contains(z.landing.e, z.landing.n):
			errs.append("%s: el punto de aterrizaje cae fuera de la zona" % z.id)
		if z.available and z.kind == "site" and z.scene == "":
			errs.append("%s: sitio disponible sin escena" % z.id)
		for nb in z.neighbors:
			var o := get_zone(nb)
			if o == null:
				errs.append("%s: vecino inexistente %s" % [z.id, nb])
			elif not o.neighbors.has(z.id):
				errs.append("%s: vecindad no simétrica con %s" % [z.id, nb])
	return errs
