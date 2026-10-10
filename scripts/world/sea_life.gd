class_name SeaLife
extends Node3D
## Fauna marina con comportamientos de dirección (steering) y bancos de peces (boids).
## Lugares REALES documentados donde los hay (ver SPOTS.source); cada grupo aparece cuando el
## avatar está a < SPAWN_M y se libera a > DESPAWN_M. Cantidades por perfil de calidad.
## Todas las mallas son procedurales (CreatureMeshes, obra propia) con ondulación en el vértice.

const SPAWN_M := 4000.0
const DESPAWN_M := 6000.0
const FISH_BY_PROFILE := {"low": 20, "medium": 50, "high": 110, "ultra": 180}
const BIG_SCALE := {"low": 0.4, "medium": 0.7, "high": 1.0, "ultra": 1.0}

## species, lat, lon, depth (m), count, radius (m), source (documentación del lugar)
const SPOTS := [
	{
		"sp": "manta",
		"lat": 4.2885,
		"lon": 73.5655,
		"depth": 7.0,
		"n": 4,
		"r": 60.0,
		"src": "Lankan Manta Point (estación de limpieza), Lankanfinolhu, Atolón Malé Norte"
	},
	{
		"sp": "manta",
		"lat": 5.1797,
		"lon": 73.1453,
		"depth": 4.0,
		"n": 8,
		"r": 150.0,
		"src": "Hanifaru Bay, Atolón Baa (Reserva de Biosfera UNESCO)"
	},
	{
		"sp": "whale_shark",
		"lat": 3.4850,
		"lon": 72.8300,
		"depth": 3.0,
		"n": 2,
		"r": 400.0,
		"src": "Área Marina Protegida South Ari (SAMPA), Atolón Ari Sur"
	},
	{
		"sp": "whale_shark",
		"lat": 4.2945,
		"lon": 73.5705,
		"depth": 3.0,
		"n": 1,
		"r": 200.0,
		"src": "ubicación de juego (no documentada): canal frente a Lankanfinolhu, para que se pueda ver"
	},
	{
		"sp": "reef_shark",
		"lat": 4.2870,
		"lon": 73.5680,
		"depth": 12.0,
		"n": 3,
		"r": 80.0,
		"src": "talud exterior del arrecife de Lankan (tiburones de punta negra/gris frecuentes en kandus)"
	},
	{
		"sp": "turtle",
		"lat": 4.2905,
		"lon": 73.5640,
		"depth": 3.0,
		"n": 2,
		"r": 60.0,
		"src": "laguna de Lankanfinolhu (tortugas carey/verde frecuentes en arrecifes de Malé Norte)"
	},
	{
		"sp": "turtle",
		"lat": 4.2395,
		"lon": 73.5340,
		"depth": 5.0,
		"n": 2,
		"r": 60.0,
		"src": "Banana Reef, Atolón Malé Norte"
	},
	{
		"sp": "dolphin",
		"lat": 4.2450,
		"lon": 73.5550,
		"depth": 0.5,
		"n": 5,
		"r": 300.0,
		"src": "canal Malé–Hulhumalé/Vaadhoo (delfines de rotador avistados en canales)"
	},
	{
		"sp": "eagle_ray",
		"lat": 4.2915,
		"lon": 73.5620,
		"depth": 4.0,
		"n": 3,
		"r": 70.0,
		"src": "laguna de Lankanfinolhu (rayas águila frecuentes en lagunas arenosas)"
	},
	{
		"sp": "fish",
		"lat": 4.2905,
		"lon": 73.5660,
		"depth": 3.0,
		"n": 1,
		"r": 25.0,
		"src": "arrecife de Lankan: banco de fusileros",
		"c": [0.15, 0.35, 0.8, 0.95, 0.85, 0.2]
	},
	{
		"sp": "fish",
		"lat": 4.2880,
		"lon": 73.5642,
		"depth": 3.5,
		"n": 1,
		"r": 25.0,
		"src": "arrecife de Lankan: banco de pargos rayados",
		"c": [0.95, 0.8, 0.2, 0.9, 0.9, 0.85]
	},
	{
		"sp": "fish",
		"lat": 4.1735,
		"lon": 73.5150,
		"depth": 2.5,
		"n": 1,
		"r": 20.0,
		"src": "Malé: rompeolas del puerto",
		"c": [0.4, 0.45, 0.5, 0.85, 0.85, 0.88]
	},
]
const SPECIES := {
	"manta": {"speed": 1.6, "turn": 0.5, "mode": 1, "amp": 0.18, "len": 3.0},
	"eagle_ray": {"speed": 1.8, "turn": 0.7, "mode": 1, "amp": 0.2, "len": 1.2},
	"whale_shark": {"speed": 1.2, "turn": 0.25, "mode": 0, "amp": 0.06, "len": 9.0},
	"reef_shark": {"speed": 2.4, "turn": 1.0, "mode": 0, "amp": 0.1, "len": 1.7},
	"turtle": {"speed": 0.7, "turn": 0.6, "mode": 2, "amp": 0.12, "len": 1.0},
	"dolphin": {"speed": 6.0, "turn": 0.9, "mode": 0, "amp": 0.05, "len": 2.4},
}

