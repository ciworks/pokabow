class_name AiCoordinator
extends RefCounted

## AI-side entry point for one match (ADR-005 sections 1, 3, 9, 10, 11, and 12;
## ADR-011 section 12).
##
## ADR-005 section 1 places the coordinator at the seam between the application
## layer and the strategies, and its data-ownership list says it "requests or
## cancels decisions and owns no game rules". This type is exactly that:
##
## - it selects the concrete strategy for the configured difficulty;
## - it derives the decision seed from the match seed, turn, player, and
##   difficulty (ADR-005 section 3), never from the tile bag's stream;
## - it builds the detached `AiGameSnapshot` the strategies work on, including the
##   two held decks ADR-011 section 12's line generation needs;
## - it revalidates a proposal LINE against the current board revision and the
##   shared `LineValidator`, and retries at most once (ADR-005 section 11);
## - it tracks the analysing state so presentation can show a thinking state
##   rather than infer one (ADR-005 section 9).
##
## It owns no rules: legality is `LineValidator` (the same validator the human
## commit path uses, so the two cannot drift), scoring is the ADR-007 coordinator,
## and committing happens only through `MoveCommitter`. The coordinator never
## mutates the match.

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
## (ADR-010 section 2).
var _deck: Array[TileDefinition] = []

## The line the last accepted proposal was decided from, in line order.
##
## ADR-011 section 12 makes a move a whole line, so revalidation has to resolve
## EVERY tile of the proposal, not one tile.
var _decided_line: Array[TileSnapshot] = []

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


## Returns the line the last accepted proposal was decided with, in line order.
##
## ADR-011 sections 1 and 5 make a move a whole line taken from the player's own
## deck, so the application layer arms every tile of this line before it commits;
## without it, a proposal decided from one hand could be committed from another.
func decided_line() -> Array[TileSnapshot]:
	return _decided_line.duplicate()


## Returns how many decision attempts the last request consumed.
##
## One for a clean decision, two when ADR-005 section 11's single retry ran.
func last_attempts() -> int:
	return _attempts


## Cancels the analysis in flight (ADR-005 section 9).
##
## A cancelled decision carries no line, so nothing can be committed from it.
## Calling this with nothing in flight changes nothing.
func cancel() -> void:
	if _token != null:
		_token.cancel()
	if _status == STATUS_THINKING:
		_status = STATUS_CANCELLED


## Returns a decision drawn from the rival's own deck, or null on unusable input.
##
## The returned decision is a proposal only: the caller validates it against the
## live board and commits it through `MoveCommitter.commit_line` (ADR-005
## section 11). ADR-011 section 12 makes the proposal a whole line - the rival's
## tiles, their target cells, and their rotations - or a swap when no line is
## legal (section 6).
##
## The deck is supplied by the caller rather than read here, so the coordinator
## can never be handed the undrawn pot (ADR-004 section 7).
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
	# resolves a proposal's tiles from the same deck the proposal was made from.
	_deck = deck.duplicate()
	_decided_line = []
	_tiles_offered = 0
	var started_at: int = Time.get_ticks_msec()
	var decision: AiDecision = _attempt_move(session, deck, cancellation, 1)
	# ADR-005 section 12 records the elapsed analysis time beside the decision
	# rather than inside its diagnostics, so the diagnostics stay a pure function
	# of the snapshot, the deck, the configuration, and the decision seed
	# (section 3). The reading covers the whole request, retries included.
	if decision != null:
		decision.elapsed_ms = Time.get_ticks_msec() - started_at
	return decision


## Revalidates a decision against the current board (ADR-005 section 11).
##
## ADR-011 section 12 makes the proposal a whole line, so every tile of it is
## resolved from the proposal itself and the deck it was drawn from, and the
## whole line is re-validated through the shared `LineValidator`: a proposal can
## only survive if the human path's validator would accept exactly that line on
## the board as it stands now.
func revalidate(session: GameSessionState, decision: AiDecision) -> AiDecision:
	if session == null or decision == null:
		return null
	return _revalidate_with(session, decision, _line_for_decision(session, decision))


