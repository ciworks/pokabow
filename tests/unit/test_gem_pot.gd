extends TestCase

func test_provisional_values_follow_closed_hand_categories() -> void:
	var categories: Array[String] = [
		"PAIR", "TWO_PAIR", "STRAIGHT_3", "THREE_OF_A_KIND",
		"STRAIGHT_4", "FULL_HOUSE", "FOUR_OF_A_KIND",
	]
	for index: int in categories.size():
		var event: ScoreEvent = _event("hand-%d" % index, categories[index])
		check_eq(GemPotRules.contribution(event), (index + 1) * 2, categories[index])
	check_eq(GemPotRules.contribution(_event("unknown", "ROYAL_FLUSH")), 0, "unknown hands never pay")


func test_only_distinct_committed_hand_events_grow_pot() -> void:
	var pair: ScoreEvent = _event("pair-1", "PAIR")
	var second_pair: ScoreEvent = _event("pair-2", "PAIR")
	var full_house: ScoreEvent = _event("full-house", "FULL_HOUSE")
	var edge: ScoreEvent = ScoreEvent.create(&"edge-1", &"move-1", &"human", ScoringEnums.ScoreCategory.EDGE_MATCH, 1, [] as Array[Vector2i])
	var events: Array[ScoreEvent] = [pair, pair, second_pair, full_house, edge]
	check_eq(GemPotRules.total(events), 16, "distinct events add once, including repeated category")
	check_eq(GemPotRules.contribution(edge), 0, "edge points do not grow pot")
	check_eq(GemPotRules.total([] as Array[ScoreEvent]), 0, "empty match has empty pot")


func test_projected_result_payout_follows_online_match_outcome() -> void:
	var result := MatchResult.new()
	result.outcome = TurnEnums.MatchOutcome.HUMAN_WIN
	result.end_reason = TurnEnums.EndReason.BOARD_FULL
	var payout: Dictionary = GemPotRules.projected_payout(result, 86)
	check_eq(payout.human_total, 96, "winner receives pot and completion")
	check_eq(payout.rival_total, 10, "loser receives completion")
	result.outcome = TurnEnums.MatchOutcome.AI_WIN
	payout = GemPotRules.projected_payout(result, 86)
	check_eq(payout.human_total, 10, "human loser receives completion")
	check_eq(payout.rival_total, 96, "rival winner receives pot and completion")
	result.outcome = TurnEnums.MatchOutcome.DRAW
	payout = GemPotRules.projected_payout(result, 86)
	check_eq(payout.human_total, 53, "draw splits pot plus completion")
	check_eq(payout.rival_total, 53, "draw split is equal")
	result.outcome = TurnEnums.MatchOutcome.AI_WIN
	result.end_reason = TurnEnums.EndReason.RESIGNATION
	payout = GemPotRules.projected_payout(result, 86)
	check_eq(payout.human_total, 0, "resigning player receives no completion")
	check_eq(payout.rival_total, 86, "opponent receives pot only")
	result.outcome = TurnEnums.MatchOutcome.INCOMPLETE
	check(GemPotRules.projected_payout(result, 86).is_empty(), "incomplete match has no payout")


func _event(identity: String, category: String) -> ScoreEvent:
	return ScoreEvent.create(
		StringName(identity), &"move-1", &"human",
		ScoringEnums.ScoreCategory.POKER_HAND, 1,
		[] as Array[Vector2i], {"category": category}
	)
