class_name TileBuilder
extends RefCounted
## Lee teselas VMT1 y construye malla de terreno, colisión y textura de profundidad del agua.
## Pensado para correr en un hilo del WorkerThreadPool (no toca el árbol de escena).

const HEADER_SIZE: int = 36


static func read_vmt(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var magic := f.get_buffer(4).get_string_from_ascii()
	if magic != "VMT1":
		return {}
	f.get_16()  # versión
	var level := f.get_8()
	f.get_8()  # banderas
	var i := f.get_32()
	var j := f.get_32()
	var n := f.get_16()
	f.get_16()  # reservado
	var hmin := f.get_float()
	var hmax := f.get_float()
	var csize := f.get_32()
	var rsize := f.get_32()
	var raw := f.get_buffer(csize).decompress(rsize, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != rsize:
		return {}
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for k in n * n:
		heights[k] = float(raw.decode_s16(k * 2))
	var mask := raw.slice(n * n * 2, n * n * 3)
	return {"level": level, "i": i, "j": j, "n": n, "hmin": hmin, "hmax": hmax, "heights": heights, "mask": mask}


## step: decimación de la malla (1, 2, 4). tex_div: decimación de la textura de profundidad.
static func build(path: String, step: int, tex_div: int, skirt_m: float, col_step: int = 0) -> Dictionary:
	var t := read_vmt(path)
	if t.is_empty():
		return {"error": "no se pudo leer %s" % path}
	var n: int = t.n
	var level: int = t.level
	var heights: PackedFloat32Array = t.heights
	var mask: PackedByteArray = t.mask
	var size: float = Geo.tile_size(level)
	var on: float = Geo.tile_origin_n(level, t.j)
	var spacing: float = size / float(n - 1)
	step = maxi(1, step)
	while (n - 1) % step != 0:
		step -= 1
	var m: int = (n - 1) / step + 1
	var sp: float = spacing * float(step)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv2 := PackedVector2Array()
	verts.resize(m * m)
	uv2.resize(m * m)
	var col := PackedFloat32Array()
	col.resize(m * m)
	for r in m:
		var k: float = Geo.scale_k(on - float(r) * sp)
		for c in m:
			var src: int = (r * step) * n + c * step
			var h: float = heights[src]
			var y: float = h * k
			verts[r * m + c] = Vector3(float(c) * sp, y, float(r) * sp)
			uv2[r * m + c] = Vector2(h, float(mask[src]))
			col[r * m + c] = y / sp
	normals.resize(m * m)
	for r in m:
		for c in m:
			var l: float = verts[r * m + maxi(c - 1, 0)].y
			var rr: float = verts[r * m + mini(c + 1, m - 1)].y
			var u: float = verts[maxi(r - 1, 0) * m + c].y
			var d: float = verts[mini(r + 1, m - 1) * m + c].y
			var dx: float = sp * float(mini(c + 1, m - 1) - maxi(c - 1, 0))
			var dz: float = sp * float(mini(r + 1, m - 1) - maxi(r - 1, 0))
			normals[r * m + c] = Vector3(-(rr - l) / dx, 1.0, -(d - u) / dz).normalized()

	var idx := PackedInt32Array()
	idx.resize((m - 1) * (m - 1) * 6)
	var w := 0
	for r in m - 1:
		for c in m - 1:
			var a: int = r * m + c
			var b: int = a + 1
			var cc: int = a + m
			var dd: int = cc + 1
			idx[w] = a
			idx[w + 1] = b
			idx[w + 2] = cc
			idx[w + 3] = b
			idx[w + 4] = dd
			idx[w + 5] = cc
			w += 6
	_add_skirts(verts, normals, uv2, idx, m, skirt_m)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Profundidad del agua: d > 0 mar (m); d < 0 tierra (se descarta en el shader).
	tex_div = maxi(1, tex_div)
	while (n - 1) % tex_div != 0:
		tex_div -= 1
	var tn: int = (n - 1) / tex_div + 1
	var depth := PackedFloat32Array()
	depth.resize(tn * tn)
	var has_water := false
	for r in tn:
		for c in tn:
			var src: int = (r * tex_div) * n + c * tex_div
			var h: float = heights[src]
			var dv: float
			# arrecife sumergido (máscara de tierra pero bajo el nivel del mar): cuenta como agua
			if mask[src] == 0 or h < 0.0:
				dv = maxf(-h, 0.0)
				has_water = true
			else:
				dv = minf(-h, -1.0)
			depth[r * tn + c] = dv
	var img := Image.create_from_data(tn, tn, false, Image.FORMAT_RF, depth.to_byte_array())

	# Colisión: puede ser más gruesa que la malla (Jolt tarda ~6 ms en armar un heightfield
	# de 257x257 y ~1.5 ms uno de 129x129, siempre en el hilo principal).
	var cstep: int = maxi(col_step, step) if col_step > 0 else step
	while (n - 1) % cstep != 0:
		cstep -= 1
	var cm: int = (n - 1) / cstep + 1
	var csp: float = spacing * float(cstep)
	if cstep != step:
		col = PackedFloat32Array()
		col.resize(cm * cm)
		for r in cm:
			var kr: float = Geo.scale_k(on - float(r) * csp)
			for c in cm:
				col[r * cm + c] = heights[(r * cstep) * n + c * cstep] * kr / csp
	m = cm
	sp = csp

	var lat_c: float = Geo.n_to_lat(on - size * 0.5)
	return {
		"mesh": mesh,
		"collision": col,
		"col_n": m,
		"col_spacing": sp,
		"depth_image": img,
		"depth_n": tn,
		"has_water": has_water,
		"size": size,
		"abs_lat": absf(lat_c),
		"level": level,
		"i": t.i,
		"j": t.j,
		"hmin": t.hmin,
		"hmax": t.hmax,
	}


## Polleras (skirts): paredes verticales en el borde para tapar grietas entre niveles de detalle.
static func _add_skirts(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uv2: PackedVector2Array,
	idx: PackedInt32Array,
	m: int,
	depth: float
) -> void:
	var perim: Array[int] = []
	for c in m:
		perim.append(c)
	for r in range(1, m):
		perim.append(r * m + (m - 1))
	for c in range(m - 2, -1, -1):
		perim.append((m - 1) * m + c)
	for r in range(m - 2, 0, -1):
		perim.append(r * m)
	perim.append(0)
	var base: int = verts.size()
	for p in perim:
		verts.append(verts[p] - Vector3(0.0, depth, 0.0))
		normals.append(normals[p])
		uv2.append(uv2[p])
	for q in perim.size() - 1:
		var a: int = perim[q]
		var b: int = perim[q + 1]
		var sa: int = base + q
		var sb: int = base + q + 1
		idx.append_array(PackedInt32Array([a, sa, b, b, sa, sb]))
