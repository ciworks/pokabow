extends Control

## Screen-level tile overlay, free to cross the clipped board and deck bounds.
## The deck tile stays fully opaque while following the pointer; only the board's
## separate placement preview uses ghost opacity.
const DRAG_TILE_ALPHA: float = 1.0

var snapshot: TileSnapshot = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	z_index = 100
	visible = false


func show_tile(tile: TileSnapshot, center: Vector2, drawn_size: Vector2) -> void:
	snapshot = tile
	size = drawn_size
	position = center - size * 0.5
	visible = snapshot != null
	queue_redraw()


func clear() -> void:
	snapshot = null
	hide()
	queue_redraw()


func _draw() -> void:
	if snapshot != null:
		TilePainter.paint_tile(self, Rect2(Vector2.ZERO, size), snapshot, DRAG_TILE_ALPHA)
