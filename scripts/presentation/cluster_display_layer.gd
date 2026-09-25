class_name ClusterDisplayLayer
extends Control

## Persistent outlines of every same-colour edge cluster on the committed board
## (AGENTS.md section 8, docs/sections/05-mobile-ux.md section 4).
##
## This layer answers one question continuously: *which same-colour regions does
## the board hold right now*. It is deliberately NOT `ScoreRevealLayer`, which
## answers a different question - *what did the move that just committed score* -
## holds for a moment, and fades. Both can be on screen at once, so this mark is
## kept subordinate to that one: a thin outline in the region's own edge colour
## over a faint wash, where the reveal is a thick opaque cyan band, and this
## layer sits earlier in the draw order so the reveal paints over it
## (ADR-008 section 9's draw order: last writer wins).
##
## What a cluster is, and which tiles belong to it, is decided in the domain and
## read out by the application layer: `GameSessionController.current_edge_clusters()`
## enumerates the components with `EdgeClusterScorer`, the tested flood fill and
## vertex test of ADR-002 sections 2 to 5, and `BoardView` hands them here. This
## layer therefore compares nothing, floods nothing, and honours nothing of the
## scoring rules (AGENTS.md section 19: UI reflects game state, it does not
## calculate game rules), so the regions it draws are exactly the regions the
## ledger is scored from.
##
## Colour is the only channel the marks need, and it comes from
## `TilePainter.edge_color_for`, the single source of truth for edge colour, so a
## blue region is marked in the very blue the player reads on the tile edges.
##
## The mark deliberately ignores `BoardRenderState.cell_zoom`: that scale belongs
## to the score bounce, which is the reveal's animation, and this outline
## describes the committed board rather than the animation playing over it.

## Stroke thickness, as a fraction of one cell.
##
## Half of `ScoreRevealLayer.OUTLINE_RATIO`, because a persistent mark must never
## be mistaken for the transient reveal it sits under.
const OUTLINE_RATIO: float = 0.055

## Alpha of the region's perimeter stroke.
const OUTLINE_ALPHA: float = 0.85

## Alpha of the wash laid over a region's tiles.
##
## Tinting the tiles is what makes several tiles read as ONE region rather than
## as a set of outlined cells; the alpha is low enough that the rank glyph, the
## edge colours, and the valid-placement highlight all stay legible underneath.
const WASH_ALPHA: float = 0.14

## The regions to draw: `{color: int, cells: Array[Vector2i]}`, one per connected
## component per colour, as the application layer enumerated them.
var _clusters: Array = []

## Shared render state, assigned by `BoardView`.
var state: BoardRenderState = null


func _ready() -> void:
	# Decorative: pointer events pass straight through to the board, which
	# hit-tests gestures itself (ADR-008 section 8).
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Replaces the outlined regions, then repaints.
##
## An empty list is a valid answer - a board with no matching boundary holds no
## cluster - and it clears the marks, so a region that no longer exists cannot
## stay drawn over the committed board (ADR-008 section 9 requires state, not
## the animation, to be the thing resynchronized from).
func show_clusters(clusters: Array) -> void:
	_clusters = clusters
	queue_redraw()


## Drops every outline, leaving the committed board untouched.
func clear_clusters() -> void:
	if _clusters.is_empty():
		return
	_clusters = []
	queue_redraw()


## Returns how many regions are outlined. For smoke tests.
func cluster_count() -> int:
	return _clusters.size()


## Returns true while anything is drawn. For smoke tests.
func has_clusters() -> bool:
	return not _clusters.is_empty()


func _draw() -> void:
	if state == null or not state.board_rect.has_area():
		return
	if _clusters.is_empty():
		return
	var cell_size: float = BoardMetrics.cell_size(state.board_rect, state.grid)
	# Floored so a small phone screen still draws a stroke rather than nothing,
	# and scaled by the cell so the marks stay in proportion on any board size.
	var line: float = maxf(1.5, cell_size * OUTLINE_RATIO)
	for raw: Variant in _clusters:
		if raw is Dictionary:
			_draw_cluster(raw, line)


## Draws one region as a single merged shape.
##
## The perimeter is what makes the outline answer "which region is this": the
## internal boundaries between two tiles of the same region are left unstroked,
## so the mark reads as one area, where outlining every tile would redraw the
## grid of cells that `ScoreRevealLayer` already uses to say "these tiles paid".
##
## Which sides of a cell face out is decided from the cell list the controller
## supplied - a membership test over cells, not a rule, and never a comparison of
## edge colours.
func _draw_cluster(cluster: Dictionary, line: float) -> void:
	var cells: Array = cluster.get("cells", [] as Array)
	if cells.is_empty():
		return
	var base: Color = TilePainter.edge_color_for(int(cluster.get("color", -1)))

	# Membership by cell, so the perimeter test below does not rescan the list
	# once per side of every tile.
	var members: Dictionary = {}
	for raw: Variant in cells:
		if not (raw is Vector2i):
			continue
		var cell: Vector2i = raw
		if not BoardMetrics.is_valid_cell(cell, state.grid):
			continue
		members[cell] = true
	if members.is_empty():
		return

	var wash: Color = Color(base.r, base.g, base.b, WASH_ALPHA)
	var stroke: Color = Color(base.r, base.g, base.b, OUTLINE_ALPHA)
	# `BoardEnums.neighbor_offsets()` is the rules layer's fixed order
	# [up, right, down, left], which is exactly `TileEnums.EdgePosition` order
	# (top, right, bottom, left), so indexing it by an edge position yields the
	# neighbour across that side without restating a mapping here.
	var offsets: Array[Vector2i] = BoardEnums.neighbor_offsets()
	for raw_member: Variant in members.keys():
		var drawn_cell: Vector2i = raw_member
		var rect: Rect2 = BoardMetrics.cell_rect(state.board_rect, drawn_cell, state.grid)
		if not TilePainter.is_drawable(rect):
			continue
		draw_rect(rect, wash, true)
		_stroke_outer_sides(rect, drawn_cell, members, offsets, stroke, line)


## Strokes the sides of `rect` whose neighbour is outside the region.
##
## The stroke is inset by half its own width so it sits inside the region it
## marks and cannot be read as the neighbouring cell's own edge.
func _stroke_outer_sides(
	rect: Rect2,
	cell: Vector2i,
	members: Dictionary,
	offsets: Array[Vector2i],
	color: Color,
	line: float
) -> void:
	var inner: Rect2 = rect.grow(-line * 0.5)
	var top_left: Vector2 = inner.position
	var top_right: Vector2 = Vector2(inner.end.x, inner.position.y)
	var bottom_left: Vector2 = Vector2(inner.position.x, inner.end.y)
	var bottom_right: Vector2 = inner.end
	if not members.has(cell + offsets[TileEnums.EdgePosition.TOP]):
		draw_line(top_left, top_right, color, line)
	if not members.has(cell + offsets[TileEnums.EdgePosition.RIGHT]):
		draw_line(top_right, bottom_right, color, line)
	if not members.has(cell + offsets[TileEnums.EdgePosition.BOTTOM]):
		draw_line(bottom_left, bottom_right, color, line)
	if not members.has(cell + offsets[TileEnums.EdgePosition.LEFT]):
		draw_line(top_left, bottom_left, color, line)
