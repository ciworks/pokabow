class_name GameSessionController
extends Node

## Application layer: one match, driven by commands from presentation
## (ADR-008 sections 5 and 7).
##
## This is the only place rules are invoked. It owns the `GameSessionState` and
## exposes narrow commands (`preview_placement`, `rotate_pending`,
## `confirm_pending`, `cancel_pending`) plus read-only accessors for the HUD.
## Screens submit intents and render the result; they never validate a
## placement, never score, and never reach into the board themselves
## (ADR-008 section 4, AGENTS.md sections 6 and 19).
##
## Every rule call is delegated to the Milestone 2 to 4 domain services:
## `PlacementValidator` for legality, `MoveCommitter` for the atomic write,
## `TurnManager` for lifecycle, and `MatchResult` for the final summary. Nothing
## here re-implements any of them, so the UI cannot drift from the rules that the
## headless tests already cover.
##
## This node is NOT an autoload and holds no global state: it is created by
## `AppRoot` and released with its screen (ADR-008 section 6).

## A new or resumed match is ready to render.
signal session_started()

## Authoritative state changed; the HUD and board should resynchronize.
signal state_changed()

## The pending preview changed (placed, moved, rotated, or refused).
signal preview_changed()

## A move was committed and turn lifecycle resolved.
signal move_committed(result: PlacementResult, turn_phase: int)

## Score events were awarded by a committed move, in deterministic order.
signal score_awarded(events: Array, cell: Vector2i)

## The match reached an end condition.
signal match_ended(result: MatchResult)

## A short player-facing notice, e.g. a save or resume outcome.
signal notice(text: String)

## The opponent started or finished analysing its move (ADR-005 section 9).
##
## Presentation drives the rival-turn message from this state instead of
## inferring it from the turn owner, so the message can never disagree with what
## the AI is actually doing (ADR-008 section 9).
signal ai_thinking_changed(thinking: bool)

## The opponent difficulty used when none is requested (ADR-005 section 5).
const DEFAULT_AI_DIFFICULTY: int = AiEnums.DEFAULT_DIFFICULTY

## Where the single match save lives (ADR-008 section 11).
const SAVE_PATH: String = "user://match_save.json"

## Tile source template, so a resumed match regenerates the identical bag.
const TILE_RULES_RESOURCE: String = "res://resources/rules/tile_generation_rules.tres"

var _session: GameSessionState = null
var _pending_snapshot: TileSnapshot = null
var _pending_valid: bool = false
var _pending_reason: String = ""
var _pending_rotation: int = 0
var _pending_cell: Vector2i = Vector2i(BoardEnums.OPENING_MIN, BoardEnums.OPENING_MIN)
var _ai_scheduled: bool = false

## The opponent's decision service. It owns no rules and mutates nothing: it
## returns a proposal this controller commits through the ordinary move path
## (ADR-005 section 1).
var _ai: AiCoordinator = null

## The analysis currently in flight, cancelled when the match changes
## (ADR-005 section 9).
var _ai_cancellation: AiCancellationToken = null

## The thinking state last reported, so the signal fires on change only.
var _ai_thinking: bool = false


## Creates the opponent's decision service.
##
## Built here rather than in the `create()` factory so that every construction
## path has a working opponent. `AppRoot` composes the game with `new()`
## (ADR-008 section 5) while the tests used `create()`, and a coordinator that
## existed on only one of those paths left the rival unable to move at all while
## the whole suite still passed.
func _init() -> void:
	_ai = AiCoordinator.create(DEFAULT_AI_DIFFICULTY)


## Builds a controller without a match. Call `start_new_match` or `resume_match`.
##
## The opponent service is created in `_init()`, so this factory exists for
## intent and reads identically to `GameSessionController.new()`.
static func create() -> GameSessionController:
	return GameSessionController.new()


