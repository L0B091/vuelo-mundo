class_name AdSlot
extends MeshInstance3D
## Espacio publicitario en la fachada de un local (monetización: avisos de comercios).
## Cada cartel tiene un id estable (data/ad_slots.json) y una textura intercambiable en
## tiempo de ejecución: AdSlot.set_ad_texture(tex) o, por id, AdSlot.assign(tree, id, tex).

const GROUP := &"ad_slots"

@export var ad_id: String = ""
@export var slot_size: Vector2 = Vector2(4, 1)


func _ready() -> void:
	add_to_group(GROUP)


func set_ad_texture(tex: Texture2D) -> void:
	var mat := material_override as StandardMaterial3D
	if mat == null:
		return
	mat = mat.duplicate() as StandardMaterial3D  # no tocar el material compartido
	mat.albedo_texture = tex
	mat.emission_texture = tex
	material_override = mat


static func assign(tree: SceneTree, id: String, tex: Texture2D) -> bool:
	for n: Node in tree.get_nodes_in_group(GROUP):
		var s := n as AdSlot
		if s != null and s.ad_id == id:
			s.set_ad_texture(tex)
			return true
	return false
