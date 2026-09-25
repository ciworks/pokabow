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
##
## That tile also carries the rotation hint: a short tick inside each of its edges
## that currently matches the committed tile across it, so the player can see for
## themselves what turning the tile would change. The verdicts arrive finished in
## `BoardRenderState.edge_matches`, read from the domain edge-match rule by
## `GameSessionController.staged_edge_matches`, so this layer compares no edge
## colour and predicts no score: it reports adjacencies the board already holds
## (AGENTS.md sections 2 and 19).

## Outline around each tile of a legal pending line.
const VALID_OUTLINE: Color = Color(0.35, 0.95, 0.55, 1.0)

## Wash and outline for a pending line that is not yet a legal move.
const INVALID_FILL: Color = Color(0.70, 0.16, 0.20, 0.35)
const INVALID_OUTLINE: Color = Color(0.96, 0.34, 0.36, 1.0)

## Outline marking the tile the rotate command will turn.
const ROTATE_OUTLINE: Color = Color(1.0, 0.86, 0.42, 1.0)

## Mark on an edge of the rotatable tile that currently matches the committed
## tile across it.
##
## Near-white rather than one of the four edge colours: a mark tinted with the
## colour it reports would restate what the tile's own edge band already shows,
## while this has to read as a verdict ABOUT an edge. It is also deliberately not
## the reveal cyan or the rotate gold, both of which already mean something else
## on this board.
const EDGE_MATCH_COLOR: Color = Color(1.0, 1.0, 1.0, 0.92)

## Length of a match mark, as a fraction of the edge it sits on.
##
## Short enough that four marks still read as four separate sides rather than as
## a second outline around the tile.
const EDGE_MATCH_LENGTH_RATIO: float = 0.42

## Thickness of a match mark, as a fraction of one cell.
const EDGE_MATCH_WIDTH_RATIO: float = 0.10

## How far inside the tile's edge a match mark is drawn, as a fraction of a cell.
##
## The tile's own edge band occupies the outer fifth of the cell, so the mark is
## placed just inside it: it must not be mistaken for the band it reports, and it
## must stay clear of the gold rotate outline.
const EDGE_MATCH_INSET_RATIO: float = 0.20

## Opacity of a ghosted tile.
const GHOST_ALPHA: float = 0.75

## Opacity of the tile being dragged, so the committed board stays readable
## underneath it.
const DRAG_GHOST_ALPHA: float = 0.65

## Outline of the dragged tile: the same two verdicts the target highlight uses, so
## the ghost and the highlight can never tell the player different stories.
const DRAG_VALID_OUTLINE: Color = Color(0.35, 0.95, 0.55, 1.0)
const DRAG_INVALID_OUTLINE: Color = Color(0.96, 0.34, 0.36, 1.0)

## Thickness of the dragged tile's outline, in pixels.
const DRAG_OUTLINE_WIDTH: float = 3.0

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
		if state.pending_valid:
			_draw_valid(rect, snapshot)
		else:
			_draw_invalid(rect, snapshot)
		if index == state.pending_line.size() - 1:
			_draw_rotate_marker(rect)
			_draw_edge_matches(rect, cell)


## Draws one tile of a legal pending line and its confirm outline.
func _draw_valid(rect: Rect2, snapshot: TileSnapshot) -> void:
	TilePainter.paint_tile(self, rect, snapshot, GHOST_ALPHA)
	draw_rect(rect, VALID_OUTLINE, false, 3.0)


## Keeps the staged tile visible while marking an incomplete or illegal line.
func _draw_invalid(rect: Rect2, snapshot: TileSnapshot) -> void:
	TilePainter.paint_tile(self, rect, snapshot, GHOST_ALPHA)
	draw_rect(rect, INVALID_FILL, true)
	draw_rect(rect, INVALID_OUTLINE, false, 3.0)


## Outlines the tile the rotate command will turn.
func _draw_rotate_marker(rect: Rect2) -> void:
	draw_rect(rect.grow(-4.0), ROTATE_OUTLINE, false, 2.0)


## Marks every edge of the rotatable tile that currently matches the committed
## tile across it (AGENTS.md section 8: show what a rotation would change).
##
## The four verdicts are read in `TileEnums.EdgePosition` order (top, right,
## bottom, left), which is the order the controller published them in, and only a
## true side is marked: drawing an explicit "no match" on the others would turn a
## factual read-out into a judgement about which orientation is better, which is a
## rule the specification does not contain (AGENTS.md section 2).
##
## Nothing is drawn when no hint describes this cell, so a staged tile can never
## wear another tile's adjacencies.
func _draw_edge_matches(rect: Rect2, cell: Vector2i) -> void:
	var matches: Array[bool] = state.edge_matches_for(cell)
	if matches.size() < TileEnums.EDGE_COUNT:
		return
	var cell_size: float = minf(rect.size.x, rect.size.y)
	if cell_size <= 1.0:
		return
	var length: float = cell_size * EDGE_MATCH_LENGTH_RATIO
	var width: float = maxf(2.0, cell_size * EDGE_MATCH_WIDTH_RATIO)
	var inset: float = cell_size * EDGE_MATCH_INSET_RATIO
	var center: Vector2 = rect.get_center()
	for position: int in range(TileEnums.EDGE_COUNT):
		if not matches[position]:
			continue
		draw_line(
			_match_start(center, position, length, inset),
			_match_end(center, position, length, inset),
			EDGE_MATCH_COLOR,
			width
		)


## Returns the first endpoint of the mark on `position`, centred on that edge.
func _match_start(center: Vector2, position: int, length: float, inset: float) -> Vector2:
	match position:
		TileEnums.EdgePosition.TOP:
			return center + Vector2(-length * 0.5, -inset)
		TileEnums.EdgePosition.RIGHT:
			return center + Vector2(inset, -length * 0.5)
		TileEnums.EdgePosition.BOTTOM:
			return center + Vector2(-length * 0.5, inset)
		TileEnums.EdgePosition.LEFT:
			return center + Vector2(-inset, -length * 0.5)
	return center


## Returns the second endpoint of the mark on `position`.
##
## Top and bottom are horizontal strokes and left and right are vertical, so a
## mark lies along the edge it reports rather than across it.
func _match_end(center: Vector2, position: int, length: float, inset: float) -> Vector2:
	match position:
		TileEnums.EdgePosition.TOP:
			return center + Vector2(length * 0.5, -inset)
		TileEnums.EdgePosition.RIGHT:
			return center + Vector2(inset, length * 0.5)
		TileEnums.EdgePosition.BOTTOM:
			return center + Vector2(length * 0.5, inset)
		TileEnums.EdgePosition.LEFT:
			return center + Vector2(-inset, length * 0.5)
	return center


## Draws the deck tile being dragged, snapped onto the board cell under the
## pointer (AGENTS.md section 8: drag to move, snap to the grid).
##
## The cell is the one `BoardMetrics` derives for the pointer, so the ghost is
## drawn on the grid and a drop lands on the cell it was drawn over. The verdict
## arrives in `drag_legal`, and a pointer that is not over the board has no cell,
## so a release there leaves nothing behind (ADR-011 section 5).
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
	TilePainter.paint_tile(self, rect, snapshot, DRAG_GHOST_ALPHA)
	if state.drag_legal:
		draw_rect(rect, DRAG_VALID_OUTLINE, false, DRAG_OUTLINE_WIDTH)
		return
	draw_rect(rect, DRAG_INVALID_OUTLINE, false, DRAG_OUTLINE_WIDTH)
