extends GutTest
## Conversión de coordenadas globales.


func test_lonlat_roundtrip() -> void:
	for p in [[73.5093, 4.1755], [12.4922, 41.8902], [2.2945, 48.8584], [-58.3816, -34.6037], [179.9, -60.0]]:
		var gp := GlobalPos.from_lonlat(p[0], p[1])
		assert_almost_eq(gp.lon(), float(p[0]), 1e-9)
		assert_almost_eq(gp.lat(), float(p[1]), 1e-9)


func test_known_values_epsg3857() -> void:
	# Valores de referencia EPSG:3857 calculados con pyproj 3.7 (Transformer 4326->3857): Malé
	var gp := GlobalPos.from_lonlat(73.5093, 4.1755)
	assert_almost_eq(gp.e, 8183017.84, 0.01)
	assert_almost_eq(gp.n, 465226.51, 0.01)


func test_scale_factor() -> void:
	assert_almost_eq(Geo.scale_k(0.0), 1.0, 1e-12)
	var n := Geo.lat_to_n(60.0)
	assert_almost_eq(Geo.scale_k(n), 2.0, 1e-9)  # 1/cos(60°)


func test_wrap_and_delta_across_antimeridian() -> void:
	var a := Geo.lon_to_e(179.99)
	var b := Geo.lon_to_e(-179.99)
	assert_almost_eq(Geo.delta_e(b, a), Geo.R * deg_to_rad(0.02), 1e-3)
	assert_almost_eq(Geo.wrap_e(Geo.HALF + 10.0), -Geo.HALF + 10.0, 1e-6)


func test_tile_of_and_origin_consistent() -> void:
	var gp := GlobalPos.from_lonlat(73.5093, 4.1755)
	var t := Geo.tile_of(6, gp.e, gp.n)
	assert_eq(t, Vector2i(45, 31))
	assert_eq(Geo.tile_of(8, gp.e, gp.n), Vector2i(180, 125))
	var oe := Geo.tile_origin_e(6, t.x)
	var on := Geo.tile_origin_n(6, t.y)
	assert_true(gp.e >= oe and gp.e < oe + Geo.tile_size(6))
	assert_true(gp.n <= on and gp.n > on - Geo.tile_size(6))
	assert_eq(Geo.tile_distance(6, t.x, t.y, gp.e, gp.n), 0.0)


func test_heading_vec() -> void:
	assert_almost_eq(Geo.heading_vec(0.0).y, 1.0, 1e-6)  # norte
	assert_almost_eq(Geo.heading_vec(90.0).x, 1.0, 1e-6)  # este


func test_origin_shift_preserves_global_position() -> void:
	var w := WorldRoot.new()
	add_child_autofree(w)
	var start := GlobalPos.from_lonlat(73.5, 4.17)
	w.set_origin(start.e, start.n)
	var n := Node3D.new()
	w.add_child(n)
	n.position = Vector3(3000.5, 120.0, -2500.25)
	var before := w.local_to_global(n.position)
	assert_true(w.maybe_shift(n))
	var after := w.local_to_global(n.position)
	assert_almost_eq(after.e, before.e, 1e-6)
	assert_almost_eq(after.n, before.n, 1e-6)
	assert_almost_eq(n.position.x, 0.0, 1e-3)
	assert_almost_eq(n.position.z, 0.0, 1e-3)
	assert_eq(w.shift_count, 1)
