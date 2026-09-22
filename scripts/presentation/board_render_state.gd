class_name BoardRenderState
extends RefCounted

## What the board layers draw, derived from authoritative state
## (ADR-008 section 9).
##
## One instance is shared by the four board layers so they always agree about
## the geometry and the pending placement. It holds references to authoritative
## objects (`BoardState`, `TileSnapshot`) rather than copies, so a layer can
## never draw a tile that the session does not actually hold.
##
## Nothing here mutates game state, and nothing here decides legality: whether a
## pending placement is legal arrives as `pending_valid` from the application
## layer, which got it from `PlacementValidator` (ADR-008 section 4:
## presentation reflects state, it does not own rules).
##
## `pending` is the preview snapshot - a tile that is *not* on the board yet.
## Keeping it here rather than in the board is what makes a preview incapable of
## corrupting committed state (ADR-007 section 3).

## Authoritative board, or null before a match starts.
var board: BoardState = null

## Board area in this view's local coordinates. Derived from `BoardMetrics`.
var board_rect: Rect2 = Rect2()

## Board side length in cells.
var grid: int = BoardEnums.BOARD_WIDTH

## The uncommitted preview placement, or null when nothing is previewed.
var pending: TileSnapshot = null

## Whether `pending` is a legal placement.
var pending_valid: bool = false

## Why `pending` is illegal, for display. Empty when legal or absent.
var pending_reason: String = ""

## Cell of the most recently committed tile, or `BoardMetrics.NO_CELL`.
var last_committed_cell: Vector2i = BoardMetrics.NO_CELL

## True while the human owns the action phase, which gates frontier
## highlighting (ADR-008 section 8: human input is gated by phase).
var human_turn: bool = true


## Returns true when a preview is being shown.
func has_pending() -> bool:
	return pending != null
