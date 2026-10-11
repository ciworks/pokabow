class_name BoardHighlightLayer
extends Control

## Draws legal-placement highlights (ADR-008 section 4, GAME_SPEC section 7.2).
##
## The frontier comes from `BoardState`, which owns it as a derived index
## (ADR-006 section 7); this layer never computes legality itself. Highlighting
## is suppressed outside the human action phase so the AI turn does not invite
## input it will refuse (ADR-008 section 8).

## Legal-placement wash drawn under the frontier.
const FRONTIER_FILL: Color = Color(0.45, 0.62, 0.95, 0.18)

## Live drag target the rules would accept (AGENTS.md section 8: valid-placement
## highlighting). Deliberately green rather than the frontier's blue, so the cell
## the finger is over cannot be confused with the cells a tap could choose.
const DROP_LEGAL_FILL: Color = Color(0.30, 0.92, 0.52, 0.28)

## Live drag target the rules would refuse: the release will change nothing.
const DROP_ILLEGAL_FILL: Color = Color(0.76, 0.20, 0.24, 0.30)

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
	_draw_drop_target()


## Draws the cell under the pointer while a deck tile is being dragged, with a
## distinct treatment for a legal drop and an illegal one.
##
## The cell comes from the shared render state, which took it from `BoardMetrics`,
## and the verdict comes from the application layer, so this layer marks where a
## drop would land without deciding whether it is allowed (AGENTS.md section 19).
## An off-board pointer has no cell, so no target is drawn.
func _draw_drop_target() -> void:
	if state == null or state.drop_cell == BoardMetrics.NO_CELL:
		return
	if not BoardMetrics.is_valid_cell(state.drop_cell, state.grid):
		return
	var rect: Rect2 = BoardMetrics.cell_rect(state.board_rect, state.drop_cell, state.grid)
	if not TilePainter.is_drawable(rect):
		return
	if state.drag_legal:
		draw_rect(rect, DROP_LEGAL_FILL, true)
		return
	draw_rect(rect, DROP_ILLEGAL_FILL, true)


## Washes every empty cell the active player may legally choose.
func _draw_frontier() -> void:
	for cell: Vector2i in state.board.get_frontier_cells():
		var rect: Rect2 = BoardMetrics.cell_rect(state.board_rect, cell, state.grid)
		draw_rect(rect, FRONTIER_FILL, true)
