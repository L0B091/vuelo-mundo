class_name CapeCloth
extends MeshInstance3D
## Capa de tela simulada (Verlet, 4 x 11 partículas) en el espacio local del cuerpo.
## Fuerzas: gravedad, viento relativo (inverso de la velocidad del avatar, saturado para no
## explotar a 1500 m/s) y un aleteo; restricciones de distancia y un plano/cápsula de espalda
## para que no atraviese el cuerpo. Barata: ~44 puntos, 3 iteraciones, una malla dinámica.

const COLS := 4
const ROWS := 11
const WIDTH := 0.52
const LENGTH := 1.2

var body: AvatarBody
var color: Color = Color(0.75, 0.08, 0.1)
var wind_scale: float = 1.0
var _p: PackedVector3Array = PackedVector3Array()
var _prev: PackedVector3Array = PackedVector3Array()
var _im: ImmediateMesh
var _t: float = 0.0
var _seg_w: float
var _seg_h: float


func setup(p_body: AvatarBody, c: Color) -> void:
	body = p_body
	color = c
	_seg_w = WIDTH / (COLS - 1)
	_seg_h = LENGTH / (ROWS - 1)
	_im = ImmediateMesh.new()
	mesh = _im
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.rim_enabled = true
	m.rim = 0.3
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_reset()


func _anchor(i: int) -> Vector3:
	# hombros: a la altura del pecho alto, apenas detrás de la espalda (+Z local = atrás)
	var base := _shoulder()
	return base + Vector3((float(i) / (COLS - 1) - 0.5) * WIDTH * 0.75, 0.0, 0.0)


func _shoulder() -> Vector3:
	if body == null or body.skeleton == null:
		return Vector3(0, 0.45, 0.14)
	var b := FlightPose.find_any(body.skeleton, "DEF-spine.003")
	if b < 0:
		return Vector3(0, 0.45, 0.14)
	var g := body.skeleton.global_transform * body.skeleton.get_bone_global_pose(b)
	var local := (get_parent() as Node3D).global_transform.affine_inverse() * g.origin
	return local + Vector3(0, 0.12, 0.13) * body.def.height_scale


func _reset() -> void:
	_p.resize(COLS * ROWS)
	_prev.resize(COLS * ROWS)
	for r in ROWS:
		for c in COLS:
			var q := _anchor(c) + Vector3(0, -r * _seg_h, 0.02 * r)
			_p[r * COLS + c] = q
			_prev[r * COLS + c] = q


func _physics_process(dt: float) -> void:
	if body == null or dt <= 0.0:
		return
	_t += dt
	var parent := get_parent() as Node3D
	var inv := parent.global_transform.basis.orthonormalized().inverse()
	var g := inv * Vector3(0, -9.8, 0)
	var av := body.get_parent() as CharacterBody3D
	var v_local := inv * (av.velocity if av != null else Vector3.ZERO)
	var wind := -v_local * 0.6
	if wind.length() > 45.0:
		wind = wind.normalized() * 45.0
	wind *= wind_scale
	var flutter := sin(_t * 17.0) * minf(wind.length() * 0.08, 2.5)
	var steps := 2
	var h := dt / steps
	for _s in steps:
		for i in _p.size():
			if i < COLS:
				continue
			var cur := _p[i]
			var row := float(i / COLS) / (ROWS - 1)
			var acc := g + wind * (0.4 + row) + Vector3(flutter * row * (1.0 if i % 2 == 0 else -1.0), 0, 0)
			var nxt := cur + (cur - _prev[i]) * 0.97 + acc * h * h
			_prev[i] = cur
			_p[i] = nxt
		for c in COLS:
			_p[c] = _anchor(c)
			_prev[c] = _p[c]
		for _it in 3:
			for r in ROWS:
				for c in COLS:
					var i := r * COLS + c
					if c + 1 < COLS:
						_solve(i, i + 1, _seg_w * 0.85, r == 0)
					if r + 1 < ROWS:
						_solve(i, i + COLS, _seg_h, r == 0)
			_collide()
	_rebuild()


func _solve(a: int, b: int, rest: float, a_pinned: bool) -> void:
	var d := _p[b] - _p[a]
	var l := d.length()
	if l < 1e-5:
		return
	var diff := (l - rest) / l
	if a_pinned or a < COLS:
		_p[b] -= d * diff
	else:
		_p[a] += d * diff * 0.5
		_p[b] -= d * diff * 0.5


## La espalda: cápsula vertical aproximada detrás del eje del cuerpo.
func _collide() -> void:
	var sh := _shoulder()
	for i in range(COLS, _p.size()):
		var q := _p[i]
		var rel := q - Vector3(0.0, q.y, sh.z - 0.13)
		var rad := 0.17
		if q.y > sh.y - 1.0 and rel.length() < rad:
			rel = rel.normalized() * rad if rel.length() > 1e-4 else Vector3(0, 0, rad)
			_p[i] = Vector3(rel.x, q.y, sh.z - 0.13 + rel.z)


func _rebuild() -> void:
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in ROWS - 1:
		for c in COLS - 1:
			var i := r * COLS + c
			var a := _p[i]
			var b := _p[i + 1]
			var cc := _p[i + COLS]
			var d := _p[i + COLS + 1]
			var n := (b - a).cross(cc - a).normalized()
			for v: Vector3 in [a, b, cc, b, d, cc]:
				_im.surface_set_normal(n)
				_im.surface_add_vertex(v)
	_im.surface_end()
