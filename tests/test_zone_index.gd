extends GutTest
## Índice de zonas: carga, validez, vecinos, conversión global -> local.

var idx: ZoneIndex


func before_all() -> void:
	idx = ZoneIndex.load_from("res://data/zone_index.json")


func test_index_loads_and_is_valid() -> void:
	assert_gt(idx.zones.size(), 0)
	assert_eq(idx.validate().size(), 0, "errores: %s" % [idx.validate()])


func test_maldives_country_contains_male() -> void:
	var male := GlobalPos.from_lonlat(73.5093, 4.1755)
	var z := idx.zone_at(male.e, male.n, "country")
	assert_not_null(z)
	assert_eq(z.id, "MV")


func test_sites_are_adjacent_with_same_scale() -> void:
	var a := idx.get_zone("mv_male_oeste")
	var b := idx.get_zone("mv_male_este")
	assert_almost_eq(a.origin_e + a.size_e, b.origin_e, 1e-6, "borde compartido exacto")
	assert_almost_eq(a.origin_n, b.origin_n, 1e-6)
	assert_eq(a.local_scale, b.local_scale)
	assert_true(a.neighbors.has(b.id) and b.neighbors.has(a.id))


func test_global_to_local_roundtrip() -> void:
	var a := idx.get_zone("mv_male_oeste")
	var l := a.global_to_local(a.landing.e, a.landing.n, a.landing.up)
	assert_between(l.x, 0.0, a.size_e)
	assert_between(l.z, 0.0, a.size_n)
	var g := a.local_to_global(l)
	assert_almost_eq(g.e, a.landing.e, 0.01)
	assert_almost_eq(g.n, a.landing.n, 0.01)


func test_distance_to_zone() -> void:
	var a := idx.get_zone("mv_male_oeste")
	assert_eq(a.distance_to(a.landing.e, a.landing.n), 0.0)
	assert_almost_eq(a.distance_to(a.origin_e - 100.0, a.origin_n - 10.0), 100.0, 1e-6)
