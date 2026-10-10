class_name AvatarFx
extends Node3D
## Efectos del vuelo de superhéroe, con presupuesto por perfil gráfico:
## despegue explosivo (polvo + onda), aterrizaje pesado (onda + polvo + marca), sacudida de
## cámara, líneas de velocidad / distorsión de aire, estiramiento de FOV.

const SH_RING := preload("res://shaders/shockwave.gdshader")
const SH_CRATER := preload("res://shaders/crater.gdshader")
const SH_LINES := preload("res://shaders/speed_lines.gdshader")
const DUST_BY_PROFILE := {"low": 16, "medium": 48, "high": 110, "ultra": 180}

var avatar: Avatar
var shake: float = 0.0
var _overlay: ColorRect
var _layer: CanvasLayer
var _rings: Array = []  # [MeshInstance3D, t, dur]
var _marks: Array = []  # [MeshInstance3D, t]
var _dust_mat: StandardMaterial3D


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
	for sh: Shader in [SH_RING, SH_CRATER]:
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
	_overlay.visible = true
	(_overlay.material as ShaderMaterial).set_shader_parameter(&"intensity", 0.0)
	for i in 3:
		await get_tree().process_frame
	for n in nodes:
		n.queue_free()


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
		var mk := MeshInstance3D.new()
		var mq := QuadMesh.new()
		mq.size = Vector2(5.0, 5.0) * k * (0.6 + strength * 0.6)
		mq.orientation = PlaneMesh.FACE_Y
		mk.mesh = mq
		var cm := ShaderMaterial.new()
		cm.shader = SH_CRATER
		mk.material_override = cm
		mk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_parent().get_parent().add_child(mk)
		mk.global_position = ground_pos + Vector3(0, 0.1 * k, 0)
		_marks.append([mk, 0.0])
		while _marks.size() > 4:
			(_marks.pop_front()[0] as Node).queue_free()
	shake = maxf(shake, 0.35 + strength * 0.65)


func _process(dt: float) -> void:
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
		var f := 1.0 - smoothstep(6.0, 9.0, mk[1])
		((mk[0] as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter(&"fade", f)
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
