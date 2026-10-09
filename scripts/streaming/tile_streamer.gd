class_name TileStreamer
extends Node
## Capa planetaria tosca (conector) + detalle regional, en la cuadrícula global.
##
## - Nivel tosco: siempre hay un anillo de teselas vivas alrededor del avatar (radio por
##   perfil, mínimo 1 => 3x3, nunca menos) más las teselas alrededor de la posición prevista.
## - Nivel de detalle: si una tesela tosca tiene hijos de detalle y el avatar está cerca,
##   se piden TODOS sus hijos; la tosca se oculta solo cuando todos están listos (sin huecos).
## - Las teselas se construyen en hilos (WorkerThreadPool) y se terminan en el hilo
##   principal con un presupuesto por cuadro (sin bloqueo ni pantalla de carga).

signal tile_ready(key: String)

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const TILE_DIR := "res://data/tiles"

var world: WorldRoot
var coarse_level: int = 6
var detail_level: int = 8
var ratio: int = 4
var detail_parents: Dictionary = {}  # Vector2i -> true
var tiles: Dictionary = {}  # key -> Dictionary
var stats: Dictionary = {"built": 0, "freed": 0, "holes": 0, "pending": 0, "live": 0, "max_build_ms": 0.0}

var _results: Array = []
var _mutex := Mutex.new()
var _terrain_mat: ShaderMaterial
var _water_mesh: Dictionary = {}  # level -> PlaneMesh
var _last_center_ready: bool = true
var _primed: bool = false
var _orphans: Array[int] = []
var _gen: int = 0


func setup(p_world: WorldRoot) -> void:
	world = p_world
	var f := FileAccess.open(TILE_DIR + "/manifest.json", FileAccess.READ)
	if f == null:
		push_error("TileStreamer: falta data/tiles/manifest.json (correr pipeline/bake_tiles.py)")
		return
	var man: Dictionary = JSON.parse_string(f.get_as_text())
	coarse_level = int(man.get("coarse_level", 6))
	detail_level = int(man.get("detail_level", 8))
	ratio = 1 << (detail_level - coarse_level)
	var lv: Dictionary = man.get("levels", {})
	for p: Variant in lv.get("detail_parents", []):
		detail_parents[Vector2i(int(p[0]), int(p[1]))] = true
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = TERRAIN_SHADER


static func key_of(level: int, i: int, j: int) -> String:
	return "%d_%d_%d" % [level, i, j]


func tile_path(level: int, i: int, j: int) -> String:
	return "%s/L%d/%d_%d.vmt" % [TILE_DIR, level, i, j]


func has_detail(ci: int, cj: int) -> bool:
	return detail_parents.has(Vector2i(ci, cj))


## Conjunto de teselas toscas que deben estar vivas.
func wanted_coarse(gp: GlobalPos, heading: Vector2, speed: float, radius: int) -> Dictionary:
	var out: Dictionary = {}
	radius = maxi(radius, 1)
	var count: int = Geo.tile_count(coarse_level)
	var centers: Array[Vector2i] = [Geo.tile_of(coarse_level, gp.e, gp.n)]
	var p := StreamMath.predict(gp.e, gp.n, heading, speed, StreamMath.LOOKAHEAD_S)
	centers.append(Geo.tile_of(coarse_level, p[0], p[1]))
	for ct in centers:
		for dj in range(-radius, radius + 1):
			for di in range(-radius, radius + 1):
				var j: int = ct.y + dj
				if j < 0 or j >= count:
					continue
				var i: int = posmod(ct.x + di, count)
				out[Vector2i(i, j)] = true
	return out


## Arranque: construye en el acto el anillo 3x3 bajo el avatar (antes del primer cuadro
## jugable). Es lo único síncrono; después todo se carga en hilos y por adelantado.
func prime(gp: GlobalPos) -> void:
	for ct: Vector2i in wanted_coarse(gp, Vector2.ZERO, 0.0, 1):
		var key := key_of(coarse_level, ct.x, ct.y)
		var path := tile_path(coarse_level, ct.x, ct.y)
		var res := TileBuilder.build(path, 1, 1, 1500.0)
		if res.has("error"):
			continue
		res["key"] = key
		tiles[key] = {
			"state": "ready",
			"level": coarse_level,
			"i": ct.x,
			"j": ct.y,
			"parent": "",
			"node": _make_tile_node(res),
			"task": -1
		}
		stats.built += 1
	_primed = true


