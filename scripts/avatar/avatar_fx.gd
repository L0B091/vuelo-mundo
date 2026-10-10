class_name AvatarFx
extends Node3D
## Efectos del vuelo de superhéroe, con presupuesto por perfil gráfico:
## despegue explosivo (polvo + onda), aterrizaje pesado (onda + polvo + marca), sacudida de
## cámara, líneas de velocidad / distorsión de aire, estiramiento de FOV.

const SH_RING := preload("res://shaders/shockwave.gdshader")
const SH_LINES := preload("res://shaders/speed_lines.gdshader")
const DUST_BY_PROFILE := {"low": 16, "medium": 48, "high": 110, "ultra": 180}

var avatar: Avatar
var shake: float = 0.0
var trails_made: int = 0
var splashes: int = 0
## Viento (sonido procedural: ruido filtrado; sube con la velocidad y en rasante).
var wind_level: float = 0.0
var booms: int = 0
var _wind: AudioStreamPlayer
var _wind_pb: AudioStreamGeneratorPlayback
var _wind_lp: float = 0.0
var _rng := RandomNumberGenerator.new()
## Rasante: rocío/estela sobre el agua, polvo y hojas sobre tierra.
var _spray: CPUParticles3D
var _dust: CPUParticles3D
var _wake: MeshInstance3D
var _wake_mesh: ImmediateMesh
var _wake_pts: Array[Vector3] = []
var _was_skim_water: bool = false
var _overlay: ColorRect
var _layer: CanvasLayer
var _rings: Array = []  # [MeshInstance3D, t, dur]
var _marks: Array = []  # [MeshInstance3D, t]
var _dust_mat: StandardMaterial3D
var _crack_tex: ImageTexture
## Estela (cinta) detrás del avatar en acrobacias y a gran velocidad.
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_pts: Array[Vector3] = []
var _trail_t: float = 0.0


func setup(p_avatar: Avatar) -> void:
	avatar = p_avatar
	_layer = CanvasLayer.new()
	_layer.layer = 0
	add_child(_layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = SH_LINES
	_overlay.material = m
	_overlay.visible = false
	_layer.add_child(_overlay)
	_prewarm.call_deferred()


## Dibuja una vez cada material de efectos (invisible) al empezar, para que el primer
## despegue no pague la compilación de shaders en medio del juego.
func _prewarm() -> void:
	var cam := avatar.camera
	var nodes: Array[Node] = []
	# traje del cuerpo, anillo de onda: se compilan antes del primer uso (sin tirón)
	for sh: Shader in [SH_RING, AvatarBody.SUIT_SHADER]:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.2, 0.2)
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter(&"progress", 1.0)
		m.set_shader_parameter(&"fade", 0.0)
		mi.material_override = m
		cam.add_child(mi)
		mi.position = Vector3(0, 0, -1.0)
		nodes.append(mi)
	var dust := _dust_material()
	var dm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.01
	sm.height = 0.02
	sm.material = dust
	dm.mesh = sm
	cam.add_child(dm)
	dm.position = Vector3(0, 0, -1.0)
	nodes.append(dm)
	_ensure_trail()
	_overlay.visible = true
	(_overlay.material as ShaderMaterial).set_shader_parameter(&"intensity", 0.0)
	for i in 3:
		await get_tree().process_frame
	for n in nodes:
		n.queue_free()


## Grietas radiales procedurales (se generan una vez; obra propia).
func _crack_texture() -> ImageTexture:
	if _crack_tex != null:
		return _crack_tex
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 11
	for c in 22:
		var ang := rnd.randf() * TAU
		var p := Vector2(n * 0.5, n * 0.5)
		var ln := rnd.randf_range(0.35, 0.95) * n * 0.5
		var stepv := 0.0
		while stepv < ln:
			ang += rnd.randf_range(-0.35, 0.35)
			p += Vector2(cos(ang), sin(ang)) * 2.0
			stepv += 2.0
			var wid := int(lerpf(3.0, 1.0, stepv / ln))
			for dx in range(-wid, wid + 1):
				for dy in range(-wid, wid + 1):
					var q := Vector2i(int(p.x) + dx, int(p.y) + dy)
					if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n:
						img.set_pixelv(q, Color(0.06, 0.05, 0.05, 0.9))
	for y in n:
		for x in n:
			var r := Vector2(x - n * 0.5, y - n * 0.5).length() / (n * 0.5)
			if r < 0.3:
				var a := (1.0 - r / 0.3) * 0.7
				var cur := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(0.07, 0.06, 0.05, maxf(cur.a, a)))
	_crack_tex = ImageTexture.create_from_image(img)
	return _crack_tex


