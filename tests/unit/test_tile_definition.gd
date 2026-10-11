extends TestCase

## Milestone 1 tile value tests (docs/PHASE-1-IMPLEMENTATION-PLAN.md).
##
## Covers the canonical edge index order, all four quarter-turn rotation
## mappings, non-mutation of the canonical edge array, snapshot rotation, and
## value validation.
##
## No scene tree is involved: ADR-008 section 13 requires domain tests to run
## headlessly, and AGENTS.md section 16 requires tile logic to be testable
## independently of presentation.

const TOP_INDEX: int = 0
const RIGHT_INDEX: int = 1
const BOTTOM_INDEX: int = 2
const LEFT_INDEX: int = 3


# --- Edge ordering (docs/sections/01-tile-system.md section 5.1) ---


func test_edge_index_order_is_clockwise_from_top() -> void:
	var tile: TileDefinition = _sample_tile()
	var edges: Array = tile.get_base_edges()

	check_eq(edges.size(), 4, "a tile must hold exactly four canonical edges")
	if edges.size() != 4:
		return
	check_eq(
		int(edges[TOP_INDEX]),
		TileEnums.EdgeColor.BLUE,
		"index 0 must be the top edge (clockwise, starting at the top)"
	)
	check_eq(int(edges[RIGHT_INDEX]), TileEnums.EdgeColor.RED, "index 1 must be the right edge")
	check_eq(int(edges[BOTTOM_INDEX]), TileEnums.EdgeColor.GREEN, "index 2 must be the bottom edge")
	check_eq(int(edges[LEFT_INDEX]), TileEnums.EdgeColor.YELLOW, "index 3 must be the left edge")


func test_edge_position_enum_matches_the_index_convention() -> void:
	check_eq(TileEnums.EdgePosition.TOP, TOP_INDEX, "EdgePosition.TOP must be index 0")
	check_eq(TileEnums.EdgePosition.RIGHT, RIGHT_INDEX, "EdgePosition.RIGHT must be index 1")
	check_eq(TileEnums.EdgePosition.BOTTOM, BOTTOM_INDEX, "EdgePosition.BOTTOM must be index 2")
	check_eq(TileEnums.EdgePosition.LEFT, LEFT_INDEX, "EdgePosition.LEFT must be index 3")
	check_eq(TileEnums.EDGE_COUNT, 4, "a tile has four edge positions")
	check_eq(TileEnums.ROTATION_COUNT, 4, "a tile has four quarter-turn orientations")


func test_get_edge_at_follows_the_index_convention() -> void:
	var tile: TileDefinition = _sample_tile()

	check_eq(
		tile.get_edge_at(TileEnums.EdgePosition.TOP),
		TileEnums.EdgeColor.BLUE,
		"the unrotated top edge must be the canonical top colour"
	)
	check_eq(
		tile.get_edge_at(TileEnums.EdgePosition.RIGHT),
		TileEnums.EdgeColor.RED,
		"the unrotated right edge must be the canonical right colour"
	)
	check_eq(
		tile.get_edge_at(TileEnums.EdgePosition.TOP, 1),
		TileEnums.EdgeColor.YELLOW,
		"a clockwise turn must bring the canonical left edge to the top"
	)
	check_eq(
		tile.get_edge_at(TileEnums.EdgePosition.RIGHT, 1),
		TileEnums.EdgeColor.BLUE,
		"a clockwise turn must bring the canonical top edge to the right"
	)
	check_eq(tile.get_edge_at(99), -1, "an invalid edge position must report the error sentinel")


# --- Rotation mapping (docs/sections/01-tile-system.md section 6.2) ---