func update(gp: GlobalPos, heading: Vector2, speed: float) -> void:
	if world == null:
		return
	if not _primed:
		prime(gp)
	var prof: Dictionary = Quality.current
	var band: float = StreamMath.band_width(speed)
	var want: Dictionary = {}  # key -> [level, i, j, parent_key]
	var coarse := wanted_coarse(gp, heading, speed, int(prof.get("coarse_radius", 1)))
	var detail_radius: float = float(prof.get("detail_radius_m", 150000.0))
	var children_wanted: Dictionary = {}  # parent key -> true
	for ct: Vector2i in coarse:
		var ck := key_of(coarse_level, ct.x, ct.y)
		want[ck] = [coarse_level, ct.x, ct.y, ""]
		if has_detail(ct.x, ct.y):
			var d: float = Geo.tile_distance(coarse_level, ct.x, ct.y, gp.e, gp.n)
			var reach: float = detail_radius + band
			if tiles.has(key_of(detail_level, ct.x * ratio, ct.y * ratio)):
				reach *= 1.3  # histéresis: no soltar el detalle por oscilar en el límite
			if d <= reach:
				children_wanted[ck] = true
				for dj in ratio:
					for di in ratio:
						var i: int = ct.x * ratio + di
						var j: int = ct.y * ratio + dj
						want[key_of(detail_level, i, j)] = [detail_level, i, j, ck]
	# pedir lo que falta (lo más cercano primero)
	var missing: Array = []
	for k: String in want:
		if not tiles.has(k):
			var w: Array = want[k]
			missing.append([Geo.tile_distance(w[0], w[1], w[2], gp.e, gp.n), k])
	missing.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var c0 := Time.get_ticks_usec()
	for item: Array in missing:
		var w: Array = want[item[1]]
		_request(item[1], w[0], w[1], w[2], w[3], prof)
	var c1 := Time.get_ticks_usec()
	_finalize_results(int(prof.get("max_finalize_per_frame", 4)))
	var c2 := Time.get_ticks_usec()
	_update_visibility(children_wanted)
	var c3 := Time.get_ticks_usec()
	_unload(want, gp, speed)
	var c4 := Time.get_ticks_usec()
	if OS.is_debug_build() and c4 - c0 > 20000:
		print(
			(
				"[perf] teselas: pedir %.1f, terminar %.1f, visibilidad %.1f, descargar %.1f ms"
				% [(c1 - c0) / 1000.0, (c2 - c1) / 1000.0, (c3 - c2) / 1000.0, (c4 - c3) / 1000.0]
			)
		)
	_check_holes(gp)
	var pending := 0
	for t: Dictionary in tiles.values():
		if t.state == "loading":
			pending += 1
	stats.pending = pending
	stats.live = tiles.size()


func _request(key: String, level: int, i: int, j: int, parent: String, prof: Dictionary) -> void:
	var is_detail: bool = level == detail_level
	var step: int = int(prof.get("detail_mesh_step", 1)) if is_detail else 1
	var tex_div: int = int(prof.get("water_tex_div", 1)) if is_detail else 1
	var skirt: float = 400.0 if is_detail else 1500.0
	var path := tile_path(level, i, j)
	if not FileAccess.file_exists(path):
		tiles[key] = {"state": "missing", "level": level, "i": i, "j": j, "parent": parent, "node": null}
		return
	var rec := {
		"state": "loading",
		"level": level,
		"i": i,
		"j": j,
		"parent": parent,
		"node": null,
		"task": -1,
		"t0": Time.get_ticks_msec(),
		"gen": _gen + 1,
	}
	_gen += 1
	tiles[key] = rec
	rec.task = WorkerThreadPool.add_task(_build_task.bind(key, path, step, tex_div, skirt, _gen), false, "tile " + key)


