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

## Fundido del agua en el borde de un micro-mapa: el agua de las teselas (611 m por muestra)
## se desvanece hacia dentro y la de la zona aparece en esa franja, sin escalón de color.
## Malé no: sus dos zonas comparten borde y allí dejaría ver el agua tosca entre ambas.
const DEFERRED_GROUPS := ["Detalle", "Arrecife"]
const VIS_BUDGET_USEC := 2000
const WATER_FADE_M := 200.0
const NO_WATER_FADE := ["mv_male_oeste", "mv_male_este"]

var world: WorldRoot
var index: ZoneIndex
var live: Dictionary = {}  # id -> {state, node, requested_ms, request}
var current_id: String = ""
var stats: Dictionary = {"requests": 0, "loaded": 0, "unloaded": 0, "late_crossings": 0, "last_request": {}}
## ¿El avatar está dentro de un micro-mapa listo? (el conector se recorta y no colisiona)
var inside_ready_site: bool = false
## El punto de aparición no cuenta como cruce (no se llegó volando).
var _first_update: bool = true
## Cuerpos de colisión de zonas recién cargadas, pendientes de agregar al árbol (Jolt arma
## cada malla de colisión en el hilo principal: se reparten entre cuadros, la más cercana primero).
var _pending_cols: Array = []  # [id, StaticBody3D, Node3D padre]
var _pending_vis: Array = []  # [id, nodo visual, padre]


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
	_add_pending_collisions(gp, 2500)
	_add_pending_visuals()
	_update_cuts(gp)
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
	# sin sub-hilos: con sub-hilos competía con el hilo principal (picos de 40-60 ms)
	var err := ResourceLoader.load_threaded_request(z.scene, "PackedScene", false)
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
		# ya pedida la instanciación: el recurso fue retirado y su estado deja de ser válido
		var st := (
			ResourceLoader.THREAD_LOAD_LOADED if rec.has("inst_task") else ResourceLoader.load_threaded_get_status(z.scene)
		)
		if st == ResourceLoader.THREAD_LOAD_LOADED and not rec.has("inst_task"):
			# instanciar ~1000 nodos costaba 50-85 ms en el hilo principal: se hace en un hilo
			var ps: PackedScene = ResourceLoader.load_threaded_get(z.scene)
			rec["inst_out"] = []
			var out: Array = rec.inst_out
			rec["inst_task"] = WorkerThreadPool.add_task(
				func() -> void: out.append(ps.instantiate()), true, "zona " + id
			)
			continue
		if rec.has("inst_task"):
			if not WorkerThreadPool.is_task_completed(rec.inst_task):
				continue
			WorkerThreadPool.wait_for_task_completion(rec.inst_task)
			rec.erase("inst_task")
			var node: Node3D = rec.inst_out[0]
			rec.erase("inst_out")
			# el detalle (mobiliario, corales, cables) entra de a poco en los cuadros siguientes
			for group_name: String in DEFERRED_GROUPS:
				var grp := node.get_node_or_null(NodePath(group_name))
				if grp == null:
					continue
				for b: Node in grp.get_children():
					b.owner = null
					grp.remove_child(b)
					_pending_vis.append([id, b, grp])
			node.name = "Zona_" + id
			var cols := node.get_node_or_null(^"Colisiones")
			if cols != null:
				for b: Node in cols.get_children():
					b.owner = null
					cols.remove_child(b)
					_pending_cols.append([id, b, cols])
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
	for k in range(_pending_cols.size() - 1, -1, -1):
		if _pending_cols[k][0] == id:
			(_pending_cols[k][1] as Node).free()
			_pending_cols.remove_at(k)
	for k in range(_pending_vis.size() - 1, -1, -1):
		if _pending_vis[k][0] == id:
			(_pending_vis[k][1] as Node).free()
			_pending_vis.remove_at(k)
	live.erase(id)
	stats.unloaded += 1
	zone_unloaded.emit(id)


func _add_pending_collisions(gp: GlobalPos, budget_usec: int) -> void:
	if _pending_cols.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var here := world.global_to_local(gp.e, gp.n)
	while not _pending_cols.is_empty() and Time.get_ticks_usec() - t0 < budget_usec:
		var best := 0
		var best_d := INF
		for k in _pending_cols.size():
			var parent: Node3D = _pending_cols[k][2]
			var b: Node3D = _pending_cols[k][1]
			var c: Vector3 = parent.global_transform * (b.get_meta(&"center", Vector3.ZERO) as Vector3)
			var d := Vector2(c.x - here.x, c.z - here.z).length()
			if d < best_d:
				best_d = d
				best = k
		var item: Array = _pending_cols[best]
		_pending_cols.remove_at(best)
		(item[2] as Node).add_child(item[1])


## Colisiones pendientes (0 = la zona ya es completamente sólida).
## Agrega nodos visuales diferidos dentro de un presupuesto de tiempo por cuadro.
func _add_pending_visuals() -> void:
	var t0 := Time.get_ticks_usec()
	while not _pending_vis.is_empty() and Time.get_ticks_usec() - t0 < VIS_BUDGET_USEC:
		var item: Array = _pending_vis.pop_back()
		(item[2] as Node).add_child(item[1])


func pending_collisions() -> int:
	return _pending_cols.size()


func _update_cuts(gp: GlobalPos) -> void:
	var rects: Array[Vector4] = []
	var fades: Array[float] = []
	inside_ready_site = false
	for id: String in live:
		if live[id].state != "ready":
			continue
		var z := index.get_zone(id)
		var o := world.global_to_local(z.origin_e, z.origin_n)
		rects.append(Vector4(o.x, o.z, o.x + z.size_e, o.z + z.size_n))
		fades.append(WATER_FADE_M if not id in NO_WATER_FADE else 0.0)
		if z.contains(gp.e, gp.n):
			inside_ready_site = true
	while rects.size() < 2:
		rects.append(Vector4.ZERO)
		fades.append(0.0)
	RenderingServer.global_shader_parameter_set(&"site_cut_fade", Vector2(fades[0], fades[1]))
	RenderingServer.global_shader_parameter_set(&"site_cut_a", rects[0])
	RenderingServer.global_shader_parameter_set(&"site_cut_b", rects[1])


func live_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in live:
		if live[id].state == "ready":
			out.append(id)
	return out


func is_ready(id: String) -> bool:
	return live.has(id) and live[id].state == "ready"
