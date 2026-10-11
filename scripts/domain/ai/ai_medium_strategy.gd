class_name AiMediumStrategy
extends AiStrategy

## Medium difficulty (ADR-005 section 5, retargeted by ADR-011 section 12).
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
## ADR-011 section 12 changes the candidate from one placement to one whole line,
## and nothing else: the line is previewed as the single atomic move it will be
## (section 5), through `ScoringCoordinator.preview_line()`, which is the same
## preview the human sees (ADR-007 sections 2 and 3). A line that completes a
## poker window therefore has its poker points counted once for the whole move,
## exactly as the commit will count them.
##
## Every candidate is evaluated: unlike Hard, Medium has no beam and no budget,
## so its result is the exact maximum under that tuple. Only the short-circuit
## the rule set needs is applied: when the best line under the tuple scores
## nothing, every line scored nothing, so the choice falls back to the section 10
## tie-break rather than to a different measure.
##
## ADR-011 section 6 finishes the policy: when no legal line exists at all, the
## rival swaps. A legal line that scores nothing is still a legal move and is
## still played, because swapping is the escape from an unplayable hand, not a
## preference about points.

## Candidates scored between cancellation polls (ADR-005 section 9).
const SCORE_BATCH: int = 8


## Returns the highest-ranked legal line, a swap, or a structured refusal.
func choose_move(
	snapshot: AiGameSnapshot,
	deck: Array[TileDefinition],
	config: AiDifficultyConfig,
	decision_seed: int,
	cancellation: AiCancellationToken
) -> AiDecision:
	var report: Dictionary = {
		"policy": "exhaustive-line-preview",
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
		# ADR-011 section 6: the held hand cannot form one legal line, so the
		# whole turn is the swap - never a stall and never a lone tile. The
		# generator's own report says why: how many empty runs and windows the
		# board offered and how many assignments the shared validator refused, so
		# the swap is an explained decision rather than a silent one
		# (ADR-005 sections 7 and 12).
		report["no_legal_line"] = true
		report["windows_offered"] = int(report.get("windows", 0))
		report["lines_rejected_by_validator"] = int(report.get("rejected", 0))
		report["deck_tiles"] = deck.size() if deck != null else 0
		return swap_decision(snapshot, config, report)

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
		return swap_decision(snapshot, config, report)

	report["policy_outcome"] = "line"
	report["best_rank"] = best.ranking_label()
	report["move_key"] = best.move_key
	report["line_length"] = best.length()
	report["line_cells"] = best.cells_label()
	report["merged_size"] = best.merged_size
	report["extends_board_line"] = best.extends_board_line
	report["tie_break_value"] = best.tie_break_value
	report["chosen_breakdown"] = breakdown_of(best)
	report["tied_candidates"] = tied_keys(candidates, rank_of, best)

	return AiDecision.create_line(
		best.snapshots,
		snapshot.board_revision(),
		best.move_key,
		build_diagnostics(config, snapshot, report)
	)
