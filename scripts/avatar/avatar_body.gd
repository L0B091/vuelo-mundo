class_name AvatarBody
extends Node3D
## Cuerpo visible del avatar (tercera persona, sombras, pantalla de selección).
## Instancia la malla base de CharacterDef, aplica colores/pelo/accesorios y elige animación
## y pose de vuelo según el estado del Avatar. Todo lo de "look" sale de CharacterDef, así que
## trajes, peinados y accesorios nuevos se agregan sin tocar la lógica de vuelo.

const SUIT_SHADER := preload("res://shaders/hero_suit.gdshader")
const ANIM := {"idle": "Idle", "walk": "Walk", "run": "Sprint", "fly": "Jump", "land": "Jump_Land"}

var def: CharacterDef
var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var pose: FlightPose
var pivot: Node3D  # gira el cuerpo entero (inclinación en vuelo)
var _cur_anim: String = ""
var _land_t: float = 0.0
var _launch_t: float = 0.0
var _pitch: float = 0.0


func setup(p_def: CharacterDef) -> void:
	def = p_def
	if pivot != null:
		pivot.queue_free()
	pivot = Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0, 0.95, 0)
	add_child(pivot)
	var ps: PackedScene = load(def.base_scene)
	model = ps.instantiate()
	model.rotation_degrees.y = 180.0  # el modelo mira a +Z; el avatar avanza hacia -Z
	model.position = Vector3(0, -0.95, 0)
	model.scale = Vector3.ONE * def.height_scale
	pivot.add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if (
		players.is_empty()
		or not (
			(players[0] as AnimationPlayer).has_animation(&"Idle_Loop")
			or (players[0] as AnimationPlayer).has_animation(&"Idle")
		)
	):
		# cuerpo sin animaciones propias: se le monta la biblioteca del mismo esqueleto
		anim = AnimationPlayer.new()
		anim.name = "AnimationPlayer"
		model.add_child(anim)
		var src: Node = (load(def.anim_scene) as PackedScene).instantiate()
		var sp := src.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		anim.add_animation_library("", sp.get_animation_library(""))
		src.free()
	else:
		anim = players[0]
	for n: String in ANIM.values():
		var an := _anim_name(n)
		if an != "" and n != "Jump_Land":
			anim.get_animation(an).loop_mode = Animation.LOOP_LINEAR
	pose = FlightPose.new()
	# el maniquí único se ajustaba para "femenino"; los cuerpos nuevos ya son distintos
	pose.female = def.body == "female" and def.base_scene == CharacterDef.BASE_SCENE
	pose.posture = 0.75 if def.original_look else 0.0
	skeleton.add_child(pose)
	_apply_look()
	_play("idle")


const BUSINESS_SHADER := preload("res://shaders/hero_business.gdshader")
const GLASSES_POS := Vector3(0, 0.098, 0.105)


func _apply_look() -> void:
	if def.original_look:
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		return
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if def.suit_style == "business" and mi.skin != null and mi.mesh.get_aabb().size.y > 1.0:
			mi.mesh = _with_rest_attrs(mi.mesh as ArrayMesh)
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			mi.set_surface_override_material(s, _suit_material(src))
	_attach_hair()
	for acc: String in def.accessories:
		match acc:
			"cape":
				_attach_cape()
			"glasses":
				_attach_glasses()
			"belt":
				_attach_ring("DEF-spine.001", 0.17, 0.05, def.accent_color, Vector3(0, 0.02, 0))
			"wristbands":
				_attach_ring("DEF-forearm.L", 0.045, 0.07, def.accent_color, Vector3(0, 0.2, 0))
				_attach_ring("DEF-forearm.R", 0.045, 0.07, def.accent_color, Vector3(0, 0.2, 0))


func _anim_name(n: String) -> String:
	if anim.has_animation(n):
		return n
	if anim.has_animation(n + "_Loop"):
		return n + "_Loop"
	return ""


