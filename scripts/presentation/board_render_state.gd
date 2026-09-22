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
## `pending_line` is the uncommitted line - tiles that are *not* on the board yet.
## Keeping them here rather than in the board is what makes a preview incapable of
## corrupting committed state (ADR-007 section 3). ADR-011 section 11 makes the
## preview a whole staged line rather than one tile, and `pending` stays the
## line's first tile so a caller that only needs the anchor keeps working.

## Authoritative board, or null before a match starts.
var board: BoardState = null

## Board area in this view's local coordinates. Derived from `BoardMetrics`.
var board_rect: Rect2 = Rect2()

## Board side length in cells.
var grid: int = BoardEnums.BOARD_WIDTH

## The pending line in staging order (ADR-011 section 11). Empty when nothing is
## staged. Never part of `board`.
var pending_line: Array[TileSnapshot] = []

## The uncommitted preview placement, or null when nothing is previewed. The
## pending line's first tile when one is staged.
var pending: TileSnapshot = null

## Whether `pending` is a legal placement.
var pending_valid: bool = false

## Why `pending` is illegal, for display. Empty when legal or absent.
var pending_reason: String = ""

## Cell of the most recently committed tile, or `BoardMetrics.NO_CELL`.
var last_committed_cell: Vector2i = BoardMetrics.NO_CELL

## Every cell the most recent committed move wrote. ADR-011 section 1 makes a
## move a whole line, so the highlight marks the line rather than one cell.
var last_committed_cells: Array[Vector2i] = []

## True while the human owns the action phase, which gates frontier
## highlighting (ADR-008 section 8: human input is gated by phase).
var human_turn: bool = true


## The tile being dragged from the deck, snapped to the board cell under the
## pointer, or null when no drag is in flight (AGENTS.md section 8). Drawn as a
## ghost at that cell, so a drag over the board reads as a placement on the grid.
var drag_snapshot: TileSnapshot = null

## The board cell a drop would land on, or `BoardMetrics.NO_CELL` when the pointer
## is off the board. Derived from `BoardMetrics`, never from a guess.
var drop_cell: Vector2i = BoardMetrics.NO_CELL

## Whether dropping `drag_snapshot` at `drop_cell` would be accepted. Arrives from
## the application layer, which is the only place a rule is read (AGENTS.md
## section 19); this state carries the verdict so a layer can draw it.
var drag_legal: bool = false


## Returns true when a dragged tile is being drawn at a real board cell.
func has_drag() -> bool:
	return drag_snapshot != null and drop_cell != BoardMetrics.NO_CELL


## Returns true when a preview is being shown, whole line or single tile.
func has_pending() -> bool:
	return not pending_line.is_empty() or pending != null


## Returns how many tiles the pending line holds (ADR-011 section 11).
func pending_count() -> int:
	return pending_line.size()