## Starts a fresh match and opens the human's first turn (ADR-003 section 2).
##
## `ai_difficulty` selects the opponent policy (ADR-005 sections 4 to 6); it
## defaults to the configured difficulty so existing callers keep working.
func start_new_match(
	match_id: StringName = &"",
	seed_value: int = 0,
	ai_difficulty: int = -1
) -> bool:
	if ai_difficulty >= 0:
		set_ai_difficulty(ai_difficulty)
	var resolved_id: StringName = match_id
	if String(resolved_id).is_empty():
		resolved_id = StringName("match-%d" % Time.get_unix_time_from_system())
	var resolved_seed: int = seed_value
	if resolved_seed == 0:
		resolved_seed = int(Time.get_unix_time_from_system())

	var session: GameSessionState = GameSessionState.create(
		resolved_id, resolved_seed, ScoringRules.create_default(), _load_generation_rules()
	)
	if session == null:
		push_error("GameSessionController: the session could not be constructed.")
		return false

	_session = session
	_cancel_ai_analysis()
	_set_ai_thinking(false)
	_ai_scheduled = false
	_reset_pending()
	TurnManager.setup(_session)
	session_started.emit()
	state_changed.emit()
	_after_state_change()
	return true


## Resumes the saved match, or reports why it could not be resumed.
func resume_match() -> bool:
	if not has_saved_match():
		return false

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("GameSessionController: the save file could not be opened.")
		return false
	var payload: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (payload is Dictionary):
		push_error("GameSessionController: the save file is not valid JSON.")
		return false

	var raw_match: Variant = (payload as Dictionary).get("match", null)
	if not (raw_match is Dictionary):
		push_error("GameSessionController: the save file holds no match record.")
		return false

	var dto: MatchSnapshotDto = MatchSnapshotDto.from_dictionary(raw_match)
	var session: GameSessionState = GameSessionState.from_snapshot(
		dto, ScoringRules.create_default(), _load_generation_rules()
	)
	if session == null:
		push_error(
			"GameSessionController: the saved match could not be restored under the current rules."
		)
		return false

	_session = session
	# ADR-003 section 9: a transient preview is never persisted, so resume with no
	# pending placement and the active tile still uncommitted.
	_cancel_ai_analysis()
	_set_ai_thinking(false)
	_ai_scheduled = false
	_reset_pending()
	session_started.emit()
	state_changed.emit()
	_after_state_change()
	return true


## Returns true when a resumable save exists.
func has_saved_match() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Writes the match to disk (ADR-008 section 11: save at stable boundaries).
##
## A pending preview is deliberately not persisted: the snapshot is built from
## the authoritative session, which never contains uncommitted state.
func save_match() -> bool:
	if _session == null:
		return false
	if _session.is_over():
		return false

	var dto: MatchSnapshotDto = _session.to_snapshot()
	if dto == null or not dto.is_valid():
		push_error("GameSessionController: the match could not be serialized.")
		return false

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("GameSessionController: the save file could not be written.")
		return false
	file.store_string(
		JSON.stringify({
			"saved_at": Time.get_datetime_string_from_system(),
			"match": dto.to_dictionary(),
		})
	)
	file.close()
	return true


## Deletes the save file, used when a match finishes.
func clear_saved_match() -> void:
	if not has_saved_match():
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# --- Commands (presentation to application, ADR-008 section 7) -------------


## Selects one of the human's deck tiles as the tile to place (ADR-010 section 4).
##
## ADR-010 section 12 makes selecting a deck tile what arms a placement, so this
## is the only way a player chooses which of their six tiles to commit. The
## selection is an application-layer choice, not authoritative state: it only
## names a tile the player already holds, which the session verifies.
##
## Returns true when the selection was accepted. An outstanding preview is
## re-checked against the newly selected tile at the same cell, so switching
## tiles never leaves a stale preview behind.
func select_deck_tile(tile_id: StringName) -> bool:
	if not is_human_turn():
		return false
	var tile: TileDefinition = _session.deck_tile(TurnEnums.HUMAN_PLAYER_ID, tile_id)
	if tile == null:
		notice.emit("That tile is not in your deck")
		return false
	if not _session.set_active_tile(TurnEnums.HUMAN_PLAYER_ID, tile):
		return false

	if _pending_snapshot != null:
		_validate_pending(tile, _pending_cell, _pending_rotation)
	else:
		_pending_rotation = 0
	preview_changed.emit()
	return true


