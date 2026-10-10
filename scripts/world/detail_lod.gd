extends MultiMeshInstance3D
## Ajusta un MultiMesh de detalle urbano al perfil gráfico: cuántas instancias se dibujan
## (prefijo de una lista barajada) y hasta qué distancia.

const DENSITY := {"low": 0.3, "medium": 0.6, "high": 1.0, "ultra": 1.0}
const RANGE := {"low": 0.5, "medium": 0.75, "high": 1.0, "ultra": 1.35}


func _ready() -> void:
	var q := get_tree().root.get_node_or_null(^"Quality")
	var p := str(q.get(&"current_name")) if q != null else "high"
	var n: int = get_meta(&"detail_count", multimesh.instance_count)
	multimesh.visible_instance_count = maxi(1, int(ceil(n * float(DENSITY.get(p, 1.0)))))
	visibility_range_end = float(get_meta(&"detail_range", visibility_range_end)) * float(RANGE.get(p, 1.0))
