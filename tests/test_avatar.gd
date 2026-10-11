extends GutTest
## Personaje: presets masculino/femenino, animaciones base, poses de vuelo y cámara.

var _seen: Dictionary = {}


## Las poses de los modificadores solo existen durante la actualización del esqueleto:
## se leen en la señal skeleton_updated.
func _watch(sk: Skeleton3D, bones: Array) -> void:
	sk.skeleton_updated.connect(
		func() -> void:
			for bn: String in bones:
				_seen[bn] = sk.get_bone_global_pose(FlightPose.find_any(sk, bn)).origin
	)


func _body(kind: String) -> AvatarBody:
	var b := AvatarBody.new()
	add_child_autofree(b)
	b.setup(CharacterDef.preset(kind))
	return b


func test_presets_differ_and_are_customizable() -> void:
	var m := CharacterDef.preset("male")
	var f := CharacterDef.preset("female")
	assert_eq(m.body, "male")
	assert_eq(f.body, "female")
	assert_ne(m.hair_style, f.hair_style)
	assert_ne(f.base_scene, m.base_scene, "cuerpos separados masculino/femenino")
	assert_true(f.accessories.has("cape"))
	assert_eq(m.suit_style, "business", "protagonista masculino de traje de calle")
	assert_false(m.accessories.has("cape"))


func test_base_animations_exist() -> void:
	var b := _body("male")
	for key: String in ["idle", "walk", "run", "fly", "land"]:
		assert_true(b.anim.has_animation(AvatarBody.ANIM[key]), "falta animación " + key)


func test_fist_forward_pose_raises_right_hand_past_head() -> void:
	var b := _body("male")
	_watch(b.skeleton, ["DEF-hand.R", "DEF-head"])
	for i in 40:
		b.drive(Avatar.State.FLY, 900.0, 0.0, true, 0.05)
		await wait_process_frames(1)
	var hand: Vector3 = _seen["DEF-hand.R"]
	var head: Vector3 = _seen["DEF-head"]
	# en espacio del modelo (+Y = arriba del cuerpo): el puño queda más allá de la cabeza
	assert_gt(hand.y, head.y + 0.2, "mano %s cabeza %s" % [hand, head])
	assert_gt(float(b.pose.weights.fist), 0.9)


func test_cruise_pose_arms_back() -> void:
	var b := _body("female")
	_watch(b.skeleton, ["DEF-hand.L", "DEF-hips"])
	for i in 40:
		b.drive(Avatar.State.FLY, 150.0, 0.0, false, 0.05)
		await wait_process_frames(1)
	var hand: Vector3 = _seen["DEF-hand.L"]
	var hips: Vector3 = _seen["DEF-hips"]
	assert_lt(hand.y, hips.y + 0.1, "brazos atrás, pegados al cuerpo")
	assert_gt(b.pivot.rotation_degrees.x, -90.0)
	assert_lt(b.pivot.rotation_degrees.x, -60.0, "cuerpo inclinado hacia adelante en crucero")


func test_camera_toggle_default_first_person() -> void:
	var a := Avatar.new()
	add_child_autofree(a)
	a.set_character(CharacterDef.preset("male"))
	assert_false(a.third_person)
	a.toggle_camera()
	assert_true(a.third_person)
	a.toggle_camera()
	assert_false(a.third_person)