func test_rotation_mapping_for_all_four_orientations() -> void:
	var tile: TileDefinition = _sample_tile()
	var blue: int = TileEnums.EdgeColor.BLUE
	var red: int = TileEnums.EdgeColor.RED
	var green: int = TileEnums.EdgeColor.GREEN
	var yellow: int = TileEnums.EdgeColor.YELLOW

	check_eq(
		_as_ints(tile.get_rotated_edges(0)),
		_four(blue, red, green, yellow),
		"rotation 0 must expose the canonical edges unchanged"
	)
	check_eq(
		_as_ints(tile.get_rotated_edges(1)),
		_four(yellow, blue, red, green),
		"one clockwise quarter turn must move each edge one position clockwise"
	)
	check_eq(
		_as_ints(tile.get_rotated_edges(2)),
		_four(green, yellow, blue, red),
		"two clockwise quarter turns must move each edge two positions clockwise"
	)
	check_eq(
		_as_ints(tile.get_rotated_edges(3)),
		_four(red, green, yellow, blue),
		"three clockwise quarter turns must move each edge three positions clockwise"
	)


func test_default_call_reports_the_canonical_orientation() -> void:
	var tile: TileDefinition = _sample_tile()

	check_eq(
		_as_ints(tile.get_rotated_edges()),
		_as_ints(tile.get_rotated_edges(0)),
		"GAME_SPEC 3.2 get_rotated_edges() must report the current orientation"
	)


func test_four_quarter_turns_return_to_the_original_orientation() -> void:
	var tile: TileDefinition = _sample_tile()

	for turn: int in range(TileEnums.ROTATION_COUNT):
		check_eq(
			_as_ints(tile.get_rotated_edges(turn + TileEnums.ROTATION_COUNT)),
			_as_ints(tile.get_rotated_edges(turn)),
			"rotation must wrap every four quarter turns (turn %d)" % turn
		)

	check_eq(
		_as_ints(tile.get_rotated_edges(-1)),
		_as_ints(tile.get_rotated_edges(3)),
		"a negative turn must wrap to the equivalent orientation"
	)


func test_rotation_does_not_mutate_the_canonical_edges() -> void:
	var tile: TileDefinition = _sample_tile()

	tile.get_rotated_edges(1)
	tile.get_rotated_edges(2)
	tile.get_rotated_edges(3)

	check_eq(
		_as_ints(tile.get_base_edges()),
		_four(
			TileEnums.EdgeColor.BLUE,
			TileEnums.EdgeColor.RED,
			TileEnums.EdgeColor.GREEN,
			TileEnums.EdgeColor.YELLOW
		),
		"ADR-004 section 4 requires rotation to leave the canonical edges untouched"
	)


func test_a_uniform_edge_tile_is_stable_under_every_rotation() -> void:
	var edges: Array[TileEnums.EdgeColor] = [
		TileEnums.EdgeColor.GREEN,
		TileEnums.EdgeColor.GREEN,
		TileEnums.EdgeColor.GREEN,
		TileEnums.EdgeColor.GREEN,
	]
	var tile: TileDefinition = TileDefinition.create(
		&"match-1:tile:007", TileEnums.TileRank.JACK, TileEnums.FaceColor.BLACK, edges
	)

	for turn: int in range(TileEnums.ROTATION_COUNT):
		check_eq(
			_as_ints(tile.get_rotated_edges(turn)),
			_four(
				TileEnums.EdgeColor.GREEN,
				TileEnums.EdgeColor.GREEN,
				TileEnums.EdgeColor.GREEN,
				TileEnums.EdgeColor.GREEN
			),
			"identical edges must look the same in every orientation (turn %d)" % turn
		)


# --- Value validation (GAME_SPEC section 3.1) ---


func test_valid_tile_is_accepted() -> void:
	check(_sample_tile().is_valid(), "a tile built from valid specification values must validate")


