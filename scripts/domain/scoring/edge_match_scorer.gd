class_name EdgeMatchScorer
extends RefCounted

## Pure matching-boundary evaluation (ADR-002 section 1).
##
## A matching edge exists when two committed tiles occupy orthogonally adjacent
## cells and their touching edges have the same visible colour after rotation.
## Top compares with the upper neighbour's bottom, right with the right
## neighbour's left, and so on, using each tile's rotated edges rather than its
## canonical orientation.
##
## Each undirected tile-to-tile boundary is evaluated once, and the second tile
## committed awards +1 (ADR-002 section 1). Non-matching boundaries are legal
## under ADR-006 section 4 and award nothing.
##
## This class holds no state and never mutates a board or a scene node, so
## preview, committed scoring, AI evaluation, and verification share one
## definition of a matching boundary.

## The two offsets that enumerate every undirected boundary exactly once when
## applied to every occupied cell: right and down.
const FORWARD_OFFSETS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]


## Returns true when `a` and `b` are orthogonally neighbouring board cells.
static func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return BoardEnums.edge_position_toward(b - a) != -1


## Returns the shared edge colour of a matching boundary, or -1.
##
## Returns -1 when either cell is off-board, empty, or not orthogonally adjacent
## to the other, and when the touching colours differ.
static func matching_color(board: BoardState, a: Vector2i, b: Vector2i) -> int:
	if board == null:
		return -1
	var position: int = BoardEnums.edge_position_toward(b - a)
	if position == -1:
		return -1
	var tile_a: TileSnapshot = board.get_tile(a)
	var tile_b: TileSnapshot = board.get_tile(b)
	if tile_a == null or tile_b == null:
		return -1
	var color_a: int = tile_a.get_edge_at(position)
	var color_b: int = tile_b.get_edge_at(BoardEnums.opposite_edge_position(position))
	if color_a < 0 or color_b < 0 or color_a != color_b:
		return -1
	return color_a


## Returns true when two cells form a matching boundary.
static func is_matching_boundary(board: BoardState, a: Vector2i, b: Vector2i) -> bool:
	return matching_color(board, a, b) >= 0


## Returns the matching boundaries a placement creates, ordered by identifier.
##
## `board` is the pre-move board and `snapshot` the tile about to be committed.
## Every boundary touching the placed cell is new, because the placed tile did
## not exist before, so all four sides are candidates (ADR-002 section 1).
## Never mutates the board.
static func evaluate_placement(board: BoardState, snapshot: TileSnapshot) -> Array[EdgeMatchResult]:
	var results: Array[EdgeMatchResult] = []
	if board == null or snapshot == null or not snapshot.is_valid():
		return results

	var placed_cell: Vector2i = snapshot.get_cell()
	for offset: Vector2i in BoardEnums.neighbor_offsets():
		var neighbor: Vector2i = placed_cell + offset
		var neighbor_tile: TileSnapshot = board.get_tile(neighbor)
		if neighbor_tile == null:
			continue
		var position: int = BoardEnums.edge_position_toward(offset)
		var placed_color: int = snapshot.get_edge_at(position)
		var neighbor_color: int = neighbor_tile.get_edge_at(
			BoardEnums.opposite_edge_position(position)
		)
		if placed_color < 0 or neighbor_color < 0 or placed_color != neighbor_color:
			continue
		results.append(
			EdgeMatchResult.create(
				ScoringEnums.boundary_id_for(placed_cell, neighbor),
				placed_color,
				_ordered_pair(placed_cell, neighbor)
			)
		)

	_sort_by_boundary_id(results)
	return results


## Returns every matching boundary on the board, ordered by identifier.
##
## This is the full-board audit path of ADR-002 section 8: each undirected
## boundary is enumerated once, so the count equals the edge-match points the
## board represents.
static func enumerate_boundaries(board: BoardState) -> Array[EdgeMatchResult]:
	var results: Array[EdgeMatchResult] = []
	if board == null:
		return results

	for cell: Vector2i in board.get_occupied_cells():
		for offset: Vector2i in FORWARD_OFFSETS:
			var neighbor: Vector2i = cell + offset
			var color: int = matching_color(board, cell, neighbor)
			if color < 0:
				continue
			results.append(
				EdgeMatchResult.create(
					ScoringEnums.boundary_id_for(cell, neighbor),
					color,
					_ordered_pair(cell, neighbor)
				)
			)

	_sort_by_boundary_id(results)
	return results


## Returns every matching boundary on the board, ordered by identifier.
##
## An explicit alias for `enumerate_boundaries` so the verification paths read the
## same as their poker and cluster counterparts.
static func evaluate_full_board(board: BoardState) -> Array[EdgeMatchResult]:
	return enumerate_boundaries(board)


## Returns the canonical identifiers of every matching boundary on the board.
static func boundary_ids(board: BoardState) -> Array[StringName]:
	var ids: Array[StringName] = []
	for result: EdgeMatchResult in enumerate_boundaries(board):
		ids.append(result.boundary_id)
	return ids


## Returns the canonical two-cell pair for a boundary.
static func _ordered_pair(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var pair: Array[Vector2i] = []
	if BoardEnums.cell_index(a) <= BoardEnums.cell_index(b):
		pair.append(a)
		pair.append(b)
	else:
		pair.append(b)
		pair.append(a)
	return pair


## Sorts results by canonical identifier, for deterministic event ordering.
static func _sort_by_boundary_id(results: Array[EdgeMatchResult]) -> void:
	results.sort_custom(
		func(a: EdgeMatchResult, b: EdgeMatchResult) -> bool:
			return String(a.boundary_id) < String(b.boundary_id)
	)
