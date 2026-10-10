class_name UnderwaterFx
extends CanvasLayer
## Vista submarina: rayos de luz en pantalla, tinte, y burbujas que suben de la cabeza del
## avatar. La niebla turquesa y el sonido apagado los manejan TimeOfDay y AmbientAudio.

var avatar: Avatar
var tod: TimeOfDay
var _rays: ColorRect
var _tint: ColorRect
var _bubbles: CPUParticles3D


func setup(p_avatar: Avatar, p_tod: TimeOfDay) -> void:
	avatar = p_avatar
	tod = p_tod
	layer = -1
	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.color = Color(0.0, 0.35, 0.45, 0.0)
	add_child(_tint)
	_rays = ColorRect.new()
	_rays.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/underwater_rays.gdshader")
	_rays.material = m
	add_child(_rays)
	_bubbles = CPUParticles3D.new()
	_bubbles.amount = 24
	_bubbles.lifetime = 2.5
	_bubbles.emitting = false
	_bubbles.direction = Vector3(0, 1, 0)
	_bubbles.spread = 15.0
	_bubbles.initial_velocity_min = 0.5
	_bubbles.initial_velocity_max = 1.2
	_bubbles.gravity = Vector3(0, 0.8, 0)
	_bubbles.scale_amount_min = 0.3
	_bubbles.scale_amount_max = 1.0
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	sm.radial_segments = 6
	sm.rings = 3
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.85, 0.95, 1.0, 0.55)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.metallic_specular = 1.0
	bm.roughness = 0.05
	sm.material = bm
	_bubbles.mesh = sm
	avatar.add_child(_bubbles)
	_bubbles.position = Vector3(0, 1.6, -0.2)


func _process(_dt: float) -> void:
	var uw := tod != null and tod.underwater
	var depth := maxf(-avatar.camera.global_position.y, 0.0)
	_tint.color.a = 0.18 if uw else 0.0
	var m := _rays.material as ShaderMaterial
	m.set_shader_parameter(&"intensity", 1.0 if uw else 0.0)
	m.set_shader_parameter(&"depth", depth)
	_rays.visible = uw
	_bubbles.emitting = avatar.global_position.y < -0.8
