class_name StartupGuard
## Arranque a prueba de fallos. Marca user://boot_pending al iniciar y la borra cuando el juego
## lleva unos segundos corriendo; si al abrir la marca sigue ahí, el arranque anterior se cerró:
## se fuerza el perfil bajo y se avisa en pantalla. Los fallos recuperables se juntan en `errors`.

const PENDING := "user://boot_pending"
static var errors: PackedStringArray = PackedStringArray()


## true si el arranque anterior no terminó (se cerró la app).
static func begin() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var crashed := FileAccess.file_exists(PENDING)
	var f := FileAccess.open(PENDING, FileAccess.WRITE)
	if f != null:
		f.store_string(Time.get_datetime_string_from_system())
	if crashed:
		report("El inicio anterior se cerró: se usa el perfil Bajo.")
	return crashed


static func ok() -> void:
	if FileAccess.file_exists(PENDING):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING))


static func report(msg: String) -> void:
	push_error(msg)
	errors.append(msg)


static func text() -> String:
	return "\n".join(errors)
