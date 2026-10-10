class_name ReefMeshes
extends RefCounted
## Corales y anémonas procedurales (obra propia) para el lecho de los micro-mapas: cerebro
## (domo grumoso), cuerno de ciervo (ramas), mesa (disco sobre pie) y anémona (tentáculos que
## ondean en el sombreador). El color sale por instancia (MultiMesh use_colors).


static func _dome(st: SurfaceTool, c: Vector3, r: float, sy: float, lumps: float) -> void:
	var seg := 8
	var rings := 4
	for i in rings:
		var a0 := PI * 0.5 * float(i) / rings
		var a1 := PI * 0.5 * float(i + 1) / rings
		for k in seg:
			var b0 := TAU * float(k) / seg
			var b1 := TAU * float(k + 1) / seg
			var q: Array[Vector3] = []
			for ab: Vector2 in [Vector2(a0, b0), Vector2(a0, b1), Vector2(a1, b1), Vector2(a1, b0)]:
				var rr := r * (1.0 + lumps * sin(ab.y * 5.0 + ab.x * 7.0))
				q.append(c + Vector3(cos(ab.x) * cos(ab.y) * rr, sin(ab.x) * rr * sy, cos(ab.x) * sin(ab.y) * rr))
			for v: Vector3 in [q[0], q[2], q[1], q[0], q[3], q[2]]:
				st.add_vertex(v)


static func _branch(st: SurfaceTool, a: Vector3, b: Vector3, r: float) -> void:
	var d := (b - a).normalized()
	var s := d.cross(Vector3.FORWARD if absf(d.y) > 0.9 else Vector3.UP).normalized()
	var t := d.cross(s)
	var seg := 5
	for k in seg:
		var a0 := TAU * float(k) / seg
		var a1 := TAU * float(k + 1) / seg
		var o0 := (s * cos(a0) + t * sin(a0)) * r
		var o1 := (s * cos(a1) + t * sin(a1)) * r
		for v: Vector3 in [a + o0, b + o0 * 0.6, a + o1, a + o1, b + o0 * 0.6, b + o1 * 0.6]:
			st.add_vertex(v)


static func brain() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_dome(st, Vector3.ZERO, 0.6, 0.7, 0.08)
	st.generate_normals()
	return st.commit()


static func staghorn() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 9:
		var a := Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))
		var b := a + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0.4, 0.8), rng.randf_range(-0.4, 0.4))
		_branch(st, a, b, 0.05)
		var c := b + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(0.15, 0.35), rng.randf_range(-0.25, 0.25))
		_branch(st, b, c, 0.03)
	st.generate_normals()
	return st.commit()


static func table() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_branch(st, Vector3.ZERO, Vector3(0, 0.45, 0), 0.08)
	_dome(st, Vector3(0, 0.45, 0), 0.9, 0.12, 0.05)
	st.generate_normals()
	return st.commit()


static func anemone() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_dome(st, Vector3.ZERO, 0.18, 0.5, 0.0)
	for i in 22:
		var a := TAU * float(i) / 22.0
		var r := 0.08 + 0.1 * float(i % 3) / 2.0
		var base := Vector3(cos(a) * r, 0.06, sin(a) * r)
		_branch(st, base, base + Vector3(cos(a) * 0.12, 0.3, sin(a) * 0.12), 0.018)
	st.generate_normals()
	return st.commit()
