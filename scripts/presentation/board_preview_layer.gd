class_name BoardPreviewLayer
extends Control

## Draws the uncommitted pending line (ADR-008 sections 4 and 9, ADR-011
## sections 1 and 11).
##
## ADR-011 section 11 makes the preview a staged line rather than one tile: every
## staged tile is drawn on the board as part of the pending line, together with
## one validity verdict for the line as a whole. This layer reads
## `BoardRenderState.pending_line`, which is never part of `BoardState`, so
## previewing cannot mutate committed state (ADR-007 section 3).
##
## The tiles are painted through the same `TilePainter` as committed tiles, so
## what the player sees before confirming is exactly what they will get. Legality
## arrives as `pending_valid` from the application layer: this layer draws the
## verdict, it never decides it (AGENTS.md section 19).
##
## Which tile the rotate command acts on is drawn too, because ADR-011 section 11
## rotates one tile of the pending line and the player has to see which one.

## Opacity of a ghosted tile.
const GHOST_ALPHA: float = 0.75

## Opacity of the tile being dragged, so the committed board stays readable
## underneath it.
const DRAG_GHOST_ALPHA: float = 0.65

## Use only the supplied artwork's frame; the target contents stay visible.
const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")
var _target_frame: StyleBoxFlat = _create_target_frame()

## Current render state, assigned by `BoardView`.
var state: BoardRenderState = null


func _ready() -> void:
	# A preview is display only; it must never intercept a board gesture
	# (ADR-008 section 8).
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if state == null:
		return
	_draw_pending_line()
	_draw_drag()


## Draws the uncommitted pending line, whole, under one verdict for the line
## (ADR-011 section 11).
func _draw_pending_line() -> void:
	if state.pending_line.is_empty():
		return
	for index: int in range(state.pending_line.size()):
		var snapshot: TileSnapshot = state.pending_line[index]
		if snapshot == null:
			continue
		var cell: Vector2i = snapshot.get_cell()
		if not BoardMetrics.is_valid_cell(cell, state.grid):
			continue
		var rect: Rect2 = BoardMetrics.cell_rect(state.board_rect, cell, state.grid)
		# Keep the staged tile visible without colouring it by hand validity.
		TilePainter.paint_tile(self, rect, snapshot, GHOST_ALPHA)
## Draws the drop-cell outline and, for staged-board drags, a snapped tile.
## Deck drags use a separate screen overlay that follows the pointer freely.
## The target still comes from BoardMetrics and legality from the controller.
func _draw_drag() -> void:
	if not state.has_drag():
		return
	var snapshot: TileSnapshot = state.drag_snapshot
	var cell: Vector2i = snapshot.get_cell()
	if not BoardMetrics.is_valid_cell(cell, state.grid):
		return
	var rect: Rect2 = BoardMetrics.cell_rect(state.board_rect, cell, state.grid)
	if not TilePainter.is_drawable(rect):
		return
	if state.drag_tile_visible:
		TilePainter.paint_tile(self, drag_tile_rect(), snapshot, DRAG_GHOST_ALPHA)
	# Draw the frame last so occupied or staged tiles cannot hide the target.
	# Scale its source-space margins with the cell, including during board zoom.
	draw_style_box(_target_frame, rect)


static func _create_target_frame() -> StyleBoxFlat:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color.TRANSPARENT
	frame.draw_center = false
	frame.border_color = Tabletop.honey()
	frame.set_border_width_all(4)
	frame.set_corner_radius_all(7)
	return frame


## Shrink around the target center without changing the drop cell or grid geometry.
func drag_tile_rect() -> Rect2:
	if state == null or not state.has_drag() or not state.drag_tile_visible:
		return Rect2()
	var rect: Rect2 = BoardMetrics.cell_rect(state.board_rect, state.drop_cell, state.grid)
	var drawn_size: Vector2 = rect.size * state.drag_scale
	return Rect2(rect.get_center() - drawn_size * 0.5, drawn_size)
