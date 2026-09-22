class_name AiEasyStrategy
extends AiStrategy

## Easy difficulty (ADR-005 section 4).
##
## ADR-005 section 4: choose a uniformly random legal candidate and rotation,
## with an even distribution over all legal moves, and do not evaluate score at
## all. Easy therefore never calls a scorer: it generates the deduplicated legal
## candidate list (ADR-005 section 2) and draws one index from its own
## deterministic stream (ADR-005 section 3).
##
## "Never evaluates score" is deliberate rather than incidental: a scorer call
## would make Easy's choice depend on scoring, and the ADR fixes Easy as the
## uninformed baseline the other difficulties are compared against.


## Returns a uniformly random legal candidate, or a structured refusal.
func choose_move(
	snapshot: AiGameSnapshot,
	active_tile: TileDefinition,
	config: AiDifficultyConfig,
	decision_seed: int,
	cancellation: AiCancellationToken
) -> AiDecision:
	var report: Dictionary = {
		"policy": "uniform-random",
		"decision_seed": decision_seed,
	}
	if snapshot == null or active_tile == null or config == null:
		return invalid_decision(snapshot, config, "missing input")

	if is_cancelled(cancellation):
		return cancelled_decision(snapshot, config, "cancelled before generation")

	var candidates: Array[AiMoveCandidate] = prepare_candidates(
		snapshot, active_tile, decision_seed, report
	)
	# ADR-005 section 4: Easy never evaluates score, so this stays zero.
	report["evaluated_candidates"] = 0
	if candidates.is_empty():
		return no_legal_move_decision(snapshot, config, report)

	if is_cancelled(cancellation):
		return cancelled_decision(snapshot, config, "cancelled before selection")

	var index: int = pick_index(candidates.size(), decision_seed)
	var chosen: AiMoveCandidate = candidates[index]
	report["pick_index"] = index
	report["move_key"] = chosen.move_key
	report["chosen_immediate_score"] = chosen.immediate_score

	return AiDecision.create_move(
		chosen.cell,
		chosen.rotation,
		snapshot.board_revision(),
		chosen.move_key,
		build_diagnostics(config, snapshot, report)
	)


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
