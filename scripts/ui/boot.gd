extends Control
## Pantalla de inicio: muestra el equipo detectado y el perfil gráfico elegido, permite
## cambiarlo, y corre una prueba corta de rendimiento si el equipo no está en la tabla.

const MAIN_SCENE := "res://scenes/main.tscn"
const BENCH_SECONDS := 3.0

var info: Label
var option: OptionButton
var go: Button
var _bench_root: Node3D
var _bench_t: float = -1.0
var _bench_frames: int = 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if (
			a.begins_with("--screenshot")
			or a.begins_with("--autotest")
			or a == "--auto"
			or a.begins_with("--quit-after")
		):
			get_tree().call_deferred("change_scene_to_file", MAIN_SCENE)
			return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.18, 0.32)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-320, -220)
	box.size = Vector2(640, 440)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	var title := Label.new()
	title.text = "Vuelo Mundo"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 18)
	box.add_child(info)
	option = OptionButton.new()
	option.add_item("Automático")
	for p in Quality.ORDER:
		option.add_item(Quality.LABELS[p])
	option.selected = 0 if Quality.override_name == "" else Quality.ORDER.find(Quality.override_name) + 1
	option.item_selected.connect(_on_option)
	option.add_theme_font_size_override("font_size", 22)
	box.add_child(option)
	go = Button.new()
	go.text = "Despegar sobre Maldivas"
	go.add_theme_font_size_override("font_size", 26)
	go.custom_minimum_size = Vector2(0, 70)
	go.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_SCENE))
	box.add_child(go)
	_refresh()
	if Quality.needs_benchmark() and DisplayServer.get_name() != "headless":
		_start_benchmark()


func _on_option(i: int) -> void:
	Quality.set_override("" if i == 0 else Quality.ORDER[i - 1])
	_refresh()


func _refresh() -> void:
	var d: Dictionary = Quality.device
	var how := {"table": "por tabla de equipos", "benchmark": "por prueba de rendimiento", "default": "por defecto"}
	info.text = (
		"Equipo: %s\nGPU: %s\nRAM: %.1f GB\nPerfil detectado: %s (%s)\nPerfil en uso: %s"
		% [
			d.get("model", "?"),
			d.get("gpu", "?"),
			float(d.get("ram_gb", -1.0)),
			Quality.LABELS[Quality.detected_name],
			how.get(Quality.detected_by, ""),
			Quality.label()
		]
	)


## Prueba corta: dibuja una escena cargada (instancias + agua) sin vsync y mide FPS.
func _start_benchmark() -> void:
	go.disabled = true
	info.text += "\n\nMidiendo rendimiento…"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_bench_root = Node3D.new()
	add_child(_bench_root)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 40, 120)
	cam.rotation_degrees = Vector3(-15, 0, 0)
	_bench_root.add_child(cam)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-50, 30, 0)
	_bench_root.add_child(light)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = SphereMesh.new()
	mm.instance_count = 4000
	for i in mm.instance_count:
		mm.set_instance_transform(
			i, Transform3D(Basis(), Vector3((i % 80) * 3.0 - 120.0, sin(i * 0.3) * 4.0, -(i / 80) * 3.0))
		)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	_bench_root.add_child(mmi)
	_bench_t = 0.0
	_bench_frames = 0


func _process(dt: float) -> void:
	if _bench_t < 0.0:
		return
	_bench_t += dt
	if _bench_t > 0.5:
		_bench_frames += 1
	if _bench_t >= BENCH_SECONDS + 0.5:
		var fps := float(_bench_frames) / BENCH_SECONDS
		_bench_t = -1.0
		_bench_root.queue_free()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		Quality.set_benchmark_result(fps)
		go.disabled = false
		_refresh()
		info.text += "\nPrueba: %.0f FPS" % fps
