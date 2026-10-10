class_name PropMeshes
extends RefCounted
## Modelos procedurales propios (CC0) para lo que no hay en Poly Haven: motos (scooters),
## autos/pickups, aires acondicionados, balcones, árboles de vereda, dhonis y gaviotas.
## Pocos triángulos, colores por vértice (y por instancia vía MultiMesh), PBR simple.


static func _add(st: SurfaceTool, m: PrimitiveMesh, x: Transform3D, c: Color) -> void:
	var a := m.get_mesh_arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var nb := x.basis.inverse().transposed()
	for i in idx:
		st.set_color(c)
		st.set_normal((nb * n[i]).normalized())
		st.add_vertex(x * v[i])


static func _box(st: SurfaceTool, size: Vector3, pos: Vector3, c: Color, rot := Basis.IDENTITY) -> void:
	var b := BoxMesh.new()
	b.size = size
	_add(st, b, Transform3D(rot, pos), c)


static func _cyl(st: SurfaceTool, r: float, h: float, pos: Vector3, c: Color, rot := Basis.IDENTITY, seg := 10) -> void:
	var cy := CylinderMesh.new()
	cy.top_radius = r
	cy.bottom_radius = r
	cy.height = h
	cy.radial_segments = seg
	cy.rings = 1
	_add(st, cy, Transform3D(rot, pos), c)


static func _sphere(st: SurfaceTool, r: float, pos: Vector3, c: Color, sc := Vector3.ONE, seg := 8) -> void:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = seg / 2
	_add(st, s, Transform3D(Basis.from_scale(sc), pos), c)


static func _mat(rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	return m


static func _commit(st: SurfaceTool, mat: Material) -> ArrayMesh:
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh


## Scooter tipo Honda Dio / Yamaha Ray (lo que se ve en Malé). Mira a +Z; el color de la
## carrocería es blanco (se tiñe por instancia con MultiMesh.use_colors).
static func scooter() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := Color(1, 1, 1)
	var dark := Color(0.06, 0.06, 0.07)
	var metal := Color(0.55, 0.56, 0.58)
	var side := Basis(Vector3.FORWARD, PI / 2)
	_cyl(st, 0.26, 0.09, Vector3(0, 0.26, 0.62), dark, side, 12)
	_cyl(st, 0.26, 0.09, Vector3(0, 0.26, -0.58), dark, side, 12)
	_box(st, Vector3(0.34, 0.32, 1.0), Vector3(0, 0.5, -0.12), body)  # cuerpo bajo
	_box(st, Vector3(0.3, 0.12, 0.62), Vector3(0, 0.74, -0.25), dark)  # asiento
	_box(st, Vector3(0.3, 0.7, 0.16), Vector3(0, 0.72, 0.5), body, Basis(Vector3.RIGHT, -0.32))  # escudo
	_cyl(st, 0.025, 0.62, Vector3(0, 1.12, 0.6), metal, side)  # manubrio
	_box(st, Vector3(0.18, 0.1, 0.12), Vector3(0, 1.08, 0.64), body)
	_box(st, Vector3(0.12, 0.06, 0.04), Vector3(0, 0.96, 0.66), Color(1.0, 0.95, 0.8))  # faro
	_box(st, Vector3(0.12, 0.05, 0.04), Vector3(0, 0.6, -0.66), Color(0.8, 0.05, 0.05))  # luz trasera
	return _commit(st, _mat(0.35, 0.1))


## Poste de alumbrado de calle (6.5 m, brazo y luminaria LED), como los de Malé.
static func street_light() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := Color(0.42, 0.44, 0.46)
	_cyl(st, 0.09, 6.5, Vector3(0, 3.25, 0), g, Basis.IDENTITY, 8)
	_cyl(st, 0.14, 0.6, Vector3(0, 0.3, 0), g, Basis.IDENTITY, 8)
	_box(st, Vector3(0.07, 0.07, 1.5), Vector3(0, 6.4, 0.72), g)
	_box(st, Vector3(0.3, 0.1, 0.6), Vector3(0, 6.38, 1.45), g)
	_box(st, Vector3(0.24, 0.02, 0.5), Vector3(0, 6.32, 1.45), Color(1.0, 0.97, 0.88))
	return _commit(st, _mat(0.45, 0.6))


## Auto chico / pickup (escala 1.25 = pickup o camioneta).
static func car() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := Color(1, 1, 1)
	var glass := Color(0.08, 0.1, 0.12)
	var dark := Color(0.05, 0.05, 0.05)
	_box(st, Vector3(1.62, 0.62, 3.7), Vector3(0, 0.6, 0), body)
	_box(st, Vector3(1.42, 0.52, 1.9), Vector3(0, 1.17, -0.2), glass)
	_box(st, Vector3(1.38, 0.06, 1.8), Vector3(0, 1.46, -0.2), body)
	var side := Basis(Vector3.FORWARD, PI / 2)
	for p: Vector3 in [
		Vector3(0.74, 0.32, 1.2), Vector3(-0.74, 0.32, 1.2), Vector3(0.74, 0.32, -1.2), Vector3(-0.74, 0.32, -1.2)
	]:
		_cyl(st, 0.31, 0.2, p, dark, side, 12)
	_box(st, Vector3(0.3, 0.1, 0.04), Vector3(0.55, 0.72, 1.86), Color(1, 0.96, 0.85))
	_box(st, Vector3(0.3, 0.1, 0.04), Vector3(-0.55, 0.72, 1.86), Color(1, 0.96, 0.85))
	return _commit(st, _mat(0.3, 0.3))


static func aircon() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0.82, 0.56, 0.3), Vector3(0, 0, 0.15), Color(0.86, 0.86, 0.84))
	_cyl(st, 0.21, 0.02, Vector3(0.12, 0, 0.305), Color(0.25, 0.26, 0.27), Basis(Vector3.RIGHT, PI / 2), 12)
	_box(st, Vector3(0.82, 0.04, 0.32), Vector3(0, -0.3, 0.16), Color(0.45, 0.45, 0.45))  # ménsula
	_cyl(st, 0.015, 1.4, Vector3(-0.36, -0.95, 0.05), Color(0.9, 0.9, 0.9))  # caño de desagüe
	return _commit(st, _mat(0.55, 0.1))


