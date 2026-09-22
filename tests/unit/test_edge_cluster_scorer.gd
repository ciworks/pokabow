extends TestCase

## Milestone 3 cluster tests (ADR-002 sections 2 to 5 and 8).
##
## Domain-level: no scene tree, no rendering, no input. Every expectation is
## checked against `EdgeClusterScorer`, `ClusterScoreRules`, and the board alone.

const BLUE: int = TileEnums.EdgeColor.BLUE
const RED: int = TileEnums.EdgeColor.RED
const GREEN: int = TileEnums.EdgeColor.GREEN
const YELLOW: int = TileEnums.EdgeColor.YELLOW


func test_entitlement_milestones_follow_the_accepted_formula() -> void:
	var rules: ClusterScoreRules = ClusterScoreRules.create_default()

	check_eq(rules.milestone_size, 4, "Phase 1 completes a milestone every four tiles")
	check_eq(rules.flat_award, 3, "Phase 1 awards three points per milestone")
	check_eq(rules.entitlement_for_size(1), 0, "a single tile is worth no cluster points")
	check_eq(rules.entitlement_for_size(3), 0, "an incomplete milestone is worth nothing")
	check_eq(rules.entitlement_for_size(4), 3, "four tiles complete one milestone")
	check_eq(rules.entitlement_for_size(7), 3, "growth within a band adds nothing")
	check_eq(rules.entitlement_for_size(8), 6, "eight tiles complete two milestones")
	check_eq(rules.entitlement_for_size(12), 9, "twelve tiles complete three milestones")
	check_eq(rules.entitlement_for_size(0), 0, "an empty cluster has no entitlement")
	check(rules.is_valid(), "the approved cluster values must validate")


func test_cluster_size_counts_unique_tiles_not_boundaries() -> void:
	var rules: ClusterScoreRules = ClusterScoreRules.create_default()

	var pair: BoardState = BoardState.create()
	_blue_block(pair, [Vector2i(5, 5), Vector2i(6, 5)])
	check_eq(EdgeClusterScorer.components_for_color(pair, BLUE).size(), 1, "two joined tiles form one component")
	check_eq(_edge_count(pair), 1, "two touching tiles hold one matching boundary")
	check_eq(
		EdgeClusterScorer.component_of(pair, Vector2i(5, 5), BLUE).size(),
		2,
		"the component counts the two unique tiles"
	)

	var loop: BoardState = BoardState.create()
	_blue_block(loop, [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6), Vector2i(6, 6)])
	var component: Array[Vector2i] = EdgeClusterScorer.component_of(loop, Vector2i(5, 5), BLUE)

	check_eq(_edge_count(loop), 4, "a 2 x 2 loop holds four matching boundaries")
	check_eq(component.size(), 4, "a loop of four tiles is a component of four unique tiles")
	check_eq(
		rules.entitlement_for_size(component.size()),
		3,
		"a loop earns one milestone, not one per boundary"
	)


func test_diagonal_contact_never_joins_a_component() -> void:
	var board: BoardState = BoardState.create()
	_blue_block(board, [Vector2i(5, 5), Vector2i(6, 6)])

	check_eq(
		EdgeClusterScorer.components_for_color(board, BLUE).size(),
		0,
		"diagonal tiles share no boundary, so neither is a vertex"
	)
	check_eq(
		EdgeClusterScorer.component_of(board, Vector2i(5, 5), BLUE).size(),
		0,
		"an isolated tile belongs to no single-colour component"
	)

	# (4,5) is orthogonally adjacent to (5,5) and touches neither (6,6) nor any
	# other tile, so it joins a component without accidentally connecting the
	# diagonal tile the way a tile placed at (6,5) would.
	_blue_block(board, [Vector2i(4, 5)])

	check_eq(
		EdgeClusterScorer.component_of(board, Vector2i(5, 5), BLUE).size(),
		2,
		"orthogonal contact does join a component"
	)
	check_eq(
		EdgeClusterScorer.components_for_color(board, BLUE).size(),
		1,
		"the diagonal tile must still not join the orthogonal component"
	)


func test_colours_never_mix_and_one_tile_may_join_two_clusters() -> void:
	var board: BoardState = BoardState.create()
	# Centre tile: top BLUE, right RED, bottom GREEN, left YELLOW.
	_place(board, Vector2i(5, 5), BLUE, RED, GREEN, YELLOW, "centre")
	# The upper tile exposes BLUE downward, the right tile exposes RED leftward.
	_place(board, Vector2i(5, 4), GREEN, BLUE, BLUE, YELLOW, "above")
	_place(board, Vector2i(6, 5), GREEN, GREEN, YELLOW, RED, "right")

	var blue: Array = EdgeClusterScorer.components_for_color(board, BLUE)
	var red: Array = EdgeClusterScorer.components_for_color(board, RED)

	check_eq(blue.size(), 1, "the centre and upper tiles form one blue component")
	check_eq(red.size(), 1, "the centre and right tiles form one red component")
	check_eq((blue[0] as Array).size(), 2, "the blue component holds two unique tiles")
	check_eq((red[0] as Array).size(), 2, "the red component holds two unique tiles")
	check_eq(
		EdgeClusterScorer.components_for_color(board, GREEN).size(),
		0,
		"a colour with no matching boundary forms no component"
	)
	check_eq(
		EdgeClusterScorer.components_for_color(board, YELLOW).size(),
		0,
		"a colour with no matching boundary forms no component"
	)


