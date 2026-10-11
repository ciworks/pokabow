class_name AiEasyStrategy
extends AiStrategy

## Easy difficulty (ADR-005 section 4, retargeted by ADR-011 section 12).
##
## ADR-005 section 4: choose a uniformly random legal candidate and rotation,
## with an even distribution over all legal moves, and do not evaluate score at
## all. ADR-011 section 12 changes what a candidate is - a whole line rather than
## a single placement - so the draws are now "which legal line" and "which
## rotation profile", and section 4's two properties are otherwise unchanged:
##
## - the line is drawn uniformly from the deduplicated legal line list
##   (`LegalMoveGenerator`, which confirms every line through `LineValidator`);
## - the rotation profile is drawn uniformly from the profiles the generator
##   offered for that window, so a rotation is picked even though it is the
##   generator that enumerated the possibilities.
##
## Easy therefore never calls a scorer: a scorer call would make Easy's choice
## depend on scoring, and the ADR fixes Easy as the uninformed baseline the other
## difficulties are compared against.
##
## ADR-011 section 6 finishes the policy: when the deck holds no legal line at
## all, the rival swaps rather than stalling or playing an illegal tile.


## Returns a uniformly random legal line, a swap, or a structured refusal.
func choose_move(
	snapshot: AiGameSnapshot,
	deck: Array[TileDefinition],
	config: AiDifficultyConfig,
	decision_seed: int,
	cancellation: AiCancellationToken
) -> AiDecision:
	var report: Dictionary = {
		"policy": "uniform-random-line",
		"decision_seed": decision_seed,
	}
	if snapshot == null or config == null:
		return invalid_decision(snapshot, config, "missing input")

	if is_cancelled(cancellation):
		return cancelled_decision(snapshot, config, "cancelled before generation")

	var candidates: Array[AiMoveCandidate] = prepare_candidates(
		snapshot, deck, decision_seed, report
	)
	# ADR-005 section 4: Easy never evaluates score, so this stays zero.
	report["evaluated_candidates"] = 0
	if candidates.is_empty():
		# ADR-011 section 6: no legal line means the rival swaps.
		return swap_decision(snapshot, config, report)

	if is_cancelled(cancellation):
		return cancelled_decision(snapshot, config, "cancelled before selection")

	var index: int = pick_index(candidates.size(), decision_seed)
	var chosen: AiMoveCandidate = candidates[index]
	report["pick_index"] = index
	report["move_key"] = chosen.move_key
	report["line_length"] = chosen.length()
	report["line_cells"] = chosen.cells_label()
	report["chosen_immediate_score"] = chosen.immediate_score
	report["policy_outcome"] = "line"

	return AiDecision.create_line(
		chosen.snapshots,
		snapshot.board_revision(),
		chosen.move_key,
		build_diagnostics(config, snapshot, report)
	)


## Returns a uniformly random rotation profile index for a line of `length`.
##
## ADR-011 section 12 makes a rotation part of the line rather than a property of
## one placement, and ADR-005 section 4 asks Easy to draw a random rotation, so
## the same seeded stream that picks the line also picks the profile. Uses the
## decision's own stream (ADR-005 section 3), so no value is ever taken from the
## tile bag's generator (ADR-004 section 7).
func pick_profile_index(profile_count: int, decision_seed: int) -> int:
	if profile_count <= 0:
		return -1
	var rng: RandomNumberGenerator = make_rng(decision_seed + 1)
	return rng.randi_range(0, profile_count - 1)


## Returns a uniformly distributed index over `count` candidates.
##
## Uses the decision's own stream (ADR-005 section 3), so the same seed and the
## same candidate list always produce the same pick, and no value is ever taken
## from the tile bag's generator (ADR-004 section 7).
func pick_index(count: int, decision_seed: int) -> int:
	if count <= 0:
		return -1
	var rng: RandomNumberGenerator = make_rng(decision_seed)
	return rng.randi_range(0, count - 1)