## Material del traje según CharacterDef. Las texturas PBR originales (color, normal,
## rugosidad) se conservan; el estilo solo tiñe/ajusta. Ojos y cejas quedan como vienen.
func _suit_material(src: Material) -> Material:
	var name := src.resource_name if src != null else ""
	if src is BaseMaterial3D and (name.contains("Eye") or name.contains("Hair")):
		if name.contains("Hair") and def.suit_style == "business":
			var hb := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
			hb.albedo_color = def.hair_color * 3.0
			return hb
		return src
	if not (src is BaseMaterial3D):
		# maniquí sin texturas (UAL): colores planos de traje/acento
		var m := StandardMaterial3D.new()
		var main := src == null or name != "M_Joints"
		m.albedo_color = def.suit_color if main else def.accent_color
		m.roughness = 0.45 if main else 0.35
		m.rim_enabled = true
		m.rim = 0.25
		return m
	var mask_path := def.base_scene.get_basename() + "_suitmask.png"
	if def.suit_style == "business" and ResourceLoader.exists(mask_path):
		var b0 := src as BaseMaterial3D
		var bs := ShaderMaterial.new()
		bs.shader = BUSINESS_SHADER
		bs.set_shader_parameter(&"base_tex", b0.albedo_texture)
		bs.set_shader_parameter(&"normal_tex", b0.normal_texture)
		bs.set_shader_parameter(&"rough_tex", b0.roughness_texture)
		bs.set_shader_parameter(&"mask_tex", load(mask_path))
		bs.set_shader_parameter(&"suit_color", def.suit_color)
		bs.set_shader_parameter(&"tie_color", def.accent_color)
		return bs
	if def.suit_style != "classic" and ResourceLoader.exists(mask_path):
		var bm := src as BaseMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = SUIT_SHADER
		sm.set_shader_parameter(&"base_tex", bm.albedo_texture)
		sm.set_shader_parameter(&"normal_tex", bm.normal_texture)
		sm.set_shader_parameter(&"rough_tex", bm.roughness_texture)
		sm.set_shader_parameter(&"mask_tex", load(mask_path))
		var sc := def.suit_color
		if def.suit_style == "stealth":
			sc = Color(0.07, 0.07, 0.08)
		sm.set_shader_parameter(&"suit_color", sc)
		sm.set_shader_parameter(&"accent_color", def.accent_color)
		sm.set_shader_parameter(&"metal", 0.7 if def.suit_style == "metal" else 0.0)
		return sm
	var mm := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
	match def.suit_style:
		"color":
			mm.albedo_color = def.suit_color.lerp(Color.WHITE, 0.15)
		"metal":
			mm.albedo_color = def.suit_color
			mm.metallic = 0.65
			mm.roughness = 0.32
		"stealth":
			mm.albedo_color = Color(0.16, 0.16, 0.18)
			mm.roughness = 0.75
	mm.rim_enabled = true
	mm.rim = 0.2
	mm.rim_tint = 0.4
	return mm


## Copia la malla con la posición de reposo de cada vértice en UV2 (x, y) y COLOR.r (z): el
## shader del traje de calle ubica camisa/corbata/zapatos sin que se deslicen con la pose.
static func _with_rest_attrs(src: ArrayMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var a := src.surface_get_arrays(si)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var uv2 := PackedVector2Array()
		var col := PackedColorArray()
		uv2.resize(v.size())
		col.resize(v.size())
		for i in v.size():
			uv2[i] = Vector2(v[i].x, v[i].y)
			col[i] = Color(clampf((v[i].z + 0.3) / 0.6, 0.0, 1.0), 0, 0, 1)
		a[Mesh.ARRAY_TEX_UV2] = uv2
		a[Mesh.ARRAY_COLOR] = col
		var fmt := src.surface_get_format(si) & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
		out.add_surface_from_arrays(src.surface_get_primitive_type(si), a, [], {}, fmt | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_COLOR)
		out.surface_set_material(si, src.surface_get_material(si))
	return out


## Anteojos de marco fino en el hueso de la cabeza (procedurales, sin textura).
func _attach_glasses() -> void:
	var ba := _attach("DEF-head")
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.03, 0.035)
	m.roughness = 0.3
	m.metallic = 0.4
	var root := Node3D.new()
	root.position = GLASSES_POS
	ba.add_child(root)
	for sx in [-1.0, 1.0]:
		var t := TorusMesh.new()
		t.inner_radius = 0.0175
		t.outer_radius = 0.0205
		t.rings = 16
		t.ring_segments = 6
		var r := MeshInstance3D.new()
		r.mesh = t
		r.material_override = m
		r.rotation_degrees.x = 90.0
		r.scale = Vector3(1.15, 1.0, 0.85)
		r.position = Vector3(0.032 * sx, 0, 0)
		root.add_child(r)
		var arm := BoxMesh.new()
		arm.size = Vector3(0.003, 0.004, 0.1)
		var am := MeshInstance3D.new()
		am.mesh = arm
		am.material_override = m
		am.position = Vector3(0.069 * sx, 0.004, -0.05)
		root.add_child(am)
	var br := BoxMesh.new()
	br.size = Vector3(0.022, 0.003, 0.003)
	var bm := MeshInstance3D.new()
	bm.mesh = br
	bm.material_override = m
	bm.position = Vector3(0, 0.006, 0)
	root.add_child(bm)


