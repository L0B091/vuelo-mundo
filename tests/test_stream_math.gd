extends GutTest
## Banda de aviso y selección de zonas vivas.

var idx: ZoneIndex
var a: ZoneInfo
var b: ZoneInfo


func before_all() -> void:
	idx = ZoneIndex.load_from("res://data/zone_index.json")
	a = idx.get_zone("mv_test_male_oeste")
	b = idx.get_zone("mv_test_male_este")


func test_band_widens_with_speed() -> void:
	assert_eq(StreamMath.band_width(0.0), StreamMath.MIN_BAND_M)
	assert_gt(StreamMath.band_width(100.0), StreamMath.band_width(10.0))
	assert_eq(StreamMath.band_width(1e9), StreamMath.MAX_BAND_M)


func test_band_independent_of_quality_profile() -> void:
	var before := StreamMath.band_width(200.0)
	Quality.set_override("low")
	assert_eq(StreamMath.band_width(200.0), before)
	Quality.set_override("")


func test_far_away_wants_nothing() -> void:
	var w := StreamMath.wanted_zones(idx, a.origin_e - 50000.0, a.origin_n, 100.0, Vector2(1, 0), 50.0)
	assert_eq(w.size(), 0)


func test_entering_band_requests_zone() -> void:
	var band := StreamMath.band_width(50.0)
	var e := a.origin_e - band * 0.5
	var w := StreamMath.wanted_zones(idx, e, a.origin_n - 10.0, 20.0, Vector2(1, 0), 50.0)
	assert_true(w.has(a.id))


func test_min_two_zones_live_inside_site() -> void:
	# en el centro de A, quieto: igual se mantiene el vecino B vivo
	var c := a.center()
	var w := StreamMath.wanted_zones(idx, c.e, c.n, 2.0, Vector2(1, 0), 0.0)
	assert_true(w.has(a.id))
	assert_true(w.has(b.id))
	assert_gte(w.size(), 2)


func test_neighbor_requested_before_crossing_at_speed() -> void:
	# a 200 m/s hacia el este, a 1 km del borde A|B: B tiene que estar pedido
	var e := a.origin_e + a.size_e - 1000.0
	var w := StreamMath.wanted_zones(idx, e, a.origin_n - a.size_n * 0.5, 50.0, Vector2(1, 0), 200.0)
	assert_true(w.has(b.id))


func test_prediction_follows_heading() -> void:
	var p := StreamMath.predict(0.0, 0.0, Vector2(0, 1), 100.0, 10.0)
	assert_almost_eq(p[0], 0.0, 1e-9)
	assert_almost_eq(p[1], 1000.0, 1e-9)


func test_unload_hysteresis() -> void:
	var band := StreamMath.band_width(0.0)
	assert_false(StreamMath.should_unload(band * 1.2, 0.0), "no descargar apenas sale de la banda")
	assert_true(StreamMath.should_unload(band * 3.0 + 2000.0, 0.0))
