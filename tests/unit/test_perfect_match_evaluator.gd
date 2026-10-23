extends TestCase


func test_four_suits_and_four_matching_internal_edges_qualify() -> void:
	var board: BoardState = _board([0, 1, 2, 3, 0], true)
	check(PerfectMatchEvaluator.qualifies(board, _cells()), "a five-tile line with four suits and all internal matches qualifies")


func test_missing_suit_or_one_mismatched_edge_refuses() -> void:
	check(not PerfectMatchEvaluator.qualifies(_board([0, 1, 2, 0, 0], true), _cells()), "three suits do not qualify")
	check(not PerfectMatchEvaluator.qualifies(_board([0, 1, 2, 3, 0], false), _cells()), "one mismatched boundary refuses the achievement")


func test_partial_or_noncontiguous_hand_refuses() -> void:
	var board: BoardState = _board([0, 1, 2, 3, 0], true)
	var short_hand: Array[Vector2i] = [Vector2i(2, 4)]
	var gapped: Array[Vector2i] = [Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(7, 4)]
	check(not PerfectMatchEvaluator.qualifies(board, short_hand), "short hands do not qualify")
	check(not PerfectMatchEvaluator.qualifies(board, gapped), "a gap does not qualify")


func _cells() -> Array[Vector2i]:
	return [Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4)]


func _board(suits: Array, matching: bool) -> BoardState:
	var board: BoardState = BoardState.create()
	var cells: Array[Vector2i] = _cells()
	for index: int in range(5):
		var edges: Array[TileEnums.EdgeColor] = []
		edges.append(TileEnums.EdgeColor.BLUE)
		edges.append(TileEnums.EdgeColor.GREEN)
		edges.append(TileEnums.EdgeColor.YELLOW)
		edges.append(TileEnums.EdgeColor.RED if index == 3 and not matching else TileEnums.EdgeColor.GREEN)
		var suit: int = suits[index]
		var color: int = TileEnums.color_for_suit(suit)
		var rank: int = TileEnums.TileRank.QUEEN if index < 3 else TileEnums.TileRank.KING
		var tile: TileDefinition = TileDefinition.create(StringName("test:%d" % index), rank, color, edges, suit)
		board.commit_tile(TileSnapshot.create(tile, cells[index]))
	return board