func _attach(bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	var bi := FlightPose.find_any(skeleton, bone)
	ba.bone_name = skeleton.get_bone_name(bi) if bi >= 0 else bone
	skeleton.add_child(ba)
	return ba


func _attach_hair() -> void:
	if def.hair_style == "none":
		return
	var ba := _attach("DEF-head")
	var m := StandardMaterial3D.new()
	m.albedo_color = def.hair_color * 2.2
	m.albedo_texture = load("res://assets/characters/superhero/T_Hair_1_BaseColor.png")
	m.uv1_scale = Vector3(1, 1, 1)
	m.roughness = 0.55
	var shell := _hair_shell(m)
	if shell == null:
		var cap := SphereMesh.new()
		cap.radius = 0.112
		cap.height = 0.2
		var mi := MeshInstance3D.new()
		mi.mesh = cap
		mi.material_override = m
		mi.position = Vector3(0, 0.165, 0.012)
		mi.scale = Vector3(1.0, 0.85, 1.08)
		ba.add_child(mi)
	if def.hair_style in ["long", "bun"]:
		var tail := CapsuleMesh.new()
		tail.radius = 0.05 if def.hair_style == "long" else 0.065
		tail.height = 0.34 if def.hair_style == "long" else 0.13
		var t := MeshInstance3D.new()
		t.mesh = tail
		t.material_override = m
		t.position = Vector3(0, 0.02, -0.11) if def.hair_style == "long" else Vector3(0, 0.17, -0.1)
		t.rotation_degrees.x = -12.0
		ba.add_child(t)


## Pelo esculpido sobre el cráneo: copia los triángulos de la cabeza del cuerpo (pesados al
## hueso de la cabeza), arriba de la frente y atrás, inflados ~1.5 cm por la normal. Comparte
## esqueleto y piel, así que se deforma con la cabeza sin costo extra de animación.
func _hair_shell(mat: Material) -> MeshInstance3D:
	var body_mi: MeshInstance3D = null
	var best := 0
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh is ArrayMesh and mi.skin != null:
			var n := (mi.mesh as ArrayMesh).surface_get_array_len(0)
			if n > best:
				best = n
				body_mi = mi
	if body_mi == null:
		return null
	var head_bone := FlightPose.find_any(skeleton, "DEF-head")
	var bind := -1
	for i in body_mi.skin.get_bind_count():
		var bb := body_mi.skin.get_bind_bone(i)
		if bb == head_bone or (bb < 0 and skeleton.find_bone(body_mi.skin.get_bind_name(i)) == head_bone):
			bind = i
	if bind < 0:
		return null
	var arr := (body_mi.mesh as ArrayMesh).surface_get_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nor: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var per := bones.size() / pos.size()
	var head := PackedByteArray()
	head.resize(pos.size())
	var ymin := INF
	var ymax := -INF
	var zc := 0.0
	var cnt := 0
	for v in pos.size():
		for j in per:
			if bones[v * per + j] == bind and wts[v * per + j] > 0.6:
				head[v] = 1
				ymin = minf(ymin, pos[v].y)
				ymax = maxf(ymax, pos[v].y)
				zc += pos[v].z
				cnt += 1
	if cnt < 50:
		return null
	zc /= cnt
	var fz := 1.0  # adelante = lado donde la cabeza tiene más volumen bajo la frente (cara)
	var hgt := ymax - ymin
	var keep := func(v: int) -> bool:
		if head[v] == 0:
			return false
		var t := (pos[v].y - ymin) / hgt
		var front := (pos[v].z - zc) * fz
		return t > 0.74 or (t > 0.42 and front < 0.0) or (t > 0.6 and front < 0.035)
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_b := PackedInt32Array()
	var out_w := PackedFloat32Array()
	var out_uv := PackedVector2Array()
	var remap := {}
	var out_i := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if not (keep.call(idx[t]) and keep.call(idx[t + 1]) and keep.call(idx[t + 2])):
			continue
		for k in 3:
			var v := idx[t + k]
			if not remap.has(v):
				remap[v] = out_v.size()
				out_v.append(pos[v] + nor[v] * 0.014)
				out_n.append(nor[v])
				out_uv.append(Vector2(pos[v].x, pos[v].z) * 6.0)
				for j in per:
					out_b.append(bones[v * per + j])
					out_w.append(wts[v * per + j])
			out_i.append(remap[v])
	if out_i.is_empty():
		return null
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = out_v
	a[Mesh.ARRAY_NORMAL] = out_n
	a[Mesh.ARRAY_TEX_UV] = out_uv
	a[Mesh.ARRAY_BONES] = out_b
	a[Mesh.ARRAY_WEIGHTS] = out_w
	a[Mesh.ARRAY_INDEX] = out_i
	var am := ArrayMesh.new()
	var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, flags)
	var hm := MeshInstance3D.new()
	hm.name = "PeloEsculpido"
	hm.mesh = am
	hm.skin = body_mi.skin
	hm.material_override = mat
	body_mi.get_parent().add_child(hm)
	hm.transform = body_mi.transform
	hm.skeleton = hm.get_path_to(skeleton)
	return hm