func _dust_material() -> StandardMaterial3D:
	if _dust_mat == null:
		_dust_mat = StandardMaterial3D.new()
		_dust_mat.albedo_color = Color(0.82, 0.78, 0.7, 0.45)
		_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dust_mat.vertex_color_use_as_albedo = true
	return _dust_mat


func _profile() -> String:
	var q := get_tree().root.get_node_or_null(^"Quality")
	return str(q.get(&"current_name")) if q != null else "high"


func burst(ground_pos: Vector3, strength: float, crater: bool) -> void:
	var k := avatar.scale_k()
	var radius := lerpf(6.0, 22.0, clampf(strength, 0.0, 1.0)) * k
	var ring := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	ring.mesh = q
	var m := ShaderMaterial.new()
	m.shader = SH_RING
	m.set_shader_parameter(&"strength", clampf(0.5 + strength, 0.0, 1.2))
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().get_parent().add_child(ring)  # en el mundo (no sigue al avatar)
	ring.global_position = ground_pos + Vector3(0, 0.06 * k, 0)
	_rings.append([ring, 0.0, 0.9])
	# polvo
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = int(DUST_BY_PROFILE.get(_profile(), 48) * clampf(0.4 + strength, 0.3, 1.0))
	p.lifetime = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 1.2 * k
	p.emission_ring_inner_radius = 0.4 * k
	p.emission_ring_height = 0.1
	p.direction = Vector3(0, 0.25, 0)
	p.spread = 85.0
	p.flatness = 0.7
	p.initial_velocity_min = 6.0 * k * (0.5 + strength)
	p.initial_velocity_max = 14.0 * k * (0.5 + strength)
	p.damping_min = 6.0
	p.damping_max = 9.0
	p.gravity = Vector3(0, -1.5, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.2
	var sm := SphereMesh.new()
	sm.radius = 0.35 * k
	sm.height = 0.5 * k
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = _dust_material()
	p.mesh = sm
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.6))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = grad
	get_parent().get_parent().add_child(p)
	p.global_position = ground_pos + Vector3(0, 0.2 * k, 0)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.2).timeout.connect(p.queue_free)
	if crater:
		# marca de impacto: Decal proyectado sobre la calle (no depende del orden de transparencias)
		var dc := Decal.new()
		var w := 5.0 * k * (0.6 + strength * 0.6)
		dc.size = Vector3(w, 1.5 * k, w)
		dc.texture_albedo = _crack_texture()
		dc.cull_mask = 0xFFFFF
		get_parent().get_parent().add_child(dc)
		dc.global_position = ground_pos
		_marks.append([dc, 0.0])
		while _marks.size() > 4:
			(_marks.pop_front()[0] as Node).queue_free()
	shake = maxf(shake, 0.35 + strength * 0.65)


## Estampido sónico: anillo de condensación vertical alrededor del avatar y sacudida.
func sonic_boom() -> void:
	booms += 1
	var k := avatar.scale_k()
	var ring := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(46.0, 46.0) * k
	ring.mesh = q
	var m := ShaderMaterial.new()
	m.shader = SH_RING
	m.set_shader_parameter(&"strength", 1.1)
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# el anillo viaja con el avatar (a 343 m/s uno fijo en el mundo quedaría atrás al instante)
	avatar.add_child(ring)
	ring.position = Vector3(0, 0.9 * k, -0.8 * k)
	_rings.append([ring, 0.0, 0.9])
	shake = maxf(shake, 0.9)