var world: WorldRoot
var avatar: Avatar
var live: Dictionary = {}  # spot index -> grupo
var spawned_total: int = 0
var _meshes: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _check_t: float = 0.0


func setup(p_world: WorldRoot, p_avatar: Avatar) -> void:
	world = p_world
	avatar = p_avatar


func _profile() -> String:
	var q := get_tree().root.get_node_or_null(^"Quality")
	return str(q.get(&"current_name")) if q != null else "high"


func _process(dt: float) -> void:
	if avatar == null:
		return
	_check_t -= dt
	if _check_t <= 0.0:
		_check_t = 0.5
		_stream()
	for g: Dictionary in live.values():
		if g.sp == "fish":
			_boids(g, dt)
		else:
			_steer(g, dt)


func _spot_local(s: Dictionary) -> Vector3:
	var gp := GlobalPos.from_lonlat(float(s.lon), float(s.lat))
	var p := world.global_to_local(gp.e, gp.n)
	return Vector3(p.x, -float(s.depth) * Geo.scale_k(gp.n), p.z)


func _stream() -> void:
	var ap := avatar.position
	for i in SPOTS.size():
		var s: Dictionary = SPOTS[i]
		var c := _spot_local(s)
		var d := Vector2(c.x - ap.x, c.z - ap.z).length()
		if d < SPAWN_M and not live.has(i):
			live[i] = _spawn(s, c)
		elif d > DESPAWN_M and live.has(i):
			(live[i].root as Node3D).queue_free()
			live.erase(i)
	# los centros se recalculan si el origen se desplazó (los nodos hijos ya se movieron)
	for i: int in live:
		live[i].center = _spot_local(SPOTS[i])


func _mesh(sp: String, s: Dictionary) -> Mesh:
	var key := sp + str(s.get("c", ""))
	if _meshes.has(key):
		return _meshes[key]
	var m: Mesh
	match sp:
		"manta":
			m = CreatureMeshes.ray(4.0, 2.2, Color(0.08, 0.08, 0.1), Color(0.92, 0.92, 0.9), true)
		"eagle_ray":
			m = CreatureMeshes.ray(1.8, 1.0, Color(0.12, 0.12, 0.16), Color(0.9, 0.9, 0.9), false)
		"whale_shark":
			m = CreatureMeshes.shark(9.0, Color(0.2, 0.25, 0.3), Color(0.85, 0.85, 0.82), Color(0.2, 0.25, 0.3))
		"reef_shark":
			m = CreatureMeshes.shark(1.7, Color(0.45, 0.48, 0.5), Color(0.9, 0.9, 0.88), Color(0.05, 0.05, 0.05))
		"turtle":
			m = CreatureMeshes.turtle()
		"dolphin":
			m = CreatureMeshes.dolphin()
		_:
			var c: Array = s.get("c", [0.3, 0.4, 0.7, 0.9, 0.9, 0.9])
			m = CreatureMeshes.fish(Color(c[0], c[1], c[2]), Color(c[3], c[4], c[5]))
	_meshes[key] = m
	return m


func _material(sp: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/creature.gdshader")
	var d: Dictionary = SPECIES.get(sp, {"mode": 0, "amp": 0.12, "len": 0.28})
	m.set_shader_parameter(&"mode", int(d.mode))
	m.set_shader_parameter(&"amp", float(d.amp))
	m.set_shader_parameter(&"length_m", float(d.len))
	m.set_shader_parameter(&"vertical", sp == "dolphin")
	m.set_shader_parameter(&"speed", 0.35 if sp in ["whale_shark", "manta"] else (1.6 if sp == "fish" else 0.8))
	m.set_shader_parameter(&"spots", 1.2 if sp == "whale_shark" else (4.0 if sp == "eagle_ray" else 0.0))
	return m


func _spawn(s: Dictionary, c: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.name = "Fauna_" + str(s.sp)
	world.add_child(root)
	var g := {"sp": s.sp, "root": root, "center": c, "r": float(s.r), "depth": float(s.depth), "agents": []}
	spawned_total += 1
	if s.sp == "fish":
		var n: int = FISH_BY_PROFILE.get(_profile(), 50)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _mesh("fish", s)
		mm.instance_count = n
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _material("fish")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-200, -60, -200), Vector3(400, 120, 400))
		root.add_child(mi)
		root.position = c
		var pos := PackedVector3Array()
		var vel := PackedVector3Array()
		for i in n:
			pos.append(Vector3(_rng.randf_range(-4, 4), _rng.randf_range(-1.5, 1.5), _rng.randf_range(-4, 4)))
			vel.append(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * 1.2)
		g.mm = mm
		g.pos = pos
		g.vel = vel
		g.goal = Vector3.ZERO
		g.goal_t = 0.0
		return g
	var sd: Dictionary = SPECIES[s.sp]
	var count := maxi(1, int(round(float(s.n) * float(BIG_SCALE.get(_profile(), 1.0)))))
	var mat := _material(str(s.sp))
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh(str(s.sp), s)
		mi.material_override = mat
		mi.set_instance_shader_parameter(&"inst_phase", _rng.randf() * 10.0)
		mi.visibility_range_end = 220.0 if s.sp != "whale_shark" else 400.0
		root.add_child(mi)
		var a := _rng.randf() * TAU
		mi.position = c + Vector3(cos(a), 0, sin(a)) * _rng.randf() * float(s.r)
		g.agents.append(
			{
				"node": mi,
				"vel": Vector3(cos(a), 0, sin(a)) * float(sd.speed),
				"target": mi.position,
				"t": 0.0,
				"jump": _rng.randf() * 6.0
			}
		)
	return g


