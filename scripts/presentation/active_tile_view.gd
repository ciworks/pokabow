class_name ActiveTileView
extends Control

## Shows the active player's uncommitted tile at its current rotation
## (ADR-008 section 4).
##
## The tile it shows is the one the session has assigned to the player
## (ADR-003 section 4: at most one active tile), so what is displayed and what
## would be committed cannot differ. Rotation here is the pending rotation the
## player is choosing; it is not written back to anything until the move commits.
##
## It paints through `TilePainter`, the same code the board uses, so the tile in
## hand and the tile on the board are drawn identically.

## Gap kept between the tile and the panel edge.
const PADDING: float = 6.0

var _tile: TileDefinition = null
var _rotation: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## Shows `tile` at `rotation` (a 0-3 quarter-turn index).
func set_tile(tile: TileDefinition, rotation: int) -> void:
	_tile = tile
	_rotation = TileEnums.normalize_rotation(rotation)
	queue_redraw()


## Shows a new rotation for the tile already displayed.
##
## Deliberately NOT named `set_rotation`: `Control` already defines
## `set_rotation(float)` for node rotation, and overriding it with an `int`
## signature is a compile error.
func set_displayed_rotation(rotation: int) -> void:
	_rotation = TileEnums.normalize_rotation(rotation)
	queue_redraw()


## Stops showing any tile, for the opponent's turn.
func clear() -> void:
	_tile = null
	queue_redraw()


## Returns the rotation currently displayed, as a 0-3 quarter-turn index.
##
## Named to avoid colliding with `Control.get_rotation()`.
func get_displayed_rotation() -> int:
	return _rotation


## Returns the tile currently displayed, or null.
func get_tile() -> TileDefinition:
	return _tile


func _draw() -> void:
	var rect: Rect2 = BoardMetrics.fit_square(Rect2(Vector2.ZERO, size), PADDING)
	TilePainter.paint_cell(self, rect, TilePainter.EMPTY_CELL)
	if _tile == null:
		return
	# Painted through a snapshot so the shared painter handles rotation exactly
	# as it does for committed tiles.
	var snapshot: TileSnapshot = TileSnapshot.create(_tile, Vector2i.ZERO, _rotation)
	TilePainter.paint_tile(self, rect, snapshot)