func test_tile_validation_rejects_out_of_range_values() -> void:
	var valid_edges: Array[TileEnums.EdgeColor] = _canonical_edges()

	check(
		not TileDefinition.create(&"", TileEnums.TileRank.ACE, TileEnums.FaceColor.RED, valid_edges).is_valid(),
		"a tile without an ID must be rejected"
	)
	check(
		not TileDefinition.create(&"a:tile:000", 99, TileEnums.FaceColor.RED, valid_edges).is_valid(),
		"an undefined face rank must be rejected"
	)
	check(
		not TileDefinition.create(&"a:tile:000", TileEnums.TileRank.ACE, 99, valid_edges).is_valid(),
		"an undefined face colour must be rejected"
	)

	var short_edges: Array[TileEnums.EdgeColor] = [
		TileEnums.EdgeColor.BLUE,
		TileEnums.EdgeColor.RED,
		TileEnums.EdgeColor.GREEN,
	]
	check(
		not TileDefinition.create(&"a:tile:000", TileEnums.TileRank.ACE, TileEnums.FaceColor.RED, short_edges).is_valid(),
		"a tile without exactly four edges must be rejected"
	)

	var bad_edges: Array[TileEnums.EdgeColor] = [
		TileEnums.EdgeColor.BLUE,
		TileEnums.EdgeColor.RED,
		TileEnums.EdgeColor.GREEN,
		4,
	]
	check(
		not TileDefinition.create(&"a:tile:000", TileEnums.TileRank.ACE, TileEnums.FaceColor.RED, bad_edges).is_valid(),
		"an edge value outside blue, red, green, and yellow must be rejected"
	)


# --- Placed snapshot (ADR-004 section 4, ADR-006 section 5) ---


func test_snapshot_defaults_to_zero_rotation() -> void:
	var snapshot: TileSnapshot = TileSnapshot.create(_sample_tile(), Vector2i(5, 5))

	check_eq(snapshot.get_rotation(), 0, "a newly placed tile must begin at zero rotation")
	check_eq(
		_as_ints(snapshot.get_rotated_edges()),
		_as_ints(_sample_tile().get_base_edges()),
		"a zero-rotation snapshot must expose the canonical edges"
	)


func test_snapshot_reports_its_committed_orientation() -> void:
	var snapshot: TileSnapshot = TileSnapshot.create(_sample_tile(), Vector2i(6, 5), 1)

	check_eq(snapshot.get_rotation(), 1, "the snapshot must keep the committed quarter turn")
	check_eq(
		snapshot.get_edge_at(TileEnums.EdgePosition.TOP),
		TileEnums.EdgeColor.YELLOW,
		"the snapshot must score against its committed rotation, not the canonical one"
	)


func test_snapshot_normalizes_and_validates_its_tile() -> void:
	var wrapped: TileSnapshot = TileSnapshot.create(_sample_tile(), Vector2i(5, 6), 5)

	check_eq(wrapped.get_rotation(), 1, "a wrapped quarter turn must normalize into 0-3")
	check(wrapped.is_valid(), "a snapshot of a valid tile must validate")
	check_eq(wrapped.get_tile_id(), &"match-1:tile:000", "a snapshot must report its tile ID")
	check_eq(wrapped.get_cell(), Vector2i(5, 6), "a snapshot must report its board cell")


# --- Helpers ---


func _sample_tile() -> TileDefinition:
	return TileDefinition.create(
		&"match-1:tile:000",
		TileEnums.TileRank.ACE,
		TileEnums.FaceColor.RED,
		_canonical_edges()
	)


func _canonical_edges() -> Array[TileEnums.EdgeColor]:
	return [
		TileEnums.EdgeColor.BLUE,
		TileEnums.EdgeColor.RED,
		TileEnums.EdgeColor.GREEN,
		TileEnums.EdgeColor.YELLOW,
	]


func _four(first: int, second: int, third: int, fourth: int) -> Array[int]:
	var values: Array[int] = [first, second, third, fourth]
	return values


func _as_ints(edges: Array[TileEnums.EdgeColor]) -> Array[int]:
	var values: Array[int] = []
	for edge in edges:
		values.append(int(edge))
	return values