## Ends the human's turn, keeping any unplaced tiles in the deck
## (ADR-010 section 4).
##
## End-turn is available throughout the action phase, including before any tile
## has been placed, so a player may pass. The turn boundary itself is the domain's
## (`TurnManager.end_turn`): it refills the deck, checks the end conditions, and
## hands play over.
func end_human_turn() -> void:
	if _session == null or _session.is_over():
		return
	if not TurnManager.is_awaiting_human_action(_session):
		return
	_reset_pending()
	TurnManager.end_turn(_session)
	_after_state_change()


## Previews a placement of the selected deck tile at `cell`.
##
## ADR-010 section 4: a placement is armed by selecting a deck tile, so the tile
## previewed is the player's selected tile, or the deck's first tile when they
## have not chosen one yet.
func preview_placement(cell: Vector2i) -> void:
	if not is_human_turn():
		return
	var tile: TileDefinition = human_tile()
	if tile == null:
		notice.emit("Your deck is empty")
		return
	_pending_rotation = 0 if _pending_snapshot == null else _pending_rotation
	_pending_cell = cell
	_validate_pending(tile, cell, _pending_rotation)
	preview_changed.emit()


## Rotates the pending preview one quarter-turn clockwise.
##
## ADR-006 section 5: rotation is an explicit command, available before or during
## a preview, and never mutates authoritative state.
func rotate_pending() -> void:
	if not is_human_turn():
		return
	var tile: TileDefinition = human_tile()
	if tile == null:
		return
	_pending_rotation = (_pending_rotation + 1) % TileEnums.ROTATION_COUNT
	if _pending_snapshot != null:
		_validate_pending(tile, _pending_cell, _pending_rotation)
	preview_changed.emit()


## Commits the previewed placement (ADR-006 section 5: explicit confirmation).
##
## Returns the commit result. A refusal leaves the turn untouched and keeps the
## preview so the player can adjust and retry (ADR-003 section 5).
func confirm_pending() -> PlacementResult:
	if not is_human_turn():
		return null
	if human_tile() == null:
		notice.emit("Your deck is empty")
		return null
	if _pending_snapshot == null:
		notice.emit("Choose a cell first")
		return null
	if not _pending_valid:
		notice.emit(_pending_reason)
		preview_changed.emit()
		return null

	var result: PlacementResult = _commit(TurnEnums.HUMAN_PLAYER_ID, _pending_cell, _pending_rotation)
	if result == null or not result.was_committed():
		_pending_valid = false
		_pending_reason = _reason_text(result)
		preview_changed.emit()
		return result

	_reset_pending()
	# ADR-010 section 5: the committed tile left the deck and the deck does not
	# refill mid-turn, so a selection of that tile is released with it (the
	# commit removes the tile from the deck, which disarms it). Any remaining
	# tile may then be placed in the same turn (ADR-010 section 3 step 9).
	state_changed.emit()
	return result


## Discards the preview without touching the turn or the active tile.
func cancel_pending() -> void:
	if not is_human_turn():
		return
	_reset_pending()
	preview_changed.emit()
	notice.emit("Placement cancelled")


# --- Read-only accessors for presentation ----------------------------------


## Returns the live session, or null before a match starts.
func get_session() -> GameSessionState:
	return _session


## Returns the board being rendered, or null.
func get_board() -> BoardState:
	if _session == null:
		return null
	return _session.get_board()


## Returns true only while the human owns the action phase.
##
## ADR-003 section 1 freezes gameplay input once the match reaches `GAME_OVER` or
## `RECOVERY_ERROR`, and the turn phase can still read `AWAIT_ACTION` at that
## moment, so the stopped state is checked first. Otherwise a finished match could
## keep accepting moves.
func is_human_turn() -> bool:
	if _session == null or _session.is_over():
		return false
	return TurnManager.is_awaiting_human_action(_session)


