class_name AiStrategy
extends RefCounted

## The shared AI decision contract (ADR-005 sections 1, 3, 7, 10, and 11).
##
## ADR-005 section 1 fixes the seam every difficulty implements:
##
##     choose_move(snapshot, active_tile, config, decision_seed, cancellation)
##         -> AiDecision
##
## This base class owns everything the three difficulties share, so no rule is
## written twice (AGENTS.md section 15):
##
## - generating and preparing the legal candidate list
##   (`LegalMoveGenerator`, ADR-005 section 2);
## - attaching the deterministic tie-break value derived from the decision seed
##   and the candidate's canonical move key (ADR-005 section 10);
## - ranking candidates by a multi-field tuple, so Medium's six-field order and
##   Hard's utility share one comparison;
## - building the decision diagnostics every difficulty reports
##   (ADR-005 section 12).
##
## A strategy never touches the scene tree, never reads the undrawn bag, and
## never mutates authoritative state: it works on a detached snapshot and returns
## a proposal that the application layer commits through the ordinary ADR-007
## transaction (ADR-005 sections 1 and 11).


## Returns this strategy's proposal for one active tile.
##
## Returns an `INVALID` decision when the inputs cannot produce a proposal, a
## `NO_LEGAL_MOVE` decision when no legal candidate exists (ADR-005 section 2),
## and a `CANCELLED` decision when the token was cancelled before analysis
## started or before it finished (ADR-005 section 9). Subclasses must return on
## every path; a partial proposal may never be committed.
func choose_move(
	_snapshot: AiGameSnapshot,
	_active_tile: TileDefinition,
	_config: AiDifficultyConfig,
	_decision_seed: int,
	_cancellation: AiCancellationToken
) -> AiDecision:
	push_error("AiStrategy.choose_move: implement this in the difficulty subclass.")
	return AiDecision.create_invalid(0, {"reason": "abstract strategy"})


