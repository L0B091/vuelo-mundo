class_name FlightPose
extends SkeletonModifier3D
## Poses de vuelo superpuestas a la animación base (diseño propio de superhéroe):
##   hover  - erguido, brazos algo abiertos, una rodilla flexionada
##   cruise - brazos hacia atrás pegados al cuerpo, piernas juntas
##   fist   - puño derecho adelante (sobre la cabeza en espacio del cuerpo), izquierdo atrás
##   land   - aterrizaje pesado: cuclillas con el puño derecho al suelo
##   launch - despegue: brazos arriba, cuerpo estirado
## Cada pose da direcciones objetivo (espacio del modelo: +Z adelante, +X izquierda, +Y arriba)
## para los huesos; el modificador gira cada hueso hacia su objetivo según el peso.
## Proporciones (cuerpo masculino/femenino) también se aplican acá, después de la animación.

const CHAINS := [
	"DEF-spine.001",
	"DEF-spine.002",
	"DEF-spine.003",
	"DEF-neck",
	"DEF-head",
	"DEF-upper_arm.L",
	"DEF-forearm.L",
	"DEF-hand.L",
	"DEF-upper_arm.R",
	"DEF-forearm.R",
	"DEF-hand.R",
	"DEF-thigh.L",
	"DEF-shin.L",
	"DEF-foot.L",
	"DEF-thigh.R",
	"DEF-shin.R",
	"DEF-foot.R"
]
const POSES := {
	"hover":
	{
		"DEF-upper_arm.L": Vector3(0.45, -0.88, 0.1),
		"DEF-forearm.L": Vector3(0.3, -0.9, 0.3),
		"DEF-upper_arm.R": Vector3(-0.45, -0.88, 0.1),
		"DEF-forearm.R": Vector3(-0.3, -0.9, 0.3),
		"DEF-thigh.L": Vector3(0.08, -0.95, 0.05),
		"DEF-shin.L": Vector3(0.05, -1.0, -0.05),
		"DEF-thigh.R": Vector3(-0.06, -0.85, 0.5),
		"DEF-shin.R": Vector3(-0.03, -0.95, -0.3),
		"DEF-foot.L": Vector3(0, -0.6, 0.8),
		"DEF-foot.R": Vector3(0, -0.7, 0.7),
	},
	"cruise":
	{
		"DEF-upper_arm.L": Vector3(0.22, -0.95, -0.2),
		"DEF-forearm.L": Vector3(0.12, -0.96, -0.25),
		"DEF-upper_arm.R": Vector3(-0.22, -0.95, -0.2),
		"DEF-forearm.R": Vector3(-0.12, -0.96, -0.25),
		"DEF-thigh.L": Vector3(0.03, -1.0, -0.03),
		"DEF-shin.L": Vector3(0.0, -1.0, -0.06),
		"DEF-thigh.R": Vector3(-0.03, -1.0, -0.03),
		"DEF-shin.R": Vector3(0.0, -1.0, -0.06),
		"DEF-foot.L": Vector3(0, -1.0, 0.1),
		"DEF-foot.R": Vector3(0, -1.0, 0.1),
		"DEF-head": Vector3(0, 0.75, 0.66),
		"DEF-neck": Vector3(0, 0.85, 0.5),
	},
	"fist":
	{
		"DEF-upper_arm.R": Vector3(-0.08, 1.0, 0.12),
		"DEF-forearm.R": Vector3(-0.02, 1.0, 0.08),
		"DEF-hand.R": Vector3(0, 1.0, 0.05),
		"DEF-upper_arm.L": Vector3(0.2, -0.95, -0.22),
		"DEF-forearm.L": Vector3(0.1, -0.96, -0.25),
		"DEF-thigh.L": Vector3(0.03, -1.0, -0.04),
		"DEF-shin.L": Vector3(0.0, -1.0, -0.05),
		"DEF-thigh.R": Vector3(-0.03, -1.0, -0.04),
		"DEF-shin.R": Vector3(0.0, -1.0, -0.05),
		"DEF-foot.L": Vector3(0, -1.0, 0.05),
		"DEF-foot.R": Vector3(0, -1.0, 0.05),
		"DEF-head": Vector3(0, 0.7, 0.7),
		"DEF-neck": Vector3(0, 0.8, 0.6),
	},
	"land":
	{
		"DEF-spine.001": Vector3(0, 0.8, 0.6),
		"DEF-spine.002": Vector3(0, 0.75, 0.66),
		"DEF-spine.003": Vector3(0, 0.8, 0.6),
		"DEF-head": Vector3(0, 0.9, 0.4),
		"DEF-upper_arm.R": Vector3(-0.15, -0.85, 0.5),
		"DEF-forearm.R": Vector3(-0.05, -1.0, 0.1),
		"DEF-upper_arm.L": Vector3(0.7, -0.4, -0.55),
		"DEF-forearm.L": Vector3(0.6, -0.2, -0.7),
		"DEF-thigh.L": Vector3(0.25, -0.15, 0.95),
		"DEF-shin.L": Vector3(0.05, -1.0, -0.1),
		"DEF-thigh.R": Vector3(-0.2, -0.85, -0.45),
		"DEF-shin.R": Vector3(-0.05, -0.15, -0.98),
		"DEF-foot.L": Vector3(0, -0.2, 1.0),
		"DEF-foot.R": Vector3(0, -0.8, -0.2),
	},
	"launch":
	{
		"DEF-upper_arm.R": Vector3(-0.15, 0.98, 0.1),
		"DEF-forearm.R": Vector3(-0.05, 1.0, 0.05),
		"DEF-upper_arm.L": Vector3(0.15, 0.98, 0.1),
		"DEF-forearm.L": Vector3(0.05, 1.0, 0.05),
		"DEF-thigh.L": Vector3(0.03, -1.0, -0.05),
		"DEF-thigh.R": Vector3(-0.03, -1.0, -0.05),
		"DEF-shin.L": Vector3(0, -1.0, -0.08),
		"DEF-shin.R": Vector3(0, -1.0, -0.08),
		"DEF-foot.L": Vector3(0, -1.0, 0.1),
		"DEF-foot.R": Vector3(0, -1.0, 0.1),
	},
}
const FIST_FINGERS := ["index", "middle", "ring", "pinky"]
## Nombres Rigify (DEF-*) -> esqueleto estilo UE de los Universal Base Characters (Quaternius).
const UE_ALIAS := {
	"DEF-hips": "pelvis",
	"DEF-spine.001": "spine_01",
	"DEF-spine.002": "spine_02",
	"DEF-spine.003": "spine_03",
	"DEF-neck": "neck_01",
	"DEF-head": "Head",
	"DEF-upper_arm.L": "upperarm_l",
	"DEF-forearm.L": "lowerarm_l",
	"DEF-hand.L": "hand_l",
	"DEF-upper_arm.R": "upperarm_r",
	"DEF-forearm.R": "lowerarm_r",
	"DEF-hand.R": "hand_r",
	"DEF-thigh.L": "thigh_l",
	"DEF-shin.L": "calf_l",
	"DEF-foot.L": "foot_l",
	"DEF-thigh.R": "thigh_r",
	"DEF-shin.R": "calf_r",
	"DEF-foot.R": "foot_r",
}

