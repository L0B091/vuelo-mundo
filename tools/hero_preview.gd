extends SceneTree
## Vista de control de personajes: masculino y femenino de frente y de perfil, más poses de vuelo.
## godot --path . --script res://tools/char_preview.gd -- out.png
var _f := 0
var _bodies: Array = []


func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 8.2)
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
	var view := 90.0
	if OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "back":
		view = 180.0
	var specs := []
	for k in ["hover", "launch", "cruise", "fist", "brake", "dive", "land"]:
		specs.append(["male", view, k])
	var a := OS.get_cmdline_user_args()
	if a.size() > 3:  # primer plano: [ancho_x, y, z] de cámara
		cam.position = Vector3(float(a[1]), float(a[2]), float(a[3]))
		cam.fov = 22
	for i in specs.size():
		var b := AvatarBody.new()
		root.add_child(b)
		b.setup(CharacterDef.preset(specs[i][0]))
		b.position = Vector3(-6.6 + i * 2.2, 0, 0)
		b.rotation_degrees.y = 180.0 + specs[i][1]
		_bodies.append([b, specs[i][2]])


func _process(dt: float) -> bool:
	_f += 1
	for e in _bodies:
		var b: AvatarBody = e[0]
		match e[1]:
			"idle":
				b.drive(Avatar.State.WALK, 0.0, 0.0, false, dt)
			"walk":
				b.drive(Avatar.State.WALK, 1.6, 0.0, false, dt)
			"run":
				b.drive(Avatar.State.WALK, 6.0, 0.0, false, dt)
			"hover":
				b.drive(Avatar.State.FLY, 0.0, 0.0, false, dt)
			"launch":
				if _f == 80:
					b.launch()
				b.drive(Avatar.State.FLY, 0.0, 30.0, false, dt)
			"brake":
				b.drive(Avatar.State.FLY, maxf(20.0, 260.0 - _f * 2.5), 0.0, false, dt)
			"dive":
				b.drive(Avatar.State.FLY, 150.0, -120.0, false, dt)
			"cruise":
				b.drive(Avatar.State.FLY, 120.0, 0.0, false, dt)
			"fist":
				b.drive(Avatar.State.FLY, 900.0, 0.0, true, dt)
			"land":
				b.impact()
				b.drive(Avatar.State.WALK, 0.0, 0.0, false, dt)
	if _f == 90:
		get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		quit()
	return false