## Dirección: cada animal elige puntos al azar dentro del radio del lugar y gira hacia ellos
## con velocidad de giro limitada (sin volteretas); se aparta del avatar si está cerca.
func _steer(g: Dictionary, dt: float) -> void:
	var sd: Dictionary = SPECIES[g.sp]
	var spd: float = sd.speed
	for a: Dictionary in g.agents:
		var n: Node3D = a.node
		a.t -= dt
		if a.t <= 0.0 or n.position.distance_to(a.target) < 3.0:
			var ang := _rng.randf() * TAU
			var dd := _rng.randf_range(0.5, 1.5) * float(g.depth)
			a.target = g.center + Vector3(cos(ang) * g.r * _rng.randf(), 0.0, sin(ang) * g.r * _rng.randf())
			a.target.y = -dd
			a.t = _rng.randf_range(6.0, 14.0)
		var want: Vector3 = (a.target - n.position).normalized() * spd
		var away: Vector3 = n.position - avatar.position
		if away.length() < 6.0 and g.sp != "whale_shark":
			want += away.normalized() * spd * 1.5
		var v: Vector3 = a.vel
		v = v.lerp(want, clampf(float(sd.turn) * dt, 0.0, 1.0))
		if g.sp == "dolphin":
			# en la superficie: saltos (marsopeo) cada pocos segundos
			a.jump -= dt
			var y := -0.6
			if a.jump < 0.0:
				y = -0.6 + sin(clampf(-a.jump / 1.2, 0.0, 1.0) * PI) * 1.8
				if a.jump < -1.2:
					a.jump = _rng.randf_range(3.0, 8.0)
			n.position.y = lerpf(n.position.y, y, clampf(dt * 6.0, 0.0, 1.0))
			v.y = 0.0
		a.vel = v
		n.position += v * dt
		if g.sp == "dolphin":
			n.position.y = minf(n.position.y, 1.3)
		elif n.position.y > -0.4:
			n.position.y = -0.4
		if v.length() > 0.05:
			n.look_at(n.position - v, Vector3.UP)  # el modelo mira a +Z


## Boids simples para el banco: cohesión, alineación, separación con vecinos por índice
## (barato: O(n·k)), meta que deambula y huida del avatar.
func _boids(g: Dictionary, dt: float) -> void:
	var pos: PackedVector3Array = g.pos
	var vel: PackedVector3Array = g.vel
	var n := pos.size()
	g.goal_t -= dt
	if g.goal_t <= 0.0:
		g.goal = Vector3(_rng.randf_range(-g.r, g.r), _rng.randf_range(-1.5, 1.0), _rng.randf_range(-g.r, g.r))
		g.goal_t = _rng.randf_range(4.0, 9.0)
	var cen := Vector3.ZERO
	var avg := Vector3.ZERO
	for i in n:
		cen += pos[i]
		avg += vel[i]
	cen /= n
	avg /= n
	var av_local: Vector3 = avatar.position - (g.root as Node3D).position
	var mm: MultiMesh = g.mm
	for i in n:
		var p := pos[i]
		var v := vel[i]
		var acc: Vector3 = (cen - p) * 0.3 + (avg - v) * 0.8 + (g.goal - p) * 0.08
		for k: int in [1, 2, 3]:
			var o := pos[(i + k) % n]
			var d := p - o
			var l := d.length()
			if l < 0.6 and l > 1e-4:
				acc += d / (l * l) * 0.25
		var fa := p - av_local
		if fa.length() < 5.0:
			acc += fa.normalized() * 8.0
		v += acc * dt
		var sp := v.length()
		if sp > 3.5:
			v = v / sp * 3.5
		elif sp < 0.6:
			v = v / maxf(sp, 1e-4) * 0.6
		p += v * dt
		p.y = minf(p.y, -0.3 - (g.root as Node3D).position.y)
		pos[i] = p
		vel[i] = v
		var b := Basis.looking_at(-v.normalized(), Vector3.UP) if absf(v.normalized().y) < 0.98 else Basis()
		mm.set_instance_transform(i, Transform3D(b, p))
	g.pos = pos
	g.vel = vel
