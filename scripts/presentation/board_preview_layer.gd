class_name BoardPreviewLayer
extends Control

## Draws the uncommitted preview placement (ADR-008 sections 4 and 9).
##
## The preview is a ghost of the tile that would be committed: it uses the same
## `TilePainter` as committed tiles, so what the player sees before confirming
## is exactly what they will get. It reads `BoardRenderState.pending`, which is
## never part of `BoardState`, so previewing cannot mutate committed state
## (ADR-007 section 3).

## Outline around a legal preview.
const VALID_OUTLINE: Color = Color(0.35, 0.95, 0.55, 1.0)

## Wash and outline for an illegal preview.
const INVALID_FILL: Color = Color(0.70, 0.16, 0.20, 0.35)
const INVALID_OUTLINE: Color = Color(0.96, 0.34, 0.36, 1.0)

## Opacity of the ghosted tile.
const GHOST_ALPHA: float = 0.75

## Current render state, assigned by `BoardView`.
var state: BoardRenderState = null


func _ready() -> void:
	# A preview is display only; it must never intercept a board gesture
	# (ADR-008 section 8).
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if state == null or not state.has_pending():
		return
	var cell: Vector2i = state.pending.get_cell()
	if not BoardMetrics.is_valid_cell(cell, state.grid):
		return
	var rect: Rect2 = BoardMetrics.cell_rect(state.board_rect, cell, state.grid)
	if state.pending_valid:
		_draw_valid(rect)
	else:
		_draw_invalid(rect)


## Draws the ghost tile and its confirm outline.
func _draw_valid(rect: Rect2) -> void:
	TilePainter.paint_tile(self, rect, state.pending, GHOST_ALPHA)
	draw_rect(rect, VALID_OUTLINE, false, 3.0)


## Draws a refusal marker instead of a tile, so an illegal preview never looks
## like a legal one.
func _draw_invalid(rect: Rect2) -> void:
	draw_rect(rect, INVALID_FILL, true)
	draw_rect(rect, INVALID_OUTLINE, false, 3.0)
