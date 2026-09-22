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

## Outline around each tile of a legal pending line.
const VALID_OUTLINE: Color = Color(0.35, 0.95, 0.55, 1.0)

## Wash and outline for a pending line that is not yet a legal move.
const INVALID_FILL: Color = Color(0.70, 0.16, 0.20, 0.35)
const INVALID_OUTLINE: Color = Color(0.96, 0.34, 0.36, 1.0)

## Outline marking the tile the rotate command will turn.
const ROTATE_OUTLINE: Color = Color(1.0, 0.86, 0.42, 1.0)

## Opacity of a ghosted tile.
const GHOST_ALPHA: float = 0.75

## Current render state, assigned by `BoardView`.
var state: BoardRenderState = null


func _ready() -> void:
	# A preview is display only; it must never intercept a board gesture
	# (ADR-008 section 8).
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if state == null or state.pending_line.is_empty():
		return
	for index: int in range(state.pending_line.size()):
		var snapshot: TileSnapshot = state.pending_line[index]
		if snapshot == null:
			continue
		var cell: Vector2i = snapshot.get_cell()
		if not BoardMetrics.is_valid_cell(cell, state.grid):
			continue
		var rect: Rect2 = BoardMetrics.cell_rect(state.board_rect, cell, state.grid)
		if state.pending_valid:
			_draw_valid(rect, snapshot)
		else:
			_draw_invalid(rect)
		if index == state.pending_line.size() - 1:
			_draw_rotate_marker(rect)


## Draws one tile of a legal pending line and its confirm outline.
func _draw_valid(rect: Rect2, snapshot: TileSnapshot) -> void:
	TilePainter.paint_tile(self, rect, snapshot, GHOST_ALPHA)
	draw_rect(rect, VALID_OUTLINE, false, 3.0)


## Draws a refusal marker instead of a tile, so an illegal pending line never
## looks like a legal one.
func _draw_invalid(rect: Rect2) -> void:
	draw_rect(rect, INVALID_FILL, true)
	draw_rect(rect, INVALID_OUTLINE, false, 3.0)


## Outlines the tile the rotate command will turn.
func _draw_rotate_marker(rect: Rect2) -> void:
	draw_rect(rect.grow(-4.0), ROTATE_OUTLINE, false, 2.0)