## Nombres Rigify -> SkeletonProfileHumanoid de Godot (modelos importados con retargeting).
const HUMANOID_ALIAS := {
	"DEF-hips": "Hips",
	"DEF-spine.001": "Spine",
	"DEF-spine.002": "Chest",
	"DEF-spine.003": "UpperChest",
	"DEF-neck": "Neck",
	"DEF-head": "Head",
	"DEF-upper_arm.L": "LeftUpperArm",
	"DEF-forearm.L": "LeftLowerArm",
	"DEF-hand.L": "LeftHand",
	"DEF-upper_arm.R": "RightUpperArm",
	"DEF-forearm.R": "RightLowerArm",
	"DEF-hand.R": "RightHand",
	"DEF-thigh.L": "LeftUpperLeg",
	"DEF-shin.L": "LeftLowerLeg",
	"DEF-foot.L": "LeftFoot",
	"DEF-thigh.R": "RightUpperLeg",
	"DEF-shin.R": "RightLowerLeg",
	"DEF-foot.R": "RightFoot",
}

## Peso de cada pose (0..1); el avatar los anima con suavizado.
var weights: Dictionary = {"hover": 0.0, "cruise": 0.0, "fist": 0.0, "land": 0.0, "launch": 0.0}
var fist_r: float = 0.0
var female: bool = false
var _ids: Dictionary = {}


