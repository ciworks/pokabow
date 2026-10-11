class_name AiHardStrategy
extends AiStrategy

## Hard difficulty (ADR-005 sections 6, 7, 8, and 10, retargeted by ADR-011
## section 12).
##
## ADR-005 section 6 makes Hard a two-ply search over public information:
##
##  1. rank the legal candidates by the section 5 immediate tuple;
##  2. keep the section 8 candidate beam;
##  3. for each kept candidate, score the immediate line, then estimate the
##     opponent's best reply averaged over the versioned representative sample
##     of `AiRepresentativeSample`, one ply deep;
##  4. combine the terms with the configured utility coefficients.
##
## ADR-011 section 12 changes the ply from one tile to one line on both sides of
## the search: the AI's candidates are lines (`LegalMoveGenerator`), and the
## opponent's replies are lines too, generated on the post-move board from the
## hand the opponent holds (public in Phase 1) plus one representative sample
## tile, which is what stands in for the refill ADR-011 section 8 draws from the
## hidden pot (ADR-004 section 7).
##
## The search is bounded by deterministic work budgets, never by wall-clock time
## (ADR-005 section 8): 24 candidate beam, 16 reply beam per sample hand, and a
## maximum of 6144 deep response evaluations per decision. A reply search is a
## line search, so it is additionally bounded by a short reply length and a small
## reply candidate limit, both of which are documented data rather than literals
## inside the loop. Cancellation is polled between batches (ADR-005 section 9) and
## no partial result is ever returned.
##
## The hidden future tile is represented by the sample, because ADR-004 section 7
## forbids reading the undrawn bag from the AI decision interface; nothing here
## calls `debug_bag_snapshot()`.
##
## Two phrasings in ADR-005 are read the way the ADR's own tests require. The
## expected human reply is the mean over the sample of each sample hand's best
## reply score, exactly as section 6 words it ("expected best immediate score ...
## averaged over the representative sample"); the mean is what makes a threat
## reliably visible instead of only half the time. And the candidate beam is
## ordered by the section 5 tuple, because that is the ranking the ADR defines for
## ordering after a shallow evaluation.

## Candidates scored between cancellation polls (ADR-005 section 9).
const SHALLOW_SCORE_BATCH: int = 8

## Longest reply line the second ply enumerates.
##
## ADR-005 section 8 bounds the search by work, and a line search costs more per
## reply than a single placement did, so the ply is limited to the shortest legal
## line lengths. A two- or three-tile reply is what an opponent actually takes
## when a threat is standing, and section 6 asks only for the best immediate
## reply, not for the best reply of every length.
const REPLY_MAX_LENGTH: int = 3

## Reply candidates generated per sample hand before scoring the reply beam.
##
## `LegalMoveGenerator` stops as soon as it has this many legal lines, so the ply
## never enumerates a whole board to answer "what is the best immediate reply".
const REPLY_CANDIDATE_LIMIT: int = 8


