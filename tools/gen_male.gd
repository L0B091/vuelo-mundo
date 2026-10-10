extends SceneTree
## Construye las escenas del Malé real desde data/sites/<zona>/ (salida de pipeline/make_male.py):
##   godot --headless --script res://tools/gen_male.gd
## Mallas por capa con materiales PBR (Poly Haven CC0), fachadas con ventanas procedurales,
## LODs automáticos, colisión troceada en celdas (se agrega de a poco al cargar la zona),
## hitos (mezquitas, plaza, bandera), palmeras, agua/lecho propios y carteles publicitarios.

const REEF_CELL := 100.0
const DETAIL_LOD := preload("res://scripts/world/detail_lod.gd")
const ZONES := ["mv_male_oeste", "mv_male_este", "mv_lankanfinolhu"]
const CELL := 250.0
const L_WALK := 2
const L_SOLID := 8
const TEX := "res://assets/textures/%s/%s_%s.jpg"

const PROP_CELL := 100.0  # celdas chicas: el rango de visibilidad del MultiMesh se mide al centro de la celda
## tipo -> [distancia de dibujo base (m), sombra]
const PROP_RANGE := {
	"lamp": [420.0, true],
	"scooter": [120.0, false],
	"car": [300.0, true],
	"bench": [150.0, false],
	"bin": [70.0, false],
	"chair": [55.0, false],
	"plant": [60.0, false],
	"ac": [130.0, false],
	"balcony": [260.0, true],
	"tree": [500.0, true],
	"lounger": [140.0, false],
	"parasol": [260.0, true],
	"taxi": [300.0, true],
	"van": [300.0, true],
	"delivery": [300.0, true],
	"suv": [300.0, true],
	"pickup": [300.0, true],
	"traffic_light": [260.0, true],
	"sign_stop": [140.0, false],
	"sign_street": [150.0, false],
	"elec_pole": [320.0, true],
	"cone": [60.0, false],
	"planter": [90.0, false],
	"fruit_stand": [90.0, false],
	"bread_stand": [80.0, false],
	"freezer": [80.0, false],
	"shop_shelf": [70.0, false],
	"crate": [60.0, false],
	"barrel": [70.0, false],
	"cafe_table": [80.0, false],
	"stool": [55.0, false],
	"roof_tank": [380.0, false],
	"antenna": [260.0, false],
	"stall_roof": [160.0, true],
	"fish_crate": [50.0, false]
}
const PH_MODEL := {
	"bin": "metal_trash_can",
	"bench": "painted_wooden_bench",
	"chair": "plastic_monobloc_chair_01",
	"plant": "potted_plant_04"
}
const SCOOTER_COLORS := [
	Color(0.9, 0.9, 0.92),
	Color(0.08, 0.08, 0.09),
	Color(0.7, 0.05, 0.06),
	Color(0.1, 0.2, 0.55),
	Color(0.55, 0.57, 0.6),
	Color(0.85, 0.7, 0.1),
	Color(0.95, 0.45, 0.65),
	Color(0.2, 0.45, 0.3)
]

var _mats: Dictionary = {}
var _ad_registry: Array = []


