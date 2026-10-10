class_name CharacterDef
extends Resource
## Definición del personaje del jugador: todo lo personalizable vive acá (se guarda en
## user://character.tres). La malla base es intercambiable: cualquier .glb con el esqueleto
## estándar de Godot / Rigify (DEF-*) del Universal Animation Library de Quaternius (CC0).

const BASE_SCENE := "res://assets/characters/ual/AnimationLibrary_Godot_Standard.gltf"
const SAVE_PATH := "user://character.tres"

@export_enum("male", "female") var body: String = "male"
@export var base_scene: String = BASE_SCENE
@export var height_scale: float = 1.0
@export var suit_color: Color = Color(0.93, 0.93, 0.95)
@export var accent_color: Color = Color(0.75, 0.08, 0.10)
@export var skin_color: Color = Color(0.76, 0.56, 0.42)
@export_enum("none", "short", "long", "bun") var hair_style: String = "short"
@export var hair_color: Color = Color(0.08, 0.06, 0.05)
## Accesorios por nombre: "cape", "belt", "wristbands" (se agregan más sin tocar el avatar).
@export var accessories: PackedStringArray = PackedStringArray(["cape", "belt"])


static func preset(kind: String) -> CharacterDef:
	var d := CharacterDef.new()
	d.body = kind
	if kind == "female":
		d.height_scale = 0.95
		d.hair_style = "long"
		d.hair_color = Color(0.16, 0.09, 0.05)
		d.suit_color = Color(0.10, 0.12, 0.20)
		d.accent_color = Color(0.95, 0.72, 0.10)
		d.skin_color = Color(0.62, 0.43, 0.30)
	return d


static func load_or_default() -> CharacterDef:
	if ResourceLoader.exists(SAVE_PATH):
		var d := ResourceLoader.load(SAVE_PATH) as CharacterDef
		if d != null:
			return d
	return preset("male")


func save() -> void:
	ResourceSaver.save(self, SAVE_PATH)
