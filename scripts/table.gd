extends Node2D

var finish := 0
const SKINS = [preload("res://resources/skins/atlantic.tres"), preload("res://resources/skins/evergreen.tres"), preload("res://resources/skins/graphite.tres")]
var surface: ColorRect
var surface_cache: SubViewport

func _ready() -> void:
	surface = ColorRect.new()
	surface.size = Vector2(600, 1000)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.08,0.35,0.48,1.0);
void fragment() {
 vec2 p = fract(UV * vec2(40.0, 67.0)) - 0.5;
 float hole = 1.0 - smoothstep(0.065, 0.12, length(p));
 float light = 0.88 + 0.16 * (1.0-UV.y) + 0.10 * sin(UV.x*3.14159);
 COLOR = vec4(tint.rgb * light * (1.0-0.38*hole), 1.0);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	surface.material = mat
	# The perforated finish is static. Bake on selection instead of shading it every frame.
	surface_cache = SubViewport.new()
	surface_cache.size = Vector2i(600, 1000)
	surface_cache.disable_3d = true
	surface_cache.world_2d = World2D.new()
	add_child(surface_cache)
	surface_cache.add_child(surface)
	var cached := Sprite2D.new()
	cached.texture = surface_cache.get_texture()
	cached.centered = false
	cached.show_behind_parent = true
	add_child(cached)
	apply_finish(finish)

func apply_finish(value: int) -> void:
	finish = clampi(value, 0, SKINS.size() - 1)
	if surface:
		surface.material.set_shader_parameter("tint", SKINS[finish].tint)
		surface_cache.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()

func _draw() -> void:
	var ink := Color(0.7, 0.93, 1.0, 0.32)
	# Metal rim: fixed visual dimensions, independent of colliders.
	draw_rect(Rect2(-30, -30, 660, 1060), Color("020a10"), false, 22)
	draw_rect(Rect2(-15, -15, 630, 1030), Color("7895a4"), false, 14)
	draw_rect(Rect2(-8, -8, 616, 1016), Color("263f50"), false, 7)
	draw_line(Vector2(-19, 0), Vector2(-19, 1000), Color("c1dbe5"), 3, true)
	draw_line(Vector2(0, -19), Vector2(190, -19), Color("c1dbe5"), 3, true)
	draw_line(Vector2(410, -19), Vector2(600, -19), Color("c1dbe5"), 3, true)
	draw_rect(Rect2(191, -30, 218, 30), Color("04101a"))
	draw_rect(Rect2(191, 1000, 218, 30), Color("04101a"))
	draw_line(Vector2(216, -17), Vector2(384, -17), Color("65d3e5"), 4, true)
	draw_line(Vector2(216, 1017), Vector2(384, 1017), Color("ffbd73"), 4, true)
	draw_line(Vector2(0, 500), Vector2(600, 500), ink, 2, true)
	draw_arc(Vector2(300, 500), 82, 0, TAU, 80, ink, 2, true)
	draw_arc(Vector2(300, 0), 150, 0, PI, 64, ink, 2, true)
	draw_arc(Vector2(300, 1000), 150, PI, TAU, 64, ink, 2, true)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(265, 508), "GLIDE", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color(0.8, 0.96, 1, 0.4))
	for y in [250, 750]:
		for x in [80, 520]:
			draw_circle(Vector2(x, y), 4, ink)