func test_a_placement_awards_the_entitlement_delta() -> void:
	var rules: ClusterScoreRules = ClusterScoreRules.create_default()

	# A blue line of three grows to four: entitlement 0 becomes 3.
	var board: BoardState = BoardState.create()
	_blue_block(board, [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)])
	var grower: TileSnapshot = _blue_tile(Vector2i(8, 5), "grower")
	var results: Array[ClusterScoreResult] = EdgeClusterScorer.evaluate_placement(board, grower, rules)

	check_eq(results.size(), 1, "one completed milestone produces one cluster event")
	check_eq(results[0].color, BLUE, "the event must name the cluster's colour")
	check_eq(results[0].previous_entitlement, 0, "a size-three component had no entitlement")
	check_eq(results[0].current_entitlement, 3, "a size-four component is worth one milestone")
	check_eq(results[0].points, 3, "the award is the entitlement difference")
	check_eq(results[0].cells.size(), 4, "the event reports the post-move component")
	check(not board.is_occupied(Vector2i(8, 5)), "evaluating a placement must not mutate the board")

	# A blue line of seven grows to eight: entitlement 3 becomes 6.
	var long_board: BoardState = BoardState.create()
	_blue_block(long_board, [
		Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5),
		Vector2i(9, 5), Vector2i(10, 5), Vector2i(11, 5),
	])
	var long_results: Array[ClusterScoreResult] = EdgeClusterScorer.evaluate_placement(
		long_board, _blue_tile(Vector2i(4, 5), "extender"), rules
	)

	check_eq(long_results.size(), 1, "one completed milestone produces one cluster event")
	check_eq(long_results[0].previous_entitlement, 3, "a size-seven component held one milestone")
	check_eq(long_results[0].current_entitlement, 6, "a size-eight component holds two milestones")
	check_eq(long_results[0].points, 3, "the award is the entitlement difference")


func test_growth_inside_a_band_awards_nothing() -> void:
	var rules: ClusterScoreRules = ClusterScoreRules.create_default()
	var board: BoardState = BoardState.create()
	_blue_block(board, [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5)])

	var results: Array[ClusterScoreResult] = EdgeClusterScorer.evaluate_placement(
		board, _blue_tile(Vector2i(9, 5), "grower"), rules
	)

	check_eq(
		results.size(),
		0,
		"growth inside a milestone band awards nothing, so no cluster event is produced"
	)
	check_eq(
		rules.entitlement_for_size(4),
		rules.entitlement_for_size(5),
		"a size-four and a size-five component hold the same entitlement"
	)


func test_a_covered_merge_awards_nothing() -> void:
	var rules: ClusterScoreRules = ClusterScoreRules.create_default()
	var board: BoardState = BoardState.create()
	# Two separate blue lines of four, on rows five and seven.
	_blue_block(board, [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5)])
	_blue_block(board, [Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7)])

	var bridge: TileSnapshot = _blue_tile(Vector2i(5, 6), "bridge")
	var results: Array[ClusterScoreResult] = EdgeClusterScorer.evaluate_placement(board, bridge, rules)

	check_eq(
		results.size(),
		0,
		"joining two already-scored components awards nothing, so no event is produced"
	)
	check_eq(rules.entitlement_for_size(4), 3, "each pre-move component held one milestone")
	check_eq(
		EdgeClusterScorer.component_of(board.with_tile(bridge), Vector2i(5, 6), BLUE).size(),
		9,
		"the joined component holds nine unique tiles"
	)
	check_eq(
		rules.entitlement_for_size(9),
		6,
		"nine tiles are worth exactly the six points the two components already held"
	)


func test_a_mixed_merge_awards_only_the_uncovered_milestone() -> void:
	var rules: ClusterScoreRules = ClusterScoreRules.create_default()
	var board: BoardState = BoardState.create()
	# A size-three component (no entitlement) and a size-four component (three).
	_blue_block(board, [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)])
	_blue_block(board, [Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7)])

	var results: Array[ClusterScoreResult] = EdgeClusterScorer.evaluate_placement(
		board, _blue_tile(Vector2i(5, 6), "bridge"), rules
	)

	check_eq(results.size(), 1, "the join completes one further milestone")
	check_eq(results[0].previous_entitlement, 3, "only the size-four component held a milestone")
	check_eq(results[0].current_entitlement, 6, "the joined component is size eight")
	check_eq(results[0].points, 3, "the award is the uncovered milestone only")


