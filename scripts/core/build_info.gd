class_name BuildInfo
## Commit y hora de compilación del APK (data/build_info.json, lo escribe tools/export_apk.sh).


static func text() -> String:
	var p := "res://data/build_info.json"
	if not FileAccess.file_exists(p):
		return "build: dev"
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(d) != TYPE_DICTIONARY:
		return "build: ?"
	return "build %s · %s" % [d.get("commit", "?"), d.get("time", "?")]
