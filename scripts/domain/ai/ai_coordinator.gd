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

## The deck the current request is decided from, in deal order
## (ADR-010 section 11).
var _deck: Array[TileDefinition] = []

## The deck tile the last accepted proposal was decided with, or null.
var _decided_tile: TileDefinition = null

## How many deck tiles the current request offered to the strategy.
var _tiles_offered: int = 0


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


## Returns the deck tile the last accepted proposal was decided with, or null.
##
## ADR-010 section 4 makes a placement commit a tile the player holds and the
## commit path derives that tile from the session, so the application layer arms
## this tile before it commits a rival's proposal. Without it, a proposal decided
## for one deck tile could be committed with another.
func decided_tile() -> TileDefinition:
	return _decided_tile


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


## Returns a decision drawn from every tile in the AI's own deck, or null when the
## inputs are unusable (ADR-010 section 11).
##
## The returned decision is a proposal only: the caller validates it against the
## live board and commits it through `MoveCommitter` (ADR-005 section 11).
##
## ADR-010 section 11 amends ADR-005 sections 2, 4, 5, and 6, which all assume a
## single active tile, so the deck - not one tile - is the candidate source. The
## deck is supplied by the caller rather than read here, so the coordinator can
## never be handed the undrawn pot (ADR-004 section 7).
func choose_move(
	session: GameSessionState,
	deck: Array[TileDefinition],
	cancellation: AiCancellationToken
) -> AiDecision:
	if session == null or _strategy == null or _config == null:
		push_error(
			"AiCoordinator.choose_move: a session and a configuration are required."
		)
		return null
	if deck == null or deck.is_empty():
		push_error("AiCoordinator.choose_move: the rival's deck is required to decide from.")
		return null
	# The deck is remembered for the duration of the request, so revalidation
	# resolves a proposal's tile from the same deck the proposal was made from
	# (ADR-010 section 11).
	_deck = deck.duplicate()
	_decided_tile = null
	_tiles_offered = 0
	var started_at: int = Time.get_ticks_msec()
	var decision: AiDecision = _attempt_move(session, deck, cancellation, 1)
	# ADR-005 section 12 records the elapsed analysis time beside the decision
	# rather than inside its diagnostics, so the diagnostics stay a pure function
	# of the snapshot, the tile, the configuration, and the decision seed
	# (section 3). The reading covers the whole request, retries included.
	if decision != null:
		decision.elapsed_ms = Time.get_ticks_msec() - started_at
	return decision


## Revalidates a decision against the current board (ADR-005 section 11).
##
## A stale, illegal, or cancelled proposal is refused rather than committed, and
## the refusal names why so the caller can retry once or fall back to the turn
## rules of ADR-003. A decision carries only data, so its tile is resolved from
## the proposal itself and from the deck the proposal was drawn from
## (ADR-010 section 11).
func revalidate(session: GameSessionState, decision: AiDecision) -> AiDecision:
	if session == null or decision == null:
		return null
	return _revalidate_with(session, decision, _tile_for_decision(session, decision))


