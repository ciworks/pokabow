class_name AiHardStrategy
extends AiStrategy

## Hard difficulty (ADR-005 sections 6, 7, 8, and 10).
##
## ADR-005 section 6 makes Hard a two-ply search over public information:
##
##  1. rank the legal candidates by the section 5 immediate tuple;
##  2. keep the section 8 candidate beam;
##  3. for each kept candidate, score the immediate placement, then estimate the
##     opponent's best reply averaged over the versioned 16-tile representative
##     sample of `AiRepresentativeSample`, one ply deep;
##  4. combine the terms with the configured utility coefficients.
##
## The search is bounded by deterministic work budgets, never by wall-clock time
## (ADR-005 section 8): 24 candidate beam, 16 reply beam per sample tile, and a
## maximum of 6144 deep response evaluations per decision. Cancellation is polled
## between batches (ADR-005 section 9) and no partial result is ever returned.
##
## The hidden future tile is represented by the sample, because ADR-004 section 7
## forbids reading the undrawn bag from the AI decision interface; nothing here
## calls `debug_bag_snapshot()`.
##
## Two phrasings in ADR-005 are read in the way the ADR's own tests require.
## The expected human reply is the mean over the sample of each sample tile's
## best opponent score, exactly as section 6 words it ("expected best immediate
## score ... averaged over the representative sample"); the mean is what makes a
## threat reliably visible instead of only half the time. And the candidate beam
## is ordered by the section 5 tuple, because that is the ranking the ADR defines
## for ordering after a shallow evaluation.

## Candidates scored between cancellation polls (ADR-005 section 9).
const SHALLOW_SCORE_BATCH: int = 8

## Sample tiles replied to between cancellation polls (ADR-005 section 9).
const DEEP_EVALUATION_BATCH: int = 16


## Returns the best legal candidate under the ADR-005 section 6 utility.
func choose_move(
	snapshot: AiGameSnapshot,
	active_tile: TileDefinition,
	config: AiDifficultyConfig,
	decision_seed: int,
	cancellation: AiCancellationToken
) -> AiDecision:
	var report: Dictionary = {
		"policy": "two-ply-representative-sample",
		"decision_seed": decision_seed,
	}
	if snapshot == null or active_tile == null or config == null:
		return invalid_decision(snapshot, config, "missing input")

	if is_cancelled(cancellation):
		return cancelled_decision(snapshot, config, "cancelled before generation")

	var candidates: Array[AiMoveCandidate] = prepare_candidates(
		snapshot, active_tile, decision_seed, report
	)
	if candidates.is_empty():
		return no_legal_move_decision(snapshot, config, report)

	var rules: ScoringRules = snapshot.get_rules()
	for index: int in range(candidates.size()):
		score_candidate(snapshot, candidates[index], rules)
		if index % SHALLOW_SCORE_BATCH == SHALLOW_SCORE_BATCH - 1 and is_cancelled(cancellation):
			return cancelled_decision(snapshot, config, "cancelled while scoring")
	if is_cancelled(cancellation):
		return cancelled_decision(snapshot, config, "cancelled after scoring")
	report["evaluated_candidates"] = candidates.size()

	var ordered: Array[AiMoveCandidate] = shallow_order(candidates)
	var beam: Array[AiMoveCandidate] = []
	var beam_size: int = mini(config.hard_candidate_beam, ordered.size())
	for index: int in range(beam_size):
		beam.append(ordered[index])
	report["candidate_beam"] = beam.size()

	var budget: int = config.deep_evaluation_budget
	var used: int = 0
	var deep_candidates: int = 0
	for candidate: AiMoveCandidate in beam:
		if budget - used <= 0:
			break
		if is_cancelled(cancellation):
			return cancelled_decision(snapshot, config, "cancelled during deep evaluation")
		used += deep_evaluate(snapshot, candidate, config, budget - used, rules)
		deep_candidates += 1
	if is_cancelled(cancellation):
		return cancelled_decision(snapshot, config, "cancelled after deep evaluation")

	# ADR-005 section 8: candidates outside the deep beam are still evaluated, but
	# only at one ply, and they still compete for the move. They carry no
	# estimated reply, because that is exactly what the deep beam pays for.
	for index: int in range(beam_size, ordered.size()):
		evaluate_at_one_ply(snapshot, ordered[index], config, rules)

	report["deep_evaluations"] = used
	report["deep_candidates"] = deep_candidates
	report["one_ply_candidates"] = maxi(0, ordered.size() - deep_candidates)
	report["evaluation_budget"] = budget
	report["budget_exhausted"] = used >= budget
	report["sample_version"] = config.sample_version()

	var utility_of: Callable = func(candidate: AiMoveCandidate) -> Array:
		return [candidate.utility]
	var best: AiMoveCandidate = best_by_rank(ordered, utility_of)
	if best == null:
		return no_legal_move_decision(snapshot, config, report)

	report["utility"] = best.utility
	report["expected_reply_points"] = best.expected_reply_points
	report["ai_open_opportunity"] = best.ai_open_opportunity
	report["human_open_threat"] = best.human_open_threat
	report["matched_edge_count"] = best.matched_edge_count
	report["occupies_high_value_cell"] = AiFeatures.occupies_high_value_completion_cell(
		snapshot, best, rules
	)
	report["chosen_breakdown"] = breakdown_of(best)
	report["move_key"] = best.move_key
	report["tie_break_value"] = best.tie_break_value
	report["tied_candidates"] = tied_keys(ordered, utility_of, best)

	return AiDecision.create_move(
		best.cell,
		best.rotation,
		snapshot.board_revision(),
		best.move_key,
		build_diagnostics(config, snapshot, report)
	)