## Returns the identity of the player whose turn it is.
func active_player_id() -> StringName:
	if _session == null:
		return &""
	return _session.get_turn_state().active_player_id


## Returns the 1-based turn number.
func turn_number() -> int:
	if _session == null:
		return 0
	return _session.get_turn_state().turn_number


## Returns the human's committed total.
func human_score() -> int:
	if _session == null:
		return 0
	return _session.score_for(TurnEnums.HUMAN_PLAYER_ID)


## Returns the opponent's committed total.
func ai_score() -> int:
	if _session == null:
		return 0
	return _session.score_for(TurnEnums.AI_PLAYER_ID)


## Returns how many tiles remain in the shared bag.
func remaining_tiles() -> int:
	if _session == null:
		return 0
	return _session.remaining_tile_count()


## Returns the pending preview snapshot, or null.
func pending_snapshot() -> TileSnapshot:
	return _pending_snapshot


## Returns whether the pending preview is legal.
func is_pending_valid() -> bool:
	return _pending_valid


## Returns why the pending preview is illegal.
func pending_reason() -> String:
	return _pending_reason


## Returns the rotation shown in the active-tile panel.
func pending_rotation() -> int:
	return _pending_rotation


## Returns the human's uncommitted tile, or null when they hold none.
##
## ADR-010 section 4: a placement commits a tile the player holds, so this is the
## tile a confirm would place: the selected deck tile when one is selected, and
## otherwise the deck's first tile.
func human_tile() -> TileDefinition:
	if _session == null:
		return null
	return _session.active_tile_for(TurnEnums.HUMAN_PLAYER_ID)


## Returns the human's deck in deal order, or an empty array (ADR-010 section 1).
##
## This is what the deck row renders: a copy of the authoritative deck, so the
## view cannot mutate the match by drawing from it. Returning the tiles rather
## than only their count is deliberate: ADR-010 section 12 has the player choose
## among their own six tiles, and the six are the player's own information.
func human_deck() -> Array[TileDefinition]:
	if _session == null:
		return [] as Array[TileDefinition]
	return _session.deck_for(TurnEnums.HUMAN_PLAYER_ID)


## Returns how many tiles the human holds.
func human_deck_count() -> int:
	if _session == null:
		return 0
	return _session.deck_count(TurnEnums.HUMAN_PLAYER_ID)


## Returns the identity of the human's selected deck tile, or an empty name.
##
## The selection lives on the session, so this and `human_tile()` can never
## disagree about which tile the next placement commits.
func selected_deck_tile_id() -> StringName:
	if _session == null:
		return &""
	return _session.armed_tile_id_for(TurnEnums.HUMAN_PLAYER_ID)


## Returns true while the human may end their turn (ADR-010 section 4).
##
## End-turn is available throughout the action phase, including before any tile
## has been placed, so this is the same condition as `is_human_turn()`.
func can_end_turn() -> bool:
	return is_human_turn()


## Returns true while a placement is previewed and awaiting confirmation.
##
## ADR-006 section 5: a preview only becomes a committed move on explicit
## confirm, so the UI needs to know whether one is outstanding.
func has_pending() -> bool:
	return _pending_snapshot != null


## Returns true once the match has ended.
func is_over() -> bool:
	if _session == null:
		return false
	return _session.is_over()


# --- Opponent (application to domain, ADR-005) -----------------------------


## Selects the opponent difficulty (ADR-005 sections 4 to 6).
##
## The change takes effect on the next decision; an analysis in flight is
## cancelled rather than finished under the previous policy. An unknown value is
## normalised to the documented default here rather than left for the search, so
## `ai_difficulty()` always reports the policy that is actually in force.
##
## The opponent is never stranded by the change: a cancelled analysis is not
## resumed by itself, so when the match is still waiting on the rival the move is
## scheduled again under the new policy (ADR-005 section 9, ADR-010 section 4).
func set_ai_difficulty(difficulty: int) -> void:
	var selected: int = difficulty
	if not AiEnums.is_valid_difficulty(selected):
		selected = DEFAULT_AI_DIFFICULTY
	if _ai == null:
		_ai = AiCoordinator.create(selected)
	else:
		_cancel_ai_analysis()
		_set_ai_thinking(false)
		_ai.set_difficulty(selected)
	if _session == null or _session.is_over():
		return
	if TurnManager.is_awaiting_ai_action(_session):
		_schedule_ai_move()