## Revalidates one decision that was made with `tile` (ADR-005 section 11).
func _revalidate_with(
	session: GameSessionState, decision: AiDecision, tile: TileDefinition
) -> AiDecision:
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
	if tile == null or not tile.is_valid():
		return AiDecision.create_invalid(revision, {"reason": "no deck tile to place"})
	var request: PlacementRequest = PlacementRequest.create(
		TurnEnums.AI_PLAYER_ID, tile.tile_id, decision.cell, decision.rotation
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


## Runs one attempt over the deck, retrying at most once through ADR-005
## section 11.
##
## ADR-010 section 11 makes every tile in the rival's own deck a candidate
## source, so one attempt walks the deck in deal order and asks the strategy for
## a proposal per tile. The first proposal that also survives revalidation is the
## decision for this attempt, which keeps ADR-005 sections 3, 10, and 12 intact:
## the first tile with a legal candidate is chosen deterministically, and the
## per-tile search is exactly the one the strategy already defines.
##
## A tile with no legal candidate is skipped rather than reported as `NO_LEGAL_MOVE`,
## because the rival may always choose a different tile from its deck; `NO_LEGAL_MOVE`
## is reported only when no deck tile has a legal placement at all
## (ADR-005 section 2).
##
## A stale or illegal result is re-decided against the current revision exactly
## once. A second failure is reported as `INVALID`, never as a substituted move,
## so the caller can apply ADR-003's turn rules instead of committing something
## the rules never allowed.
func _attempt_move(
	session: GameSessionState,
	deck: Array[TileDefinition],
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
	var no_legal_move: AiDecision = null
	for tile: TileDefinition in _usable_tiles(deck):
		_tiles_offered += 1
		var decision: AiDecision = _strategy.choose_move(
			snapshot, tile, _config, decision_seed(session), _token
		)
		_last_decision = decision
		if decision == null:
			continue
		if decision.is_cancelled():
			_status = STATUS_CANCELLED
			return decision
		if decision.is_no_legal_move():
			# ADR-005 section 2: this tile has no legal placement. Another deck
			# tile still might, so the attempt continues (ADR-010 section 11).
			if no_legal_move == null:
				no_legal_move = decision
			continue

		var stale: bool = decision.board_revision != _requested_revision
		var verified: AiDecision = _revalidate_with(session, decision, tile)
		if verified != null and verified.has_move():
			verified.diagnostics["final_validation"] = "accepted"
			verified.diagnostics["attempts"] = attempt
			verified.diagnostics["tiles_offered"] = _tiles_offered
			verified.diagnostics["tile_id"] = String(tile.tile_id)
			_status = STATUS_DECIDED
			_decided_tile = tile
			_last_decision = verified
			return verified
		if verified == null:
			continue
		# The proposal is no longer legal, so this tile produced no usable move.
		# A later tile may still produce one; the attempt only fails once every
		# deck tile has been tried (ADR-005 section 11).
		if no_legal_move == null and not stale:
			no_legal_move = verified

	if no_legal_move != null and no_legal_move.is_no_legal_move():
		# Every deck tile was tried and none had a legal placement: this is the
		# structured refusal of ADR-005 section 2, whose turn outcome ADR-003
		# owns. It carries the analysis shape for diagnostics.
		_status = STATUS_DECIDED
		var refusal: AiDecision = AiDecision.create_no_legal_move(
			_requested_revision, _no_legal_move_diagnostics(session, attempt)
		)
		_last_decision = refusal
		return refusal

	if cancellation != null and cancellation.is_cancelled():
		# ADR-005 section 9: the match moved on mid-request, so no partial result
		# may be produced.
		_status = STATUS_CANCELLED
		return AiDecision.create_cancelled(_requested_revision, {"reason": "cancelled"})

	# ADR-005 section 11: retry once against the current board revision.
	if attempt < MAX_ATTEMPTS:
		return _attempt_move(session, deck, cancellation, attempt + 1)

	_status = STATUS_INVALID
	var diagnostics: Dictionary = _invalid_diagnostics(attempt)
	var last_decision: AiDecision = _last_decision
	if last_decision != null and last_decision.diagnostics.has("move_key"):
		diagnostics["move_key"] = last_decision.diagnostics["move_key"]
	_last_decision = AiDecision.create_invalid(_requested_revision, diagnostics)
	return _last_decision


## Returns the proposal's tile, resolved from the decision itself and the deck the
## request was made from (ADR-005 section 11, ADR-010 section 11).
##
## The tile identifier is recorded in the decision diagnostics when the
## coordinator accepted it, so revalidation of an already-decided proposal is
## exact. A decision built by a caller (a test or a replay fixture) carries no
## tile identifier, so the deck order supplies the tile: the proposal was drawn
## from that deck. The rival's armed tile is deliberately not consulted, so
## revalidation does not depend on presentation state having been set.
func _tile_for_decision(session: GameSessionState, decision: AiDecision) -> TileDefinition:
	if session == null or decision == null or not decision.has_move():
		return null
	if decision.diagnostics.has("tile_id"):
		var named: StringName = StringName(String(decision.diagnostics["tile_id"]))
		var held: TileDefinition = session.deck_tile(TurnEnums.AI_PLAYER_ID, named)
		if held != null:
			return held
	for tile: TileDefinition in _usable_tiles(_deck):
		if tile.tile_id == _tile_id_of_move_key(decision.move_key):
			return tile
	var deck: Array[TileDefinition] = _usable_tiles(_deck)
	if not deck.is_empty():
		return deck[0]
	return session.active_tile_for(TurnEnums.AI_PLAYER_ID)


## Returns the tile identifier embedded in a candidate's canonical move key.
##
## `AiMoveCandidate.move_key_for()` builds `ai-move:<tile-id>:<x>,<y>:<rotation>`,
## so the identifier sits between the prefix and the coordinate. Returns an empty
## name for a key that does not have that shape, so a malformed key cannot be
## mistaken for a tile.
func _tile_id_of_move_key(move_key: String) -> StringName:
	var parts: PackedStringArray = move_key.split(":")
	if parts.size() < 4:
		return &""
	return StringName(parts[1])


## Returns `deck` without unusable entries, preserving deal order.
func _usable_tiles(deck: Array[TileDefinition]) -> Array[TileDefinition]:
	var tiles: Array[TileDefinition] = []
	if deck == null:
		return tiles
	for tile: TileDefinition in deck:
		if tile != null and tile.is_valid():
			tiles.append(tile)
	return tiles


## Returns the diagnostics for the `NO_LEGAL_MOVE` refusal (ADR-005 section 2).
func _no_legal_move_diagnostics(session: GameSessionState, attempt: int) -> Dictionary:
	var diagnostics: Dictionary = {
		"reason": "no deck tile has a legal placement",
		"attempts": attempt,
		"tiles_offered": _tiles_offered,
		"deck_size": _deck.size(),
	}
	if _config != null:
		diagnostics["difficulty"] = AiEnums.difficulty_name(_config.difficulty)
	if session != null:
		diagnostics["board_revision"] = _requested_revision
	return diagnostics


## Returns the diagnostics for an `INVALID` refusal (ADR-005 section 11).
##
## The reason is the strategy's own refusal when it reported one, and the deck
## exhaustion of ADR-010 section 11 otherwise.
func _invalid_diagnostics(attempt: int) -> Dictionary:
	var diagnostics: Dictionary = {
		"reason": "no proposal survived revalidation",
		"attempts": attempt,
		"final_validation": "rejected",
		"tiles_offered": _tiles_offered,
		"deck_size": _deck.size(),
	}
	var last_decision: AiDecision = _last_decision
	if last_decision != null and last_decision.diagnostics.has("reason"):
		diagnostics["reason"] = last_decision.diagnostics["reason"]
	if _config != null:
		diagnostics["difficulty"] = AiEnums.difficulty_name(_config.difficulty)
	return diagnostics


## Returns the strategy implementation for a difficulty (ADR-005 sections 4-6).
func _build_strategy(difficulty: int) -> AiStrategy:
	match difficulty:
		AiEnums.Difficulty.EASY:
			return AiEasyStrategy.new()
		AiEnums.Difficulty.HARD:
			return AiHardStrategy.new()
	return AiMediumStrategy.new()
