class_name AvatarBody
extends Node3D
## Cuerpo visible del avatar (tercera persona, sombras, pantalla de selección).
## Instancia la malla base de CharacterDef, aplica colores/pelo/accesorios y elige animación
## y pose de vuelo según el estado del Avatar. Todo lo de "look" sale de CharacterDef, así que
## trajes, peinados y accesorios nuevos se agregan sin tocar la lógica de vuelo.

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
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	for n in ANIM.values():
		if anim.has_animation(n) and n != "Jump_Land":
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	pose = FlightPose.new()
	pose.female = def.body == "female"
	skeleton.add_child(pose)
	_apply_look()
	_play("idle")


func _apply_look() -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var m := StandardMaterial3D.new()
			var main := src == null or src.resource_name != "M_Joints"
			m.albedo_color = def.suit_color if main else def.accent_color
			m.roughness = 0.45 if main else 0.35
			m.metallic = 0.0 if main else 0.2
			m.rim_enabled = true
			m.rim = 0.25
			mi.set_surface_override_material(s, m)
	_attach_hair()
	for acc: String in def.accessories:
		match acc:
			"cape":
				_attach_cape()
			"belt":
				_attach_ring("DEF-spine.001", 0.17, 0.05, def.accent_color, Vector3(0, 0.02, 0))
			"wristbands":
				_attach_ring("DEF-forearm.L", 0.045, 0.07, def.accent_color, Vector3(0, 0.2, 0))
				_attach_ring("DEF-forearm.R", 0.045, 0.07, def.accent_color, Vector3(0, 0.2, 0))


func _attach(bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	return ba


func _attach_hair() -> void:
	if def.hair_style == "none":
		return
	var ba := _attach("DEF-head")
	var m := StandardMaterial3D.new()
	m.albedo_color = def.hair_color
	m.roughness = 0.6
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
	var ba := _attach("DEF-spine.003")
	var q := QuadMesh.new()
	q.size = Vector2(0.48, 1.15)
	q.subdivide_width = 3
	q.subdivide_depth = 10
	var mi := MeshInstance3D.new()
	mi.name = "Capa"
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/cape.gdshader")
	m.set_shader_parameter(&"color", def.accent_color)
	mi.material_override = m
	mi.position = Vector3(0, -0.42, -0.13)
	mi.rotation_degrees = Vector3(8, 0, 0)
	ba.add_child(mi)


func set_cape_wind(v: float) -> void:
	var c := model.find_child("Capa", true, false) as MeshInstance3D
	if c != null:
		(c.material_override as ShaderMaterial).set_shader_parameter(&"wind", v)


func _play(key: String) -> void:
	if _cur_anim == key:
		return
	_cur_anim = key
	var n: String = ANIM[key]
	if anim.has_animation(n):
		anim.play(n, 0.25)


func impact() -> void:
	_land_t = 1.1


func launch() -> void:
	_launch_t = 0.7


## Lo llama el avatar cada cuadro.
func drive(state: int, speed: float, climb: float, boosted: bool, dt: float) -> void:
	if model == null:
		return
	_land_t = maxf(0.0, _land_t - dt)
	_launch_t = maxf(0.0, _launch_t - dt)
	var target := {"hover": 0.0, "cruise": 0.0, "fist": 0.0, "land": 0.0, "launch": 0.0}
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
		var fast := smoothstep(260.0, 600.0, speed) if boosted or speed > 300.0 else 0.0
		var cruise := smoothstep(8.0, 60.0, speed) * (1.0 - fast)
		target.hover = 1.0 - maxf(cruise, fast)
		target.cruise = cruise
		target.fist = fast
		fist = fast
		pitch = 75.0 * cruise + 88.0 * fast
		pitch -= clampf(climb / maxf(speed, 20.0), -0.6, 0.9) * 35.0 * (cruise + fast)
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
	_pitch = lerpf(_pitch, pitch, clampf(dt * 3.0, 0.0, 1.0))
	pivot.rotation.x = -deg_to_rad(_pitch)
	# en cuclillas la cadera baja: los pies quedan en el suelo
	model.position.y = -0.95 - 0.42 * float(pose.weights.land) * def.height_scale
	set_cape_wind(clampf(speed / 300.0, 0.0, 1.0) if state != Avatar.State.WALK else clampf(speed / 6.0, 0.0, 0.3))