## Returns the opponent difficulty in force (`AiEnums.Difficulty` value).
func ai_difficulty() -> int:
	if _ai == null:
		return DEFAULT_AI_DIFFICULTY
	return _ai.difficulty()


## Returns true while the opponent is analysing its move.
##
## This is the state the rival-turn message is driven from, not the turn owner
## (ADR-005 section 9).
func is_ai_thinking() -> bool:
	return _ai_thinking


## Returns the opponent's decision service, or null before construction.
func get_ai_coordinator() -> AiCoordinator:
	return _ai


## Returns the final summary, or null while the match is running.
func final_result() -> MatchResult:
	if _session == null or not _session.is_over():
		return null
	return MatchResult.build(_session)


# --- Internals -------------------------------------------------------------


## Commits one move for `player_id`, then resolves the turn.
##
## The two steps are paired exactly as the domain tests pair them:
## `MoveCommitter.commit` performs the atomic board-and-score write (ADR-007
## section 4) and `TurnManager.resolve` advances the turn (ADR-003 section 3).
## A refused commit never reaches resolution, so an illegal move cannot consume
## a turn (ADR-003 section 5).
func _commit(player_id: StringName, cell: Vector2i, rotation: int) -> PlacementResult:
	var result: PlacementResult = MoveCommitter.commit(_session, player_id, cell, rotation)
	if result == null or not result.was_committed():
		return result

	var phase: int = TurnManager.resolve(_session, result)
	move_committed.emit(result, phase)
	if not result.score_events.is_empty():
		score_awarded.emit(result.score_events, cell)
	_after_state_change()
	return result


## Stores a validated preview at `cell` with `rotation`.
func _validate_pending(tile: TileDefinition, cell: Vector2i, rotation: int) -> void:
	var request: PlacementRequest = PlacementRequest.create(
		TurnEnums.HUMAN_PLAYER_ID, tile.tile_id, cell, rotation
	)
	var result: PlacementResult = PlacementValidator.validate(
		_get_board_safe(), request, tile, true
	)
	if result != null and result.accepted:
		_pending_snapshot = result.placed_tile
		_pending_valid = true
		_pending_reason = ""
		return

	# Keep a snapshot so the refusal is drawn at the right cell, but mark it
	# illegal so it can never be confirmed (ADR-006 section 5).
	_pending_snapshot = TileSnapshot.create(tile, cell, rotation)
	_pending_valid = false
	_pending_reason = _reason_text(result)


## Clears the preview and returns rotation to the tile's base orientation.
func _reset_pending() -> void:
	_pending_snapshot = null
	_pending_valid = false
	_pending_reason = ""
	_pending_rotation = 0


## Returns the board, or a throwaway empty board before a match exists.
func _get_board_safe() -> BoardState:
	if _session == null:
		return BoardState.create()
	return _session.get_board()