func trick_started(_name: String) -> void:
	shake = maxf(shake, 0.25)
	_trail_t = 1.2
	trails_made += 1


func _ensure_trail() -> void:
	if _trail != null:
		return
	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	_trail.material_override = m
	add_child(_trail)


func _update_trail(dt: float) -> void:
	_trail_t = maxf(0.0, _trail_t - dt)
	var on := (
		avatar.state == Avatar.State.FLY
		and (_trail_t > 0.0 or avatar.acro.active() or (avatar.boost and avatar.speed > 300.0))
	)
	if _profile() == "low":
		on = on and avatar.acro.active()
	_ensure_trail()
	var p := avatar.global_position + Vector3(0, 0.9 * avatar.scale_k(), 0)
	if not _trail_pts.is_empty() and p.distance_to(_trail_pts[-1]) > 400.0:
		_trail_pts.clear()  # salto (cambio de origen): no dibujar una cinta enorme
	if on:
		_trail_pts.append(p)
	elif not _trail_pts.is_empty():
		_trail_pts.remove_at(0)
	while _trail_pts.size() > 28:
		_trail_pts.remove_at(0)
	_trail_mesh.clear_surfaces()
	if _trail_pts.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else p + Vector3.UP
	var w := 0.16 * avatar.scale_k()
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _trail_pts.size()
	for i in n:
		var a := _trail_pts[i]
		var b := _trail_pts[mini(i + 1, n - 1)] if i < n - 1 else a + (a - _trail_pts[i - 1])
		var side := (b - a).cross(eye - a).normalized() * w * (float(i) / n)
		# cerca de la cámara (tercera persona) la cinta se desvanece: si no, tapa la pantalla
		var near_fade := smoothstep(5.0, 14.0, a.distance_to(eye) / avatar.scale_k())
		var col := Color(0.75, 0.88, 1.0, 0.45 * pow(float(i) / n, 1.5) * near_fade)
		_trail_mesh.surface_set_color(col)
		_trail_mesh.surface_add_vertex(a - side)
		_trail_mesh.surface_set_color(col)
		_trail_mesh.surface_add_vertex(a + side)
	_trail_mesh.surface_end()


func _make_emitter(col: Color, size: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.9
	p.emitting = false
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 35.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = m
	p.mesh = sm
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.85))
	g.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	add_child(p)
	return p


func _update_skim(_dt: float) -> void:
	var on := avatar.state == Avatar.State.FLY and avatar.skim > 0.25 and avatar.speed > 30.0
	var water := avatar.surface == "agua"
	if _spray == null:
		var n := {"low": 24, "medium": 48, "high": 96, "ultra": 140}.get(_profile(), 48) as int
		_spray = _make_emitter(Color(0.92, 0.97, 1.0), 2.2, n)
		_dust = _make_emitter(Color(0.78, 0.68, 0.52), 2.8, n)
		_wake_mesh = ImmediateMesh.new()
		_wake = MeshInstance3D.new()
		_wake.mesh = _wake_mesh
		_wake.top_level = true
		_wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var wm := StandardMaterial3D.new()
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.vertex_color_use_as_albedo = true
		wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_wake.material_override = wm
		add_child(_wake)
	var k := avatar.scale_k()
	var ground_y := avatar.global_position.y - avatar.agl * k
	var at := Vector3(avatar.global_position.x, ground_y + 0.05 * k, avatar.global_position.z)
	if not at.is_finite():
		return
	var inten := clampf(avatar.skim * smoothstep(30.0, 250.0, avatar.speed), 0.0, 1.0)
	_spray.emitting = on and water
	_dust.emitting = on and not water
	for e: CPUParticles3D in [_spray, _dust]:
		e.global_position = at
		e.initial_velocity_max = 4.0 + 14.0 * inten
		e.speed_scale = 0.8 + inten
	if on:
		shake = maxf(shake, 0.18 * inten)
	# primer contacto rasante con el agua a velocidad: salpicón (anillo + rocío)
	var skim_water := on and water and avatar.skim > 0.6
	if skim_water and not _was_skim_water and avatar.speed > 60.0:
		splashes += 1
		burst(at, 0.35, false)
	_was_skim_water = skim_water
	# estela de espuma sobre el agua
	if on and water:
		_wake_pts.append(at)
	elif not _wake_pts.is_empty():
		_wake_pts.remove_at(0)
	if not _wake_pts.is_empty() and at.distance_to(_wake_pts[-1]) > 400.0:
		_wake_pts.clear()
	while _wake_pts.size() > 60:
		_wake_pts.remove_at(0)
	_wake_mesh.clear_surfaces()
	if _wake_pts.size() < 2:
		return
	_wake_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n2 := _wake_pts.size()
	for i in n2:
		var a := _wake_pts[i]
		var b := _wake_pts[mini(i + 1, n2 - 1)] if i < n2 - 1 else a + (a - _wake_pts[i - 1])
		var dir := b - a
		dir.y = 0.0
		var side := Vector3(-dir.z, 0.0, dir.x).normalized() * (0.6 + 2.4 * (1.0 - float(i) / n2)) * k
		var col := Color(1, 1, 1, 0.5 * float(i) / n2)
		_wake_mesh.surface_set_color(col)
		_wake_mesh.surface_add_vertex(a - side)
		_wake_mesh.surface_set_color(col)
		_wake_mesh.surface_add_vertex(a + side)
	_wake_mesh.surface_end()


