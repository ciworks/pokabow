extends TestCase

## Milestone 3 matching-boundary tests (ADR-002 sections 1 and 7).
##
## Domain-level: no scene tree, no rendering. Every expectation is checked against
## `EdgeMatchScorer` and the board alone.

const BLUE: int = TileEnums.EdgeColor.BLUE
const RED: int = TileEnums.EdgeColor.RED
const GREEN: int = TileEnums.EdgeColor.GREEN
const YELLOW: int = TileEnums.EdgeColor.YELLOW


func test_touching_edges_are_compared_in_every_direction() -> void:
	var board: BoardState = BoardState.create()
	# Centre tile: top BLUE, right RED, bottom GREEN, left YELLOW.
	_place(board, Vector2i(5, 5), BLUE, RED, GREEN, YELLOW, "centre")
	# Each neighbour exposes the colour that must face the centre tile.
	_place(board, Vector2i(5, 4), GREEN, GREEN, BLUE, YELLOW, "above")
	_place(board, Vector2i(6, 5), GREEN, GREEN, YELLOW, RED, "right")
	_place(board, Vector2i(5, 6), GREEN, RED, GREEN, GREEN, "below")
	_place(board, Vector2i(4, 5), YELLOW, YELLOW, GREEN, YELLOW, "left")

	check(
		EdgeMatchScorer.is_matching_boundary(board, Vector2i(5, 5), Vector2i(5, 4)),
		"the centre tile's top edge must be compared with the upper tile's bottom edge"
	)
	check(
		EdgeMatchScorer.is_matching_boundary(board, Vector2i(5, 5), Vector2i(6, 5)),
		"the centre tile's right edge must be compared with the right tile's left edge"
	)
	check(
		EdgeMatchScorer.is_matching_boundary(board, Vector2i(5, 5), Vector2i(5, 6)),
		"the centre tile's bottom edge must be compared with the lower tile's top edge"
	)
	check(
		EdgeMatchScorer.is_matching_boundary(board, Vector2i(5, 5), Vector2i(4, 5)),
		"the centre tile's left edge must be compared with the left tile's right edge"
	)

	check_eq(
		EdgeMatchResult.create(&"probe", EdgeMatchScorer.matching_color(
			board, Vector2i(5, 5), Vector2i(5, 4)
		), []).color,
		BLUE,
		"the shared colour must be reported"
	)


func test_rotated_edges_are_used_for_comparison() -> void:
	var board: BoardState = BoardState.create()
	# Base order top / right / bottom / left is BLUE, RED, GREEN, YELLOW.
	# One clockwise quarter-turn moves the left edge (YELLOW) to the top and the
	# top edge (BLUE) to the right.
	_place_rotated(board, Vector2i(5, 5), BLUE, RED, GREEN, YELLOW, 1, "rotated")
	_place(board, Vector2i(6, 5), GREEN, GREEN, YELLOW, BLUE, "right")

	check(
		EdgeMatchScorer.is_matching_boundary(board, Vector2i(5, 5), Vector2i(6, 5)),
		"after one quarter-turn the tile's right edge is its original top colour"
	)
	check_eq(
		EdgeMatchScorer.matching_color(board, Vector2i(5, 5), Vector2i(6, 5)),
		BLUE,
		"the compared colour must come from the rotated orientation"
	)

	# The same neighbour fails to match the unrotated tile on the right side,
	# because the unrotated right edge is RED.
	var unrotated: BoardState = BoardState.create()
	_place(unrotated, Vector2i(5, 5), BLUE, RED, GREEN, YELLOW, "flat")
	_place(unrotated, Vector2i(6, 5), GREEN, GREEN, YELLOW, BLUE, "right")
	check(
		not EdgeMatchScorer.is_matching_boundary(unrotated, Vector2i(5, 5), Vector2i(6, 5)),
		"rotation must change which edges touch"
	)


func test_mismatched_and_diagonal_boundaries_award_nothing() -> void:
	var board: BoardState = BoardState.create()
	_place(board, Vector2i(5, 5), BLUE, BLUE, BLUE, BLUE, "centre")
	_place(board, Vector2i(6, 5), RED, RED, RED, RED, "mismatched")
	_place(board, Vector2i(6, 6), BLUE, BLUE, BLUE, BLUE, "diagonal")

	check(
		not EdgeMatchScorer.is_matching_boundary(board, Vector2i(5, 5), Vector2i(6, 5)),
		"a legal mismatching boundary awards no edge-match point"
	)
	check_eq(
		EdgeMatchScorer.matching_color(board, Vector2i(5, 5), Vector2i(6, 5)),
		-1,
		"a mismatching boundary has no shared colour"
	)
	check(
		not EdgeMatchScorer.are_adjacent(Vector2i(5, 5), Vector2i(6, 6)),
		"diagonal contact is not a boundary"
	)
	check(
		not EdgeMatchScorer.are_adjacent(Vector2i(5, 5), Vector2i(5, 5)),
		"a cell is not adjacent to itself"
	)
	check_eq(
		EdgeMatchScorer.matching_color(board, Vector2i(5, 5), Vector2i(6, 6)),
		-1,
		"diagonal contact cannot produce an edge match"
	)


