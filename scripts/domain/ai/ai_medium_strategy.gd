class_name AiMediumStrategy
extends AiStrategy

## Medium difficulty (ADR-005 section 5).
##
## ADR-005 section 5: evaluate every legal candidate with the ADR-007 preview
## calculators and rank them by a fixed six-field tuple, in this precedence:
##
## 1. total immediate score;
## 2. poker points;
## 3. cluster points;
## 4. edge-match points;
## 5. distinct score event count;
## 6. the deterministic seeded tie-break of section 10.
##
## Every candidate is evaluated: unlike Hard, Medium has no beam and no budget,
## so its result is the exact maximum under that tuple. The numbers come from
## `ScoringCoordinator.breakdown()`, which is the same preview the human sees
## (ADR-007 sections 2 and 3), so Medium can never disagree with committed
## scoring about what a placement is worth.

## Candidates scored between cancellation polls (ADR-005 section 9).
const SCORE_BATCH: int = 8


## Returns the highest-ranked legal candidate, or a structured refusal.
func choose_move(
	snapshot: AiGameSnapshot,
	active_tile: TileDefinition,
	config: AiDifficultyConfig,
	decision_seed: int,
	cancellation: AiCancellationToken
) -> AiDecision:
	var report: Dictionary = {
		"policy": "exhaustive-preview",
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
		if (
			index % SCORE_BATCH == SCORE_BATCH - 1
			and is_cancelled(cancellation)
		):
			return cancelled_decision(snapshot, config, "cancelled while scoring")
	if is_cancelled(cancellation):
		return cancelled_decision(snapshot, config, "cancelled after scoring")
	report["evaluated_candidates"] = candidates.size()

	var rank_of: Callable = func(candidate: AiMoveCandidate) -> Array:
		return [
			candidate.immediate_score,
			candidate.poker_points,
			candidate.cluster_points,
			candidate.edge_points,
			candidate.event_count,
		]
	var best: AiMoveCandidate = best_by_rank(candidates, rank_of)
	if best == null:
		return no_legal_move_decision(snapshot, config, report)

	report["best_rank"] = best.ranking_label()
	report["move_key"] = best.move_key
	report["tie_break_value"] = best.tie_break_value
	report["chosen_breakdown"] = breakdown_of(best)
	report["tied_candidates"] = tied_keys(candidates, rank_of, best)

	return AiDecision.create_move(
		best.cell,
		best.rotation,
		snapshot.board_revision(),
		best.move_key,
		build_diagnostics(config, snapshot, report)
	)