## Returns a player-facing sentence for a refusal reason.
##
## Wording only: the rule itself is the `PlacementRejection` value supplied by
## the validator, so no rule is restated here (AGENTS.md section 19).
func _reason_text(result: PlacementResult) -> String:
	if result == null:
		return "That move is not available"
	match result.rejection:
		PlacementEnums.PlacementRejection.OUT_OF_BOUNDS:
			return "Outside the board"
		PlacementEnums.PlacementRejection.CELL_OCCUPIED:
			return "That cell is already taken"
		PlacementEnums.PlacementRejection.OPENING_CELL_REQUIRED:
			return "The first tile goes in the centre"
		PlacementEnums.PlacementRejection.NOT_CONNECTED:
			return "Must touch an existing tile"
		PlacementEnums.PlacementRejection.TILE_NOT_AVAILABLE:
			return "No tile available"
		PlacementEnums.PlacementRejection.NOT_PLAYERS_TURN:
			return "Not your turn"
		PlacementEnums.PlacementRejection.INVALID_ROTATION:
			return "That rotation is not allowed"
		PlacementEnums.PlacementRejection.DUPLICATE_MOVE:
			return "That move has already been played"
		PlacementEnums.PlacementRejection.MATCH_FINISHED:
			return "The match is over"
	return "That move is not allowed"


## Loads the versioned tile generation rules, tolerating a missing resource.
func _load_generation_rules() -> TileGenerationRules:
	var resource: Resource = load(TILE_RULES_RESOURCE)
	var rules: TileGenerationRules = resource as TileGenerationRules
	if rules != null and rules.is_valid():
		return rules
	push_error(
		"GameSessionController: '%s' is missing or invalid; using defaults."
		% TILE_RULES_RESOURCE
	)
	return TileGenerationRules.create_default()


## Emits state changes and hands over to the opponent when it is their turn.
func _after_state_change() -> void:
	state_changed.emit()
	if _session == null:
		return
	if _session.is_over():
		clear_saved_match()
		match_ended.emit(final_result())
		return
	if TurnManager.is_awaiting_ai_action(_session):
		_schedule_ai_move()


## Schedules the opponent's move after the configured presentation delay.
##
## The delay comes from the difficulty configuration, not from a literal here:
## it is presentation pacing only and cannot influence move selection, because
## ADR-005 section 8 requires deterministic work budgets rather than wall-clock
## cutoffs inside the search (ADR-008 section 9).
##
## The thinking state is deliberately NOT raised here. ADR-005 section 9 makes it
## describe an analysis, not a pause, and a turn now holds several placements
## (ADR-010 section 11), so raising it at scheduling time would report the rival
## as still thinking the moment its previous placement landed and never let the
## state clear between placements.
func _schedule_ai_move() -> void:
	if _ai_scheduled:
		return
	if get_tree() == null:
		return
	_ai_scheduled = true
	var delay: float = 0.0
	if _ai != null:
		delay = _ai.presentation_delay_seconds()
	var timer: SceneTreeTimer = get_tree().create_timer(delay)
	timer.timeout.connect(_on_ai_think_timeout)


## Plays the scheduled opponent move.
##
## This is where the rival's analysis actually starts, so this is where the
## thinking state is raised (ADR-005 section 9).
func _on_ai_think_timeout() -> void:
	_ai_scheduled = false
	if _session == null or _session.is_over():
		_set_ai_thinking(false)
		return
	if not TurnManager.is_awaiting_ai_action(_session):
		_set_ai_thinking(false)
		return
	_set_ai_thinking(true)
	_play_ai_move()