## Returns a new deterministic RNG for one decision (ADR-005 section 3).
##
## The AI owns its own stream, so analysis can never consume a value from the
## tile bag's generator and change draw order (ADR-004 section 7).
func make_rng(decision_seed: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = decision_seed
	return rng


## Returns the deterministic tie-break value of one candidate (ADR-005 section
## 10).
##
## ADR-005 section 10 forbids resolving ties by iteration order, object address,
## frame time, or platform hashing, so the value is a pure function of the
## decision seed and the candidate's canonical move key.
func tie_break_value_for(decision_seed: int, move_key: String) -> int:
	var hashing: HashingContext = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(("%d|%s" % [decision_seed, move_key]).to_utf8_buffer())
	var digest: PackedByteArray = hashing.finish()
	var value: int = 0
	for index: int in range(4):
		value = (value << 8) | int(digest[index])
	return value


## Returns the legal candidates for one tile, each carrying its tie-break value.
##
## Candidates are ordered by cell row-major then rotation (ADR-005 section 2), so
## every later stage of the search is reproducible from the candidate order alone.
func prepare_candidates(
	snapshot: AiGameSnapshot,
	active_tile: TileDefinition,
	decision_seed: int,
	report: Dictionary
) -> Array[AiMoveCandidate]:
	var candidates: Array[AiMoveCandidate] = []
	if snapshot == null:
		return candidates
	candidates = LegalMoveGenerator.generate_with_report(
		snapshot.get_board(), active_tile, snapshot.ai_player_id(), report
	)
	for candidate: AiMoveCandidate in candidates:
		candidate.tie_break_value = tie_break_value_for(decision_seed, candidate.move_key)
	return candidates


## Attaches the ADR-007 preview numbers to one candidate.
##
## Delegates to `ScoringCoordinator.breakdown()` so the AI reads exactly the
## numbers the human preview reads (ADR-007 sections 2 and 3).
func score_candidate(
	snapshot: AiGameSnapshot,
	candidate: AiMoveCandidate,
	rules: ScoringRules
) -> void:
	if snapshot == null or candidate == null or candidate.snapshot == null:
		return
	candidate.apply_breakdown(
		ScoringCoordinator.breakdown(
			snapshot.get_board(),
			candidate.snapshot,
			rules,
			snapshot.get_scored_hand_set()
		)
	)


## Returns one candidate's score-event breakdown, for diagnostics only.
##
## ADR-005 section 12 records the score-event breakdowns behind a decision, so
## every difficulty that evaluates score reports the same four numbers rather
## than its own summary.
func breakdown_of(candidate: AiMoveCandidate) -> Dictionary:
	if candidate == null:
		return {}
	return {
		"total": candidate.immediate_score,
		"poker": candidate.poker_points,
		"edge": candidate.edge_points,
		"cluster": candidate.cluster_points,
		"events": candidate.event_count,
	}


## Returns the highest-ranked candidate under `rank_of`.
##
## `rank_of` receives a candidate and returns the ordering tuple: the primary
## fields in precedence order, strongest first. A tie on every ranking field is
## resolved by the deterministic tie-break value -- the HIGHEST value wins, as
## ADR-005 section 10 requires -- and then by the canonical move key, so the same
## seed and board always produce the same choice. Nothing here reads iteration
## order, an object address, or the frame clock.
func best_by_rank(candidates: Array[AiMoveCandidate], rank_of: Callable) -> AiMoveCandidate:
	var best: AiMoveCandidate = null
	var best_rank: Array = []
	for candidate: AiMoveCandidate in candidates:
		if candidate == null:
			continue
		var rank: Array = rank_of.call(candidate)
		if best == null or is_stronger(rank, best_rank):
			best = candidate
			best_rank = rank
			continue
		if is_stronger(best_rank, rank):
			continue
		if candidate.tie_break_value != best.tie_break_value:
			if candidate.tie_break_value > best.tie_break_value:
				best = candidate
				best_rank = rank
			continue
		if candidate.move_key < best.move_key:
			best = candidate
			best_rank = rank
	return best


## Returns the canonical move keys that tied with `winner` on every ranking field.
##
## ADR-005 section 12 requires the tied candidates and the tie-break outcome to
## be recorded, which is the only reason this is computed: the comparison itself
## is already decided inside `best_by_rank`.
func tied_keys(
	candidates: Array[AiMoveCandidate],
	rank_of: Callable,
	winner: AiMoveCandidate
) -> Array:
	var keys: Array = []
	if winner == null:
		return keys
	var winner_rank: Array = rank_of.call(winner)
	for candidate: AiMoveCandidate in candidates:
		if candidate == null or candidate.move_key == winner.move_key:
			continue
		if is_stronger(rank_of.call(candidate), winner_rank):
			continue
		if is_stronger(winner_rank, rank_of.call(candidate)):
			continue
		keys.append(candidate.move_key)
	keys.sort()
	return keys


## Returns true when `rank` outranks `other`, comparing fields in order.
func is_stronger(rank: Array, other: Array) -> bool:
	var count: int = mini(rank.size(), other.size())
	for index: int in range(count):
		var value: float = float(rank[index])
		var reference: float = float(other[index])
		if is_equal_approx(value, reference):
			continue
		return value > reference
	return false


## Returns the dialogue-friendly description of one candidate's ranking tuple.
func ranking_of(candidate: AiMoveCandidate) -> String:
	if candidate == null:
		return ""
	return candidate.ranking_label()


## Returns the diagnostics dictionary every difficulty reports.
##
## ADR-005 section 12 requires a recorded difficulty, evaluation version, and
## search shape; extra keys carry the per-decision evidence.
func build_diagnostics(
	config: AiDifficultyConfig,
	snapshot: AiGameSnapshot,
	extra: Dictionary
) -> Dictionary:
	var diagnostics: Dictionary = {
		"difficulty": AiEnums.difficulty_name(config.difficulty),
		"evaluation_version": config.evaluation_version,
		"config_version": config.version_key(),
		"sample_version": config.sample_version(),
		"search": "legal-move-generation",
	}
	if snapshot != null:
		diagnostics["turn_number"] = snapshot.turn_number()
		diagnostics["board_revision"] = snapshot.board_revision()
		diagnostics["match_id"] = String(snapshot.match_id())
	for key: Variant in extra.keys():
		diagnostics[key] = extra[key]
	return diagnostics


## Returns the decision a strategy reports when no legal candidate exists.
##
## ADR-005 section 2 gives this its own status so the caller never receives an
## illegal substitute; ADR-003 decides what the turn does next.
func no_legal_move_decision(
	snapshot: AiGameSnapshot,
	config: AiDifficultyConfig,
	report: Dictionary
) -> AiDecision:
	var revision: int = 0 if snapshot == null else snapshot.board_revision()
	return AiDecision.create_no_legal_move(
		revision, build_diagnostics(config, snapshot, report)
	)


## Returns the decision a strategy reports when it cannot start or finish.
func invalid_decision(
	snapshot: AiGameSnapshot,
	config: AiDifficultyConfig,
	reason: String
) -> AiDecision:
	var revision: int = 0 if snapshot == null else snapshot.board_revision()
	return AiDecision.create_invalid(
		revision, build_diagnostics(config, snapshot, {"reason": reason})
	)


## Returns the decision a strategy reports when its analysis was cancelled.
##
## ADR-005 section 9 forbids committing a partial result, so a cancelled decision
## carries no coordinate.
func cancelled_decision(
	snapshot: AiGameSnapshot,
	config: AiDifficultyConfig,
	reason: String
) -> AiDecision:
	var revision: int = 0 if snapshot == null else snapshot.board_revision()
	return AiDecision.create_cancelled(
		revision, build_diagnostics(config, snapshot, {"reason": reason})
	)


## Returns true when the caller cancelled the analysis (ADR-005 section 9).
func is_cancelled(cancellation: AiCancellationToken) -> bool:
	return cancellation != null and cancellation.is_cancelled()