func _update_wind(dt: float) -> void:
	if _wind == null:
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = 22050.0
		gen.buffer_length = 0.15
		_wind = AudioStreamPlayer.new()
		_wind.stream = gen
		_wind.volume_db = -60.0
		add_child(_wind)
		_wind.play()
		_wind_pb = _wind.get_stream_playback() as AudioStreamGeneratorPlayback
	var fly := avatar.state == Avatar.State.FLY
	var want := 0.0
	if fly:
		want = smoothstep(10.0, 600.0, avatar.speed) * 0.7 + avatar.skim * smoothstep(30.0, 250.0, avatar.speed) * 0.3
	wind_level = lerpf(wind_level, want, clampf(dt * 3.0, 0.0, 1.0))
	_wind.volume_db = linear_to_db(maxf(wind_level, 0.0005)) - 6.0
	if _wind_pb == null:
		return
	# ruido blanco con pasa-bajos cuyo corte sube con la velocidad (silbido más agudo)
	var cut := lerpf(0.02, 0.25, wind_level)
	var frames := _wind_pb.get_frames_available()
	for i in frames:
		_wind_lp += (_rng.randf_range(-1.0, 1.0) - _wind_lp) * cut
		_wind_pb.push_frame(Vector2(_wind_lp, _wind_lp) * 2.0)


func _process(dt: float) -> void:
	_update_trail(dt)
	_update_skim(dt)
	_update_wind(dt)
	for i in range(_rings.size() - 1, -1, -1):
		var r: Array = _rings[i]
		r[1] += dt
		var prog: float = r[1] / r[2]
		if prog >= 1.0:
			(r[0] as Node).queue_free()
			_rings.remove_at(i)
		else:
			((r[0] as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter(&"progress", prog)
	for i in range(_marks.size() - 1, -1, -1):
		var mk: Array = _marks[i]
		mk[1] += dt
		(mk[0] as Decal).albedo_mix = 1.0 - smoothstep(6.0, 9.0, mk[1])
		if mk[1] > 9.0:
			(mk[0] as Node).queue_free()
			_marks.remove_at(i)
	shake = maxf(0.0, shake - dt * 1.6)
	# líneas de velocidad y distorsión (la distorsión solo en perfiles altos)
	var inten := 0.0
	if avatar.state == Avatar.State.FLY:
		inten = smoothstep(220.0, 1200.0, avatar.speed)
	var mat := _overlay.material as ShaderMaterial
	_overlay.visible = inten > 0.02
	mat.set_shader_parameter(&"intensity", inten)
	mat.set_shader_parameter(&"distort", _profile() in ["high", "ultra"])