## Plays one opponent placement, then lets the turn continue or close.
##
## The AI never reaches the board directly: it returns a proposal and
## `_commit()` validates, commits, and resolves it exactly as a human move is
## resolved, so there is one commit path for both players (ADR-005 section 11,
## ADR-007 section 4).
##
## ADR-010 section 11 makes a placement commit one tile out of the rival's whole
## deck and its turn policy "keep placing until the deck is exhausted, then end
## the turn". The rival therefore places one tile here, and the turn either
## continues (the deck still holds a tile, so a follow-up analysis is scheduled
## through the ordinary presentation timer) or closes:
##
## - a deck emptied by the placement ends the turn inside `TurnManager.resolve`
##   (ADR-010 section 4), and
## - a refusal or a decision with no legal move ends the turn here, through the
##   same `TurnManager.end_turn` boundary the human uses, so a rival who cannot
##   move never leaves the match waiting.
func _play_ai_move() -> void:
	if _session == null or _session.is_over():
		_set_ai_thinking(false)
		return
	if _ai == null:
		_set_ai_thinking(false)
		return
	if not TurnManager.is_awaiting_ai_action(_session):
		_set_ai_thinking(false)
		return
	var deck: Array[TileDefinition] = _session.deck_for(TurnEnums.AI_PLAYER_ID)
	if deck.is_empty():
		# ADR-010 section 4: a player holding no tiles has no legal placement, so
		# the turn ends rather than stalling the match.
		TurnManager.end_turn(_session)
		_set_ai_thinking(false)
		_after_state_change()
		return

	# ADR-010 section 11: the candidate source is every tile in the rival's own
	# deck, never a single tile and never the undrawn pot (ADR-004 section 7).
	_ai_cancellation = AiCancellationToken.new()
	var decision: AiDecision = _ai.choose_move(_session, deck, _ai_cancellation)
	_ai_cancellation = null
	_set_ai_thinking(_ai.is_thinking())

	if decision == null or not decision.has_move():
		_report_unplayable_decision(decision)
		return

	# ADR-010 sections 3 and 4: the commit path places the tile the player has
	# armed, so the tile the decision was made with is armed here. The rival
	# therefore commits through exactly the same path as the human, and a
	# proposal decided for one deck tile can never be committed with another.
	var decided: TileDefinition = _ai.decided_tile()
	if decided == null or not _session.set_active_tile(TurnEnums.AI_PLAYER_ID, decided):
		notice.emit("Rival could not play a move")
		TurnManager.fail_recovery(_session, TurnEnums.EndReason.RULES_FAILURE)
		_after_state_change()
		return

	var result: PlacementResult = _commit(
		TurnEnums.AI_PLAYER_ID, decision.cell, decision.rotation
	)
	if result != null and result.was_committed():
		return

	# ADR-005 section 11: the coordinator already revalidated the proposal and
	# retried at most once against the current revision, so a refusal here is an
	# AI implementation failure. It enters ADR-003's recoverable error state
	# rather than substituting an illegal move or silently changing difficulty.
	notice.emit("Rival could not play a move")
	TurnManager.fail_recovery(_session, TurnEnums.EndReason.RULES_FAILURE)
	_after_state_change()


## Reports a decision that carried no committable move, and closes the turn.
##
## ADR-005 section 2 requires the structured refusal to be reported rather than
## replaced with an illegal fallback, and ADR-005 section 9 forbids acting on a
## cancelled analysis at all. ADR-005 section 11 sends an AI implementation
## failure to ADR-003's recoverable error state instead of substituting a move.
##
## ADR-010 section 4 ends the rival's turn in every non-failure case, so a
## structured refusal can never leave the match waiting on a move that will not
## come. The turn boundary stays the domain's: `TurnManager.end_turn` refills the
## deck, checks the end conditions, and hands play back.
func _report_unplayable_decision(decision: AiDecision) -> void:
	if decision != null and decision.is_cancelled():
		# The match moved on (a restart, a difficulty change, or the node being
		# freed), so the turn is not closed here and nothing is reported.
		return

	if decision == null or not decision.is_no_legal_move():
		notice.emit("Rival could not choose a move")
		TurnManager.fail_recovery(_session, TurnEnums.EndReason.RULES_FAILURE)
	else:
		notice.emit("Rival has no legal move")
		TurnManager.end_turn(_session)

	_set_ai_thinking(false)
	_after_state_change()


## Publishes the thinking state, emitting only when it changes.
func _set_ai_thinking(thinking: bool) -> void:
	if thinking == _ai_thinking:
		return
	_ai_thinking = thinking
	ai_thinking_changed.emit(thinking)


## Cancels the analysis in flight, so a partial result can never be committed
## (ADR-005 section 9).
func _cancel_ai_analysis() -> void:
	if _ai_cancellation != null:
		_ai_cancellation.cancel()
		_ai_cancellation = null
	if _ai != null:
		_ai.cancel()


## Releases the outstanding analysis with the controller (ADR-005 section 9).
func _exit_tree() -> void:
	_cancel_ai_analysis()

