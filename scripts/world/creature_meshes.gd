class_name CreatureMeshes
extends RefCounted
## Mallas procedurales de fauna marina (obra propia; sin modelos de terceros). Cuerpo de
## revolución (radios a lo largo del eje Z, +Z = cabeza) achatado/ensanchado + aletas
## triangulares. Color por vértice: lomo (top) arriba, vientre (belly) abajo.

const RINGS := 10


static func body(
	length: float, radii: Array, sx: float, sy: float, top: Color, belly: Color, seg: int = 8
) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := radii.size()
	var rings: Array = []
	for i in n:
		var z := length * 0.5 - length * float(i) / (n - 1)
		var r: float = radii[i]
		var ring: Array = []
		for k in seg:
			var a := TAU * float(k) / seg
			ring.append(Vector3(cos(a) * r * sx, sin(a) * r * sy, z))
		rings.append(ring)
	for i in n - 1:
		for k in seg:
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i][(k + 1) % seg]
			var c: Vector3 = rings[i + 1][k]
			var d: Vector3 = rings[i + 1][(k + 1) % seg]
			for v: Vector3 in [a, c, b, b, c, d]:
				st.set_color(top if v.y >= 0.0 else belly)
				st.add_vertex(v)
	return st


static func fin(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for v: Vector3 in [a, b, c]:
		st.set_color(col)
		st.add_vertex(v)


static func finish(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()


static func fish(top: Color, belly: Color) -> ArrayMesh:
	var ln := 0.28
	var st := body(ln, [0.0, 0.04, 0.06, 0.065, 0.055, 0.04, 0.025, 0.012, 0.006, 0.0], 0.45, 1.0, top, belly, 6)
	fin(st, Vector3(0, 0, -ln * 0.45), Vector3(0, 0.06, -ln * 0.62), Vector3(0, -0.06, -ln * 0.62), top)
	fin(st, Vector3(0, 0.05, 0.02), Vector3(0, 0.09, -0.04), Vector3(0, 0.04, -0.07), top)
	return finish(st)


static func shark(length: float, top: Color, belly: Color, tip: Color) -> ArrayMesh:
	var ln := length
	var r := [0.0, 0.05, 0.08, 0.095, 0.09, 0.075, 0.055, 0.035, 0.02, 0.01, 0.0]
	for i in r.size():
		r[i] = r[i] * ln
	var st := body(ln, r, 0.9, 1.0, top, belly)
	fin(st, Vector3(0, 0.08 * ln, 0.05 * ln), Vector3(0, 0.2 * ln, -0.08 * ln), Vector3(0, 0.07 * ln, -0.12 * ln), tip)
	fin(
		st,
		Vector3(0.06 * ln, -0.03 * ln, 0.12 * ln),
		Vector3(0.24 * ln, -0.08 * ln, -0.02 * ln),
		Vector3(0.05 * ln, -0.03 * ln, 0.0),
		top
	)
	fin(
		st,
		Vector3(-0.06 * ln, -0.03 * ln, 0.12 * ln),
		Vector3(-0.24 * ln, -0.08 * ln, -0.02 * ln),
		Vector3(-0.05 * ln, -0.03 * ln, 0.0),
		top
	)
	fin(st, Vector3(0, 0, -0.45 * ln), Vector3(0, 0.2 * ln, -0.62 * ln), Vector3(0, -0.1 * ln, -0.56 * ln), tip)
	return finish(st)


static func ray(span: float, length: float, top: Color, belly: Color, horns: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := span * 0.5
	var pts := [
		Vector3(0, 0.03 * span, length * 0.5),
		Vector3(h, 0, -length * 0.05),
		Vector3(0, 0.02 * span, -length * 0.5),
		Vector3(-h, 0, -length * 0.05)
	]
	var mid := Vector3(0, 0.06 * span, 0)
	for i in 4:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % 4]
		fin(st, mid, a, b, top)
		fin(st, mid - Vector3(0, 0.08 * span, 0), b, a, belly)
	# cola fina
	fin(
		st,
		Vector3(0.02 * span, 0, -length * 0.5),
		Vector3(0, 0, -length * 1.6),
		Vector3(-0.02 * span, 0, -length * 0.5),
		top
	)
	if horns:  # aletas cefálicas de la manta
		for s: float in [1.0, -1.0]:
			fin(
				st,
				Vector3(s * 0.06 * span, 0.02 * span, length * 0.5),
				Vector3(s * 0.1 * span, 0, length * 0.72),
				Vector3(s * 0.14 * span, 0, length * 0.45),
				top
			)
	return finish(st)


static func turtle() -> ArrayMesh:
	var st := body(
		1.0, [0.0, 0.25, 0.42, 0.48, 0.46, 0.38, 0.2, 0.0], 1.0, 0.38, Color(0.33, 0.26, 0.14), Color(0.78, 0.72, 0.5)
	)
	var sk := Color(0.42, 0.4, 0.3)
	for s: float in [1.0, -1.0]:
		fin(st, Vector3(s * 0.35, 0, 0.25), Vector3(s * 0.95, -0.02, 0.05), Vector3(s * 0.4, 0, -0.02), sk)
		fin(st, Vector3(s * 0.3, 0, -0.3), Vector3(s * 0.55, -0.02, -0.5), Vector3(s * 0.2, 0, -0.42), sk)
	var hd := body(0.3, [0.0, 0.08, 0.1, 0.08, 0.0], 1.0, 0.8, sk, sk, 6)
	var hm := hd.commit_to_arrays()
	var verts: PackedVector3Array = hm[Mesh.ARRAY_VERTEX]
	for v in verts:
		st.set_color(sk)
		st.add_vertex(v + Vector3(0, 0.02, 0.6))
	return finish(st)


static func dolphin() -> ArrayMesh:
	var ln := 2.4
	var r := [0.0, 0.035, 0.09, 0.15, 0.17, 0.16, 0.13, 0.09, 0.05, 0.03, 0.0]
	for i in r.size():
		r[i] = r[i] * ln * 0.6
	var top := Color(0.36, 0.4, 0.46)
	var st := body(ln, r, 0.85, 1.0, top, Color(0.78, 0.8, 0.82))
	fin(st, Vector3(0, 0.2, 0.0), Vector3(0, 0.48, -0.3), Vector3(0, 0.18, -0.4), top)
	fin(st, Vector3(0, 0, -1.1), Vector3(0.4, 0, -1.35), Vector3(-0.4, 0, -1.35), top)
	for s: float in [1.0, -1.0]:
		fin(st, Vector3(s * 0.15, -0.1, 0.45), Vector3(s * 0.5, -0.25, 0.2), Vector3(s * 0.12, -0.1, 0.2), top)
	return finish(st)