func test_a_placement_awards_one_point_per_new_matching_boundary() -> void:
	var board: BoardState = BoardState.create()
	_place(board, Vector2i(5, 4), GREEN, BLUE, BLUE, YELLOW, "above")
	_place(board, Vector2i(6, 5), GREEN, GREEN, YELLOW, GREEN, "right")

	var snapshot: TileSnapshot = _snapshot(Vector2i(5, 5), BLUE, GREEN, YELLOW, YELLOW, true, "placed")
	var results: Array[EdgeMatchResult] = EdgeMatchScorer.evaluate_placement(board, snapshot)

	check_eq(results.size(), 2, "only the two matching sides of the placement award points")
	check_eq(results[0].points, 1, "a matching boundary awards exactly one point")
	check_eq(results[1].points, 1, "a matching boundary awards exactly one point")
	check_eq(
		EdgeMatchScorer.evaluate_placement(board, snapshot)[0].color,
		BLUE,
		"the reported colour is the shared touching colour"
	)
	check(not board.is_occupied(Vector2i(5, 5)), "evaluating a placement must not mutate the board")


func test_each_undirected_boundary_is_evaluated_once() -> void:
	var board: BoardState = BoardState.create()
	for cell: Vector2i in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6), Vector2i(6, 6)]:
		_place(board, cell, BLUE, BLUE, BLUE, BLUE, "block")

	var results: Array[EdgeMatchResult] = EdgeMatchScorer.enumerate_boundaries(board)

	check_eq(results.size(), 4, "a 2 x 2 block holds four boundaries, not eight")
	check_eq(
		results.size(),
		EdgeMatchScorer.boundary_ids(board).size(),
		"the id list and the result list must describe the same boundaries"
	)
	check_eq(
		EdgeMatchScorer.enumerate_boundaries(board).size(),
		EdgeMatchScorer.evaluate_full_board(board).size(),
		"the full-board path must agree with the enumeration path"
	)


func test_boundary_ids_are_canonical_and_order_independent() -> void:
	var a: Vector2i = Vector2i(5, 5)
	var b: Vector2i = Vector2i(6, 5)
	var forward: StringName = ScoringEnums.boundary_id_for(a, b)
	var backward: StringName = ScoringEnums.boundary_id_for(b, a)

	check_eq(String(forward), String(backward), "a boundary id must not depend on direction")
	check_eq(String(forward), "edge:5,5-6,5", "the pair must be ordered by row-major index")
	check_eq(
		String(ScoringEnums.boundary_id_for(Vector2i(5, 5), Vector2i(4, 5))),
		"edge:4,5-5,5",
		"a left neighbour still orders the pair row-major"
	)
	check_eq(
		String(ScoringEnums.boundary_id_for(Vector2i(5, 5), Vector2i(6, 6))),
		"",
		"a diagonal pair cannot hold a boundary id"
	)
	check_eq(
		String(ScoringEnums.boundary_id_for(Vector2i(11, 5), Vector2i(12, 5))),
		"",
		"an out-of-bounds pair cannot hold a boundary id"
	)

	var board: BoardState = BoardState.create()
	_place(board, a, BLUE, BLUE, BLUE, BLUE, "a")
	_place(board, b, BLUE, BLUE, BLUE, BLUE, "b")
	var results: Array[EdgeMatchResult] = EdgeMatchScorer.enumerate_boundaries(board)
	check_eq(results.size(), 1, "two touching tiles hold one boundary")
	check_eq(
		results[0].cells,
		_pair(a, b),
		"the reported pair must be in canonical order"
	)
	check_eq(String(results[0].boundary_id), "edge:5,5-6,5", "the reported id must be canonical")


func test_edge_arity_is_fixed_by_the_accepted_rule() -> void:
	check_eq(ScoringEnums.EDGE_MATCH_POINTS, 1, "a matching boundary is worth exactly one point")
	check_eq(
		ScoringEnums.ScoreCategory.values().size(),
		3,
		"Phase 1 has exactly three score categories"
	)


## Places a tile with the given base edges in top / right / bottom / left order.
func _place(
	board: BoardState,
	cell: Vector2i,
	top: int,
	right: int,
	bottom: int,
	left: int,
	id: String
) -> TileSnapshot:
	return _place_rotated(board, cell, top, right, bottom, left, 0, id)


## Places a tile with the given base edges and quarter-turn rotation.
func _place_rotated(
	board: BoardState,
	cell: Vector2i,
	top: int,
	right: int,
	bottom: int,
	left: int,
	rotation: int,
	id: String
) -> TileSnapshot:
	var snapshot: TileSnapshot = _snapshot(cell, top, right, bottom, left, true, id)
	if not board.commit_tile(TileSnapshot.create(snapshot.get_tile(), cell, rotation)):
		push_error("test setup could not commit tile '%s'" % id)
	var committed: TileSnapshot = board.get_tile(cell)
	return committed


## Builds a snapshot without committing it.
func _snapshot(
	cell: Vector2i,
	top: int,
	right: int,
	bottom: int,
	left: int,
	valid: bool,
	id: String
) -> TileSnapshot:
	var edges: Array[TileEnums.EdgeColor] = [top, right, bottom, left]
	var tile: TileDefinition = TileDefinition.create(
		StringName(id), TileEnums.TileRank.ACE, TileEnums.FaceColor.RED, edges
	)
	if not valid:
		push_error("test helper only builds valid tiles")
	return TileSnapshot.create(tile, cell, 0)


## Converts a literal list into a typed cell array for comparison.
func _pair(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var pair: Array[Vector2i] = []
	if BoardEnums.cell_index(a) <= BoardEnums.cell_index(b):
		pair.append(a)
		pair.append(b)
	else:
		pair.append(b)
		pair.append(a)
	return pair
