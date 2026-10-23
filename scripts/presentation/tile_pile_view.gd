class_name TilePileView
extends Control

## Shared tile-pot artwork and remaining tile count. Counts come from the
## controller; this view only presents those values.
const POT_TEXTURE: Texture2D = preload("res://assets/ui/tile_pot.png")

var _tile_count: int = 0
var _stack_rect: Rect2

@onready var count_label: Label = $AvailableTilesLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	count_label.theme_changed.connect(_layout.call_deferred)
	_layout()


func set_tile_count(tile_count: int) -> void:
	var clamped: int = maxi(tile_count, 0)
	_tile_count = clamped
	count_label.text = "%d left" % _tile_count
	_layout()


func tile_count() -> int:
	return _tile_count


func stack_origin_global() -> Vector2:
	return get_global_transform() * (_stack_rect.position + _stack_rect.size * Vector2(0.5, 0.36))


func _draw() -> void:
	if POT_TEXTURE != null and _stack_rect.has_area():
		# The supplied square PNG has generous transparent margins. Draw its
		# artwork bounds so the visible pot remains compact and crisp.
		var texture_size: Vector2 = POT_TEXTURE.get_size()
		var source_rect := Rect2(
			Vector2(texture_size.x * 0.18, texture_size.y * 0.15),
			Vector2(texture_size.x * 0.64, texture_size.y * 0.68)
		)
		draw_texture_rect_region(POT_TEXTURE, _stack_rect, source_rect)


func _layout() -> void:
	var side: float = maxf(1.0, minf(size.x, size.y))
	var pot_size := Vector2(side * 0.42, side * 0.38)
	_stack_rect = Rect2(Vector2((size.x - pot_size.x) * 0.5, side * 0.02), pot_size)
	count_label.position = Vector2(0.0, side * 0.58)
	var text_size := Vector2(size.x, maxf(16.0, side * 0.28))
	var font: Font = count_label.get_theme_font("font")
	var font_size: int = maxi(1, ceili(text_size.y))
	while font_size > 1:
		var text_width: float = font.get_string_size(count_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if text_width <= text_size.x and font.get_height(font_size) <= text_size.y:
			break
		font_size -= 1
	if count_label.get_theme_font_size("font_size") != font_size:
		count_label.add_theme_font_size_override("font_size", font_size)
	count_label.size = text_size
	queue_redraw()
