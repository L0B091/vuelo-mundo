class_name ZoneStreamer
extends Node
## Streaming de micro-mapas (zonas "site") con banda de aviso y carga en hilo.
##
## Al entrar a la banda de un borde se emite una petición con coordenada global, rumbo y
## altitud; la escena se carga con ResourceLoader.load_threaded_request y se instancia
## (memoria + GPU) apenas está lista, antes del cruce. Sin bloqueo de control.

signal zone_loaded(id: String)
signal zone_unloaded(id: String)
signal zone_entered(id: String)

var world: WorldRoot
var index: ZoneIndex
var live: Dictionary = {}  # id -> {state, node, requested_ms, request}
var current_id: String = ""
var stats: Dictionary = {"requests": 0, "loaded": 0, "unloaded": 0, "late_crossings": 0, "last_request": {}}
## El punto de aparición no cuenta como cruce (no se llegó volando).
var _first_update: bool = true


func setup(p_world: WorldRoot, p_index: ZoneIndex) -> void:
	world = p_world
	index = p_index


func update(gp: GlobalPos, heading: Vector2, speed: float) -> void:
	if index == null:
		return
	var wanted := StreamMath.wanted_zones(index, gp.e, gp.n, gp.up, heading, speed, "site")
	for id in wanted:
		if not live.has(id):
			_request(index.get_zone(id), gp, heading)
	_poll()
	# cruce: ¿entramos a una zona? ¿estaba lista?
	var cur := index.zone_at(gp.e, gp.n, "site")
	var cid := cur.id if cur != null else ""
	if cid != current_id:
		if cur != null and cur.available and not _first_update:
			var rec: Dictionary = live.get(cid, {})
			if (rec.is_empty() or rec.state != "ready") and gp.up < StreamMath.LATE_CROSS_MAX_ALT:
				stats.late_crossings += 1
				push_warning("Streaming: se cruzó a %s antes de que estuviera lista" % cid)
		current_id = cid
		zone_entered.emit(cid)
	_first_update = false
	# descarga con histéresis (nunca la actual)
	var drop: Array[String] = []
	for id: String in live:
		if id == current_id or wanted.has(id):
			continue
		var z := index.get_zone(id)
		if StreamMath.should_unload(z.distance_3d(gp.e, gp.n, gp.up), speed):
			drop.append(id)
	for id in drop:
		_unload(id)


func _request(z: ZoneInfo, gp: GlobalPos, heading: Vector2) -> void:
	if z == null or z.scene == "":
		return
	var req := {
		"zone": z.id,
		"e": gp.e,
		"n": gp.n,
		"up": gp.up,
		"heading": Vector2(heading.x, heading.y),
		"ms": Time.get_ticks_msec()
	}
	stats.requests += 1
	stats.last_request = req
	var err := ResourceLoader.load_threaded_request(z.scene, "PackedScene", true)
	if err != OK:
		push_error("ZoneStreamer: no se pudo pedir %s (%d)" % [z.scene, err])
		return
	live[z.id] = {"state": "loading", "node": null, "request": req}


func _poll() -> void:
	for id: String in live:
		var rec: Dictionary = live[id]
		if rec.state != "loading":
			continue
		var z := index.get_zone(id)
		var st := ResourceLoader.load_threaded_get_status(z.scene)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			var ps: PackedScene = ResourceLoader.load_threaded_get(z.scene)
			var node: Node3D = ps.instantiate()
			node.name = "Zona_" + id
			node.scale = Vector3.ONE * z.local_scale
			world.add_child(node)
			world.place(node, z.origin_e, z.origin_n, 0.0)
			rec.node = node
			rec.state = "ready"
			rec["ready_ms"] = Time.get_ticks_msec()
			stats.loaded += 1
			zone_loaded.emit(id)
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("ZoneStreamer: falló la carga de %s" % z.scene)
			rec.state = "failed"


func _unload(id: String) -> void:
	var rec: Dictionary = live[id]
	if rec.state == "loading":
		return  # se descarta cuando termine; evitar abortar a mitad de carga
	if rec.node != null:
		(rec.node as Node).queue_free()
	live.erase(id)
	stats.unloaded += 1
	zone_unloaded.emit(id)


func live_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in live:
		if live[id].state == "ready":
			out.append(id)
	return out


func is_ready(id: String) -> bool:
	return live.has(id) and live[id].state == "ready"
