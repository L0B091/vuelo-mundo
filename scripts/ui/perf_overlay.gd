class_name PerfOverlay
extends CanvasLayer
## Medidor de rendimiento para probar en el teléfono: FPS, ms de cuadro (media y peor del
## último segundo), llamadas de dibujo, primitivas, objetos y memoria. Escribe una línea por
## segundo en user://perf_log.csv (en Android: /sdcard/Android/data/<paquete>/files/ con
## acceso externo, o `adb shell run-as <paquete> cat files/perf_log.csv`).
## Se activa con --perf o con el botón "FPS" del HUD.

const LOG_PATH := "user://perf_log.csv"

var context: Callable = Callable()  # devuelve un texto corto (perfil, zona, altura)
var _label: Label
var _file: FileAccess
var _acc := 0.0
var _n := 0
var _worst := 0.0
var _t := 0.0


func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.position = Vector2(8, 8)
	_label.add_theme_font_size_override(&"font_size", 16)
	_label.add_theme_color_override(&"font_color", Color(1, 1, 0.6))
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	add_child(_label)
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _file != null:
		_file.store_line(
			"t_s,fps,avg_ms,worst_ms,draw_calls,primitives,objects,static_mem_mb,video_mem_mb,load,context"
		)
	print("perf: registro en ", ProjectSettings.globalize_path(LOG_PATH))


func _process(dt: float) -> void:
	var ms := dt * 1000.0
	_acc += ms
	_n += 1
	_worst = maxf(_worst, ms)
	_t += dt
	if _acc < 1000.0:
		return
	var avg := _acc / float(_n)
	var dc := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var pr := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var ob := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var sm := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var vm := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var ctx := str(context.call()) if context.is_valid() else ""
	var load := _loadavg()
	_label.text = (
		"%d fps  %.1f ms (peor %.1f)\n%d draws  %dk tris  %d obj\nRAM %.0f MB  VRAM %.0f MB\n%s\n%s"
		% [Engine.get_frames_per_second(), avg, _worst, dc, int(pr / 1000.0), ob, sm, vm, ctx, BuildInfo.text()]
	)
	if _file != null:
		_file.store_line(
			(
				"%.1f,%d,%.2f,%.2f,%d,%d,%d,%.1f,%.1f,%s,%s"
				% [_t, Engine.get_frames_per_second(), avg, _worst, dc, pr, ob, sm, vm, load, ctx.replace(",", ";")]
			)
		)
		_file.flush()
	_acc = 0.0
	_n = 0
	_worst = 0.0


## Carga de la máquina (solo Linux/escritorio): sirve para separar regresiones reales de
## una máquina de pruebas ocupada.
func _loadavg() -> String:
	if OS.get_name() != "Linux":
		return ""
	var f := FileAccess.open("/proc/loadavg", FileAccess.READ)
	return f.get_line().split(" ")[0] if f != null else ""
