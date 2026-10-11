class_name PropCatalog
extends RefCounted
## Catálogo de modelos listos para el detalle urbano (fuentes y licencias en assets/ASSETS.json).

## Modelos realistas de 3dassets.dev (CC0): tipo -> [archivo bajo assets/models/3da, tamaño mayor en m]
## Props de fachada: se apoyan al ras de la pared (ver flush_back).
## gente estática (multitud lejana / sentada / en filas): pose del UAL horneada a malla fija
const PERSON_POSES := {
	"person_stand": "Idle_Loop",
	"person_sit": "Sitting_Idle_Loop",
	"person_talk": "Idle_Talking_Loop",
	"person_kid": "Dance_Loop"
}
const PERSON_KINDS := [
	"person_stand",
	"person_sit",
	"person_talk",
	"person_kid",
	"person_stand_f",
	"person_sit_f",
	"person_talk_f",
	"person_kid_f"
]
const HERO_M := "res://assets/characters/superhero/Superhero_Male_FullBody.gltf"
const HERO_F := "res://assets/characters/superhero/Superhero_Female_FullBody.gltf"
const HERO_ANIMS := "res://assets/characters/superhero/UAL1_UE.glb"
const MASK_M := "res://assets/characters/superhero/Superhero_Male_FullBody_suitmask.png"
const MASK_F := "res://assets/characters/superhero/Superhero_Female_FullBody_suitmask.png"
const CROWD_SHADER := preload("res://shaders/crowd_person.gdshader")
const WALL_MOUNT := ["balcony", "ac", "shutter", "laundry_wall"]
const PROP_SHADER := preload("res://shaders/prop_lib.gdshader")
const PROP_RANGE := {
	"lamp": [420.0, true],
	"scooter": [120.0, false],
	"car": [300.0, true],
	"bench": [150.0, false],
	"bin": [70.0, false],
	"chair": [55.0, false],
	"plant": [60.0, false],
	"ac": [130.0, false],
	"balcony": [260.0, true],
	"tree": [500.0, true],
	"lounger": [140.0, false],
	"parasol": [260.0, true],
	"taxi": [300.0, true],
	"van": [300.0, true],
	"delivery": [300.0, true],
	"suv": [300.0, true],
	"pickup": [300.0, true],
	"traffic_light": [260.0, true],
	"sign_stop": [140.0, false],
	"sign_street": [150.0, false],
	"elec_pole": [320.0, true],
	"cone": [60.0, false],
	"planter": [90.0, false],
	"fruit_stand": [90.0, false],
	"bread_stand": [80.0, false],
	"freezer": [80.0, false],
	"shop_shelf": [70.0, false],
	"crate": [60.0, false],
	"barrel": [70.0, false],
	"cafe_table": [80.0, false],
	"stool": [55.0, false],
	"roof_tank": [380.0, false],
	"antenna": [260.0, false],
	"stall_roof": [160.0, true],
	"fish_crate": [50.0, false],
	"hydrant": [70.0, false],
	"wood_crate": [70.0, false],
	"utility_box": [90.0, false],
	"manhole": [60.0, false],
	"trashbag": [50.0, false],
	"gas": [50.0, false],
	"bananas": [45.0, false],
	"tyre": [60.0, false],
	"covered_car": [300.0, true],
	"barrier": [120.0, false],
	"scooter_a": [120.0, false],
	"scooter_b": [120.0, false],
	"scooter_c": [120.0, false],
	"scooter_d": [120.0, false],
	"motorbike": [120.0, false],
	"bicycle": [90.0, false],
	"bicycle_delivery": [90.0, false],
	"hatchback": [300.0, true],
	"laundry": [160.0, false],
	"aframe": [60.0, false],
	"container": [600.0, true],
	"crane": [1500.0, true],
	"palm_lean": [700.0, true],
	"palm_young": [400.0, true],
	"sea_grape": [200.0, true],
	"trawler": [900.0, true],
	"seagull": [80.0, false],
	"ice_kiosk": [200.0, true],
	"ice_cart": [120.0, false],
	"ticket_kiosk": [200.0, true],
	"food_counter": [150.0, false],
	"queue_post": [60.0, false],
	"person_stand": [140.0, false],
	"person_sit": [110.0, false],
	"person_talk": [140.0, false],
	"person_kid": [120.0, false],
	"person_stand_f": [140.0, false],
	"m_man": [150.0, false],
	"m_woman": [150.0, false],
	"m_tourist": [150.0, false],
	"m_fisher": [150.0, false],
	"m_boy": [120.0, false],
	"m_girl": [120.0, false],
	"m_sit": [120.0, false],
	"cat": [70.0, false],
	"dog": [90.0, false],
	"beach_ball": [70.0, false],
	"sand_toys": [50.0, false],
	"food_truck": [300.0, true],
	"person_sit_f": [110.0, false],
	"person_talk_f": [140.0, false],
	"person_kid_f": [120.0, false],
	"shutter": [90.0, false],
	"bollard": [60.0, false],
	"buoy": [300.0, false],
	"frangipani": [200.0, true],
	"banana_clump": [160.0, true],
	"pandanus": [200.0, true]
}
const DA3 := {
	"palm_lean": ["palm_lean.glb", 9.0],
	"palm_young": ["palm_young.glb", 4.5],
	"sea_grape": ["sea_grape.glb", 3.0],
	"trawler": ["trawler.glb", 14.0],
	"seagull": ["seagull.glb", 1.4],
	"ice_kiosk": ["ice_kiosk.glb", 3.2],
	"ice_cart": ["ice_cart.glb", 1.8],
	"ticket_kiosk": ["ticket_kiosk.glb", 3.0],
	"food_counter": ["food_counter.glb", 2.6],
	"queue_post": ["queue_post.glb", 1.0],
	"palm_tall": ["palm_tall.glb", 9.0],
	"lamp": ["lamp.glb", 6.5],
	"fruit_stand": ["fruit_stand.glb", 2.2],
	"stall_roof": ["stall_roof.glb", 3.2],
	"fish_crate": ["fish_crate.glb", 2.4],
	"cafe_table": ["cafe_table.glb", 1.4],
	"parasol": ["parasol.glb", 2.6],
	"lounger": ["lounger.glb", 2.0],
	"shutter": ["shutter.glb", 2.8],
	"bollard": ["bollard.glb", 1.0],
	"buoy": ["buoy.glb", 1.6],
	"frangipani": ["frangipani.glb", 3.5],
	"banana_clump": ["banana_clump.glb", 3.0],
	"pandanus": ["pandanus.glb", 4.0],
	"scooter_a": ["scooter_a.glb", 1.82],
	"scooter_b": ["scooter_b.glb", 1.82],
	"scooter_c": ["scooter_c.glb", 1.85],
	"scooter_d": ["scooter_d.glb", 1.85],
	"motorbike": ["motorbike.glb", 2.05],
	"bicycle": ["bicycle.glb", 1.75],
	"bicycle_delivery": ["bicycle_delivery.glb", 1.8],
	"car": ["saloon.glb", 4.5],
	"taxi": ["taxi.glb", 4.5],
	"van": ["van.glb", 5.0],
	"hatchback": ["hatchback.glb", 4.0],
	"ac": ["ac_unit.glb", 0.85],
	"roof_tank": ["roof_tank.glb", 1.7],
	"antenna": ["dish.glb", 0.9],
	"balcony": ["balcony.glb", 2.6],
	"laundry": ["laundry.glb", 3.0],
	"aframe": ["aframe.glb", 0.95],
	"container": ["container.glb", 6.0],
	"crane": ["crane.glb", 14.0],
	"dhoni": ["boat_fishing_l.glb", 12.0],
	"speedboat": ["rib.glb", 7.0],
	"railing": ["railing.glb", 3.0],
}
## tope de triángulos de los modelos 3dassets tras simplificar
## Modelos generados con Meshy (text-to-3D, cuenta paga del usuario; ver ATTRIBUTION.md):
## gente local y turistas, chicos, mascotas, juguetes de playa, camioneta de comida y dhoni.
const MESHY := {
	"m_man": ["man.glb", 1.72],
	"m_woman": ["woman.glb", 1.62],
	"m_tourist": ["tourist.glb", 1.68],
	"m_fisher": ["fisherman.glb", 1.7],
	"m_boy": ["boy.glb", 1.25],
	"m_girl": ["girl.glb", 1.18],
	"m_sit": ["sitting.glb", 1.25],
	"cat": ["cat.glb", 0.5],
	"dog": ["dog.glb", 0.8],
	"beach_ball": ["ball.glb", 0.45],
	"sand_toys": ["sand_toys.glb", 0.35],
	"food_truck": ["food_truck.glb", 4.6],
	"dhoni": ["dhoni.glb", 12.0]
}
const MESHY_TRIS := {"food_truck": 4000, "dhoni": 4000}
const DA3_TRIS := {"bicycle": 900, "car": 1500, "taxi": 1500, "hatchback": 1500, "crane": 2500, "dhoni": 2500}
const PH_MODEL := {
	"bin": "metal_trash_can",
	"bench": "painted_wooden_bench",
	"chair": "plastic_monobloc_chair_01",
	"plant": "potted_plant_04",
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
		arr = compact(arr, best)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(si, im.get_surface_material(si))
	return out


## Deja en los arrays solo los vértices que usan `idx` (los LOD de ImporterMesh comparten el
## buffer completo; sin esto la malla simplificada pesa lo mismo que la original).
static func compact(arr: Array, idx: PackedInt32Array) -> Array:
	var remap := {}
	var order := PackedInt32Array()
	var ni := PackedInt32Array()
	ni.resize(idx.size())
	for k in idx.size():
		var o := idx[k]
		if not remap.has(o):
			remap[o] = order.size()
			order.append(o)
		ni[k] = remap[o]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for a in Mesh.ARRAY_MAX:
		var src = arr[a]
		if src == null or a == Mesh.ARRAY_INDEX:
			continue
		if a == Mesh.ARRAY_TANGENT or a == Mesh.ARRAY_BONES or a == Mesh.ARRAY_WEIGHTS:
			continue  # tangentes se recalculan si hace falta; las props no tienen huesos
		var dst = src.duplicate()
		dst.resize(order.size())
		for k in order.size():
			dst[k] = src[order[k]]
		out[a] = dst
	out[Mesh.ARRAY_INDEX] = ni
	return out


## Junta todas las superficies sin textura en una sola, con el color de cada material como
## color de vértice: un modelo de 8 materiales pasa a ser 1 llamada de dibujo por celda.
static func flatten(m: ArrayMesh) -> ArrayMesh:
	for si in m.get_surface_count():
		var mt := m.surface_get_material(si) as BaseMaterial3D
		if mt != null and mt.albedo_texture != null:
			return m
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rough := 0.0
	var metal := 0.0
	for si in m.get_surface_count():
		var mt := m.surface_get_material(si) as BaseMaterial3D
		var c := mt.albedo_color if mt != null else Color(0.7, 0.7, 0.7)
		rough += (mt.roughness if mt != null else 0.8) / m.get_surface_count()
		metal += (mt.metallic if mt != null else 0.0) / m.get_surface_count()
		var arr := m.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx = PackedInt32Array(range(v.size()))
		for k in idx:
			st.set_color(c)
			if nn.size() == v.size():
				st.set_normal(nn[k])
			st.add_vertex(v[k])
	st.index()
	var mat := ShaderMaterial.new()
	mat.shader = PROP_SHADER
	mat.set_shader_parameter(&"roughness", clampf(rough, 0.35, 0.95))
	mat.set_shader_parameter(&"metallic", clampf(metal, 0.0, 0.6))
	st.set_material(mat)
	return st.commit()


## Quita los triángulos que quedan enteros por debajo de `frac` de la altura (p. ej. la ménsula
## bajo la losa del balcón, que se ve suelta contra la fachada).
static func cut_below(m: ArrayMesh, frac: float) -> ArrayMesh:
	var bb := m.get_aabb()
	var y_cut := bb.position.y + bb.size.y * frac
	var out := ArrayMesh.new()
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		for k in range(0, idx.size(), 3):
			if maxf(v[idx[k]].y, maxf(v[idx[k + 1]].y, v[idx[k + 2]].y)) > y_cut:
				keep.append_array([idx[k], idx[k + 1], idx[k + 2]])
		arr[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, compact(arr, keep))
		out.surface_set_material(si, m.surface_get_material(si))
	return out


## Letreros de comercio: un MultiMesh por celda de cell con el índice del atlas en el dato
## custom (la distancia de visibilidad se mide al centro de cada celda).
static func signs(holder: Node3D, items: Array, cell: float) -> void:
	if items.is_empty():
		return
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 0.65)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/shop_sign.gdshader")
	mat.set_shader_parameter(&"atlas", load("res://assets/textures/shop_signs.png"))
	q.material = mat
	var cells := {}
	for it: Array in items:
		var key := Vector2i(int(float(it[0]) / cell), int(float(it[2]) / cell))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(it)
	for key: Vector2i in cells:
		var lst: Array = cells[key]
		var org := Vector3(key.x * cell, 0.0, key.y * cell)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = q
		mm.instance_count = lst.size()
		for k in lst.size():
			var it: Array = lst[k]
			var pos := Vector3(float(it[0]), float(it[1]), float(it[2])) - org
			mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, float(it[3])), pos))
			mm.set_instance_custom_data(k, Color(float(it[4]), 0, 0, 0))
		var mi := MultiMeshInstance3D.new()
		mi.name = "Letreros_%d_%d" % [key.x, key.y]
		mi.multimesh = mm
		mi.position = org
		mi.custom_aabb = AABB(Vector3(-10, -5, -10), Vector3(cell + 20, 40, cell + 20))
		mi.visibility_range_end = 160.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)


