class_name BoardHighlightLayer
extends Control

## Draws legal-placement and last-move highlights (ADR-008 section 4,
## GAME_SPEC section 7.2).
##
## The frontier comes from `BoardState`, which owns it as a derived index
## (ADR-006 section 7); this layer never computes legality itself. Highlighting
## is suppressed outside the human action phase so the AI turn does not invite
## input it will refuse (ADR-008 section 8).

## Legal-placement wash drawn under the frontier.
const FRONTIER_FILL: Color = Color(0.45, 0.62, 0.95, 0.18)

## Outline marking the tile committed on the previous move.
const LAST_MOVE_OUTLINE: Color = Color(1.0, 0.95, 0.55, 0.90)

## Current render state, assigned by `BoardView`.
var state: BoardRenderState = null


func _ready() -> void:
	# Decorative only, so pointer events must pass straight through to
	# BoardInputController (ADR-008 section 8).
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if state == null or state.board == null:
		return
	if state.human_turn:
		_draw_frontier()
	_draw_last_move()


## Washes every empty cell the active player may legally choose.
func _draw_frontier() -> void:
	for cell: Vector2i in state.board.get_frontier_cells():
		var rect: Rect2 = BoardMetrics.cell_rect(state.board_rect, cell, state.grid)
		draw_rect(rect, FRONTIER_FILL, true)


## Outlines where the previous move's tile landed, so the opponent's reply is
## readable on a busy board.
func _draw_last_move() -> void:
	if state.last_committed_cell == BoardMetrics.NO_CELL:
		return
	if not BoardMetrics.is_valid_cell(state.last_committed_cell, state.grid):
		return
	var rect: Rect2 = BoardMetrics.cell_rect(
		state.board_rect, state.last_committed_cell, state.grid
	)
	draw_rect(rect.grow(-2.0), LAST_MOVE_OUTLINE, false, 2.0)