## Evaluates one candidate at one ply only (ADR-005 section 8).
##
## The public-state features of section 7 are available at one ply, so they are
## computed here; the expected human reply is left at zero because estimating it
## is the deep pass, and pretending otherwise would fabricate evidence.
func evaluate_at_one_ply(
	snapshot: AiGameSnapshot,
	candidate: AiMoveCandidate,
	config: AiDifficultyConfig,
	rules: ScoringRules
) -> void:
	if snapshot == null or candidate == null or candidate.snapshot == null:
		return
	candidate.expected_reply_points = 0.0
	candidate.ai_open_opportunity = AiFeatures.open_opportunity(snapshot, candidate, rules, null)
	candidate.human_open_threat = AiFeatures.human_open_threat(snapshot, candidate, rules)
	candidate.matched_edge_count = AiFeatures.matched_edge_count(snapshot, candidate)
	candidate.utility = int(floor(utility_value(config, candidate)))


## Returns the candidates ordered strongest-first by the ADR-005 section 5 tuple.
##
## The comparison falls back to the section 10 tie-break and then the canonical
## move key, so the beam is reproducible and never depends on sort stability.
func shallow_order(candidates: Array[AiMoveCandidate]) -> Array[AiMoveCandidate]:
	var ordered: Array[AiMoveCandidate] = candidates.duplicate()
	ordered.sort_custom(_comes_first)
	return ordered


## Returns the section 6 utility as a signed number.
##
## Kept as a float because the expected reply is an average; the candidate stores
## the integer-rounded value so one utility ordering is exact and reproducible.
func utility_value(config: AiDifficultyConfig, candidate: AiMoveCandidate) -> float:
	return (
		float(config.ai_immediate_coefficient * candidate.immediate_score)
		- float(config.expected_human_reply_coefficient) * candidate.expected_reply_points
		+ float(config.ai_open_opportunity_coefficient * candidate.ai_open_opportunity)
		- float(config.human_open_threat_coefficient * candidate.human_open_threat)
		+ float(config.matched_edge_count_coefficient * candidate.matched_edge_count)
	)


## Scores one candidate's two-ply utility and returns the evaluations spent.
##
## Never spends more than `remaining_budget` evaluations, so the ADR-005 section 8
## budget holds even when the sample is larger than the remaining allowance.
func deep_evaluate(
	snapshot: AiGameSnapshot,
	candidate: AiMoveCandidate,
	config: AiDifficultyConfig,
	remaining_budget: int,
	rules: ScoringRules
) -> int:
	if candidate == null or candidate.snapshot == null or remaining_budget <= 0:
		return 0
	var sample: AiRepresentativeSample = config.sample
	if sample == null:
		return 0

	var board: BoardState = snapshot.get_board()
	var ai_after: BoardState = board.with_tile(candidate.snapshot)
	var tiles: Array[TileDefinition] = sample.tiles()
	var evaluated: int = 0
	var reply_total: float = 0.0
	for tile: TileDefinition in tiles:
		if evaluated >= remaining_budget:
			break
		reply_total += float(_best_reply_points(ai_after, tile, snapshot, rules, config.hard_reply_beam))
		evaluated += 1
	if evaluated > 0:
		candidate.expected_reply_points = reply_total / float(evaluated)

	candidate.ai_open_opportunity = AiFeatures.open_opportunity(snapshot, candidate, rules, null)
	candidate.human_open_threat = AiFeatures.human_open_threat(snapshot, candidate, rules)
	candidate.matched_edge_count = AiFeatures.matched_edge_count(snapshot, candidate)
	candidate.utility = int(floor(utility_value(config, candidate)))
	candidate.deep_evaluated = true
	return evaluated


## Returns the strongest immediate score the opponent could take with one tile.
##
## The reply is a one-ply preview of the human's turn on the board the candidate
## would leave behind. Candidates arrive in the deterministic generation order of
## ADR-005 section 2, the section 8 reply beam bounds how many of them are
## scored, and the strongest of those is reported. The beam is what keeps the
## work bounded: scoring every reply on a developed board would defeat the
## deterministic budget of section 8.
##
## Returns 0 when the opponent has no legal reply at all, which is a total answer
## rather than a missing one.
func _best_reply_points(
	ai_after: BoardState,
	reply_tile: TileDefinition,
	snapshot: AiGameSnapshot,
	rules: ScoringRules,
	reply_beam: int
) -> int:
	var replies: Array[AiMoveCandidate] = LegalMoveGenerator.generate(
		ai_after, reply_tile, snapshot.human_player_id()
	)
	if replies.is_empty():
		return 0
	var limit: int = mini(reply_beam, replies.size())
	var best: int = 0
	for index: int in range(limit):
		var candidate: AiMoveCandidate = replies[index]
		candidate.apply_breakdown(
			ScoringCoordinator.breakdown(ai_after, candidate.snapshot, rules, null)
		)
		best = maxi(best, candidate.immediate_score)
	return best


## Returns true when `a` precedes `b` in strongest-first order.
func _comes_first(a: AiMoveCandidate, b: AiMoveCandidate) -> bool:
	if a.immediate_score != b.immediate_score:
		return a.immediate_score > b.immediate_score
	if a.poker_points != b.poker_points:
		return a.poker_points > b.poker_points
	if a.cluster_points != b.cluster_points:
		return a.cluster_points > b.cluster_points
	if a.edge_points != b.edge_points:
		return a.edge_points > b.edge_points
	if a.event_count != b.event_count:
		return a.event_count > b.event_count
	if a.tie_break_value != b.tie_break_value:
		return a.tie_break_value > b.tie_break_value
	return a.move_key < b.move_key
