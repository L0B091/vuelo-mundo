class_name PropCatalog
extends RefCounted
## Catálogo de modelos listos para el detalle urbano (fuentes y licencias en assets/ASSETS.json).

## Modelos listos de Kenney (CC0): tipo -> [archivo bajo assets/models/kenney, tamaño mayor en m]
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
	"planter": ["furniture-kit/pottedPlant.glb", 1.1],
	"fruit_stand": ["mini-market/display-fruit.glb", 1.6],
	"bread_stand": ["mini-market/display-bread.glb", 1.6],
	"freezer": ["mini-market/freezer.glb", 1.5],
	"shop_shelf": ["mini-market/shelf-boxes.glb", 1.8],
	"crate": ["survival-kit/box-large.glb", 0.8],
	"barrel": ["survival-kit/barrel.glb", 0.9],
	"cafe_table": ["furniture-kit/tableRound.glb", 0.9],
	"stool": ["furniture-kit/stoolBar.glb", 0.75],
	"roof_tank": ["survival-kit/barrel.glb", 1.8],
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
