extends SceneTree
## Crea los BoneMap (SkeletonProfileHumanoid) para importar el héroe de Meshy y la librería UAL
## con retargeting: así las animaciones UAL se reproducen sobre el esqueleto de Meshy.

const HERO := {
	"Hips": "Hips", "Spine": "Spine02", "Chest": "Spine01", "UpperChest": "Spine", "Neck": "neck", "Head": "Head",
	"LeftShoulder": "LeftShoulder", "LeftUpperArm": "LeftArm", "LeftLowerArm": "LeftForeArm", "LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder", "RightUpperArm": "RightArm", "RightLowerArm": "RightForeArm",
	"RightHand": "RightHand", "LeftUpperLeg": "LeftUpLeg", "LeftLowerLeg": "LeftLeg", "LeftFoot": "LeftFoot",
	"LeftToes": "LeftToeBase", "RightUpperLeg": "RightUpLeg", "RightLowerLeg": "RightLeg", "RightFoot": "RightFoot",
	"RightToes": "RightToeBase"
}


func _initialize() -> void:
	var ue := {
		"Root": "root", "Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_02", "UpperChest": "spine_03",
		"Neck": "neck_01", "Head": "Head"
	}
	for s in ["Left", "Right"]:
		var x := "_l" if s == "Left" else "_r"
		ue[s + "Shoulder"] = "clavicle" + x
		ue[s + "UpperArm"] = "upperarm" + x
		ue[s + "LowerArm"] = "lowerarm" + x
		ue[s + "Hand"] = "hand" + x
		ue[s + "UpperLeg"] = "thigh" + x
		ue[s + "LowerLeg"] = "calf" + x
		ue[s + "Foot"] = "foot" + x
		ue[s + "Toes"] = "ball" + x
		ue[s + "ThumbMetacarpal"] = "thumb_01" + x
		ue[s + "ThumbProximal"] = "thumb_02" + x
		ue[s + "ThumbDistal"] = "thumb_03" + x
		for f in [["Index", "index"], ["Middle", "middle"], ["Ring", "ring"], ["Little", "pinky"]]:
			ue[s + f[0] + "Proximal"] = f[1] + "_01" + x
			ue[s + f[0] + "Intermediate"] = f[1] + "_02" + x
			ue[s + f[0] + "Distal"] = f[1] + "_03" + x
	for pair in [[HERO, "hero_bonemap.tres"], [ue, "ue_bonemap.tres"]]:
		var bm := BoneMap.new()
		bm.profile = SkeletonProfileHumanoid.new()
		for k: String in pair[0]:
			bm.set_skeleton_bone_name(StringName(k), StringName(pair[0][k]))
		ResourceSaver.save(bm, "res://assets/characters/meshy_hero/" + str(pair[1]))
	quit()
