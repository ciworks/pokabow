extends TestCase


func test_difficulty_caps_bound_the_whole_match_not_each_hand() -> void:
	check_eq(AiGemPotRules.cap_for(AiEnums.Difficulty.EASY), 20, "Easy ceiling")
	check_eq(AiGemPotRules.cap_for(AiEnums.Difficulty.MEDIUM), 40, "Medium ceiling")
	check_eq(AiGemPotRules.cap_for(AiEnums.Difficulty.HARD), 80, "Hard ceiling")
	var events: Array[ScoreEvent] = []
	for index: int in range(8):
		events.append(_event("full-%d" % index, "FULL_HOUSE", &"human" if index % 2 == 0 else &"ai"))
	check_eq(AiGemPotRules.total(events, AiEnums.Difficulty.EASY), 20, "Either player's hands fill Easy pot")
	check_eq(AiGemPotRules.total(events, AiEnums.Difficulty.MEDIUM), 40, "Medium pot has a larger ceiling")
	check_eq(AiGemPotRules.total(events, AiEnums.Difficulty.HARD), 80, "Hard pot has the largest ceiling")
	check_eq(AiGemPotRules.contribution(events[0], 16, AiEnums.Difficulty.EASY), 4,
		"the final hand contributes only remaining capacity")
	check_eq(AiGemPotRules.contribution(events[0], 20, AiEnums.Difficulty.EASY), 0,
		"a full pot cannot grow")
	events.append(events[0])
	check_eq(AiGemPotRules.total(events, AiEnums.Difficulty.HARD), 80, "replayed event cannot contribute twice")


func test_ai_never_receives_a_pot_and_resignation_pays_nothing() -> void:
	var result := MatchResult.new()
	result.end_reason = TurnEnums.EndReason.BOARD_FULL
	result.outcome = TurnEnums.MatchOutcome.HUMAN_WIN
	var payout: Dictionary = AiGemPotRules.projected_payout(result, 60, AiEnums.Difficulty.MEDIUM)
	check_eq(payout.human_total, 40, "win receives capped pot without completion grant")
	check_eq(payout.rival_total, 0, "AI receives no Gems")
	result.outcome = TurnEnums.MatchOutcome.DRAW
	check_eq(AiGemPotRules.projected_payout(result, 40, AiEnums.Difficulty.MEDIUM).human_total, 20,
		"draw pays half the even pot")
	result.outcome = TurnEnums.MatchOutcome.AI_WIN
	check_eq(AiGemPotRules.projected_payout(result, 40, AiEnums.Difficulty.MEDIUM).human_total, 0,
		"loss forfeits the unclaimed pot")
	result.outcome = TurnEnums.MatchOutcome.HUMAN_WIN
	result.end_reason = TurnEnums.EndReason.RESIGNATION
	check_eq(AiGemPotRules.projected_payout(result, 40, AiEnums.Difficulty.MEDIUM).human_total, 0,
		"resignation cannot earn a pot")
	result.outcome = TurnEnums.MatchOutcome.INCOMPLETE
	check(AiGemPotRules.projected_payout(result, 40, AiEnums.Difficulty.MEDIUM).is_empty(),
		"incomplete match has no payout")


func test_reward_tier_cannot_be_raised_mid_match_or_on_resume() -> void:
	var controller := GameSessionController.new()
	controller.save_path = "user://ai_gem_pot_test_match.json"
	check(controller.start_new_match(&"ai-gem-tier", 4231, AiEnums.Difficulty.HARD), "Hard match starts")
	check_eq(controller.ai_gem_difficulty(), AiEnums.Difficulty.HARD, "new match locks initial tier")
	controller.set_ai_difficulty(AiEnums.Difficulty.EASY)
	controller.set_ai_difficulty(AiEnums.Difficulty.HARD)
	check_eq(controller.ai_difficulty(), AiEnums.Difficulty.HARD, "rival may return to Hard")
	check_eq(controller.ai_gem_difficulty(), AiEnums.Difficulty.EASY,
		"raising difficulty cannot raise reward ceiling after an Easy turn")
	check(controller.save_match(), "reward tier is saved with the match")
	var restored := GameSessionController.new()
	restored.save_path = controller.save_path
	check(restored.resume_match(), "match with reward tier resumes")
	check_eq(restored.ai_difficulty(), AiEnums.Difficulty.HARD, "active rival difficulty survives resume")
	check_eq(restored.ai_gem_difficulty(), AiEnums.Difficulty.EASY, "lower reward tier survives resume")
	restored.clear_saved_match()
	controller.free()
	restored.free()


func _event(identity: String, category: String, player: StringName) -> ScoreEvent:
	return ScoreEvent.create(StringName(identity), &"move-1", player,
		ScoringEnums.ScoreCategory.POKER_HAND, 1, [] as Array[Vector2i], {"category": category})
