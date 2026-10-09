extends Node
## Registra las acciones de entrada (teclado para probar en escritorio).
## En el celular se usan los controles táctiles del HUD, que inyectan los mismos valores.

const ACTIONS: Dictionary = {
	"throttle_up": [KEY_W],
	"throttle_down": [KEY_S],
	"yaw_left": [KEY_A, KEY_LEFT],
	"yaw_right": [KEY_D, KEY_RIGHT],
	"climb": [KEY_E, KEY_UP, KEY_SPACE],
	"descend": [KEY_Q, KEY_DOWN, KEY_CTRL],
	"land": [KEY_L],
	"takeoff": [KEY_T],
	"run": [KEY_SHIFT],
	"boost": [KEY_B],
}


func _ready() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)