## Lleva la cara trasera del modelo (z mínima; mira a +Z) a z = 0, al ras de la pared.
static func flush_back(m: ArrayMesh) -> ArrayMesh:
	var bb := m.get_aabb()
	var out := ArrayMesh.new()
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for k in v.size():
			v[k].z -= bb.position.z
		arr[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(si, m.surface_get_material(si))
	return out


## Hornea una pose del cuerpo base texturizado (Universal Base Characters, CC0) a malla fija:
## piel y pelo reales, ropa de calle pintada por instancia (shaders/crowd_person.gdshader).
## kind termina en "_f" para el cuerpo femenino. Necesita un nodo en el árbol.
static func person(kind: String, host: Node) -> ArrayMesh:
	var fem := kind.ends_with("_f")
	var pose := str(PERSON_POSES[kind.trim_suffix("_f")])
	var body: Node3D = (load(HERO_F if fem else HERO_M) as PackedScene).instantiate()
	host.add_child(body)
	var lib: Node = (load(HERO_ANIMS) as PackedScene).instantiate()
	var ap: AnimationPlayer = lib.find_children("*", "AnimationPlayer", true, false)[0]
	var anim := ap.get_animation(pose) if ap.has_animation(pose) else ap.get_animation(pose.trim_suffix("_Loop"))
	var sk: Skeleton3D = body.find_children("*", "Skeleton3D", true, false)[0]
	# pose aplicada a mano por nombre de hueso (el mixer no procesa en un script de herramienta)
	for tr in anim.get_track_count():
		var bone := sk.find_bone(anim.track_get_path(tr).get_concatenated_subnames())
		if bone < 0:
			continue
		match anim.track_get_type(tr):
			Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(tr, 0.4))
			Animation.TYPE_POSITION_3D:
				if bone == 0 or sk.get_bone_parent(bone) <= 0:
					sk.set_bone_pose_position(bone, anim.position_track_interpolate(tr, 0.4))
	lib.free()
	sk.force_update_all_bone_transforms()
	var out := ArrayMesh.new()
	var hmax := 1.75
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		var skin := mi.skin
		var xs := _rel(sk, body)
		var binds: Array[Transform3D] = []
		if skin != null:
			for bi in skin.get_bind_count():
				var bone := skin.get_bind_bone(bi)
				if bone < 0:
					bone = sk.find_bone(skin.get_bind_name(bi))
				binds.append(sk.get_bone_global_pose(bone) * skin.get_bind_pose(bi))
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var bo = arr[Mesh.ARRAY_BONES]
			var we = arr[Mesh.ARRAY_WEIGHTS]
			var nb := 4 if bo == null or bo.size() <= v.size() * 4 else 8
			var pv := PackedVector3Array()
			var pn := PackedVector3Array()
			var uv2 := PackedVector2Array()
			pv.resize(v.size())
			pn.resize(v.size())
			uv2.resize(v.size())
			for k in v.size():
				var p := Vector3.ZERO
				var q := Vector3.ZERO
				if binds.is_empty() or bo == null:
					p = v[k]
					q = nn[k]
				else:
					for j in nb:
						var w: float = we[k * nb + j]
						if w > 0.0:
							var t: Transform3D = binds[int(bo[k * nb + j])]
							p += (t * v[k]) * w
							q += (t.basis * nn[k]) * w
				pv[k] = xs * p
				pn[k] = (xs.basis * q).normalized()
				# altura y lateralidad de la pose de reposo (para que la ropa siga al cuerpo al sentarse)
				var rest := _rel(mi, body) * v[k]
				uv2[k] = Vector2(absf(rest.x), rest.y / hmax)
			if v.is_empty():
				continue
			var res := [] as Array
			res.resize(Mesh.ARRAY_MAX)
			res[Mesh.ARRAY_VERTEX] = pv
			res[Mesh.ARRAY_NORMAL] = pn
			res[Mesh.ARRAY_TEX_UV] = arr[Mesh.ARRAY_TEX_UV]
			res[Mesh.ARRAY_TEX_UV2] = uv2
			res[Mesh.ARRAY_INDEX] = arr[Mesh.ARRAY_INDEX]
			var mat := mi.get_active_material(si)
			var bm := mat as StandardMaterial3D
			if bm != null and str(bm.resource_name).contains("Superhero"):
				var sm := ShaderMaterial.new()
				sm.shader = CROWD_SHADER
				sm.set_shader_parameter(&"base_tex", bm.albedo_texture)
				sm.set_shader_parameter(&"normal_tex", bm.normal_texture)
				sm.set_shader_parameter(&"rough_tex", bm.roughness_texture)
				sm.set_shader_parameter(&"mask_tex", load(MASK_F if fem else MASK_M))
				mat = sm
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res)
			out.surface_set_material(out.get_surface_count() - 1, mat)
	body.queue_free()
	return decimate(out, 2500)


static func _rel(n: Node3D, top: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != top:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


## Losa maciza de hormigón bajo la baranda del balcón (el modelo trae solo ménsulas, que se
## recortan): el balcón apoya visualmente en la fachada en lugar de flotar.
static func with_slab(m: ArrayMesh) -> ArrayMesh:
	var bb := m.get_aabb()
	var bx := BoxMesh.new()
	bx.size = Vector3(bb.size.x + 0.1, 0.16, bb.size.z + 0.05)
	var arr := bx.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var col := PackedColorArray()
	for k in v.size():
		v[k] += Vector3(bb.get_center().x, bb.position.y - 0.08, bb.get_center().z + 0.025)
		col.append(Color(0.78, 0.76, 0.72))
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_COLOR] = col
	var out := m.duplicate() as ArrayMesh
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	out.surface_set_material(out.get_surface_count() - 1, m.surface_get_material(0))
	return out