static func balcony() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color(0.9, 0.9, 0.88)
	var rail := Color(0.2, 0.22, 0.24)
	_box(st, Vector3(2.4, 0.14, 0.95), Vector3(0, 0, 0.475), c)
	_box(st, Vector3(2.4, 0.05, 0.05), Vector3(0, 1.0, 0.92), rail)
	for k in 9:
		_box(st, Vector3(0.03, 1.0, 0.03), Vector3(-1.18 + k * 0.295, 0.5, 0.92), rail)
	_box(st, Vector3(0.05, 0.05, 0.9), Vector3(1.18, 1.0, 0.47), rail)
	_box(st, Vector3(0.05, 0.05, 0.9), Vector3(-1.18, 1.0, 0.47), rail)
	return _commit(st, _mat(0.6, 0.0))


## Árbol de vereda (almendro / árbol de la lluvia, copa redondeada).
static func tree() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cyl(st, 0.18, 3.0, Vector3(0, 1.5, 0), Color(0.36, 0.28, 0.2), Basis.IDENTITY, 8)
	var g := Color(0.22, 0.42, 0.16)
	_sphere(st, 1.8, Vector3(0, 4.1, 0), g, Vector3(1.2, 0.75, 1.1))
	_sphere(st, 1.3, Vector3(1.1, 3.8, 0.3), g * 1.1, Vector3(1, 0.8, 1))
	_sphere(st, 1.2, Vector3(-0.9, 3.9, -0.5), g * 0.9, Vector3(1, 0.8, 1))
	_sphere(st, 1.1, Vector3(0.2, 4.6, -0.9), g * 1.05, Vector3(1, 0.8, 1))
	return _commit(st, _mat(0.85, 0.0))


## Dhoni (barco tradicional maldivo): casco alargado con proa alta, cabina y mástil.
static func dhoni() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hull := Color(0.92, 0.9, 0.85)
	var wood := Color(0.45, 0.3, 0.18)
	_box(st, Vector3(2.6, 0.9, 9.0), Vector3(0, 0.25, 0), hull)
	_box(st, Vector3(1.6, 0.8, 1.6), Vector3(0, 0.45, 4.9), hull, Basis(Vector3.RIGHT, -0.35))  # proa
	_box(st, Vector3(0.25, 1.6, 0.25), Vector3(0, 1.3, 5.6), wood, Basis(Vector3.RIGHT, -0.5))  # roda
	_box(st, Vector3(2.4, 0.08, 8.8), Vector3(0, 0.72, 0), wood)  # cubierta
	_box(st, Vector3(2.2, 1.5, 3.2), Vector3(0, 1.5, -2.0), Color(0.95, 0.95, 0.95))  # cabina
	_box(st, Vector3(2.6, 0.08, 4.2), Vector3(0, 2.3, -1.6), Color(0.15, 0.35, 0.6))  # toldo
	_cyl(st, 0.07, 4.5, Vector3(0, 3.0, 1.6), wood)
	return _commit(st, _mat(0.6, 0.0))


## Lancha rápida (speedboat de traslado).
static func speedboat() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(2.4, 0.8, 8.0), Vector3(0, 0.2, 0), Color(0.97, 0.97, 0.97))
	_box(st, Vector3(1.4, 0.7, 1.4), Vector3(0, 0.3, 4.3), Color(0.97, 0.97, 0.97), Basis(Vector3.RIGHT, -0.4))
	_box(st, Vector3(2.2, 0.9, 3.0), Vector3(0, 1.0, -0.5), Color(0.1, 0.12, 0.15))
	_box(st, Vector3(2.4, 0.1, 3.4), Vector3(0, 1.5, -0.6), Color(0.95, 0.95, 0.95))
	_box(st, Vector3(2.42, 0.12, 8.0), Vector3(0, -0.05, 0), Color(0.05, 0.25, 0.55))
	return _commit(st, _mat(0.3, 0.1))


## Gaviota / garza: dos alas planas (el aleteo lo hace el shader con VERTEX.x).
static func bird() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color(0.95, 0.95, 0.95)
	_sphere(st, 0.12, Vector3.ZERO, c, Vector3(0.8, 0.7, 2.2), 6)
	for sd in [-1.0, 1.0]:
		for v: Vector3 in [Vector3(0, 0, 0.12), Vector3(0.55 * sd, 0.02, -0.05), Vector3(0, 0, -0.15)]:
			st.set_color(c * 0.92)
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/birds.gdshader")
	return _commit(st, m)
