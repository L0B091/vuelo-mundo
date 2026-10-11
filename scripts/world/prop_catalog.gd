class_name PropCatalog
extends RefCounted
## Catálogo de modelos listos para el detalle urbano (fuentes y licencias en assets/ASSETS.json).

## Modelos listos de Kenney (CC0): tipo -> [archivo bajo assets/models/kenney, tamaño mayor en m]
const PH_MODEL := {
	"bin": "metal_trash_can",
	"bench": "painted_wooden_bench",
	"chair": "plastic_monobloc_chair_01",
	"plant": "potted_plant_04",
	"ac": "exterior_aircon_unit",
	"hydrant": "fire_hydrant",
	"planter": "planter_box_01",
	"crate": "plastic_crate_01",
	"wood_crate": "wooden_crate_01",
	"barrel": "barrel_03",
	"roof_tank": "barrel_03",
	"utility_box": "utility_box_01",
	"manhole": "water_manhole_cover",
	"trashbag": "trashbag",
	"gas": "propane_tank",
	"lifebuoy": "lifebuoy",
	"bananas": "bananas",
	"tyre": "old_tyre",
	"covered_car": "covered_car",
	"barrier": "concrete_road_barrier"
}
## tope de triángulos por tipo tras simplificar (presupuesto móvil)
const PH_TRIS := {"ac": 400, "hydrant": 600, "bananas": 500, "barrier": 500, "crate": 400, "lifebuoy": 400}
const KENNEY := {
	"car": ["car-kit/sedan.glb", 4.3],
	"taxi": ["car-kit/taxi.glb", 4.3],
	"van": ["car-kit/van.glb", 4.8],
	"delivery": ["car-kit/delivery.glb", 5.2],
	"suv": ["car-kit/suv.glb", 4.6],
	"pickup": ["car-kit/truck.glb", 5.3],
	"traffic_light": ["city-kit-roads/traffic-light.glb", 4.2],
	"sign_stop": ["city-kit-roads/road-sign-stop.glb", 2.4],
	"sign_street": ["city-kit-roads/road-sign-object-street.glb", 2.6],
	"elec_pole": ["city-kit-roads/electricity-pole.glb", 8.0],
	"cone": ["car-kit/cone.glb", 0.6],
	"fruit_stand": ["mini-market/display-fruit.glb", 1.6],
	"bread_stand": ["mini-market/display-bread.glb", 1.6],
	"freezer": ["mini-market/freezer.glb", 1.5],
	"shop_shelf": ["mini-market/shelf-boxes.glb", 1.8],
	"cafe_table": ["furniture-kit/tableRound.glb", 0.9],
	"stool": ["furniture-kit/stoolBar.glb", 0.75],
	"antenna": ["furniture-kit/televisionAntenna.glb", 1.2],
	"stall_roof": ["survival-kit/structure-canvas.glb", 3.0],
	"fish_crate": ["survival-kit/fish-large.glb", 0.9],
}


## Escala una malla para que su mayor dimensión mida `size_m` y apoye en y = 0.
static func fit_size(m: ArrayMesh, size_m: float) -> ArrayMesh:
	var bb := m.get_aabb()
	var big := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
	var s := size_m / maxf(big, 0.001)
	var out := ArrayMesh.new()
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for k in v.size():
			v[k] = Vector3(v[k].x * s, (v[k].y - bb.position.y) * s, v[k].z * s)
		arr[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(si, m.surface_get_material(si))
	return out


## Simplifica una malla al LOD de ImporterMesh más cercano a `max_tris` triángulos por
## superficie (los modelos de Poly Haven traen hasta 90k; en la calle alcanzan unos cientos).
static func decimate(m: ArrayMesh, max_tris: int) -> ArrayMesh:
	var im := ImporterMesh.new()
	for si in m.get_surface_count():
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(si), [], {}, m.surface_get_material(si))
	im.generate_lods(25.0, 60.0, [])
	var out := ArrayMesh.new()
	for si in im.get_surface_count():
		var arr := im.get_surface_arrays(si)
		var best: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for li in im.get_surface_lod_count(si):
			var idx := im.get_surface_lod_indices(si, li)
			if best.size() / 3 > max_tris and idx.size() < best.size():
				best = idx
		arr[Mesh.ARRAY_INDEX] = best
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(si, im.get_surface_material(si))
	return out
