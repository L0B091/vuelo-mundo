extends SceneTree
## Vista de control de personajes: masculino y femenino de frente y de perfil, más poses de vuelo.
## godot --path . --script res://tools/char_preview.gd -- out.png
var _f := 0
var _bodies: Array = []


func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 7.5)
	cam.fov = 38
	root.add_child(cam)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-35, 25, 0)
	root.add_child(l)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.4, 0.5)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	root.add_child(env)
	var specs := [
		["male", 0.0, "idle"],
		["female", 0.0, "idle"],
		["male", 90.0, "idle"],
		["male", 90.0, "cruise"],
		["male", 90.0, "fist"],
		["female", 90.0, "land"]
	]
	for i in specs.size():
		var b := AvatarBody.new()
		root.add_child(b)
		b.setup(CharacterDef.preset(specs[i][0]))
		b.position = Vector3(-5.0 + i * 2.0, 0, 0)
		b.rotation_degrees.y = 180.0 + specs[i][1]
		_bodies.append([b, specs[i][2]])


func _process(dt: float) -> bool:
	_f += 1
	for e in _bodies:
		var b: AvatarBody = e[0]
		match e[1]:
			"idle":
				b.drive(Avatar.State.WALK, 0.0, 0.0, false, dt)
			"cruise":
				b.drive(Avatar.State.FLY, 200.0, 0.0, false, dt)
			"fist":
				b.drive(Avatar.State.FLY, 900.0, 0.0, true, dt)
			"land":
				b.impact()
				b.drive(Avatar.State.WALK, 0.0, 0.0, false, dt)
	if _f == 90:
		get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		quit()
	return false
