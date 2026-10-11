class_name NpcCrowd
extends Node
## Gente en las calles de los micro-mapas: peatones por las veredas y motociclistas por los
## carriles, solo cerca del avatar (se reciclan al alejarse). Cantidad por perfil gráfico.
## Reglas anti-tirón: se crea como mucho un NPC por cuadro, y solo con la zona ya lista.

const BASE := "res://assets/characters/ual/AnimationLibrary_Godot_Standard.gltf"
const SPAWN_R := 110.0
const DESPAWN_R := 170.0
const SHIRTS := [
	Color(0.9, 0.9, 0.9),
	Color(0.1, 0.25, 0.55),
	Color(0.65, 0.1, 0.12),
	Color(0.15, 0.5, 0.35),
	Color(0.95, 0.75, 0.2),
	Color(0.3, 0.3, 0.32),
	Color(0.85, 0.5, 0.65),
	Color(0.4, 0.25, 0.15)
]

const PANTS := [Color(0.18, 0.2, 0.3), Color(0.15, 0.15, 0.16), Color(0.55, 0.48, 0.36), Color(0.3, 0.3, 0.32)]

var avatar: Avatar
var zones: ZoneStreamer
var max_peds: int = 12
var max_riders: int = 5
var npcs: Array = []  # {node, kind, zone, path, i, t, speed}
var _base: PackedScene
var _scooter: Mesh
var _rnd := RandomNumberGenerator.new()


func setup(p_avatar: Avatar, p_zones: ZoneStreamer, prof: Dictionary) -> void:
	avatar = p_avatar
	zones = p_zones
	max_peds = int(prof.get("npc_pedestrians", 12))
	max_riders = int(prof.get("npc_riders", 5))
	_base = load(BASE)
	_scooter = PropMeshes.scooter()
	_rnd.seed = 1234
	zones.zone_unloaded.connect(_on_unloaded)


func _on_unloaded(id: String) -> void:
	for k in range(npcs.size() - 1, -1, -1):
		if npcs[k].zone == id:
			npcs.remove_at(k)  # el nodo se liberó con la zona


func counts() -> Vector2i:
	var p := 0
	var r := 0
	for n: Dictionary in npcs:
		if n.kind == "walk":
			p += 1
		else:
			r += 1
	return Vector2i(p, r)


func _process(dt: float) -> void:
	if avatar == null:
		return
	var apos := avatar.global_position
	# mover y reciclar
	for k in range(npcs.size() - 1, -1, -1):
		var n: Dictionary = npcs[k]
		var node: Node3D = n.node
		if not is_instance_valid(node):
			npcs.remove_at(k)
			continue
		_advance(n, dt)
		if node.global_position.distance_to(apos) > DESPAWN_R * avatar.scale_k():
			node.queue_free()
			npcs.remove_at(k)
	# crear (uno por cuadro como máximo)
	var c := counts()
	if c.x < max_peds:
		_spawn("walk")
	elif c.y < max_riders:
		_spawn("ride")


func _advance(n: Dictionary, dt: float) -> void:
	var path: Array = n.path
	var node: Node3D = n.node
	var p := node.position
	var tgt := Vector3(path[n.i][0], p.y, path[n.i][1])
	var d := p.distance_to(tgt)
	var stepv: float = n.speed * dt
	if d < stepv:
		n.i += n.dir
		if n.i < 0 or n.i >= path.size():
			n.dir = -n.dir
			n.i = clampi(n.i + n.dir * 2, 0, path.size() - 1)
		return
	var v := (tgt - p) / d
	node.position = p + v * stepv
	var yaw := atan2(v.x, v.z)
	node.rotation.y = lerp_angle(node.rotation.y, yaw, clampf(dt * 6.0, 0.0, 1.0))


func _spawn(kind: String) -> void:
	# zona lista que contenga (o esté cerca de) el avatar
	for id: String in zones.live:
		var rec: Dictionary = zones.live[id]
		if rec.state != "ready" or rec.node == null:
			continue
		var zn: Node3D = rec.node
		var paths: Dictionary = zn.get_meta(&"npc_paths", {})
		var lst: Array = paths.get(kind, [])
		if lst.is_empty():
			continue
		var local_av := zn.to_local(avatar.global_position)
		# probar unos recorridos al azar y elegir un punto cercano al avatar pero fuera de vista inmediata
		for attempt in 6:
			var path: Array = lst[_rnd.randi_range(0, lst.size() - 1)]
			var i := _rnd.randi_range(0, path.size() - 1)
			var pt := Vector3(path[i][0], 0, path[i][1])
			var dd := Vector2(pt.x - local_av.x, pt.z - local_av.z).length()
			if dd > SPAWN_R or dd < 8.0:
				continue
			var node := _make(kind)
			node.position = Vector3(pt.x, float(zn.get_meta(&"deck_y", 1.8)) + 0.03, pt.z)
			zn.add_child(node)
			var dirv := 1 if _rnd.randf() < 0.5 else -1
			npcs.append(
				{
					"node": node,
					"kind": kind,
					"zone": id,
					"path": path,
					"i": clampi(i + dirv, 0, path.size() - 1),
					"dir": dirv,
					"speed": _rnd.randf_range(1.1, 1.6) if kind == "walk" else _rnd.randf_range(6.0, 9.0)
				}
			)
			return


func _make(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "NPC_" + kind
	var body: Node3D = _base.instantiate()
	var hgt := _rnd.randf_range(0.88, 1.06)
	var wid := hgt * _rnd.randf_range(0.9, 1.15)  # proporciones variadas (alto / corpulento)
	body.scale = Vector3(wid, hgt, wid)
	root.add_child(body)
	var shirt: Color = SHIRTS[_rnd.randi_range(0, SHIRTS.size() - 1)]
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s in mi.mesh.get_surface_count():
			var m := StandardMaterial3D.new()
			m.albedo_color = shirt if s == 0 else PANTS[_rnd.randi_range(0, PANTS.size() - 1)]
			m.roughness = 0.8
			mi.set_surface_override_material(s, m)
		mi.visibility_range_end = 140.0
	var ap: AnimationPlayer = body.find_children("*", "AnimationPlayer", true, false)[0]
	if kind == "walk":
		ap.get_animation("Walk").loop_mode = Animation.LOOP_LINEAR
		ap.play("Walk")
		ap.seek(_rnd.randf() * 1.0, true)
	else:
		var sc := MeshInstance3D.new()
		sc.mesh = _scooter
		var sm := StandardMaterial3D.new()
		sm.vertex_color_use_as_albedo = true
		sm.albedo_color = SHIRTS[_rnd.randi_range(0, SHIRTS.size() - 1)]
		sm.roughness = 0.35
		sc.material_override = sm
		sc.visibility_range_end = 160.0
		root.add_child(sc)
		ap.get_animation("Driving").loop_mode = Animation.LOOP_LINEAR
		ap.play("Driving")
		body.position = Vector3(0, 0.12, -0.12)
	return root