func _build_task(key: String, path: String, step: int, tex_div: int, skirt: float, gen: int) -> void:
	var t0 := Time.get_ticks_usec()
	var res := TileBuilder.build(path, step, tex_div, skirt)
	res["key"] = key
	res["gen"] = gen
	res["build_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	_mutex.lock()
	_results.append(res)
	_mutex.unlock()


func _finalize_results(budget: int) -> void:
	for idx in range(_orphans.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_orphans[idx]):
			WorkerThreadPool.wait_for_task_completion(_orphans[idx])
			_orphans.remove_at(idx)
	_mutex.lock()
	var batch: Array = _results.slice(0, budget)
	_results = _results.slice(budget)
	_mutex.unlock()
	for res: Dictionary in batch:
		var key: String = res.key
		var rec: Dictionary = tiles.get(key, {})
		if rec.is_empty() or rec.state != "loading" or rec.get("gen", -1) != res.gen:
			continue  # ya no se quiere (su tarea queda en _orphans)
		WorkerThreadPool.wait_for_task_completion(rec.task)
		if res.has("error"):
			push_warning(res.error)
			rec.state = "missing"
			continue
		rec.node = _make_tile_node(res)
		rec.state = "ready"
		stats.built += 1
		stats.max_build_ms = maxf(stats.max_build_ms, res.build_ms)
		tile_ready.emit(key)


func _make_tile_node(res: Dictionary) -> Node3D:
	var level: int = res.level
	var root := Node3D.new()
	root.name = "T_" + str(res.key)
	var mi := MeshInstance3D.new()
	mi.mesh = res.mesh
	mi.material_override = _terrain_mat
	mi.set_instance_shader_parameter(&"abs_lat", res.abs_lat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if res.has_water:
		var wm := MeshInstance3D.new()
		wm.mesh = _water_plane(level, res.size)
		wm.position = Vector3(res.size * 0.5, 0.0, res.size * 0.5)
		var mat := ShaderMaterial.new()
		mat.shader = WATER_SHADER
		mat.set_shader_parameter(&"depth_tex", ImageTexture.create_from_image(res.depth_image))
		mat.set_shader_parameter(&"tex_n", float(res.depth_n))
		mat.set_shader_parameter(&"abs_lat", res.abs_lat)
		mat.set_shader_parameter(&"foam_depth", 1.2 if level == detail_level else 2.5)
		wm.material_override = mat
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wm)
	var body := StaticBody3D.new()
	body.collision_layer = 1  # terreno: sólido pero NO caminable
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	var cn: int = res.col_n
	hm.map_width = cn
	hm.map_depth = cn
	hm.map_data = res.collision
	cs.shape = hm
	var sp: float = res.col_spacing
	cs.scale = Vector3(sp, sp, sp)
	cs.position = Vector3(res.size * 0.5, 0.0, res.size * 0.5)
	body.add_child(cs)
	root.add_child(body)
	root.set_meta(&"collision", cs)
	world.add_child(root)
	world.place(root, Geo.tile_origin_e(level, res.i), Geo.tile_origin_n(level, res.j), 0.0)
	return root


func _water_plane(level: int, size: float) -> PlaneMesh:
	if not _water_mesh.has(level):
		var pm := PlaneMesh.new()
		pm.size = Vector2(size, size)
		pm.subdivide_width = 15
		pm.subdivide_depth = 15
		_water_mesh[level] = pm
	return _water_mesh[level]


func _set_tile_visible(rec: Dictionary, v: bool) -> void:
	var node: Node3D = rec.get("node")
	if node == null or node.visible == v:
		return  # solo tocar cuando cambia: re-habilitar colisión reconstruye el heightfield
	node.visible = v
	var cs: CollisionShape3D = node.get_meta(&"collision")
	cs.set_deferred(&"disabled", not v)


## Una tesela tosca con hijos se oculta solo cuando TODOS sus hijos están listos.
func _update_visibility(children_wanted: Dictionary) -> void:
	var by_parent: Dictionary = {}
	for k: String in tiles:
		var t: Dictionary = tiles[k]
		if t.parent != "":
			if not by_parent.has(t.parent):
				by_parent[t.parent] = []
			by_parent[t.parent].append(t)
	for pk: String in tiles:
		var p: Dictionary = tiles[pk]
		if p.level != coarse_level:
			continue
		var kids: Array = by_parent.get(pk, [])
		var all_ready: bool = children_wanted.has(pk) and kids.size() == ratio * ratio
		for kid: Dictionary in kids:
			if kid.state != "ready":
				all_ready = false
				break
		_set_tile_visible(p, not all_ready)
		for kid: Dictionary in kids:
			_set_tile_visible(kid, all_ready)


func _unload(want: Dictionary, gp: GlobalPos, speed: float) -> void:
	var drop: Array[String] = []
	for k: String in tiles:
		if want.has(k):
			continue
		var t: Dictionary = tiles[k]
		var d: float = Geo.tile_distance(t.level, t.i, t.j, gp.e, gp.n)
		if t.level == detail_level:
			# un hijo se suelta recién cuando su padre está listo (y por lo tanto visible)
			var parent: Dictionary = tiles.get(t.parent, {})
			if not parent.is_empty() and parent.state == "loading":
				continue
		elif not StreamMath.should_unload(d - Geo.tile_size(t.level) * 0.25, speed):
			continue
		drop.append(k)
	for k in drop:
		_free(k)


func _free(key: String) -> void:
	var t: Dictionary = tiles[key]
	if t.state == "loading" and t.task >= 0:
		_orphans.append(t.task)  # no bloquear: se recoge cuando el hilo termine
	if t.node != null:
		(t.node as Node).queue_free()
	tiles.erase(key)
	stats.freed += 1


## Hueco = el avatar está sobre una tesela tosca que no está lista (ni sus hijos).
func _check_holes(gp: GlobalPos) -> void:
	var ct := Geo.tile_of(coarse_level, gp.e, gp.n)
	var rec: Dictionary = tiles.get(key_of(coarse_level, ct.x, ct.y), {})
	var ok: bool = not rec.is_empty() and rec.state == "ready"
	if not ok and _last_center_ready:
		stats.holes += 1
		push_warning("Streaming: hueco bajo el avatar en tesela %s" % ct)
	_last_center_ready = ok


func is_idle() -> bool:
	if stats.pending > 0:
		return false
	_mutex.lock()
	var empty := _results.is_empty()
	_mutex.unlock()
	return empty


func _exit_tree() -> void:
	for task in _orphans:
		WorkerThreadPool.wait_for_task_completion(task)
	for t: Dictionary in tiles.values():
		if t.state == "loading" and t.task >= 0:
			WorkerThreadPool.wait_for_task_completion(t.task)
