extends TestCase

const BLUE: int = TileEnums.EdgeColor.BLUE
const RED: int = TileEnums.EdgeColor.RED
const GREEN: int = TileEnums.EdgeColor.GREEN
const YELLOW: int = TileEnums.EdgeColor.YELLOW


func test_card_values_and_match_priority() -> void:
	var cells: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5)]
	var edges: Array[TileEnums.EdgeColor] = [BLUE, BLUE, BLUE, BLUE]
	var a: TileDefinition = TileDefinition.create(&"a", TileEnums.TileRank.KING, TileEnums.FaceColor.RED, edges, TileEnums.Suit.HEARTS)
	var b: TileDefinition = TileDefinition.create(&"b", TileEnums.TileRank.KING, TileEnums.FaceColor.RED, edges, TileEnums.Suit.HEARTS)
	var board: BoardState = BoardState.create().with_tiles([
		TileSnapshot.create(a, cells[0]), TileSnapshot.create(b, cells[1])
	])
	check_eq(HandMultiplierScorer.card_points(board, cells), 6, "two Kings have six card points")
	check_eq(HandMultiplierScorer.card_multiplier(board, cells), 4, "identical cards use only x4")
	b.suit = TileEnums.Suit.DIAMONDS
	check_eq(HandMultiplierScorer.card_multiplier(board, cells), 2, "red suits share only color")


func test_new_hand_edges_use_only_matching_colors() -> void:
	var cells: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)]
	var left_edges: Array[TileEnums.EdgeColor] = [BLUE, BLUE, BLUE, BLUE]
	var middle_edges: Array[TileEnums.EdgeColor] = [BLUE, BLUE, BLUE, RED]
	var right_edges: Array[TileEnums.EdgeColor] = [BLUE, BLUE, BLUE, BLUE]
	var board: BoardState = BoardState.create().with_tiles([
		TileSnapshot.create(TileDefinition.create(&"a", TileEnums.TileRank.JACK, TileEnums.FaceColor.RED, left_edges), cells[0]),
		TileSnapshot.create(TileDefinition.create(&"b", TileEnums.TileRank.QUEEN, TileEnums.FaceColor.RED, middle_edges), cells[1]),
		TileSnapshot.create(TileDefinition.create(&"c", TileEnums.TileRank.KING, TileEnums.FaceColor.RED, right_edges), cells[2]),
	])
	var ids: Array[StringName] = HandMultiplierScorer.new_boundary_ids(board, cells, [cells[2]])
	check_eq(ids.size(), 1, "only the matching boundary created by the staged tile counts")
	check_eq(HandMultiplierScorer.edge_multiplier_from_ids(board, cells, ids), 2, "a matching color adds one to the hand factor")
	check_eq(HandMultiplierScorer.boundary_bonus(board, cells[0], cells[1]), 0, "different colors do not match")
	check_eq(EdgeMatchScorer.matching_color(board, cells[1], cells[2]), BLUE, "matching blue edges earn the ordinary edge point")


func test_joker_is_suitless_and_outside_straights() -> void:
	var edges: Array[TileEnums.EdgeColor] = [BLUE, BLUE, BLUE, BLUE]
	var joker: TileDefinition = TileDefinition.create(&"j", TileEnums.TileRank.JOKER, TileEnums.FaceColor.NONE, edges, TileEnums.Suit.NONE)
	var queen: TileDefinition = TileDefinition.create(&"q", TileEnums.TileRank.QUEEN, TileEnums.FaceColor.RED, edges, TileEnums.Suit.HEARTS)
	var cells: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5)]
	var board: BoardState = BoardState.create().with_tiles([
		TileSnapshot.create(joker, cells[0]), TileSnapshot.create(queen, cells[1])
	])
	check(joker.is_valid(), "suitless Joker is a valid tile")
	check_eq(HandMultiplierScorer.card_points(board, cells), 7, "Joker contributes five points")
	check_eq(HandMultiplierScorer.card_multiplier(board, cells), 1, "Joker suppresses card multipliers")
	check_eq(TileEnums.sequence_position(TileEnums.TileRank.JOKER), -1, "Joker is outside the straight ladder")
	check_eq(PokerHandEvaluator.classify_ranks([TileEnums.TileRank.JOKER, TileEnums.TileRank.JOKER]), ScoringEnums.PokerHandCategory.PAIR, "repeated Jokers form a Pair")
	check_eq(PokerHandEvaluator.classify_ranks([TileEnums.TileRank.JACK, TileEnums.TileRank.QUEEN, TileEnums.TileRank.JOKER]), ScoringEnums.PokerHandCategory.NONE, "Joker cannot extend a straight")


func test_preview_commit_and_audit_share_the_formula() -> void:
	var board: BoardState = BoardState.create()
	var ledger: ScoreLedger = ScoreLedger.create()
	var scored: ScoredHandSet = ScoredHandSet.create()
	var rules: ScoringRules = ScoringRules.create_default()
	var edges: Array[TileEnums.EdgeColor] = [BLUE, BLUE, BLUE, BLUE]
	var line: Array[TileSnapshot] = [
		TileSnapshot.create(TileDefinition.create(&"a", TileEnums.TileRank.KING, TileEnums.FaceColor.RED, edges, TileEnums.Suit.HEARTS), Vector2i(5, 5)),
		TileSnapshot.create(TileDefinition.create(&"b", TileEnums.TileRank.KING, TileEnums.FaceColor.RED, edges, TileEnums.Suit.HEARTS), Vector2i(6, 5)),
	]
	var preview: ScoreTransaction = ScoringCoordinator.preview_line(board, line, &"human", rules, scored)
	check_eq(preview.points_for_category(ScoringEnums.ScoreCategory.POKER_HAND), 64, "(Pair 2 + two Kings 6) x exact 4 x edge 2")
	check_eq(preview.points_for_category(ScoringEnums.ScoreCategory.EDGE_MATCH), 1, "ordinary edge bonus remains separate")
	var committed: ScoreTransaction = ScoringCoordinator.commit_line(board, line, ledger, scored, &"human", &"move:fixture:1:1", 1, rules)
	check_eq(committed.total_points(), preview.total_points(), "commit matches preview")
	var audit: ScoringAudit.Report = ScoringAudit.audit(board, ledger, scored, rules)
	check(audit.ok, "full board audit accepts multiplied hand score")


func test_suit_and_four_edge_colors_survive_tile_save() -> void:
	var edges: Array[TileEnums.EdgeColor] = [YELLOW, RED, BLUE, GREEN]
	var original: TileDefinition = TileDefinition.create(
		&"saved", TileEnums.TileRank.ACE, TileEnums.FaceColor.RED, edges, TileEnums.Suit.DIAMONDS
	)
	var record: TileDto = TileDto.from_dictionary(original.to_dto().to_dictionary())
	var restored: TileDefinition = TileDefinition.from_dto(record)
	check(record.is_valid(), "versioned tile record accepts suit and the four edge colors")
	check_not_null(restored, "tile restores from its record")
	check_eq(restored.suit, TileEnums.Suit.DIAMONDS, "the suit survives JSON serialization")
	check_eq(restored.base_edges[0], YELLOW, "edge color survives JSON serialization")