func _init() -> void:
	# con --headless el renderizador ficticio descarta los datos de los MultiMesh (palmeras,
	# mobiliario, corales) y la escena se guarda sin instancias: exigir un renderizador real
	if DisplayServer.get_name() == "headless":
		push_error("gen_male necesita un renderizador real: xvfb-run godot --rendering-method mobile ...")
		quit(1)
		return
	for z: String in ZONES:
		_build(z)
	var f := FileAccess.open("res://data/ad_slots.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "slots": _ad_registry}, " "))
	print("carteles: ", _ad_registry.size())
	quit()


func _pbr(id: String, uv_scale: float = 1.0, tint: Color = Color.WHITE) -> BaseMaterial3D:
	var key := "%s_%s_%s" % [id, uv_scale, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	var path := "res://materials/%s.tres" % key.replace(".", "_")
	# ORMMaterial3D: AO/rugosidad/metal empaquetados en una sola textura (arm de Poly Haven)
	var orm := ORMMaterial3D.new()
	orm.albedo_texture = load(TEX % [id, id, "diff"])
	orm.albedo_color = tint
	orm.normal_enabled = true
	orm.normal_texture = load(TEX % [id, id, "nor_gl"])
	orm.orm_texture = load(TEX % [id, id, "arm"])
	orm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	orm.uv1_scale = Vector3(uv_scale, uv_scale, 1)
	ResourceSaver.save(orm, path)
	var res: BaseMaterial3D = load(path)
	_mats[key] = res
	return res


func _facade() -> ShaderMaterial:
	if _mats.has("facade"):
		return _mats.facade
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/facade.gdshader")
	m.set_shader_parameter(&"plaster_albedo", load(TEX % ["white_stucco", "white_stucco", "diff"]))
	m.set_shader_parameter(&"plaster_normal", load(TEX % ["white_stucco", "white_stucco", "nor_gl"]))
	m.set_shader_parameter(&"plaster_orm", load(TEX % ["white_stucco", "white_stucco", "arm"]))
	m.set_shader_parameter(&"coral_albedo", load(TEX % ["coral_stone_wall", "coral_stone_wall", "diff"]))
	m.set_shader_parameter(&"coral_normal", load(TEX % ["coral_stone_wall", "coral_stone_wall", "nor_gl"]))
	m.set_shader_parameter(&"coral_orm", load(TEX % ["coral_stone_wall", "coral_stone_wall", "arm"]))
	ResourceSaver.save(m, "res://materials/facade.tres")
	_mats.facade = load("res://materials/facade.tres")
	return _mats.facade


func _simple(key: String, c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	ResourceSaver.save(m, "res://materials/%s.tres" % key)
	_mats[key] = load("res://materials/%s.tres" % key)
	return _mats[key]


## Lee una capa VMM1 -> {v, n, uv, uv2, c, i}
func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	f.get_buffer(4)
	var nv := f.get_32()
	var ni := f.get_32()
	return {
		"v": f.get_buffer(nv * 12).to_float32_array(),
		"n": f.get_buffer(nv * 12).to_float32_array(),
		"uv": f.get_buffer(nv * 8).to_float32_array(),
		"uv2": f.get_buffer(nv * 8).to_float32_array(),
		"c": f.get_buffer(nv * 16).to_float32_array(),
		"i": f.get_buffer(ni * 4).to_int32_array(),
	}


## Parte la capa en celdas de CELL m por el centroide de cada triángulo.
func _chunks(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var v: PackedFloat32Array = d.v
	var idx: PackedInt32Array = d.i
	for t in range(0, idx.size(), 3):
		var a := idx[t]
		var cx := (v[a * 3] + v[idx[t + 1] * 3] + v[idx[t + 2] * 3]) / 3.0
		var cz := (v[a * 3 + 2] + v[idx[t + 1] * 3 + 2] + v[idx[t + 2] * 3 + 2]) / 3.0
		var key := Vector2i(floori(cx / CELL), floori(cz / CELL))
		if not out.has(key):
			out[key] = PackedInt32Array()
		var arr: PackedInt32Array = out[key]
		arr.append(a)
		arr.append(idx[t + 1])
		arr.append(idx[t + 2])
		out[key] = arr
	return out


func _mesh_from(d: Dictionary, tris: PackedInt32Array, lods: bool, mat: Material) -> Array:
	# reindexa solo los vértices usados
	var remap: Dictionary = {}
	var pv := PackedVector3Array()
	var pn := PackedVector3Array()
	var puv := PackedVector2Array()
	var puv2 := PackedVector2Array()
	var pc := PackedColorArray()
	var pi := PackedInt32Array()
	var v: PackedFloat32Array = d.v
	var n: PackedFloat32Array = d.n
	var uv: PackedFloat32Array = d.uv
	var uv2: PackedFloat32Array = d.uv2
	var c: PackedFloat32Array = d.c
	var faces := PackedVector3Array()
	for a in tris:
		if not remap.has(a):
			remap[a] = pv.size()
			pv.append(Vector3(v[a * 3], v[a * 3 + 1], v[a * 3 + 2]))
			pn.append(Vector3(n[a * 3], n[a * 3 + 1], n[a * 3 + 2]))
			puv.append(Vector2(uv[a * 2], uv[a * 2 + 1]))
			puv2.append(Vector2(uv2[a * 2], uv2[a * 2 + 1]))
			pc.append(Color(c[a * 4], c[a * 4 + 1], c[a * 4 + 2], c[a * 4 + 3]))
		pi.append(remap[a])
		faces.append(Vector3(v[a * 3], v[a * 3 + 1], v[a * 3 + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pv
	arrays[Mesh.ARRAY_NORMAL] = pn
	arrays[Mesh.ARRAY_TEX_UV] = puv
	arrays[Mesh.ARRAY_TEX_UV2] = puv2
	arrays[Mesh.ARRAY_COLOR] = pc
	arrays[Mesh.ARRAY_INDEX] = pi
	var mesh: ArrayMesh
	if lods:
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mat)
		im.generate_lods(25.0, 60.0, [])
		mesh = im.get_mesh()
	else:
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, mat)
	var center := Vector3.ZERO
	for p in pv:
		center += p
	center /= maxf(1.0, float(pv.size()))
	return [mesh, faces, center]


func _own(n: Node, root: Node) -> void:
	if n != root:
		n.owner = root
	for ch in n.get_children():
		_own(ch, root)


func _layer(
	root: Node3D,
	cols: Node3D,
	dir: String,
	name: String,
	mat: Material,
	layer: int,
	lods: bool,
	vis_end: float = 0.0,
	both_sides: bool = false
) -> int:
	var d := _read("%s/%s.vmm" % [dir, name])
	if d.is_empty():
		return 0
	var tri := 0
	var ch := _chunks(d)
	for key: Vector2i in ch:
		var r := _mesh_from(d, ch[key], lods, mat)
		var mi := MeshInstance3D.new()
		mi.name = "%s_%d_%d" % [name, key.x, key.y]
		mi.mesh = r[0]
		if vis_end > 0.0:
			mi.visibility_range_end = vis_end
			mi.visibility_range_end_margin = vis_end * 0.1
		if name in ["deck", "road", "sidewalk", "paint", "park", "square", "pitch", "seabed", "beach"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		tri += (ch[key] as PackedInt32Array).size() / 3
		if layer != 0:
			var body := StaticBody3D.new()
			body.name = "col_" + mi.name
			body.collision_layer = layer
			body.collision_mask = 0
			body.set_meta(&"center", r[2])
			var cs := CollisionShape3D.new()
			var sh := ConcavePolygonShape3D.new()
			sh.backface_collision = both_sides
			sh.set_faces(r[1])
			cs.shape = sh
			body.add_child(cs)
			cols.add_child(body)
	return tri


func _palm_mesh() -> ArrayMesh:
	if _mats.has("palm_mesh"):
		return _mats.palm_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# tronco curvo, 8 lados
	var segs := 7
	var hgt := 9.0
	var pts: Array[Vector3] = []
	for s in segs + 1:
		var t := float(s) / segs
		pts.append(Vector3(sin(t * 1.2) * 0.9, t * hgt, 0))
	for s in segs:
		var r0 := lerpf(0.24, 0.15, float(s) / segs)
		var r1 := lerpf(0.24, 0.15, float(s + 1) / segs)
		for k in 8:
			var a0 := TAU * k / 8.0
			var a1 := TAU * (k + 1) / 8.0
			var p00 := pts[s] + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
			var p01 := pts[s] + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
			var p10 := pts[s + 1] + Vector3(cos(a0) * r1, 0, sin(a0) * r1)
			var p11 := pts[s + 1] + Vector3(cos(a1) * r1, 0, sin(a1) * r1)
			for q: Array in [
				[p00, a0, 0.0], [p10, a0, 1.0], [p11, a1, 1.0], [p00, a0, 0.0], [p11, a1, 1.0], [p01, a1, 0.0]
			]:
				st.set_normal(Vector3(cos(q[1]), 0.2, sin(q[1])).normalized())
				st.set_uv(Vector2(-1.0, 0.0))  # u<0 => tronco (en el shader)
				st.set_color(Color(0.42, 0.34, 0.25))
				st.add_vertex(q[0])
	# frondas: 11 cintas arqueadas con textura recortada
	var top := pts[segs]
	for f in 11:
		var ang := TAU * f / 11.0 + 0.3 * sin(f * 2.1)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := dir.cross(Vector3.UP).normalized()
		var flen := 4.2 + 0.6 * sin(f * 1.7)
		var prev_c := top
		for s in 6:
			var t0 := float(s) / 6.0
			var t1 := float(s + 1) / 6.0
			var c0 := top + dir * flen * t0 + Vector3.UP * (sin(t0 * 2.2) * 1.4 - t0 * t0 * 2.6)
			var c1 := top + dir * flen * t1 + Vector3.UP * (sin(t1 * 2.2) * 1.4 - t1 * t1 * 2.6)
			var w0 := 0.9 * sin(PI * clampf(t0 * 1.05 + 0.05, 0, 1))
			var w1 := 0.9 * sin(PI * clampf(t1 * 1.05 + 0.05, 0, 1))
			var nn := (c1 - c0).cross(side).normalized()
			if nn.y < 0:
				nn = -nn
			var quad := [
				[c0 - side * w0, Vector2(0, t0)],
				[c1 - side * w1, Vector2(0, t1)],
				[c1 + side * w1, Vector2(1, t1)],
				[c0 - side * w0, Vector2(0, t0)],
				[c1 + side * w1, Vector2(1, t1)],
				[c0 + side * w0, Vector2(1, t0)]
			]
			for q: Array in quad:
				st.set_normal(nn)
				st.set_uv(q[1])
				st.set_color(Color.WHITE)
				st.add_vertex(q[0])
			prev_c = c1
	var mesh := st.commit()
	# las palmeras se mecen con el viento (shader de vértice, sin costo de CPU)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/palm.gdshader")
	m.set_shader_parameter(&"frond", load("res://assets/generated/palm_frond.png"))
	mesh.surface_set_material(0, m)
	ResourceSaver.save(mesh, "res://materials/palm_mesh.res")
	_mats.palm_mesh = load("res://materials/palm_mesh.res")
	return _mats.palm_mesh


func _prop_mesh(kind: String) -> Mesh:
	var key := "prop_" + kind
	if _mats.has(key):
		return _mats[key]
	var mesh: Mesh
	if PropCatalog.KENNEY.has(kind):
		var sc: Node = (
			(load("res://assets/models/kenney/" + str(PropCatalog.KENNEY[kind][0])) as PackedScene).instantiate()
		)
		mesh = PropCatalog.fit_size(_merge_meshes(sc), float(PropCatalog.KENNEY[kind][1]))
		sc.free()
	elif PH_MODEL.has(kind):
		var id: String = PH_MODEL[kind]
		var sc: Node = (load("res://assets/models/%s/%s.gltf" % [id, id]) as PackedScene).instantiate()
		mesh = _merge_meshes(sc)
		sc.free()
	else:
		match kind:
			"lamp":
				mesh = PropMeshes.street_light()
			"lounger":
				mesh = PropMeshes.lounger()
			"parasol":
				mesh = PropMeshes.parasol()
			"scooter":
				mesh = PropMeshes.scooter()
			"car":
				mesh = PropMeshes.car()
			"ac":
				mesh = PropMeshes.aircon()
			"balcony":
				mesh = PropMeshes.balcony()
			"tree":
				mesh = PropMeshes.tree()
			"dhoni":
				mesh = PropMeshes.dhoni()
			"speedboat":
				mesh = PropMeshes.speedboat()
			"bird":
				mesh = PropMeshes.bird()
	if kind in ["dhoni", "speedboat"]:
		var bm := ShaderMaterial.new()
		bm.shader = load("res://shaders/boat_bob.gdshader")
		(mesh as ArrayMesh).surface_set_material(0, bm)
	if kind == "scooter":
		# color por instancia (MultiMesh.use_colors) multiplicado al color de vértice
		var mat := (mesh as ArrayMesh).surface_get_material(0) as StandardMaterial3D
		mat.vertex_color_is_srgb = true
	var path := "res://materials/prop_%s.res" % kind
	ResourceSaver.save(mesh, path)
	_mats[key] = load(path)
	return _mats[key]


## Une las superficies de todos los MeshInstance3D de un glTF en un solo ArrayMesh (con sus
## materiales), aplicando las transformaciones de los nodos.
func _merge_meshes(sc: Node) -> ArrayMesh:
	var out := ArrayMesh.new()
	var stack: Array = [[sc, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var n: Node = it[0]
		var x: Transform3D = it[1]
		if n is Node3D:
			x = x * (n as Node3D).transform if n != sc else x
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			for si in mi.mesh.get_surface_count():
				var st := SurfaceTool.new()
				st.create_from(mi.mesh, si)
				var arr := st.commit_to_arrays()
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for k in v.size():
					v[k] = x * v[k]
					if nn.size() == v.size():
						nn[k] = (x.basis * nn[k]).normalized()
				arr[Mesh.ARRAY_VERTEX] = v
				if nn.size() == v.size():
					arr[Mesh.ARRAY_NORMAL] = nn
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				var mat := mi.get_active_material(si)
				out.surface_set_material(out.get_surface_count() - 1, mat)
		for c in n.get_children():
			stack.append([c, x])
	return out


## Mobiliario y detalle urbano: un MultiMesh por tipo y por celda de 250 m; densidad y distancia
## se ajustan por perfil en tiempo de ejecución (DetailLod) sobre instancias barajadas.
func _props(root: Node3D, meta: Dictionary) -> void:
	if not meta.has("props"):
		return
	var holder := Node3D.new()
	holder.name = "Detalle"
	root.add_child(holder)
	var props: Dictionary = meta.props
	var total := 0
	for kind: String in PROP_RANGE:
		var all_items: Array = props.get(kind, [])
		# raleo: Malé tiene motos y aires por todos lados, pero el móvil no
		var every: int = {"scooter": 2}.get(kind, 1)
		var items: Array = []
		for k in all_items.size():
			if k % every == 0:
				items.append(all_items[k])
		if items.is_empty():
			continue
		var cells: Dictionary = {}
		for it: Array in items:
			var key := Vector2i(int(float(it[0]) / PROP_CELL), int(float(it[2]) / PROP_CELL))
			if not cells.has(key):
				cells[key] = []
			cells[key].append(it)
		var mesh := _prop_mesh(kind)
		for key: Vector2i in cells:
			var lst: Array = cells[key]
			# barajado determinista: un prefijo es una muestra pareja (densidad por perfil)
			var rnd := RandomNumberGenerator.new()
			rnd.seed = hash(kind) ^ (key.x * 73856093) ^ (key.y * 19349663)
			for a in range(lst.size() - 1, 0, -1):
				var b := rnd.randi_range(0, a)
				var tmp = lst[a]
				lst[a] = lst[b]
				lst[b] = tmp
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = kind == "scooter"
			mm.mesh = mesh
			mm.instance_count = lst.size()
			var org := Vector3(key.x * PROP_CELL, 0, key.y * PROP_CELL)
			for k in lst.size():
				var it: Array = lst[k]
				var b := Basis(Vector3.UP, float(it[3])).scaled(Vector3.ONE * float(it[4]))
				mm.set_instance_transform(k, Transform3D(b, Vector3(it[0], it[1], it[2]) - org))
				if mm.use_colors:
					var ci := hash(Vector2(it[0], it[2])) % SCOOTER_COLORS.size()
					mm.set_instance_color(k, SCOOTER_COLORS[ci])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%d" % [kind, key.x, key.y]
			mmi.multimesh = mm
			mmi.position = org
			mmi.cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if PROP_RANGE[kind][1]
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)
			mmi.visibility_range_end = PROP_RANGE[kind][0]
			mmi.visibility_range_end_margin = 20.0
			mmi.set_meta(&"detail_kind", kind)
			mmi.set_meta(&"detail_count", lst.size())
			mmi.set_meta(&"detail_range", PROP_RANGE[kind][0])
			mmi.set_script(DETAIL_LOD)
			holder.add_child(mmi)
			total += lst.size()
	_cables(holder, props.get("cables", []))
	_boats_birds(root, meta)
	print("  detalle urbano: %d instancias" % total)


## Arrecife: corales y anémonas sobre los píxeles "Coral/Algae" (y algo en "Rock") del mapa
## bentónico del Allen Coral Atlas, entre 0.8 y 20 m. Agrupados en celdas de 250 m con
## DetailLod (densidad y distancia por perfil).
func _reef(root: Node3D, dir: String, meta: Dictionary, depth_img: Image) -> void:
	if not ResourceLoader.exists(dir + "/benthic.png"):
		return
	var ben := (load(dir + "/benthic.png") as Texture2D).get_image()
	var w: float = meta.size[0]
	var h: float = meta.size[1]
	var dn := depth_img.get_width()
	var kinds := {
		"brain": [ReefMeshes.brain(), 0.0],
		"staghorn": [ReefMeshes.staghorn(), 0.0],
		"table": [ReefMeshes.table(), 0.0],
		"anemone": [ReefMeshes.anemone(), 0.25],
	}
	var palette := {
		"brain": [Color(0.62, 0.52, 0.32), Color(0.45, 0.5, 0.28), Color(0.7, 0.45, 0.4)],
		"staghorn": [Color(0.75, 0.62, 0.42), Color(0.55, 0.42, 0.62), Color(0.4, 0.55, 0.65)],
		"table": [Color(0.6, 0.55, 0.35), Color(0.5, 0.58, 0.45)],
		"anemone": [Color(0.85, 0.55, 0.65), Color(0.7, 0.75, 0.4), Color(0.9, 0.7, 0.45)],
	}
	var cells := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(dir)
	var tries := int(w * h / 300.0)
	for t in tries:
		var x := rng.randf() * w
		var z := rng.randf() * h
		var c := int(
			round(ben.get_pixel(int(x / w * (ben.get_width() - 1)), int(z / h * (ben.get_height() - 1))).r * 255.0)
		)
		if c != 3 and not (c == 5 and rng.randf() < 0.25):
			continue
		var d := depth_img.get_pixel(int(x / w * (dn - 1)), int(z / h * (dn - 1))).r
		if d < 0.8 or d > 20.0:
			continue
		# cabezo: un racimo de 4-14 corales/anémonas en ~5 m
		for j in rng.randi_range(4, 14):
			var cx := x + rng.randf_range(-5.0, 5.0)
			var cz := z + rng.randf_range(-5.0, 5.0)
			var cd := (
				depth_img
				. get_pixel(clampi(int(cx / w * (dn - 1)), 0, dn - 1), clampi(int(cz / h * (dn - 1)), 0, dn - 1))
				. r
			)
			if cd < 0.8:
				continue
			var roll := rng.randf()
			var kind := (
				"brain" if roll < 0.4 else ("staghorn" if roll < 0.7 else ("table" if roll < 0.85 else "anemone"))
			)
			var key := Vector2i(int(cx / REEF_CELL), int(cz / REEF_CELL))
			if not cells.has(key):
				cells[key] = {}
			if not cells[key].has(kind):
				cells[key][kind] = []
			var sc := rng.randf_range(0.6, 1.8) * (0.6 if kind == "anemone" else 1.0)
			cells[key][kind].append([cx, -maxf(cd, 0.5) - 0.05, cz, rng.randf() * TAU, sc])
	var holder := Node3D.new()
	holder.name = "Arrecife"
	root.add_child(holder)
	var total := 0
	for key: Vector2i in cells:
		for kind: String in cells[key]:
			var lst: Array = cells[key][kind]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = kinds[kind][0]
			mm.instance_count = lst.size()
			var org := Vector3(key.x * REEF_CELL, 0, key.y * REEF_CELL)
			var pal: Array = palette[kind]
			# sin esto el AABB del MultiMesh guardado queda en cero y se descarta al dibujar
			mm.custom_aabb = AABB(Vector3(-4, -40, -4), Vector3(REEF_CELL + 8, 44, REEF_CELL + 8))
			for k in lst.size():
				var it: Array = lst[k]
				var b := Basis(Vector3.UP, float(it[3])).scaled(Vector3.ONE * float(it[4]))
				mm.set_instance_transform(k, Transform3D(b, Vector3(it[0], it[1], it[2]) - org))
				mm.set_instance_color(k, pal[k % pal.size()])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "coral_%s_%d_%d" % [kind, key.x, key.y]
			mmi.multimesh = mm
			mmi.position = org
			var m := ShaderMaterial.new()
			m.shader = load("res://shaders/reef.gdshader")
			m.set_shader_parameter(&"sway", kinds[kind][1])
			mmi.material_override = m
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.set_meta(&"detail_kind", "coral")
			mmi.set_meta(&"detail_count", lst.size())
			mmi.set_meta(&"detail_range", 90.0)
			mmi.visibility_range_end = 90.0
			mmi.set_script(DETAIL_LOD)
			holder.add_child(mmi)
			total += lst.size()
	print("  arrecife: %d corales/anémonas" % total)


## Cables entre postes: cintas finas con catenaria, una malla por zona.
func _cables(holder: Node3D, cables: Array) -> void:
	if cables.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c: Array in cables:
		var a := Vector3(c[0], c[1], c[2])
		var b := Vector3(c[3], c[4], c[5])
		var segs := 8
		var sag := a.distance_to(b) * 0.04
		for wire in 2:
			var off := Vector3(0, -0.35 * wire, 0)
			for k in segs:
				var t0 := float(k) / segs
				var t1 := float(k + 1) / segs
				var p0 := a.lerp(b, t0) + off + Vector3(0, -sag * 4.0 * t0 * (1.0 - t0), 0)
				var p1 := a.lerp(b, t1) + off + Vector3(0, -sag * 4.0 * t1 * (1.0 - t1), 0)
				var w := Vector3(0, 0.025, 0)
				for v: Vector3 in [p0 - w, p1 - w, p1 + w, p0 - w, p1 + w, p0 + w]:
					st.set_normal(Vector3.UP)
					st.add_vertex(v)
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.05, 0.05)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.6
	mesh.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.name = "Cables"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 250.0
	holder.add_child(mi)


## Barcos fondeados que se mecen (puerto/malecón) y gaviotas en círculos sobre la costa.
func _boats_birds(root: Node3D, meta: Dictionary) -> void:
	var boats: Array = meta.get("boats", [])
	for kind: String in ["dhoni", "speedboat"]:
		var lst: Array = []
		for k in boats.size():
			if (k % 3 == 0) == (kind == "speedboat"):
				lst.append(boats[k])
		if lst.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _prop_mesh(kind)
		mm.instance_count = lst.size()
		for k in lst.size():
			var it: Array = lst[k]
			var b := Basis(Vector3.UP, float(it[3])).scaled(Vector3.ONE * float(it[4]) * 0.9)
			mm.set_instance_transform(k, Transform3D(b, Vector3(it[0], -0.1, it[2])))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Barcos_" + kind
		mmi.multimesh = mm
		mmi.visibility_range_end = 1500.0
		root.add_child(mmi)
	# gaviotas: 3 bandadas sobre la costa
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.use_custom_data = true
	mm2.mesh = _prop_mesh("bird")
	var n_b := 24
	mm2.instance_count = n_b
	var rnd := RandomNumberGenerator.new()
	rnd.seed = hash(meta.id)
	var w: float = meta.size[0]
	var h: float = meta.size[1]
	for k in n_b:
		var c := Vector3(rnd.randf_range(0.1, 0.9) * w, meta.deck_y + 22.0, rnd.randf_range(0.1, 0.9) * h)
		mm2.set_instance_transform(k, Transform3D(Basis.IDENTITY, c))
		mm2.set_instance_custom_data(k, Color(rnd.randf(), rnd.randf(), rnd.randf(), rnd.randf()))
	var bi := MultiMeshInstance3D.new()
	bi.name = "Gaviotas"
	bi.multimesh = mm2
	bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bi.visibility_range_end = 600.0
	bi.custom_aabb = AABB(Vector3(-50, -20, -50), Vector3(w + 100, 80, h + 100))
	root.add_child(bi)


func _centroid(poly: Array) -> Vector3:
	var c := Vector2.ZERO
	for p: Array in poly:
		c += Vector2(p[0], p[1])
	c /= maxf(1.0, poly.size())
	return Vector3(c.x, 0, c.y)


func _prim(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3, name: String, solid: bool, cols: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)
	if solid:
		var b := StaticBody3D.new()
		b.name = "col_" + name
		b.collision_layer = L_SOLID
		b.collision_mask = 0
		b.position = pos
		b.set_meta(&"center", Vector3.ZERO)
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_convex_shape()
		b.add_child(cs)
		cols.add_child(b)


func _landmarks(root: Node3D, cols: Node3D, meta: Dictionary) -> void:
	var deck: float = meta.deck_y
	var lm := Node3D.new()
	lm.name = "Hitos"
	root.add_child(lm)
	var gold := _simple("gold", Color(0.86, 0.66, 0.24), 0.28, 1.0)
	var white := _simple("white_paint", Color(0.93, 0.93, 0.9), 0.6)
	for l: Dictionary in meta.landmarks:
		var c := _centroid(l.poly)
		match l.kind:
			"islamic_centre":
				# cúpula dorada sobre tambor + alminar (diseño propio inspirado en el Centro Islámico)
				var drum := CylinderMesh.new()
				drum.top_radius = 9.5
				drum.bottom_radius = 9.5
				drum.height = 4.0
				_prim(lm, drum, white, c + Vector3(0, deck + 14.0 + 2.0, 0), "IslamicCentre_tambor", true, cols)
				var dome := SphereMesh.new()
				dome.radius = 9.6
				dome.height = 14.0
				dome.is_hemisphere = false
				_prim(lm, dome, gold, c + Vector3(0, deck + 18.0, 0), "IslamicCentre_cupula", false, cols)
				var fin := CylinderMesh.new()
				fin.top_radius = 0.05
				fin.bottom_radius = 0.35
				fin.height = 4.0
				_prim(lm, fin, gold, c + Vector3(0, deck + 27.0, 0), "IslamicCentre_remate", false, cols)
				var mn := CylinderMesh.new()
				mn.top_radius = 1.6
				mn.bottom_radius = 2.0
				mn.height = 40.0
				var mpos := c + Vector3(22.0, deck + 20.0, -12.0)
				_prim(lm, mn, white, mpos, "IslamicCentre_alminar", true, cols)
				var cap := CylinderMesh.new()
				cap.top_radius = 0.0
				cap.bottom_radius = 2.2
				cap.height = 6.0
				_prim(lm, cap, gold, mpos + Vector3(0, 23.0, 0), "IslamicCentre_alminar_punta", false, cols)
			"republic_square":
				var pole := CylinderMesh.new()
				pole.top_radius = 0.12
				pole.bottom_radius = 0.22
				pole.height = 30.0
				_prim(lm, pole, white, c + Vector3(0, deck + 15.0, 0), "Plaza_mastil", true, cols)
				var flag := QuadMesh.new()
				flag.size = Vector2(9.0, 6.0)
				var fm := StandardMaterial3D.new()
				fm.albedo_texture = load("res://assets/generated/flag_mv.png")
				fm.cull_mode = BaseMaterial3D.CULL_DISABLED
				fm.roughness = 0.9
				var fl := MeshInstance3D.new()
				fl.name = "Plaza_bandera_Maldivas"
				fl.mesh = flag
				fl.material_override = fm
				fl.position = c + Vector3(4.7, deck + 26.5, 0)
				lm.add_child(fl)
			"hukuru_miskiy":
				var mn2 := CylinderMesh.new()
				mn2.top_radius = 1.1
				mn2.bottom_radius = 1.4
				mn2.height = 14.0
				_prim(lm, mn2, white, c + Vector3(-18, deck + 7.0, 10), "HukuruMiskiy_munnaaru", true, cols)
				var cap2 := CylinderMesh.new()
				cap2.top_radius = 0.0
				cap2.bottom_radius = 1.5
				cap2.height = 3.0
				_prim(lm, cap2, white, c + Vector3(-18, deck + 15.5, 10), "HukuruMiskiy_punta", false, cols)


func _ads(root: Node3D, meta: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "Carteles"
	root.add_child(node)
	var base := StandardMaterial3D.new()
	base.albedo_texture = load("res://assets/generated/ad_placeholder.png")
	base.emission_enabled = true
	base.emission_texture = base.albedo_texture
	base.emission_energy_multiplier = 0.35
	base.roughness = 0.5
	ResourceSaver.save(base, "res://materials/ad_slot.tres")
	var mat: Material = load("res://materials/ad_slot.tres")
	var script: Script = load("res://scripts/world/ad_slot.gd")
	for a: Dictionary in meta.ad_slots:
		var s := MeshInstance3D.new()
		s.set_script(script)
		s.name = a.id
		var q := QuadMesh.new()
		q.size = Vector2(a.size[0], a.size[1])
		s.mesh = q
		s.material_override = mat
		s.set(&"ad_id", a.id)
		s.set(&"slot_size", Vector2(a.size[0], a.size[1]))
		var p := Vector3(a.pos[0], a.pos[1], a.pos[2])
		var nrm := Vector3(a.normal[0], 0, a.normal[2])
		s.position = p
		s.basis = Basis.looking_at(-nrm, Vector3.UP)
		s.visibility_range_end = 350.0
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(s)
		_ad_registry.append(
			{
				"id": a.id,
				"zone": meta.id,
				"pos_local": a.pos,
				"normal": a.normal,
				"size_m": a.size,
				"texture": "res://assets/generated/ad_placeholder.png"
			}
		)


## Resort sobre el agua: arena, jardín, senderos, muelles de madera en pilotes, villas con
## paredes de tablas y techos de paja (texturas Poly Haven CC0).
func _resort_layers(root: Node3D, cols: Node3D, dir: String, meta: Dictionary) -> int:
	var t := 0
	t += _layer(root, cols, dir, "deck", _pbr("coast_sand_01", 1.0, Color(1.12, 1.1, 1.04)), L_WALK, false)
	t += _layer(root, cols, dir, "beach", _pbr("coast_sand_01", 1.0), L_WALK, false)
	t += _layer(root, cols, dir, "park", _pbr("sparse_grass", 1.0, Color(0.72, 1.0, 0.55)), L_WALK, false)
	t += _layer(root, cols, dir, "sidewalk", _pbr("coast_sand_01", 1.0, Color(0.92, 0.88, 0.8)), 0, false)
	t += _layer(root, cols, dir, "pier", _pbr("wood_floor_deck", 1.0), L_WALK, false)
	t += _layer(root, cols, dir, "stilts", _pbr("wood_floor_deck", 1.0, Color(0.7, 0.6, 0.5)), 0, true, 350.0, true)
	t += _layer(root, cols, dir, "walls", _pbr("white_planks_clean", 1.0), L_SOLID, true, 0.0, true)
	t += _layer(root, cols, dir, "roofs", _pbr("white_planks_clean", 1.0), L_WALK, true)
	t += _layer(root, cols, dir, "glass", _simple("villa_glass", Color(0.12, 0.18, 0.22), 0.05, 0.6), 0, false, 400.0)
	t += _layer(root, cols, dir, "frames", _simple("villa_frame", Color(0.35, 0.25, 0.17), 0.6), 0, false, 300.0)
	t += _layer(root, cols, dir, "thatch", _pbr("thatch_roof_angled", 1.0, Color(1.0, 0.86, 0.66)), 0, true)
	t += _layer(
		root, cols, dir, "seabed", _seabed(Color(0.9, 0.9, 0.85), dir, Vector2(meta.size[0], meta.size[1])), 0, false
	)
	return t


## Lecho marino: arena PBR + pasada aditiva de cáusticas (intensidad global por perfil).
func _seabed(tint: Color, dir: String = "", size: Vector2 = Vector2.ZERO) -> Material:
	var m: Material = (_pbr("coast_sand_01", 0.05, tint) as Material).duplicate()
	if dir != "" and ResourceLoader.exists(dir + "/benthic.png"):
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/seabed.gdshader")
		sm.set_shader_parameter(&"benthic", load(dir + "/benthic.png"))
		sm.set_shader_parameter(&"zone_size", size)
		sm.set_shader_parameter(&"sand_albedo", load(TEX % ["coast_sand_01", "coast_sand_01", "diff"]))
		sm.set_shader_parameter(&"sand_normal", load(TEX % ["coast_sand_01", "coast_sand_01", "nor_gl"]))
		sm.set_shader_parameter(&"tint", tint)
		if ResourceLoader.exists(dir + "/s2_tint.png"):
			var s2: Texture2D = load(dir + "/s2_tint.png")
			var im := s2.get_image()
			im.decompress()
			var acc := Vector3.ZERO
			for y in im.get_height():
				for x in im.get_width():
					var c := im.get_pixel(x, y).srgb_to_linear()
					acc += Vector3(c.r, c.g, c.b)
			sm.set_shader_parameter(&"s2_tint", s2)
			sm.set_shader_parameter(&"s2_mean", acc / float(im.get_width() * im.get_height()))
			sm.set_shader_parameter(&"s2_strength", 0.45)
		m = sm
	var c := ShaderMaterial.new()
	c.shader = load("res://shaders/caustics.gdshader")
	m.next_pass = c
	return m


func _build(zid: String) -> void:
	var dir := "res://data/sites/" + zid
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "/meta.json"))
	var root := Node3D.new()
	root.name = zid
	root.set_meta(&"zone_id", zid)
	root.set_meta(&"npc_paths", meta.get("paths", {}))
	root.set_meta(&"deck_y", meta.deck_y)
	var cols := Node3D.new()
	cols.name = "Colisiones"
	root.add_child(cols)
	var tri := 0
	if meta.get("style", "") == "resort":
		tri += _resort_layers(root, cols, dir, meta)
	else:
		tri += _layer(root, cols, dir, "deck", _pbr("concrete_floor_02", 1.0), L_WALK, false)
		tri += _layer(root, cols, dir, "road", _pbr("asphalt_02", 1.0), 0, false)
		tri += _layer(root, cols, dir, "sidewalk", _pbr("concrete_pavers", 1.0), 0, false)
		tri += _layer(root, cols, dir, "paint", _simple("road_paint", Color(0.92, 0.92, 0.88), 0.7), 0, false, 220.0)
		tri += _layer(root, cols, dir, "park", _pbr("sparse_grass", 1.0), 0, false)
		tri += _layer(root, cols, dir, "square", _pbr("patterned_paving", 1.0), 0, false)
		tri += _layer(root, cols, dir, "pitch", _pbr("sparse_grass", 1.0, Color(0.75, 0.95, 0.75)), 0, false)
		tri += _layer(root, cols, dir, "beach", _pbr("coast_sand_01", 1.0), L_WALK, false)
		tri += _layer(root, cols, dir, "pier", _pbr("concrete_floor_02", 1.0, Color(0.9, 0.88, 0.84)), L_WALK, false)
		tri += _layer(
			root, cols, dir, "breakwater", _pbr("coral_stone_wall", 1.0, Color(0.8, 0.8, 0.8)), L_SOLID, false
		)
		tri += _layer(
			root,
			cols,
			dir,
			"seawall",
			_pbr("coral_stone_wall", 1.0, Color(0.85, 0.85, 0.85)),
			L_SOLID,
			false,
			0.0,
			true
		)
		tri += _layer(root, cols, dir, "walls", _facade(), L_SOLID, true, 0.0, true)
		tri += _layer(root, cols, dir, "roofs", _pbr("concrete_floor_02", 1.0, Color(0.82, 0.8, 0.78)), L_WALK, true)
		tri += _layer(
			root,
			cols,
			dir,
			"seabed",
			_seabed(Color(0.85, 0.85, 0.8), dir, Vector2(meta.size[0], meta.size[1])),
			0,
			false
		)
	# agua propia (el conector se recorta dentro del rectángulo de la zona)
	var n: int = meta.depth_n
	var raw := FileAccess.get_file_as_bytes(dir + "/depth.f32")
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RF, raw)
	var wm := MeshInstance3D.new()
	wm.name = "Agua"
	var pm := PlaneMesh.new()
	pm.size = Vector2(meta.size[0], meta.size[1])
	pm.subdivide_width = 31
	pm.subdivide_depth = 31
	wm.mesh = pm
	wm.position = Vector3(meta.size[0] * 0.5, 0.0, meta.size[1] * 0.5)
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://shaders/water.gdshader")
	wmat.set_shader_parameter(&"depth_tex", ImageTexture.create_from_image(img))
	wmat.set_shader_parameter(&"tex_n", float(n))
	wmat.set_shader_parameter(&"abs_lat", 4.17)
	wmat.set_shader_parameter(&"foam_depth", 1.2)  # igual que el agua de las teselas L8
	wmat.set_shader_parameter(&"use_cut", false)
	if str(meta.get("style", "")) == "resort":
		# se funde con el agua de las teselas en los 200 m del borde (ZoneStreamer.WATER_FADE_M)
		wmat.set_shader_parameter(&"zone_size", Vector2(meta.size[0], meta.size[1]))
		wmat.set_shader_parameter(&"zone_fade_m", 200.0)
	if ResourceLoader.exists(dir + "/geomorph.png"):
		wmat.set_shader_parameter(&"geo_tex", load(dir + "/geomorph.png"))
		wmat.set_shader_parameter(&"use_geo", true)
	wm.material_override = wmat
	wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wm)
	_landmarks(root, cols, meta)
	_reef(root, dir, meta, img)
	# palmeras (MultiMesh: un solo dibujo por zona)
	var palms: Array = meta.palms
	if not palms.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _palm_mesh()
		mm.instance_count = palms.size()
		for k in palms.size():
			var p: Array = palms[k]
			var b := Basis(Vector3.UP, deg_to_rad(p[2])).scaled(Vector3.ONE * float(p[3]))
			mm.set_instance_transform(k, Transform3D(b, Vector3(p[0], meta.deck_y, p[1])))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Palmeras"
		mmi.multimesh = mm
		mmi.visibility_range_end = 900.0
		root.add_child(mmi)
	_ads(root, meta)
	_props(root, meta)
	_own(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	var out := "res://scenes/zones/%s.scn" % zid
	var err := ResourceSaver.save(ps, out, ResourceSaver.FLAG_COMPRESS)
	print(
		(
			"%s: %d triángulos, %d cuerpos de colisión, %d carteles -> %s (%d)"
			% [zid, tri, cols.get_child_count(), meta.ad_slots.size(), out, err]
		)
	)
	root.free()
