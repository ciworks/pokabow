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

## Presentation scale of the dragged tile; staged and committed tiles stay full size.
var drag_scale: float = 1.0

## Deck drags paint their tile in a screen overlay; the board paints only the target.
var drag_tile_visible: bool = true

## Draw scale each cell pops to, keyed by cell. 1.0 is rest.
##
## Written only by `ScoreRevealLayer` while a scoring bounce runs and read by
## `BoardTileLayer`, so a tile can grow toward the viewer without any game state
## moving. The board is 2D, so the Z axis is expressed as scale about the cell's
## centre: the tile reads as rising toward the player while staying in the cell it
## belongs to, where a positional hop would read as sliding across the grid.
##
## Empty at rest, which is what ADR-008 section 9 requires of an animation that
## can be interrupted.
var cell_zoom: Dictionary = {}

## One entry per connected same-colour edge cluster the board currently holds,
## each `{color: int, cells: Array[Vector2i]}`, as `GameSessionController`
## enumerated them with `EdgeClusterScorer`.
##
## Carried here rather than read from the board by a layer, because a component is
## a rule and AGENTS.md section 19 keeps rules out of the UI. Empty is a valid
## state: a board with no matching boundary holds no cluster.
var edge_clusters: Array = []

## Per-edge verdicts for the staged tile on `edge_match_cell`, in
## `TileEnums.EdgePosition` order (top, right, bottom, left).
##
## Each entry is true when that side of the staged tile currently matches the
## committed tile across it, as `GameSessionController` read it from
## `EdgeMatchScorer`. This is a read-out of the adjacencies the board holds right
## now, never a score prediction: the layer that draws it decides nothing, so the
## hint cannot invent a rule the specification does not contain (AGENTS.md
## section 2).
var edge_matches: Array[bool] = []

## The staged cell `edge_matches` describes, or `BoardMetrics.NO_CELL` when no
## hint is being drawn.
var edge_match_cell: Vector2i = BoardMetrics.NO_CELL


## Returns true when a dragged tile is being drawn at a real board cell.
func has_drag() -> bool:
	return drag_snapshot != null and drop_cell != BoardMetrics.NO_CELL


## Returns true when a preview is being shown, whole line or single tile.
func has_pending() -> bool:
	return not pending_line.is_empty() or pending != null


## Returns how many tiles the pending line holds (ADR-011 section 11).
func pending_count() -> int:
	return pending_line.size()


## Returns the scale `cell` is currently drawn at, or 1.0 at rest.
##
## A scale of 1.0 or below is rest: the bounce only ever grows a tile, so a stray
## value can never shrink a committed tile.
func zoom_for(cell: Vector2i) -> float:
	var value: Variant = cell_zoom.get(cell, null)
	if value is float or value is int:
		var scale: float = float(value)
		if scale > 1.0:
			return scale
	return 1.0


## Returns the four current edge verdicts for `cell`, or an empty array when no
## hint describes that cell.
##
## Only one tile of the staged line can be hinted at a time - the last staged
## tile, which is the one the rotate command acts on - so the cell is part of the
## verdict: a layer that drew the marks without checking it would stamp one
## tile's adjacencies onto another tile.
func edge_matches_for(cell: Vector2i) -> Array[bool]:
	if edge_match_cell == BoardMetrics.NO_CELL or cell != edge_match_cell:
		return [] as Array[bool]
	return edge_matches
