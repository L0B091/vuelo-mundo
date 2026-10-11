class_name CharacterDef
extends Resource
## Definición del personaje del jugador: todo lo personalizable vive acá (se guarda en
## user://character.tres). La malla base es intercambiable: cualquier .glb con el esqueleto
## estándar de Godot / Rigify (DEF-*) del Universal Animation Library de Quaternius (CC0).

const BASE_SCENE := "res://assets/characters/ual/AnimationLibrary_Godot_Standard.gltf"
## Cuerpos separados masculino/femenino (Universal Base Characters "Superhero", Quaternius,
## CC0) con las animaciones del Universal Animation Library en el mismo esqueleto.
const HERO_MALE := "res://assets/characters/superhero/Superhero_Male_FullBody.gltf"
const HERO_FEMALE := "res://assets/characters/superhero/Superhero_Female_FullBody.gltf"
const HERO_ANIMS := "res://assets/characters/superhero/UAL1_UE.glb"
## Protagonista masculino por defecto: hombre joven de traje (Meshy text-to-3D + auto-rig),
## importado con retargeting al SkeletonProfileHumanoid; las animaciones UAL se reimportan
## con el mismo perfil (UAL1_humanoid.glb) para reproducirse sobre su esqueleto.
const MESHY_HERO := "res://assets/characters/meshy_hero/hero.glb"
const HUMANOID_ANIMS := "res://assets/characters/meshy_hero/UAL1_humanoid.glb"
## Trajes: "classic" = textura original; "color" = textura teñida con suit_color;
## "metal" = teñido metálico satinado; "stealth" = negro mate con acentos.
const SUITS := ["classic", "color", "metal", "stealth"]
const SAVE_PATH := "user://character.tres"

@export_enum("male", "female") var body: String = "male"
@export var base_scene: String = HERO_MALE
## Escena de donde se toman las animaciones si la malla base no trae AnimationPlayer.
@export var anim_scene: String = HERO_ANIMS
@export_enum("classic", "color", "metal", "stealth", "business") var suit_style: String = "color"
@export var height_scale: float = 1.0
## true: se usa el material/textura original del modelo (sin traje teñido, pelo ni capa generados)
@export var original_look: bool = false
@export var suit_color: Color = Color(0.82, 0.83, 0.88)
@export var accent_color: Color = Color(0.75, 0.08, 0.10)
@export var skin_color: Color = Color(0.76, 0.56, 0.42)
@export_enum("none", "short", "long", "bun") var hair_style: String = "short"
@export var hair_color: Color = Color(0.08, 0.06, 0.05)
## Accesorios por nombre: "cape", "belt", "wristbands" (se agregan más sin tocar el avatar).
@export var accessories: PackedStringArray = PackedStringArray(["cape", "belt"])


static func preset(kind: String) -> CharacterDef:
	var d := CharacterDef.new()
	d.body = kind
	if kind == "male":
		# hombre joven de traje sobre el cuerpo Quaternius (rig humanoide completo con dedos,
		# mismas animaciones UAL sin retargeting): el héroe Meshy deformaba cuello y hombros
		d.base_scene = HERO_MALE
		d.suit_style = "business"
		d.suit_color = Color(0.12, 0.125, 0.14)
		d.accent_color = Color(0.13, 0.17, 0.38)
		d.skin_color = Color(0.80, 0.62, 0.50)
		d.hair_style = "short"
		d.hair_color = Color(0.06, 0.045, 0.035)
		d.accessories = PackedStringArray(["glasses"])
	if kind == "female":
		d.base_scene = HERO_FEMALE
		d.height_scale = 1.0
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
			if d.body == "male" and (d.base_scene == MESHY_HERO or (d.base_scene == HERO_MALE and d.suit_style != "business")):
				return preset("male")  # guardado de una versión anterior: pasa al protagonista nuevo
			return d
	return preset("male")


func save() -> void:
	ResourceSaver.save(self, SAVE_PATH)
