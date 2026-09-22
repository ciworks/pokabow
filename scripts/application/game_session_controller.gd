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

## How long the scripted opponent "thinks" before moving.
##
## A visible pause makes the turn handover legible. It is presentation pacing
## only and cannot change the rules (ADR-008 section 9).
const AI_THINK_SECONDS: float = 0.55

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


## Builds a controller without a match. Call `start_new_match` or `resume_match`.
static func create() -> GameSessionController:
	return GameSessionController.new()


## Starts a fresh match and opens the human's first turn (ADR-003 section 2).
func start_new_match(match_id: StringName = &"", seed_value: int = 0) -> bool:
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


## Previews a placement of the active tile at `cell`.
func preview_placement(cell: Vector2i) -> void:
	if not is_human_turn():
		return
	var tile: TileDefinition = _session.active_tile_for(TurnEnums.HUMAN_PLAYER_ID)
	if tile == null:
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
	var tile: TileDefinition = _session.active_tile_for(TurnEnums.HUMAN_PLAYER_ID)
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
## ADR-003 section 4: a player has at most one active tile, so this is exactly
## what the active-tile panel must display and exactly what a confirm would
## place.
func human_tile() -> TileDefinition:
	if _session == null:
		return null
	return _session.active_tile_for(TurnEnums.HUMAN_PLAYER_ID)


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


## Schedules the scripted opponent's move after a short visible pause.
func _schedule_ai_move() -> void:
	if _ai_scheduled:
		return
	if get_tree() == null:
		return
	_ai_scheduled = true
	var timer: SceneTreeTimer = get_tree().create_timer(AI_THINK_SECONDS)
	timer.timeout.connect(_on_ai_think_timeout)


## Plays the scheduled opponent move.
func _on_ai_think_timeout() -> void:
	_ai_scheduled = false
	if _session == null or _session.is_over():
		return
	if not TurnManager.is_awaiting_ai_action(_session):
		return

	var tile: TileDefinition = _session.active_tile_for(TurnEnums.AI_PLAYER_ID)
	if tile == null:
		return
	var cell: Vector2i = _choose_ai_cell()
	if cell == BoardMetrics.NO_CELL:
		return

	# Rotate through the orientations until one validates, so the opponent
	# reaches the board through the same validation path as the human
	# (ADR-003 section 6).
	var board: BoardState = _session.get_board()
	var rotation: int = 0
	for candidate: int in range(TileEnums.ROTATION_COUNT):
		var request: PlacementRequest = PlacementRequest.create(
			TurnEnums.AI_PLAYER_ID, tile.tile_id, cell, candidate
		)
		var validation: PlacementResult = PlacementValidator.validate(
			board, request, tile, true
		)
		if validation != null and validation.accepted:
			rotation = candidate
			break

	var result: PlacementResult = _commit(TurnEnums.AI_PLAYER_ID, cell, rotation)
	if result != null and result.was_committed():
		return

	# ADR-003 section 6: a move that fails revalidation is not silently skipped.
	# Retry once from the current state and give up rather than looping.
	var retry_cell: Vector2i = _choose_ai_cell()
	if retry_cell != BoardMetrics.NO_CELL and retry_cell != cell:
		_commit(TurnEnums.AI_PLAYER_ID, retry_cell, 0)


## Returns the opponent's chosen cell, or `BoardMetrics.NO_CELL` if none exists.
##
## Milestone 5 placeholder: the first frontier cell in row-major order. ADR-005
## owns real difficulty behaviour and Milestone 6 replaces this method with the
## Easy/Medium/Hard strategies; no other code needs to change for that swap.
func _choose_ai_cell() -> Vector2i:
	var frontier: Array[Vector2i] = _get_board_safe().get_frontier_cells()
	if frontier.is_empty():
		return BoardMetrics.NO_CELL
	return frontier[0]
