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
var stats: Dictionary = {
	"built": 0,
	"freed": 0,
	"holes": 0,
	"pending": 0,
	"live": 0,
	"max_build_ms": 0.0,
	"collisions": 0,
	"max_update_ms": 0.0,
	"last_update_ms": 0.0,
	"queued": 0,
	"updates": 0,
	"slow_updates": 0,
	"swaps": 0,
	"swapped_this_frame": false
}

## Rectángulos globales (e0, n_sur, ancho, alto) de los micro-mapas; los pone main.
var site_rects: Array[Rect2] = []

var _results: Array = []
var _mutex := Mutex.new()
var _terrain_mat: ShaderMaterial
var _water_mesh: Dictionary = {}  # level -> PlaneMesh
var _last_center_ready: bool = true
var _primed: bool = false
var _orphans: Array[int] = []
var _gen: int = 0
var _col_enables_left: int = 1


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
	for k: String in tiles:
		_make_collision(tiles[k])  # arranque: el 3x3 inicial ya con colisión
	_primed = true


func update(gp: GlobalPos, heading: Vector2, speed: float) -> void:
	if world == null:
		return
	if not _primed:
		prime(gp)
		return
	var u0 := Time.get_ticks_usec()
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
	# pocas tareas en vuelo a la vez: los hilos no le roban CPU al hilo principal
	var inflight := 0
	for t: Dictionary in tiles.values():
		if t.state == "loading":
			inflight += 1
	var slots: int = maxi(1, int(prof.get("max_inflight", 3))) - inflight
	stats.queued = maxi(0, missing.size() - maxi(slots, 0))
	for item: Array in missing:
		if slots <= 0:
			break
		var w: Array = want[item[1]]
		_request(item[1], w[0], w[1], w[2], w[3], prof)
		slots -= 1
	var c1 := Time.get_ticks_usec()
	_finalize_results(int(prof.get("max_finalize_per_frame", 4)), int(prof.get("finalize_budget_usec", 3000)))
	_build_collisions(gp, int(prof.get("collision_budget_usec", 2500)))
	var c2 := Time.get_ticks_usec()
	stats.swapped_this_frame = false
	_update_visibility(children_wanted)
	var c3 := Time.get_ticks_usec()
	_unload(want, gp, speed)
	var c4 := Time.get_ticks_usec()
	if OS.is_debug_build() and c4 - u0 > 8000:
		print(
			(
				"[perf] teselas: previo %.1f, pedir %.1f, terminar %.1f, visibilidad %.1f, descargar %.1f ms"
				% [(c0 - u0) / 1000.0, (c1 - c0) / 1000.0, (c2 - c1) / 1000.0, (c3 - c2) / 1000.0, (c4 - c3) / 1000.0]
			)
		)
	_check_holes(gp)
	var pending := 0
	for t: Dictionary in tiles.values():
		if t.state == "loading":
			pending += 1
	stats.pending = pending
	stats.live = tiles.size()
	var ums := float(Time.get_ticks_usec() - u0) / 1000.0
	stats.last_update_ms = ums
	stats.max_update_ms = maxf(stats.max_update_ms, ums)
	stats.updates += 1
	if ums > 8.0:
		stats.slow_updates += 1


func _touches_site(level: int, i: int, j: int) -> bool:
	var sz := Geo.tile_size(level)
	var r := Rect2(Geo.tile_origin_e(level, i), Geo.tile_origin_n(level, j) - sz, sz, sz)
	for sr: Rect2 in site_rects:
		if r.intersects(sr, true):
			return true
	return false


func _request(key: String, level: int, i: int, j: int, parent: String, prof: Dictionary) -> void:
	var is_detail: bool = level == detail_level
	var step: int = int(prof.get("detail_mesh_step", 1)) if is_detail else 1
	var tex_div: int = int(prof.get("water_tex_div", 1)) if is_detail else 1
	if is_detail and _touches_site(level, i, j):
		# junto a un micro-mapa la profundidad va a resolución completa: el agua propia de la
		# zona empalma en el borde con la misma batimetría (sin línea de color)
		tex_div = 1
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
	rec.task = WorkerThreadPool.add_task(
		_build_task.bind(key, path, step, tex_div, skirt, 2 if is_detail else 1, _gen), false, "tile " + key
	)


