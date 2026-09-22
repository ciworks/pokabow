class_name AiCoordinator
extends RefCounted

## AI-side entry point for one match (ADR-005 sections 1, 3, 9, 10, 11, and 12).
##
## ADR-005 section 1 places the coordinator at the seam between the application
## layer and the strategies, and section 232 of its data-ownership list says it
## "requests or cancels decisions and owns no game rules". This type is exactly
## that:
##
## - it selects the concrete strategy for the configured difficulty;
## - it derives the decision seed from the match seed, turn, player, and
##   difficulty (ADR-005 section 3), never from the tile bag's stream;
## - it builds the detached `AiGameSnapshot` the strategies work on;
## - it revalidates a proposal against the current board revision and retries at
##   most once (ADR-005 section 11);
## - it tracks the analysing state so presentation can show a thinking state
##   rather than infer one (ADR-005 section 9).
##
## It owns no rules: legality is `PlacementValidator`, scoring is the ADR-007
## coordinator, and committing happens only through `MoveCommitter`. The
## coordinator never mutates the match.

## There is no analysis in flight; the next request starts a new one.
const STATUS_READY: int = 0

## An analysis is in flight, which is what a thinking state reflects.
const STATUS_THINKING: int = 1

## The last analysis was cancelled and nothing may be committed (ADR-005
## section 9).
const STATUS_CANCELLED: int = 2

## No proposal survived revalidation; the caller must stop (ADR-005 section 11).
const STATUS_INVALID: int = 3

## A proposal is available for the caller to validate and commit.
const STATUS_DECIDED: int = 4

## Maximum decision attempts per request, as ADR-005 section 11 requires: one
## attempt plus at most one retry after a stale or illegal result.
const MAX_ATTEMPTS: int = 2


var _config: AiDifficultyConfig = null
var _strategy: AiStrategy = null
var _status: int = STATUS_READY
var _token: AiCancellationToken = null
var _requested_revision: int = -1
var _attempts: int = 0
var _last_decision: AiDecision = null


## Builds a coordinator for one difficulty (ADR-005 section 5 default: Medium).
static func create(difficulty: int) -> AiCoordinator:
	var coordinator: AiCoordinator = AiCoordinator.new()
	coordinator.set_difficulty(difficulty)
	return coordinator


## Selects the difficulty and rebuilds the configuration and strategy.
##
## Cancels any analysis in flight, because a difficulty change must never be
## resolved by finishing a decision started under the previous policy.
func set_difficulty(difficulty: int) -> void:
	var selected: int = difficulty
	if not AiEnums.is_valid_difficulty(selected):
		selected = AiEnums.DEFAULT_DIFFICULTY
	cancel()
	_config = AiDifficultyConfig.create_default(selected)
	_strategy = _build_strategy(selected)
	_status = STATUS_READY


## Returns the configured difficulty.
func difficulty() -> int:
	if _config == null:
		return AiEnums.DEFAULT_DIFFICULTY
	return _config.difficulty


## Returns the configuration in force.
func config() -> AiDifficultyConfig:
	return _config


## Returns the strategy in force, or null before configuration.
func strategy() -> AiStrategy:
	return _strategy


## Returns the presentation delay for a thinking state, in seconds.
##
## Presentation timing only: ADR-005 section 8 forbids wall-clock cutoffs in move
## selection, and nothing in the search reads this value.
func presentation_delay_seconds() -> float:
	if _config == null:
		return 0.0
	return _config.presentation_delay_seconds()


## Returns the analysis status (one of the `STATUS_*` constants).
func status() -> int:
	return _status


## Returns true while an analysis is in flight, for a thinking state.
func is_thinking() -> bool:
	return _status == STATUS_THINKING


## Returns the status's name, for diagnostics only.
func status_name() -> String:
	return status_name_for(_status)


## Returns the status's name, for diagnostics only.
static func status_name_for(status: int) -> String:
	match status:
		STATUS_READY:
			return "READY"
		STATUS_THINKING:
			return "THINKING"
		STATUS_CANCELLED:
			return "CANCELLED"
		STATUS_INVALID:
			return "INVALID"
		STATUS_DECIDED:
			return "DECIDED"
	return "UNKNOWN"


## Returns the last decision this coordinator produced, or null.
func last_decision() -> AiDecision:
	return _last_decision


## Returns how many decision attempts the last request consumed.
##
## One for a clean decision, two when ADR-005 section 11's single retry ran.
func last_attempts() -> int:
	return _attempts


## Cancels the analysis in flight (ADR-005 section 9).
##
## A cancelled decision carries no coordinate, so nothing can be committed from
## it. Calling this with nothing in flight changes nothing.
func cancel() -> void:
	if _token != null:
		_token.cancel()
	if _status == STATUS_THINKING:
		_status = STATUS_CANCELLED


## Returns a decision for one active tile, or null when the inputs are unusable.
##
## The returned decision is a proposal only: the caller validates it against the
## live board and commits it through `MoveCommitter` (ADR-005 section 11).
func choose_move(
	session: GameSessionState,
	active_tile: TileDefinition,
	cancellation: AiCancellationToken
) -> AiDecision:
	if session == null or active_tile == null or _strategy == null or _config == null:
		push_error("AiCoordinator.choose_move: a session, a tile, and a configuration are required.")
		return null
	return _attempt_move(session, active_tile, cancellation, 1)


