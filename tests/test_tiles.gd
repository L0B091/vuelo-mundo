extends GutTest
## Teselas horneadas: formato, y que los bordes compartidos coincidan (sin escalón).


func _tile(level: int, i: int, j: int) -> Dictionary:
	return TileBuilder.read_vmt("res://data/tiles/L%d/%d_%d.vmt" % [level, i, j])


func test_read_coarse_tile() -> void:
	var t := _tile(6, 45, 31)
	assert_false(t.is_empty())
	assert_eq(t.n, 65)
	assert_eq((t.heights as PackedFloat32Array).size(), 65 * 65)


func test_shared_edges_match_coarse() -> void:
	var a := _tile(6, 44, 31)
	var b := _tile(6, 45, 31)
	var n: int = a.n
	for r in n:
		assert_eq(a.heights[r * n + (n - 1)], b.heights[r * n], "fila %d" % r)


func test_shared_edges_match_detail_vertical() -> void:
	var a := _tile(8, 180, 124)
	var b := _tile(8, 180, 125)
	var n: int = a.n
	var bad := 0
	for c in n:
		if a.heights[(n - 1) * n + c] != b.heights[c]:
			bad += 1
	assert_eq(bad, 0)


func test_antimeridian_edges_match() -> void:
	var w := _tile(6, 63, 20)
	var e := _tile(6, 0, 20)
	var n: int = w.n
	for r in n:
		assert_eq(w.heights[r * n + (n - 1)], e.heights[r * n])


func test_build_produces_mesh_and_collision() -> void:
	var res := TileBuilder.build("res://data/tiles/L6/45_31.vmt", 1, 1, 100.0)
	assert_false(res.has("error"))
	assert_true(res.mesh is ArrayMesh)
	assert_eq((res.collision as PackedFloat32Array).size(), 65 * 65)
	assert_true(res.has_water)


## Muestra la altura L8 (m) más cercana a una lat/lon.
func _sample_detail(lat: float, lon: float) -> float:
	var e := Geo.lon_to_e(lon)
	var n := Geo.lat_to_n(lat)
	var ij := Geo.tile_of(8, e, n)
	var t := _tile(8, ij.x, ij.y)
	var sz := Geo.tile_size(8)
	var nn: int = t.n
	var c: int = roundi((e - Geo.tile_origin_e(8, ij.x)) / sz * float(nn - 1))
	var r: int = roundi((Geo.tile_origin_n(8, ij.y) - n) / sz * float(nn - 1))
	return t.heights[r * nn + c]


func test_atoll_lagoon_is_deep() -> void:
	# centro de la laguna del atolón Malé Norte: 30-60 m según la literatura (no los -5..-15 de ETOPO)
	var d := _sample_detail(4.42, 73.52)
	assert_between(d, -70.0, -30.0, "laguna Malé Norte: %.0f m" % d)


func test_reef_flat_is_shallow() -> void:
	# borde de arrecife junto a Malé (planicie arrecifal del ACA): poco profundo
	var d := _sample_detail(4.1725, 73.5165)
	assert_between(d, -6.0, 3.0, "arrecife de Malé: %.0f m" % d)
