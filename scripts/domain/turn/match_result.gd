class_name MatchResult
extends RefCounted

## The final result of one match (ADR-003 section 8).
##
## ADR-003 section 8 requires the results screen to show each player's total and
## a breakdown by poker, edge-match, and edge-cluster points, with no endgame
## bonus, remaining-tile penalty, multiplier, or tie-breaker. Every figure here is
## derived from the committed score ledger, so the result can never disagree with
## the events that produced it (ADR-007 section 1).
##
## Section 8 also requires final scores to be recalculated from committed match
## history in debug and test builds and checked against the incremental totals.
## `verify_against()` does exactly that, through the same replay path ADR-007
## section 9 designates as authoritative.

## `TurnEnums.MatchOutcome` value.
var outcome: int = TurnEnums.MatchOutcome.IN_PROGRESS

## `TurnEnums.EndReason` value.
var end_reason: int = TurnEnums.EndReason.NONE

## The human player's committed total.
var human_score: int = 0

## The AI player's committed total.
var ai_score: int = 0

## Per-player breakdown, keyed by player name: `poker`, `edge`, `cluster`, `total`.
var terms: Dictionary = {}

## How many moves were committed before the match ended.
var move_count: int = 0

## How many cells held a committed tile when the match ended.
var board_occupied: int = 0

## Tiles still undrawn when the match ended.
var tiles_remaining: int = 0


## Builds the result for a finished or in-progress match.
##
## Returns null without a session. The outcome and end reason are read from the
## session rather than passed in, so a caller cannot report a result the session
## does not support.
static func build(session: GameSessionState) -> MatchResult:
	if session == null:
		push_error("MatchResult.build: a session is required.")
		return null

	var result: MatchResult = MatchResult.new()
	result.outcome = session.get_outcome()
	result.end_reason = session.get_end_reason()
	result.human_score = session.score_for(TurnEnums.HUMAN_PLAYER_ID)
	result.ai_score = session.score_for(TurnEnums.AI_PLAYER_ID)
	result.move_count = session.move_count()
	result.board_occupied = session.get_board().occupied_count()
	result.tiles_remaining = session.remaining_tile_count()
	result.terms = _build_terms(session.get_ledger())
	return result


## Returns the winning player's identifier, or an empty name for a draw or an
## incomplete match. Phase 1 has no tie-breaker (ADR-003 section 8).
func winner_id() -> StringName:
	if outcome == TurnEnums.MatchOutcome.HUMAN_WIN:
		return TurnEnums.HUMAN_PLAYER_ID
	if outcome == TurnEnums.MatchOutcome.AI_WIN:
		return TurnEnums.AI_PLAYER_ID
	return &""


## Returns true when the match ended with equal totals.
func is_draw() -> bool:
	return outcome == TurnEnums.MatchOutcome.DRAW


## Returns true when the match stopped on an unrecoverable failure, which awards
## no winner (ADR-003 section 7 condition 3).
func is_incomplete() -> bool:
	return outcome == TurnEnums.MatchOutcome.INCOMPLETE


## Returns one player's category breakdown, or an empty dictionary.
func terms_for(player_id: StringName) -> Dictionary:
	return terms.get(String(player_id), {})


## Returns a short human-readable summary, for diagnostics only.
func describe() -> String:
	return "%s (%s) after %d move(s): human %d, ai %d; %d/%d cells filled" % [
		TurnEnums.outcome_name(outcome),
		TurnEnums.end_reason_name(end_reason),
		move_count,
		human_score,
		ai_score,
		board_occupied,
		BoardEnums.CELL_COUNT,
	]


## Returns a JSON-safe dictionary, for the results screen and bug reports.
func to_dictionary() -> Dictionary:
	return {
		"outcome": outcome,
		"outcome_name": TurnEnums.outcome_name(outcome),
		"end_reason": end_reason,
		"end_reason_name": TurnEnums.end_reason_name(end_reason),
		"winner": String(winner_id()),
		"human_score": human_score,
		"ai_score": ai_score,
		"move_count": move_count,
		"board_occupied": board_occupied,
		"tiles_remaining": tiles_remaining,
		"terms": terms.duplicate(true),
	}


## Recalculates the match from its committed history and reports any divergence.
##
## Returns an empty string when the replayed board, score events, totals, scored
## windows, boundaries, and cluster entitlements all agree with live play, or the
## first mismatch as a human-readable description. ADR-003 section 8 requires
## this check in debug and test builds.
static func verify_against(session: GameSessionState) -> String:
	if session == null:
		return "a session is required"
	var replay: ScoringReplay.Report = ScoringReplay.replay(
		session.get_history(),
		session.get_rules(),
		Callable(session, "tile_by_id")
	)
	return ScoringReplay.compare(
		session.get_board(),
		session.get_ledger(),
		session.get_scored_hand_set(),
		replay,
		session.get_rules()
	)


## Returns per-player category totals, rebuilt from the committed events.
static func _build_terms(ledger: ScoreLedger) -> Dictionary:
	var built: Dictionary = {}
	for player_id: StringName in TurnEnums.player_ids():
		built[String(player_id)] = {"poker": 0, "edge": 0, "cluster": 0, "total": 0}
	if ledger == null:
		return built

	for event: ScoreEvent in ledger.get_events():
		var key: String = String(event.player_id)
		if not built.has(key):
			built[key] = {"poker": 0, "edge": 0, "cluster": 0, "total": 0}
		# Dictionaries are reference types, so this entry is the stored one.
		var entry: Dictionary = built[key]
		if event.category == ScoringEnums.ScoreCategory.POKER_HAND:
			entry["poker"] = int(entry["poker"]) + event.points
		elif event.category == ScoringEnums.ScoreCategory.EDGE_MATCH:
			entry["edge"] = int(entry["edge"]) + event.points
		elif event.category == ScoringEnums.ScoreCategory.EDGE_CLUSTER:
			entry["cluster"] = int(entry["cluster"]) + event.points
		entry["total"] = int(entry["total"]) + event.points
	return built