## Revalidates a decision against the current board (ADR-005 section 11).
##
## A stale, illegal, or cancelled proposal is refused rather than committed, and
## the refusal names why so the caller can retry once or fall back to the turn
## rules of ADR-003.
func revalidate(session: GameSessionState, decision: AiDecision) -> AiDecision:
	if session == null or decision == null:
		return null
	var board: BoardState = session.get_board()
	var revision: int = 0 if board == null else board.get_revision()
	if decision.is_cancelled():
		return AiDecision.create_cancelled(revision, {"reason": "cancelled"})
	if not decision.has_move():
		return decision
	if decision.board_revision != revision:
		return AiDecision.create_invalid(revision, {"reason": "stale board revision"})
	var tile: TileDefinition = session.active_tile_for(session.get_turn_state().active_player_id)
	if tile == null:
		return AiDecision.create_invalid(revision, {"reason": "no active tile"})
	var request: PlacementRequest = PlacementRequest.create(
		session.get_turn_state().active_player_id, tile.tile_id, decision.cell, decision.rotation
	)
	var result: PlacementResult = PlacementValidator.validate(board, request, tile, true)
	if result == null or not result.accepted:
		return AiDecision.create_invalid(
			revision,
			{
				"reason": "the proposal is no longer legal",
				"rejection": PlacementEnums.rejection_name(
					0 if result == null else result.rejection
				),
			}
		)
	return decision


## Returns the decision seed for one turn (ADR-005 section 3).
##
## Deterministic in the match seed, the turn number, the AI player identity, and
## the difficulty, so a replay of the same match yields the same decision stream
## without touching the tile bag's generator (ADR-004 section 7).
static func derive_seed(
	match_seed: int,
	turn_number: int,
	ai_player_id: StringName,
	difficulty: int
) -> int:
	var hashing: HashingContext = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(
		(
			"%d|%d|%s|%s"
			% [
				match_seed,
				turn_number,
				String(ai_player_id),
				AiEnums.difficulty_slug(difficulty),
			]
		).to_utf8_buffer()
	)
	var digest: PackedByteArray = hashing.finish()
	var value: int = 0
	for index: int in range(8):
		value = (value << 8) | int(digest[index])
	return value & 0x7FFFFFFFFFFFFFFF


## Returns the decision seed for the session's current turn.
func decision_seed(session: GameSessionState) -> int:
	if session == null or _config == null:
		return 0
	return derive_seed(
		session.get_seed(),
		session.get_turn_state().turn_number,
		TurnEnums.AI_PLAYER_ID,
		_config.difficulty
	)


## Runs one attempt, retrying at most once through ADR-005 section 11.
##
## A stale or illegal result is re-decided against the current revision exactly
## once. A second failure is reported as `INVALID`, never as a substituted move,
## so the caller can apply ADR-003's turn rules instead of committing something
## the rules never allowed.
func _attempt_move(
	session: GameSessionState,
	active_tile: TileDefinition,
	cancellation: AiCancellationToken,
	attempt: int
) -> AiDecision:
	_attempts = attempt
	var board: BoardState = session.get_board()
	_requested_revision = 0 if board == null else board.get_revision()

	_token = AiCancellationToken.new()
	if cancellation != null:
		_token = cancellation

	var snapshot: AiGameSnapshot = AiGameSnapshot.create(session, TurnEnums.AI_PLAYER_ID)
	if snapshot == null:
		_status = STATUS_INVALID
		return AiDecision.create_invalid(
			_requested_revision, {"reason": "the match could not be snapshotted"}
		)

	_status = STATUS_THINKING
	var started_at: int = Time.get_ticks_msec()
	var decision: AiDecision = _strategy.choose_move(
		snapshot, active_tile, _config, decision_seed(session), _token
	)
	var elapsed: int = Time.get_ticks_msec() - started_at
	_last_decision = decision
	if decision == null:
		_status = STATUS_INVALID
		return AiDecision.create_invalid(
			_requested_revision, {"reason": "the strategy produced no decision"}
		)
	# ADR-005 section 12 records elapsed analysis time. It sits beside the
	# diagnostics rather than inside them, so the diagnostics stay a pure function
	# of the snapshot, tile, configuration, and decision seed (section 3).
	decision.elapsed_ms = elapsed

	if decision.is_cancelled():
		_status = STATUS_CANCELLED
		return decision

	if decision.is_no_legal_move():
		# ADR-005 section 2: no legal candidate exists. ADR-003 owns what the
		# turn does next, so the coordinator reports the fact and stops.
		_status = STATUS_DECIDED
		return decision

	var stale: bool = decision.has_move() and decision.board_revision != _requested_revision
	var verified: AiDecision = revalidate(session, decision)
	if verified != null and verified.has_move():
		verified.diagnostics["final_validation"] = "accepted"
		verified.diagnostics["attempts"] = attempt
		_status = STATUS_DECIDED
		return verified

	# ADR-005 section 11: retry once against the current board revision.
	if attempt < MAX_ATTEMPTS:
		return _attempt_move(session, active_tile, cancellation, attempt + 1)

	_status = STATUS_INVALID
	var diagnostics: Dictionary = {
		"reason": "stale board revision" if stale else "the proposal is no longer legal",
		"attempts": attempt,
		"final_validation": "rejected",
	}
	if verified != null:
		for key: Variant in verified.diagnostics.keys():
			diagnostics[key] = verified.diagnostics[key]
		diagnostics["status"] = AiEnums.status_name(verified.status)
	if decision.diagnostics.has("move_key"):
		diagnostics["move_key"] = decision.diagnostics["move_key"]
	_last_decision = AiDecision.create_invalid(_requested_revision, diagnostics)
	_last_decision.elapsed_ms = elapsed
	return _last_decision


## Returns the strategy implementation for a difficulty (ADR-005 sections 4-6).
func _build_strategy(difficulty: int) -> AiStrategy:
	match difficulty:
		AiEnums.Difficulty.EASY:
			return AiEasyStrategy.new()
		AiEnums.Difficulty.HARD:
			return AiHardStrategy.new()
	return AiMediumStrategy.new()
