extends SceneTree
## Genera los dos micro-mapas de PRUEBA (no son el Malé real):
##   godot --headless --script res://tools/gen_test_zones.gd
## Ambos se construyen con el mismo origen de referencia y la misma escala: la vereda y la
## calle tienen exactamente la misma altura en el borde compartido (x = 400 de A = x = 0 de B).
## Espacio local: x = este, z = sur, y = arriba; origen = esquina NO de la zona; metros reales.

const W := 400.0
const H := 300.0
const DECK_TOP := 2.0
const CURB := 0.15
const STREET_Z0 := 142.0
const STREET_Z1 := 158.0
const WALK_W := 6.0
const LAYER_TERRAIN := 1
const LAYER_WALKABLE := 2

var _mats: Dictionary = {}


func _init() -> void:
	_make("mv_test_male_oeste", true)
	_make("mv_test_male_este", false)
	quit()


func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		_mats[key] = m
	return _mats[key]


func _box(root: Node3D, name: String, center: Vector3, size: Vector3, color: Color, layer: int) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = center
	root.add_child(mi)
	mi.owner = root
	if layer != 0:
		var body := StaticBody3D.new()
		body.name = name + "_col"
		body.collision_layer = layer
		body.collision_mask = 0
		body.position = center
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		root.add_child(body)
		body.owner = root
		cs.owner = root


func _make(id: String, west: bool) -> void:
	var root := Node3D.new()
	root.name = id
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	# suelo de la isla (caminable)
	_box(
		root,
		"Suelo",
		Vector3(W / 2, DECK_TOP - 1.0, H / 2),
		Vector3(W, 2.0, H),
		Color(0.80, 0.76, 0.66),
		LAYER_WALKABLE
	)
	# calle (asfalto visual) y veredas elevadas con cordón (caminables)
	_box(
		root,
		"Calle",
		Vector3(W / 2, DECK_TOP + 0.01, (STREET_Z0 + STREET_Z1) / 2),
		Vector3(W, 0.02, STREET_Z1 - STREET_Z0),
		Color(0.22, 0.22, 0.24),
		0
	)
	_box(
		root,
		"VeredaNorte",
		Vector3(W / 2, DECK_TOP + CURB / 2, STREET_Z0 - WALK_W / 2),
		Vector3(W, CURB, WALK_W),
		Color(0.70, 0.68, 0.64),
		LAYER_WALKABLE
	)
	_box(
		root,
		"VeredaSur",
		Vector3(W / 2, DECK_TOP + CURB / 2, STREET_Z1 + WALK_W / 2),
		Vector3(W, CURB, WALK_W),
		Color(0.70, 0.68, 0.64),
		LAYER_WALKABLE
	)
	# senda peatonal en el cruce
	for s in 6:
		_box(
			root,
			"Cebra%d" % s,
			Vector3(200.0 + s * 1.2 - 3.0, DECK_TOP + 0.02, 150.0),
			Vector3(0.6, 0.02, 15.0),
			Color(0.95, 0.95, 0.92),
			0
		)
	# frentes de edificios (sólidos y caminables arriba), con un cruce en x 190..210
	var palette := [
		Color(0.95, 0.85, 0.55),
		Color(0.55, 0.80, 0.85),
		Color(0.95, 0.65, 0.55),
		Color(0.85, 0.90, 0.95),
		Color(0.70, 0.85, 0.60),
		Color(0.95, 0.95, 0.90)
	]
	for side in [-1, 1]:
		var x := 6.0
		var z_front: float = STREET_Z0 - WALK_W if side < 0 else STREET_Z1 + WALK_W
		while x < W - 6.0:
			var bw := rng.randf_range(10.0, 22.0)
			if x + bw > W - 6.0:
				bw = W - 6.0 - x
			if x < 210.0 and x + bw > 190.0:
				x = 210.0
				continue
			var depth := rng.randf_range(12.0, 30.0)
			var height := rng.randf_range(7.0, 20.0)
			var zc: float = z_front - depth / 2 - 0.5 if side < 0 else z_front + depth / 2 + 0.5
			_box(
				root,
				"Edificio_%d_%d" % [side, int(x)],
				Vector3(x + bw / 2, DECK_TOP + height / 2, zc),
				Vector3(bw - 0.6, height, depth),
				palette[rng.randi() % palette.size()],
				LAYER_TERRAIN | LAYER_WALKABLE
			)
			x += bw
	# faroles cada 25 m sobre las veredas
	for i in int(W / 25.0):
		for zz in [STREET_Z0 - 0.6, STREET_Z1 + 0.6]:
			_box(
				root,
				"Farol_%d_%d" % [i, int(zz)],
				Vector3(12.5 + i * 25.0, DECK_TOP + CURB + 2.5, zz),
				Vector3(0.15, 5.0, 0.15),
				Color(0.2, 0.2, 0.2),
				0
			)
	# malecón en los bordes exteriores (no en el borde compartido A|B)
	var wall_c := Color(0.85, 0.85, 0.80)
	_box(
		root,
		"MaleconN",
		Vector3(W / 2, DECK_TOP + 0.5, 0.3),
		Vector3(W, 1.0, 0.6),
		wall_c,
		LAYER_TERRAIN | LAYER_WALKABLE
	)
	_box(
		root,
		"MaleconS",
		Vector3(W / 2, DECK_TOP + 0.5, H - 0.3),
		Vector3(W, 1.0, 0.6),
		wall_c,
		LAYER_TERRAIN | LAYER_WALKABLE
	)
	var outer_x := 0.3 if west else W - 0.3
	_box(
		root,
		"MaleconExt",
		Vector3(outer_x, DECK_TOP + 0.5, H / 2),
		Vector3(0.6, 1.0, H),
		wall_c,
		LAYER_TERRAIN | LAYER_WALKABLE
	)
	# cartel honesto
	var lbl := Label3D.new()
	lbl.name = "Cartel"
	lbl.text = "BANCO DE PRUEBAS\n(no es el Malé real)\n%s" % id
	lbl.font_size = 96
	lbl.pixel_size = 0.02
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(W / 2, DECK_TOP + 8.0, 125.0)
	root.add_child(lbl)
	lbl.owner = root
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack falló: %d" % err)
		return
	var path := "res://scenes/zones/%s.tscn" % id
	err = ResourceSaver.save(ps, path)
	print("escena generada: ", path, " err=", err)
	root.free()
