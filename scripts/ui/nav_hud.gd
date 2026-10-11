class_name NavHud
extends Control
## Brújula (franja de rumbo arriba con N/E/S/O y marca hacia la zona aterrizable más cercana)
## y minimapa que gira con el rumbo: costa/arrecifes (data/minimap), flecha del jugador y un
## marcador por cada zona caminable del índice (punto de aterrizaje) con su distancia.
## Se dibuja con _draw a ~15 Hz: barato en el teléfono.

const MAP_R := 95.0
const LAND_RANGE_M := 400.0  # = Avatar.LAND_RAY: se puede tocar "Aterrizar"
var avatar: Avatar
var index: ZoneIndex
var map_range_m: float = 12000.0  # radio visible del minimapa
var _tex: Texture2D
var _geo: Dictionary = {}
var _t: float = 0.0
var _near: Dictionary = {}
var _clock: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://data/minimap/mv.png"):
		_tex = load("res://data/minimap/mv.png")
		var f := FileAccess.open("res://data/minimap/mv.json", FileAccess.READ)
		_geo = JSON.parse_string(f.get_as_text())


func _process(dt: float) -> void:
	_t += dt
	_clock += dt
	if _t > 1.0 / 15.0 and avatar != null:
		_t = 0.0
		_near = nearest()
		queue_redraw()


## Zona caminable más cercana: {name, dist_m, bearing_deg} (o vacío).
func nearest() -> Dictionary:
	var best := {}
	if index == null:
		return best
	var gp := avatar.global_pos()
	for z: ZoneInfo in index.list("site"):
		if z.landing == null:
			continue
		var d := rel(gp, z.landing)
		if best.is_empty() or d.length() < float(best.dist_m):
			best = {"name": z.name, "dist_m": d.length(), "bearing_deg": bearing(gp, z.landing)}
	return best


## Vector este/norte en metros reales del jugador a un punto global.
static func rel(gp: GlobalPos, p: GlobalPos) -> Vector2:
	var k := cosh(gp.n / 6378137.0)
	return Vector2(Geo.delta_e(p.e, gp.e), p.n - gp.n) / k


## Rumbo (grados, 0 = norte, 90 = este) del jugador a un punto.
static func bearing(gp: GlobalPos, p: GlobalPos) -> float:
	var d := rel(gp, p)
	return fposmod(rad_to_deg(atan2(d.x, d.y)), 360.0)


func _draw() -> void:
	if avatar == null:
		return
	var font := get_theme_default_font()
	var vs := get_viewport_rect().size
	var hd := avatar.heading_deg
	# --- brújula ---
	var w := minf(vs.x * 0.5, 520.0)
	var cx := vs.x * 0.5
	var top := 6.0
	draw_rect(Rect2(cx - w * 0.5, top, w, 34), Color(0, 0, 0, 0.35))
	var span := 120.0  # grados visibles
	for deg in range(0, 360, 15):
		var dd := wrapf(float(deg) - hd, -180.0, 180.0)
		if absf(dd) > span * 0.5:
			continue
		var x := cx + dd / span * w
		var card := {0: "N", 90: "E", 180: "S", 270: "O"}
		if card.has(deg):
			draw_string(
				font,
				Vector2(x - 6, top + 26),
				card[deg],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				20,
				Color(1, 0.35, 0.3) if deg == 0 else Color.WHITE
			)
		else:
			draw_line(Vector2(x, top + 4), Vector2(x, top + (14 if deg % 45 == 0 else 9)), Color(1, 1, 1, 0.7), 2)
	draw_line(Vector2(cx, top + 30), Vector2(cx, top + 40), Color(1, 0.85, 0.3), 3)
	if not _near.is_empty():
		var bd := wrapf(float(_near.bearing_deg) - hd, -180.0, 180.0)
		var bx := cx + clampf(bd / span, -0.5, 0.5) * w
		var inr: bool = float(_near.dist_m) < LAND_RANGE_M
		var col := Color(0.3, 1, 0.4) if inr else Color(0.4, 0.85, 1)
		draw_colored_polygon(
			PackedVector2Array([Vector2(bx, top + 2), Vector2(bx - 7, top - 6), Vector2(bx + 7, top - 6)]), col
		)
		var txt := "%s · %s" % [_near.name, _fmt(float(_near.dist_m))]
		draw_string(font, Vector2(cx - w * 0.5, top + 56), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 16, col)
	# --- minimapa (gira con el rumbo: arriba = hacia donde vuela) ---
	var c := Vector2(vs.x - MAP_R - 16, MAP_R + 60)
	draw_circle(c, MAP_R + 3, Color(0, 0, 0, 0.45))
	var gp := avatar.global_pos()
	var rot := deg_to_rad(hd)
	if _tex != null and not _geo.is_empty():
		var mpp: float = float(_geo.m_per_px)
		var px := Vector2((gp.e - float(_geo.e0)) / mpp, (float(_geo.n0) - gp.n) / mpp)
		# disco recortado: polígono circular con UV giradas (arriba = rumbo)
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var tsz := Vector2(float(_geo.w), float(_geo.h))
		var img_per_px := map_range_m / MAP_R / mpp
		for i in 40:
			var a := TAU * i / 40.0
			var o := Vector2(cos(a), sin(a)) * MAP_R
			pts.append(c + o)
			uvs.append((px + o.rotated(rot) * img_per_px) / tsz)
		draw_polygon(pts, PackedColorArray([Color(1, 1, 1, 0.9)]), uvs, _tex)
	draw_arc(c, MAP_R, 0, TAU, 48, Color(1, 1, 1, 0.6), 2.0)
	if index != null:
		for z: ZoneInfo in index.list("site"):
			if z.landing == null:
				continue
			var d := rel(gp, z.landing)
			var v := Vector2(d.x, -d.y).rotated(-rot) / map_range_m * MAP_R
			var clipped := v.length() > MAP_R - 6
			if clipped:
				v = v.normalized() * (MAP_R - 6)
			var inr := d.length() < LAND_RANGE_M
			var col := Color(0.3, 1, 0.4) if inr else Color(1, 0.8, 0.2)
			# icono de ciudad/zona: anillo que late + edificio (visible aunque quede en el borde)
			var ph := fmod(_clock * 1.2, 1.0)
			draw_arc(c + v, 7.0 + 9.0 * ph, 0, TAU, 24, Color(col, 0.9 * (1.0 - ph)), 2.5)
			draw_circle(c + v, 8.0, Color(0, 0, 0, 0.6))
			var p0 := c + v
			draw_rect(Rect2(p0 + Vector2(-5, -2), Vector2(4, 7)), col)
			draw_rect(Rect2(p0 + Vector2(0, -6), Vector2(5, 11)), col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(-6, 7), c + Vector2(6, 7)]), Color.WHITE)
	draw_string(
		font, c + Vector2(-MAP_R, MAP_R + 18), "%s" % _fmt(map_range_m), HORIZONTAL_ALIGNMENT_CENTER, MAP_R * 2, 13
	)


func _fmt(m: float) -> String:
	return "%d m" % int(m) if m < 1000.0 else "%.1f km" % (m / 1000.0)
