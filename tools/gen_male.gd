extends SceneTree
## Construye las escenas del Malé real desde data/sites/<zona>/ (salida de pipeline/make_male.py):
##   godot --headless --script res://tools/gen_male.gd
## Mallas por capa con materiales PBR (Poly Haven CC0), fachadas con ventanas procedurales,
## LODs automáticos, colisión troceada en celdas (se agrega de a poco al cargar la zona),
## hitos (mezquitas, plaza, bandera), palmeras, agua/lecho propios y carteles publicitarios.

const ZONES := ["mv_male_oeste", "mv_male_este"]
const CELL := 250.0
const L_WALK := 2
const L_SOLID := 8
const TEX := "res://assets/textures/%s/%s_%s.jpg"

var _mats: Dictionary = {}
var _ad_registry: Array = []


func _init() -> void:
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
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/generated/palm_frond.png")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.8
	m.uv1_scale = Vector3(1, 1, 1)
	mesh.surface_set_material(0, m)
	ResourceSaver.save(mesh, "res://materials/palm_mesh.res")
	_mats.palm_mesh = load("res://materials/palm_mesh.res")
	return _mats.palm_mesh


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


func _build(zid: String) -> void:
	var dir := "res://data/sites/" + zid
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "/meta.json"))
	var root := Node3D.new()
	root.name = zid
	root.set_meta(&"zone_id", zid)
	var cols := Node3D.new()
	cols.name = "Colisiones"
	root.add_child(cols)
	var tri := 0
	tri += _layer(root, cols, dir, "deck", _pbr("concrete_floor_02", 1.0), L_WALK, false)
	tri += _layer(root, cols, dir, "road", _pbr("asphalt_02", 1.0), 0, false)
	tri += _layer(root, cols, dir, "sidewalk", _pbr("concrete_pavers", 1.0), 0, false)
	tri += _layer(root, cols, dir, "paint", _simple("road_paint", Color(0.92, 0.92, 0.88), 0.7), 0, false, 220.0)
	tri += _layer(root, cols, dir, "park", _pbr("sparse_grass", 1.0), 0, false)
	tri += _layer(root, cols, dir, "square", _pbr("patterned_paving", 1.0), 0, false)
	tri += _layer(root, cols, dir, "pitch", _pbr("sparse_grass", 1.0, Color(0.75, 0.95, 0.75)), 0, false)
	tri += _layer(root, cols, dir, "beach", _pbr("coast_sand_01", 1.0), L_WALK, false)
	tri += _layer(root, cols, dir, "pier", _pbr("concrete_floor_02", 1.0, Color(0.9, 0.88, 0.84)), L_WALK, false)
	tri += _layer(root, cols, dir, "breakwater", _pbr("coral_stone_wall", 1.0, Color(0.8, 0.8, 0.8)), L_SOLID, false)
	tri += _layer(
		root, cols, dir, "seawall", _pbr("coral_stone_wall", 1.0, Color(0.85, 0.85, 0.85)), L_SOLID, false, 0.0, true
	)
	tri += _layer(root, cols, dir, "walls", _facade(), L_SOLID, true, 0.0, true)
	tri += _layer(root, cols, dir, "roofs", _pbr("concrete_floor_02", 1.0, Color(0.82, 0.8, 0.78)), L_WALK, true)
	tri += _layer(root, cols, dir, "seabed", _pbr("coast_sand_01", 0.05, Color(0.85, 0.85, 0.8)), 0, false)
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
	wmat.set_shader_parameter(&"foam_depth", 0.8)
	wmat.set_shader_parameter(&"use_cut", false)
	wm.material_override = wmat
	wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wm)
	_landmarks(root, cols, meta)
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
