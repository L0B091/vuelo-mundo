extends SceneTree
## Lista los archivos de res:// que el juego usa: dependencias (recursivas) de las escenas y de
## toda ruta "res://..." escrita en los scripts y datos. Lo demás se puede excluir del APK.

var seen := {}


func _walk(p: String) -> void:
	if seen.has(p) or not ResourceLoader.exists(p):
		return
	seen[p] = true
	for d in ResourceLoader.get_dependencies(p):
		var path := d.get_slice("::", 2) if d.contains("::") else d
		if path.begins_with("uid://"):
			path = ResourceUID.get_id_path(ResourceUID.text_to_id(path))
		_walk(path)


func _scan(dir: String, roots: Array) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		var full := dir.path_join(f)
		if f.ends_with(".gd") or f.ends_with(".json") or f.ends_with(".tscn") or f.ends_with(".gdshader"):
			var txt := FileAccess.get_file_as_string(full)
			var re := RegEx.create_from_string("res://[A-Za-z0-9_./%-]+")
			for m in re.search_all(txt):
				roots.append(m.get_string().rstrip("."))
	for d in da.get_directories():
		if not d.begins_with(".") and d not in ["addons", "tests", "pipeline", "docs", "tools"]:
			_scan(dir.path_join(d), roots)


func _initialize() -> void:
	var roots: Array = ["res://scenes/boot.tscn", "res://scenes/main.tscn"]
	_scan("res://", roots)
	for z in DirAccess.get_files_at("res://scenes/zones"):
		roots.append("res://scenes/zones/" + z)
	for r: String in roots:
		if r.ends_with("/"):
			continue
		_walk(r)
	var f := FileAccess.open("user://deps.txt", FileAccess.WRITE)
	for k: String in seen:
		f.store_line(k)
	print("USED ", seen.size(), " ", ProjectSettings.globalize_path("user://deps.txt"))
	quit()