## Índice de hueso aceptando nombres Rigify o UE (el modelo base es intercambiable).
static func find_any(sk: Skeleton3D, name: String) -> int:
	var b := sk.find_bone(name)
	if b >= 0:
		return b
	if UE_ALIAS.has(name):
		b = sk.find_bone(UE_ALIAS[name])
		if b >= 0:
			return b
	if HUMANOID_ALIAS.has(name):
		return sk.find_bone(HUMANOID_ALIAS[name])
	if name.begins_with("DEF-f_"):
		# DEF-f_index.01.R -> index_01_r
		var parts := name.substr(6).split(".")
		if parts.size() == 3:
			return sk.find_bone("%s_%s_%s" % [parts[0], parts[1], parts[2].to_lower()])
	return -1


func _bone(sk: Skeleton3D, name: String) -> int:
	if not _ids.has(name):
		_ids[name] = find_any(sk, name)
	return _ids[name]


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var total := 0.0
	for p: String in weights:
		total += float(weights[p])
	if total > 0.001:
		for bname: String in CHAINS:
			var dir := Vector3.ZERO
			var w := 0.0
			for p: String in weights:
				var pw: float = weights[p]
				if pw <= 0.001 or not POSES[p].has(bname):
					continue
				dir += (POSES[p][bname] as Vector3).normalized() * pw
				w += pw
			if w <= 0.001:
				continue
			var b := _bone(sk, bname)
			if b < 0:
				continue
			_aim(sk, b, dir.normalized(), clampf(w, 0.0, 1.0))
	if fist_r > 0.01:
		for f: String in FIST_FINGERS:
			for seg in ["01", "02", "03"]:
				var fb := _bone(sk, "DEF-f_%s.%s.R" % [f, seg])
				if fb >= 0:
					var q := sk.get_bone_pose_rotation(fb)
					var rest := sk.get_bone_rest(fb).basis.get_rotation_quaternion()
					sk.set_bone_pose_rotation(fb, q.slerp(rest * Quaternion(Vector3.RIGHT, 1.35), fist_r))
	if female:
		# caderas algo más anchas y hombros más angostos (mismo maniquí base)
		for side: Array in [["DEF-thigh.L", 1.0], ["DEF-thigh.R", -1.0]]:
			var tb := _bone(sk, side[0])
			if tb >= 0:
				var p := sk.get_bone_rest(tb).origin
				sk.set_bone_pose_position(tb, p + Vector3(0.012 * float(side[1]), 0, 0))
		var ch := _bone(sk, "DEF-spine.003")
		if ch >= 0:
			sk.set_bone_pose_scale(ch, Vector3(0.9, 1.0, 0.95))


func _aim(sk: Skeleton3D, b: int, target: Vector3, w: float) -> void:
	var g := sk.get_bone_global_pose(b)
	var gb := g.basis.orthonormalized()
	var cur := gb.y.normalized()
	var to := cur.slerp(target, w).normalized()
	if cur.dot(to) > 0.99999:
		return
	var nb := Basis(Quaternion(cur, to)) * gb
	var parent := sk.get_bone_parent(b)
	var pb := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(b, (pb.inverse() * nb).get_rotation_quaternion())
