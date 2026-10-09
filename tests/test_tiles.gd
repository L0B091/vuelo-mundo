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