## Revalidates one decision that was decided from `line` (ADR-005 section 11).
func _revalidate_with(
	session: GameSessionState, decision: AiDecision, line: Array[TileSnapshot]
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
	if decision.is_swap_move():
		# ADR-011 section 6: a swap is a whole-turn move, and whether the pot can
		# supply it is the session's decision, not this one's. It has no line to
		# re-validate, so it passes through with the revision it was decided at.
		return decision
	if line.is_empty():
		return AiDecision.create_invalid(
			revision, {"reason": "the proposal has no tiles"}
		)
	var result: LineResult = LineValidator.validate(board, line)
	if result == null or not result.accepted:
		return AiDecision.create_invalid(
			revision,
			{
				"reason": "the proposed line is no longer legal",
				"rejection": PlacementEnums.rejection_name(
					0 if result == null else result.rejection
				),
			}
		)
	# ADR-011 sections 1 and 5: a move is exactly the line the validator judged and
	# nothing else, so an accepted proposal is re-seated as the VALIDATED line -
	# the tiles in the line order `LineValidator` returned, which is the order the
	# commit path writes and refills by. Keeping the proposal's own order, or any
	# subset of it, would let the caller commit a line one tile short of the one
	# the rules accepted, which is the partial line section 5 forbids.
	return _decision_from_line(result, revision, decision.diagnostics)


## Returns one accepted validated line as a decision (ADR-011 sections 1 and 5).
##
## The canonical move key is rebuilt from the validated line rather than carried
## over from the proposal, so a line the validator reordered is identified by what
## will actually be committed and the ADR-005 section 10 tie-break stays a pure
## function of the move.
func _decision_from_line(
	result: LineResult, revision: int, diagnostics: Dictionary
) -> AiDecision:
	var cells: Array[Vector2i] = []
	var rotations: Array[int] = []
	var tile_ids: Array[StringName] = []
	for snapshot: TileSnapshot in result.staged_tiles:
		if snapshot == null or not snapshot.is_valid():
			continue
		cells.append(snapshot.get_cell())
		rotations.append(snapshot.get_rotation())
		tile_ids.append(snapshot.get_tile_id())
	return AiDecision.create_line(
		result.staged_tiles,
		revision,
		AiMoveCandidate.move_key_for(cells, rotations, tile_ids),
		diagnostics
	)


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
## ADR-011 section 12 makes the candidate a whole line, so the strategy is asked
## once for the whole deck rather than once per tile: a line spans several deck
## tiles, and asking per tile would fragment the move the rules define.
##
## A swap decision is a complete answer (ADR-011 section 6), so it is returned
## without revalidation: it places nothing and the session decides whether the pot
## can supply it. A stale or illegal proposal is re-decided against the current
## revision exactly once; a second failure is reported as `INVALID`, never as a
## substituted move, so the caller can apply the turn rules instead of committing
## something the rules never allowed.
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
	if snapshot == null or not snapshot.is_valid():
		_status = STATUS_INVALID
		return AiDecision.create_invalid(
			_requested_revision, {"reason": "the match could not be snapshotted"}
		)

	_tiles_offered = _usable_tiles(deck).size()
	_status = STATUS_THINKING
	var decision: AiDecision = _strategy.choose_move(
		snapshot, deck, _config, decision_seed(session), _token
	)
	_last_decision = decision
	if decision == null:
		_status = STATUS_INVALID
		return AiDecision.create_invalid(
			_requested_revision, {"reason": "the strategy produced no decision"}
		)
	if decision.is_cancelled():
		_status = STATUS_CANCELLED
		return decision
	if decision.is_swap_move():
		# ADR-011 section 6: the rival holds tiles it cannot line up, so its whole
		# turn is the swap. Nothing is committed, so nothing needs revalidating.
		_status = STATUS_DECIDED
		_decided_line = [] as Array[TileSnapshot]
		return decision

	# ADR-005 section 11: a stale or illegal proposal is re-decided against the
	# board as it stands now. Rebuilding the snapshot on the retry is what makes
	# the second attempt fresh rather than a replay of the first.
	var refused: Dictionary = (
		{} if decision.diagnostics == null else decision.diagnostics
	)
	var verified: AiDecision = _revalidate_with(
		session, decision, _line_for_decision(session, decision)
	)
	if verified != null and verified.has_line():
		verified.diagnostics["final_validation"] = "accepted"
		verified.diagnostics["attempts"] = attempt
		verified.diagnostics["tiles_offered"] = _tiles_offered
		_status = STATUS_DECIDED
		_decided_line = _tiles_of(verified)
		_last_decision = verified
		return verified
	if verified != null and verified.diagnostics != null:
		refused = verified.diagnostics

	if cancellation != null and cancellation.is_cancelled():
		_status = STATUS_CANCELLED
		return AiDecision.create_cancelled(_requested_revision, {"reason": "cancelled"})

	if attempt < MAX_ATTEMPTS:
		return _attempt_move(session, deck, cancellation, attempt + 1)

	_status = STATUS_INVALID
	var diagnostics: Dictionary = _invalid_diagnostics(attempt, refused)
	_last_decision = AiDecision.create_invalid(_requested_revision, diagnostics)
	return _last_decision


## Returns the proposal's line, resolved from the decision and the deck the
## request was made from (ADR-005 section 11, ADR-011 section 12).
##
## The tile identities are recorded in the decision diagnostics when the
## coordinator accepted it, so revalidation of an already-decided proposal is
## exact. A decision built by a caller (a test or a replay fixture) may carry only
## tile identities from another source, so the deck order supplies any tile the
## session does not hold: the proposal was drawn from that deck.
func _line_for_decision(
	session: GameSessionState, decision: AiDecision
) -> Array[TileSnapshot]:
	var line: Array[TileSnapshot] = []
	if session == null or decision == null or not decision.has_move():
		return line
	if decision.is_swap_move():
		return line
	for index: int in range(decision.tile_ids.size()):
		var tile_id: StringName = decision.tile_ids[index]
		var cell: Vector2i = Vector2i.ZERO
		if index < decision.line_cells.size():
			cell = decision.line_cells[index]
		var rotation: int = 0
		if index < decision.line_rotations.size():
			rotation = decision.line_rotations[index]
		var tile: TileDefinition = session.deck_tile(TurnEnums.AI_PLAYER_ID, tile_id)
		if tile == null:
			tile = _deck_tile(tile_id)
		if tile == null or not tile.is_valid():
			return [] as Array[TileSnapshot]
		line.append(TileSnapshot.create(tile, cell, rotation))
	return line


## Returns the snapshots of an accepted decision, in line order.
func _tiles_of(decision: AiDecision) -> Array[TileSnapshot]:
	var line: Array[TileSnapshot] = []
	if decision == null:
		return line
	for snapshot: TileSnapshot in decision.line:
		if snapshot != null and snapshot.is_valid():
			line.append(snapshot)
	return line


## Returns the deck tile with `tile_id` from the remembered deck, or null.
func _deck_tile(tile_id: StringName) -> TileDefinition:
	for tile: TileDefinition in _usable_tiles(_deck):
		if tile.tile_id == tile_id:
			return tile
	return null


## Returns `deck` without unusable entries, preserving deal order.
func _usable_tiles(deck: Array[TileDefinition]) -> Array[TileDefinition]:
	var tiles: Array[TileDefinition] = []
	if deck == null:
		return tiles
	for tile: TileDefinition in deck:
		if tile != null and tile.is_valid():
			tiles.append(tile)
	return tiles


## Returns the diagnostics for an `INVALID` refusal (ADR-005 section 11).
##
## The reason is the strategy's own refusal when it reported one, and the
## revalidation refusal otherwise.
func _invalid_diagnostics(attempt: int, rejected: Variant) -> Dictionary:
	var diagnostics: Dictionary = {
		"reason": "no legal line survived revalidation",
		"attempts": attempt,
		"final_validation": "rejected",
		"tiles_offered": _tiles_offered,
		"deck_size": _deck.size(),
	}
	var last_decision: AiDecision = _last_decision
	if last_decision != null and last_decision.diagnostics.has("reason"):
		diagnostics["last_reason"] = last_decision.diagnostics["reason"]
	if rejected is Dictionary:
		var refused: Dictionary = rejected
		if refused.has("reason"):
			diagnostics["revalidation_reason"] = refused["reason"]
		if refused.has("rejection"):
			diagnostics["rejection"] = refused["rejection"]
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