func _build_task(key: String, path: String, step: int, tex_div: int, skirt: float, col_step: int, gen: int) -> void:
	var t0 := Time.get_ticks_usec()
	var res := TileBuilder.build(path, step, tex_div, skirt, col_step)
	res["key"] = key
	res["gen"] = gen
	# la textura geomórfica (4096 px) se decodifica aquí, en el hilo, no en el principal
	var geo_path := "res://data/tiles/L8/geo/%s.png" % key.substr(2)
	if res.get("has_water", false) and key.begins_with(str(detail_level)) and ResourceLoader.exists(geo_path):
		res["geo_tex"] = load(geo_path)
	res["build_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	_mutex.lock()
	_results.append(res)
	_mutex.unlock()


func _finalize_results(budget: int, budget_usec: int = 3000) -> void:
	var t_start := Time.get_ticks_usec()
	for idx in range(_orphans.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_orphans[idx]):
			WorkerThreadPool.wait_for_task_completion(_orphans[idx])
			_orphans.remove_at(idx)
	var done := 0
	while done < budget and Time.get_ticks_usec() - t_start < budget_usec:
		_mutex.lock()
		if _results.is_empty():
			_mutex.unlock()
			break
		var res: Dictionary = _results.pop_front()
		_mutex.unlock()
		done += 1
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
		# geomorfología del Allen Coral Atlas por tesela (planicies, lagunas, crestas)
		if level == detail_level and res.has("geo_tex"):
			mat.set_shader_parameter(&"geo_tex", res.geo_tex)
			mat.set_shader_parameter(&"use_geo", true)
			mat.set_shader_parameter(&"geo_jitter", 0.0)
		wm.material_override = mat
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wm)
	root.visible = level == coarse_level  # el detalle aparece solo en el cambio atómico
	root.set_meta(&"col_data", [res.collision, res.col_n, res.col_spacing, res.size])
	world.add_child(root)
	world.place(root, Geo.tile_origin_e(level, res.i), Geo.tile_origin_n(level, res.j), 0.0)
	return root


## Arma el cuerpo de colisión de una tesela (la parte cara: Jolt construye el heightfield).
func _make_collision(rec: Dictionary) -> void:
	var root: Node3D = rec.node
	var data: Array = root.get_meta(&"col_data")
	var body := StaticBody3D.new()
	body.collision_layer = 1  # terreno: sólido pero NO caminable
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = data[1]
	hm.map_depth = data[1]
	hm.map_data = data[0]
	cs.shape = hm
	var sp: float = data[2]
	cs.scale = Vector3(sp, sp, sp)
	cs.position = Vector3(data[3] * 0.5, 0.0, data[3] * 0.5)
	body.add_child(cs)
	root.add_child(body)
	# Se crea habilitada (Jolt arma el heightfield ahora, dentro del presupuesto) y recién
	# después se deshabilita si corresponde: re-habilitarla luego es barato. Si se creara
	# deshabilitada, el armado caería en el cuadro del cambio de nivel (el tirón de antes).
	cs.disabled = not bool(rec.get("col_on", true))
	root.remove_meta(&"col_data")
	rec.col = cs


## Colisiones pendientes: la más cercana primero, con presupuesto de tiempo por cuadro.
func _build_collisions(gp: GlobalPos, budget_usec: int) -> void:
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < budget_usec:
		var best_key := ""
		var best_d := INF
		for k: String in tiles:
			var t: Dictionary = tiles[k]
			if t.state == "ready" and t.get("col") == null:
				var d: float = Geo.tile_distance(t.level, t.i, t.j, gp.e, gp.n)
				if d < best_d:
					best_d = d
					best_key = k
		if best_key == "":
			return
		_make_collision(tiles[best_key])
		stats.collisions += 1


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
	if node != null and node.visible != v:
		node.visible = v


func _set_tile_collision(rec: Dictionary, on: bool) -> void:
	var cs: CollisionShape3D = rec.get("col")
	if cs != null and cs.disabled == on:
		# activar un campo de alturas reinserta la forma en el espacio físico (caro con 16
		# hijas a la vez): como mucho una activación por cuadro, el resto espera al siguiente
		if on:
			if _col_enables_left <= 0:
				rec.col_on = false
				return
			_col_enables_left -= 1
		cs.disabled = not on
	rec.col_on = on


func _update_visibility(children_wanted: Dictionary) -> void:
	_col_enables_left = 1
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
		# lo visual cambia de golpe (sin huecos); la colisión tosca se apaga recién cuando
		# todas las hijas ya tienen la suya (se construyen de a una por cuadro)
		var kids_col: bool = all_ready
		for kid: Dictionary in kids:
			if kid.get("col") == null or not kid.get("col_on", false):
				kids_col = false
		var node: Node3D = p.get("node")
		if node != null and node.visible == all_ready:
			stats.swaps += 1
			stats.swapped_this_frame = true
		_set_tile_visible(p, not all_ready)
		_set_tile_collision(p, not kids_col)
		for kid: Dictionary in kids:
			_set_tile_visible(kid, all_ready)
			_set_tile_collision(kid, all_ready)


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
	if stats.pending > 0 or stats.queued > 0:
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