## Returns the best legal line under the ADR-005 section 6 utility, or a swap.
func choose_move(
	snapshot: AiGameSnapshot,
	deck: Array[TileDefinition],
	config: AiDifficultyConfig,
	decision_seed: int,
	cancellation: AiCancellationToken
) -> AiDecision:
	var report: Dictionary = {
		"policy": "two-ply-line-representative-sample",
		"decision_seed": decision_seed,
	}
	if snapshot == null or config == null:
		return invalid_decision(snapshot, config, "missing input")

	if is_cancelled(cancellation):
		return cancelled_decision(snapshot, config, "cancelled before generation")

	var candidates: Array[AiMoveCandidate] = prepare_candidates(
		snapshot, deck, decision_seed, report
	)
	if candidates.is_empty():
		# ADR-011 section 6: no legal line means the rival swaps its hand.
		return swap_decision(snapshot, config, report)

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
	report["reply_sample_size"] = config.hard_reply_sample_size

	var utility_of: Callable = func(candidate: AiMoveCandidate) -> Array:
		return [candidate.utility]
	var best: AiMoveCandidate = best_by_rank(ordered, utility_of)
	if best == null:
		return swap_decision(snapshot, config, report)

	report["policy_outcome"] = "line"
	report["utility"] = best.utility
	report["expected_reply_points"] = best.expected_reply_points
	report["ai_open_opportunity"] = best.ai_open_opportunity
	report["human_open_threat"] = best.human_open_threat
	report["matched_edge_count"] = best.matched_edge_count
	report["line_length"] = best.length()
	report["line_cells"] = best.cells_label()
	report["occupies_high_value_cell"] = AiFeatures.occupies_high_value_completion_cell(
		snapshot, best, rules
	)
	report["chosen_breakdown"] = breakdown_of(best)
	report["move_key"] = best.move_key
	report["tie_break_value"] = best.tie_break_value
	report["tied_candidates"] = tied_keys(ordered, utility_of, best)

	return AiDecision.create_line(
		best.snapshots,
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
	if snapshot == null or candidate == null or candidate.snapshots.is_empty():
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
## The second ply is the opponent's best LINE on the board this candidate would
## leave behind, averaged over the representative sample hands: the opponent's own
## held deck plus one sample tile, which stands in for the refill of ADR-011
## section 8 that the AI may not read (ADR-004 section 7). The sample hands are
## capped by `config.hard_reply_sample_size`, so the ply stays inside the section
## 8 budget, and never more than `remaining_budget` replies are spent.
func deep_evaluate(
	snapshot: AiGameSnapshot,
	candidate: AiMoveCandidate,
	config: AiDifficultyConfig,
	remaining_budget: int,
	rules: ScoringRules
) -> int:
	if candidate == null or candidate.snapshots.is_empty() or remaining_budget <= 0:
		return 0
	var sample: AiRepresentativeSample = config.sample
	if sample == null:
		return 0

	var board: BoardState = snapshot.get_board()
	var ai_after: BoardState = board.with_tiles(candidate.snapshots)
	var held: Array[TileDefinition] = snapshot.human_deck()
	var sample_tiles: Array[TileDefinition] = sample.tiles()
	var hands: Array = reply_hands(held, sample_tiles, config.hard_reply_sample_size)
	if hands.is_empty():
		return 0

	var evaluated: int = 0
	var reply_total: float = 0.0
	for raw_hand: Variant in hands:
		if evaluated >= remaining_budget:
			break
		var hand: Array[TileDefinition] = raw_hand
		reply_total += float(
			_best_reply_points(ai_after, hand, snapshot, rules, config.hard_reply_beam)
		)
		evaluated += 1
	if evaluated > 0:
		candidate.expected_reply_points = reply_total / float(evaluated)

	candidate.ai_open_opportunity = AiFeatures.open_opportunity(snapshot, candidate, rules, null)
	candidate.human_open_threat = AiFeatures.human_open_threat(snapshot, candidate, rules)
	candidate.matched_edge_count = AiFeatures.matched_edge_count(snapshot, candidate)
	candidate.utility = int(floor(utility_value(config, candidate)))
	candidate.deep_evaluated = true
	return evaluated


## Returns the sample hands the second ply evaluates, in a fixed order.
##
## The first hand is the opponent's own deck, so a reply the opponent can already
## make is never missed. Each further hand is the held deck plus one sample tile,
## which is the refill of ADR-011 section 8 the AI cannot see; the cap is what
## keeps the ply inside the ADR-005 section 8 budget.
func reply_hands(
	held: Array[TileDefinition],
	sample_tiles: Array[TileDefinition],
	hand_cap: int
) -> Array:
	var hands: Array = []
	if not held.is_empty():
		hands.append(held.duplicate())
	if sample_tiles.is_empty():
		return hands
	var cap: int = hand_cap
	if cap < 1:
		cap = 1
	for sampled: TileDefinition in sample_tiles:
		if hands.size() >= cap:
			break
		if sampled == null or not sampled.is_valid():
			continue
		var hand: Array[TileDefinition] = held.duplicate()
		if not hand.any(
			func(tile: TileDefinition) -> bool:
				return tile != null and tile.tile_id == sampled.tile_id
		):
			hand.append(sampled)
		if not hand.is_empty():
			hands.append(hand)
	return hands


## Returns the strongest immediate score the opponent could take with one line.
##
## ADR-011 section 12 makes the reply a line, so the reply is a one-ply line
## preview on the board the candidate would leave behind. The reply candidates
## come from `LegalMoveGenerator`, which validates every line through the shared
## `LineValidator`, so the threat the AI prices is a threat the rules would really
## allow. Candidates arrive in the generator's deterministic order, the section 8
## reply beam bounds how many are scored, and the strongest of those is reported.
##
## Returns 0 when the opponent has no legal reply at all, which is a total answer
## rather than a missing one.
func _best_reply_points(
	ai_after: BoardState,
	hand: Array[TileDefinition],
	snapshot: AiGameSnapshot,
	rules: ScoringRules,
	reply_beam: int
) -> int:
	if ai_after == null or hand == null or hand.is_empty():
		return 0
	var report: Dictionary = {}
	var replies: Array[AiMoveCandidate] = LegalMoveGenerator.generate_with_report(
		ai_after,
		hand,
		report,
		REPLY_CANDIDATE_LIMIT,
		REPLY_MAX_LENGTH
	)
	if replies.is_empty():
		return 0
	var limit: int = mini(reply_beam, replies.size())
	var best: int = 0
	for index: int in range(limit):
		var candidate: AiMoveCandidate = replies[index]
		best = maxi(
			best,
			line_points_for(
				ai_after,
				candidate.snapshots,
				snapshot.human_player_id(),
				rules,
				null
			)
		)
	return best


## Returns true when `a` precedes `b` in strongest-first order.
func _comes_first(a: AiMoveCandidate, b: AiMoveCandidate) -> bool:
	if a == null or b == null:
		return a != null
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