func test_two_colours_can_complete_a_milestone_in_one_placement() -> void:
	var rules: ClusterScoreRules = ClusterScoreRules.create_default()
	var board: BoardState = BoardState.create()
	# A blue line of three above the target, and a red line of three to its right.
	_blue_block(board, [Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5)])
	_place(board, Vector2i(7, 6), GREEN, RED, YELLOW, RED, "red-a")
	_place(board, Vector2i(8, 6), GREEN, RED, YELLOW, RED, "red-b")
	_place(board, Vector2i(9, 6), GREEN, RED, YELLOW, RED, "red-c")

	var placed: TileSnapshot = _make(Vector2i(6, 6), BLUE, RED, GREEN, YELLOW, "placed")
	var results: Array[ClusterScoreResult] = EdgeClusterScorer.evaluate_placement(board, placed, rules)

	check_eq(results.size(), 2, "one placement can complete milestones in two colours")
	check_eq(results[0].color, BLUE, "cluster events are ordered by the colour enum")
	check_eq(results[1].color, RED, "cluster events are ordered by the colour enum")
	check_eq(results[0].points, 3, "the blue line of three becomes four")
	check_eq(results[1].points, 3, "the red line of three becomes four")
	check_eq(results[0].current_entitlement, 3, "the blue component holds one milestone")
	check_eq(results[1].current_entitlement, 3, "the red component holds one milestone")
	check_eq(
		EdgeClusterScorer.total_entitlement(board, rules),
		0,
		"before the placement neither colour had completed a milestone"
	)
	check_eq(
		EdgeClusterScorer.total_entitlement(board.with_tile(placed), rules),
		6,
		"after the placement both colours hold one milestone"
	)
	check_eq(
		EdgeClusterScorer.entitlement_for_color(board.with_tile(placed), BLUE, rules),
		3,
		"the blue total must be reported separately from the red total"
	)
	check_eq(
		EdgeClusterScorer.entitlement_for_color(board.with_tile(placed), RED, rules),
		3,
		"the red total must be reported separately from the blue total"
	)


func test_full_board_entitlement_totals_are_reported_per_colour() -> void:
	var rules: ClusterScoreRules = ClusterScoreRules.create_default()
	var board: BoardState = BoardState.create()
	_blue_block(board, [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5)])

	var totals: Dictionary = EdgeClusterScorer.entitlement_totals(board, rules)

	check_eq(totals.get("blue", -1), 3, "the blue component holds one milestone")
	check_eq(totals.get("red", -1), 0, "a colour with no boundary holds nothing")
	check_eq(totals.get("green", -1), 0, "a colour with no boundary holds nothing")
	check_eq(totals.get("yellow", -1), 0, "a colour with no boundary holds nothing")
	check_eq(EdgeClusterScorer.total_entitlement(board, rules), 3, "the board holds one milestone")
	check_eq(
		EdgeClusterScorer.total_entitlement(board, rules),
		int(totals.get("blue", 0)) + int(totals.get("red", 0))
		+ int(totals.get("green", 0)) + int(totals.get("yellow", 0)),
		"the board total must equal the sum of the colour totals"
	)


## Commits a tile whose four edges are all BLUE at each given cell.
func _blue_block(board: BoardState, cells: Array) -> void:
	for value: Variant in cells:
		var cell: Vector2i = value
		board.commit_tile(_blue_tile(cell, "blue-%d-%d" % [cell.x, cell.y]))


## Returns an uncommitted all-BLUE snapshot.
func _blue_tile(cell: Vector2i, id: String) -> TileSnapshot:
	return _make(cell, BLUE, BLUE, BLUE, BLUE, id)


## Commits a tile with the given base edges in top / right / bottom / left order.
func _place(
	board: BoardState,
	cell: Vector2i,
	top: int,
	right: int,
	bottom: int,
	left: int,
	id: String
) -> void:
	board.commit_tile(_make(cell, top, right, bottom, left, id))


## Builds an uncommitted snapshot whose base edges are in top / right / bottom /
## left order.
func _make(cell: Vector2i, top: int, right: int, bottom: int, left: int, id: String) -> TileSnapshot:
	var edges: Array[TileEnums.EdgeColor] = [top, right, bottom, left]
	var tile: TileDefinition = TileDefinition.create(
		StringName(id), TileEnums.TileRank.ACE, TileEnums.FaceColor.RED, edges
	)
	return TileSnapshot.create(tile, cell, 0)


## Returns the number of matching boundaries on the board.
func _edge_count(board: BoardState) -> int:
	return EdgeMatchScorer.boundary_ids(board).size()