func _attach_ring(bone: String, radius: float, h: float, c: Color, off: Vector3) -> void:
	var ba := _attach(bone)
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = h
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.5
	m.roughness = 0.3
	mi.material_override = m
	mi.position = off
	ba.add_child(mi)


func _attach_cape() -> void:
	# capa de tela simulada (antes: quad con sombreador de vaivén)
	var cape := CapeCloth.new()
	cape.name = "Capa"
	pivot.add_child(cape)
	cape.setup(self, def.accent_color)


func set_cape_wind(v: float) -> void:
	var c := pivot.get_node_or_null("Capa") as CapeCloth
	if c != null:
		c.wind_scale = 0.6 + v


func _play(key: String) -> void:
	if _cur_anim == key:
		return
	_cur_anim = key
	var n := _anim_name(ANIM[key])
	if n != "":
		anim.play(n, 0.25)


func impact() -> void:
	_land_t = 1.1


func launch() -> void:
	_launch_t = 0.7


## Lo llama el avatar cada cuadro.
## Actitud de vuelo: alabeo en curvas y rotaciones de acrobacia (grados), sobre la pose.
func set_attitude(bank_deg: float, roll_deg: float, pitch_deg: float, yaw_deg: float) -> void:
	if pivot == null:
		return
	pivot.rotation.x = -deg_to_rad(_pitch + pitch_deg)
	pivot.rotation.y = -deg_to_rad(yaw_deg)
	pivot.rotation.z = -deg_to_rad(bank_deg + roll_deg)


var _prev_speed: float = 0.0
var _brake: float = 0.0


func drive(state: int, speed: float, climb: float, boosted: bool, dt: float) -> void:
	if model == null:
		return
	_land_t = maxf(0.0, _land_t - dt)
	_launch_t = maxf(0.0, _launch_t - dt)
	var target := {"hover": 0.0, "cruise": 0.0, "fist": 0.0, "brake": 0.0, "land": 0.0, "launch": 0.0}
	var fist := 0.0
	var pitch := 0.0
	if state == Avatar.State.WALK:
		if _land_t > 0.0:
			target.land = 1.0
			_play("land")
		elif speed > 3.0:
			_play("run")
		elif speed > 0.3:
			_play("walk")
		else:
			_play("idle")
	else:
		_play("fly")
		var fast := smoothstep(220.0, 520.0, speed)
		var cruise := smoothstep(6.0, 45.0, speed) * (1.0 - fast)
		# frenado brusco (pierde > 25 m/s²): se endereza con pose de freno
		var decel := (_prev_speed - speed) / maxf(dt, 0.001)
		_brake = lerpf(_brake, 1.0 if decel > 25.0 and speed > 8.0 else 0.0, clampf(dt * 6.0, 0.0, 1.0))
		var moving := maxf(cruise, fast) * (1.0 - _brake)
		target.hover = (1.0 - maxf(cruise, fast)) * (1.0 - _brake)
		target.cruise = cruise * (1.0 - _brake)
		target.fist = fast * (1.0 - _brake)
		target.brake = _brake
		fist = maxf(cruise, fast)
		# horizontal en crucero; en picada de cabeza (hasta 180°), en subida se endereza
		var slope := rad_to_deg(asin(clampf(climb / maxf(speed, 1.0), -1.0, 1.0)))
		pitch = 86.0 * moving - slope * moving - 20.0 * _brake
		pitch = clampf(pitch, -25.0, 175.0)
		if _launch_t > 0.0:
			for p: String in target:
				target[p] = 0.0
			target.launch = 1.0
			fist = 0.0
			pitch = 0.0
	var a := clampf(dt * 5.0, 0.0, 1.0)
	var a_fast := clampf(dt * 16.0, 0.0, 1.0)  # despegue/impacto: pose casi instantánea
	for p: String in target:
		var r := a_fast if p in ["land", "launch"] else a
		pose.weights[p] = lerpf(float(pose.weights[p]), float(target[p]), r)
	pose.fist_r = lerpf(pose.fist_r, fist, a)
	_prev_speed = speed
	_pitch = lerpf(_pitch, pitch, clampf(dt * 3.0, 0.0, 1.0))
	pivot.rotation.x = -deg_to_rad(_pitch)
	# en cuclillas la cadera baja: los pies quedan en el suelo
	model.position.y = -0.95 - 0.42 * float(pose.weights.land) * def.height_scale
	set_cape_wind(clampf(speed / 300.0, 0.0, 1.0) if state != Avatar.State.WALK else clampf(speed / 6.0, 0.0, 0.3))
