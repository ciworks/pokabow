class_name GameSessionController
extends Node

## Application layer: one match, driven by commands from presentation
## (ADR-008 sections 5 and 7).
##
## This is the only place rules are invoked. It owns the `GameSessionState` and
## exposes the line-shaped commands ADR-011 sections 1, 6, and 11 imply:
## `select_deck_tile`, `stage_tile`, `unstage_tile`, `rotate_staged`,
## `commit_line`, `cancel_staged`, and `request_swap`, plus read-only accessors
## for the HUD. Screens submit intents and render the result; they never validate
## a line, never score, and never reach into the board themselves
## (ADR-008 section 4, AGENTS.md sections 6 and 19).
##
## ADR-011 section 11 requires a staging state: tiles chosen from the deck are
## shown on the board as a pending line, rotating one updates the pending line
## without writing to the board, and a single confirm commits the whole line.
## The staged line lives here rather than in the session, because ADR-003
## section 9 forbids persisting a transient preview as authoritative state.
##
## Every rule call is delegated to the domain services: `LineValidator` for line
## legality, `MoveCommitter` for the atomic whole-line write, `TurnManager` for
## lifecycle, and `MatchResult` for the final summary. Nothing here re-implements
## any of them, so the UI cannot drift from the rules that the headless tests
## already cover.
##
## This node is NOT an autoload and holds no global state: it is created by
## `AppRoot` and released with its screen (ADR-008 section 6).

## A new or resumed match is ready to render.
signal session_started()

## Authoritative state changed; the HUD and board should resynchronize.
signal state_changed()

## The pending preview changed (placed, moved, rotated, or refused).
signal preview_changed()

## A whole line was committed and the turn lifecycle resolved
## (ADR-011 sections 5 and 7).
signal line_committed(result: LineResult, turn_phase: int)

## A line was committed, carrying the move's anchor as a placement-shaped payload.
##
## Presentation compatibility only: the board tile layer marks the cell a move
## landed on, and the payload's `changed_cells`, `move_id`, and `score_events`
## describe the whole line. `line_committed` is the authoritative payload for a
## UI that renders the line itself, and the presentation pass that owns the
## staging interface should move to it.
signal move_committed(result: PlacementResult, turn_phase: int)

## A swap was committed and the turn lifecycle resolved (ADR-011 section 6).
signal swap_committed(returned_count: int, turn_phase: int)

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

## The line the player has assembled and not yet committed (ADR-011 section 11).
##
## One entry per staged tile, in the order they were staged. A tile is staged at
## a cell with a rotation; rotating or repositioning it replaces its entry.
var _staged: Array[TileSnapshot] = []

## Whether `_staged` is currently a legal whole move, and why not when it is not.
var _staged_valid: bool = false
var _staged_reason: String = ""

## Rotation applied to the next staged tile (ADR-006 section 5).
var _pending_rotation: int = 0

## The cell the last staging command addressed, for the refusal message.
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
	_clear_staged()
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
	_clear_staged()
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


## Selects one of the human's deck tiles as the tile the next staging command
## places (ADR-010 section 12, ADR-011 section 11).
##
## ADR-011 section 11 lets the player choose several tiles from the deck for one
## pending line, so selection is not an arm-and-place action any more: it names
## which tile the next `stage_tile` call takes from the deck. The selection is an
## application-layer choice, not authoritative state, and it only names a tile the
## player already holds, which the session verifies.
##
## Returns true when the selection was accepted.
func select_deck_tile(tile_id: StringName) -> bool:
	if not is_human_turn():
		return false
	var tile: TileDefinition = _session.deck_tile(TurnEnums.HUMAN_PLAYER_ID, tile_id)
	if tile == null:
		notice.emit("That tile is not in your deck")
		return false
	if not _session.set_active_tile(TurnEnums.HUMAN_PLAYER_ID, tile):
		return false

	_pending_rotation = 0
	preview_changed.emit()
	return true


## Stages the selected deck tile at `cell` as one tile of the pending line
## (ADR-011 section 11).
##
## Returns true when the tile was staged. The staged line is re-validated as a
## whole after every staging command, so `is_line_valid()` always describes the
## line as it stands, and a tile may be staged even while the line is not yet
## legal: a pair only becomes a pair on the second tile (ADR-011 section 3).
##
## A tile already staged is refused, and so is a cell already staged or already
## occupied, because a move cannot place the same tile or fill the same cell
## twice.
func stage_tile(tile_id: StringName, cell: Vector2i, rotation: int = -1) -> bool:
	if not is_human_turn():
		return false
	var tile: TileDefinition = _session.deck_tile(TurnEnums.HUMAN_PLAYER_ID, tile_id)
	if tile == null:
		notice.emit("That tile is not in your deck")
		return false
	for staged: TileSnapshot in _staged:
		if staged.get_tile_id() == tile_id:
			notice.emit("That tile is already in the line")
			return false
		if staged.get_cell() == cell:
			notice.emit("That cell is already in the line")
			return false

	var applied_rotation: int = _pending_rotation
	if rotation >= 0 and rotation < TileEnums.ROTATION_COUNT:
		applied_rotation = rotation
	_staged.append(TileSnapshot.create(tile, cell, applied_rotation))
	_pending_cell = cell
	_pending_rotation = applied_rotation
	_revalidate_line()
	preview_changed.emit()
	return true


## Removes one staged tile from the pending line, by its cell or tile identity.
##
## Returns true when something was removed. ADR-011 section 11 lets a player
## adjust the line before confirming, so un-staging must not touch the board, the
## deck, or the turn.
func unstage_tile(key: Variant) -> bool:
	if not is_human_turn():
		return false
	for index: int in range(_staged.size()):
		var staged: TileSnapshot = _staged[index]
		if key is Vector2i and staged.get_cell() == key:
			_staged.remove_at(index)
			_revalidate_line()
			preview_changed.emit()
			return true
		if key is StringName and staged.get_tile_id() == key:
			_staged.remove_at(index)
			_revalidate_line()
			preview_changed.emit()
			return true
	return false


## Rotates the most recently staged tile one quarter-turn clockwise.
##
## ADR-011 section 11: rotating a tile updates the pending line without writing to
## the board. Returns the new rotation, or -1 when nothing is staged.
func rotate_staged() -> int:
	if not is_human_turn():
		return -1
	if _staged.is_empty():
		_pending_rotation = (_pending_rotation + 1) % TileEnums.ROTATION_COUNT
		preview_changed.emit()
		return _pending_rotation
	var last: TileSnapshot = _staged[_staged.size() - 1]
	var rotation: int = (last.get_rotation() + 1) % TileEnums.ROTATION_COUNT
	_staged[_staged.size() - 1] = TileSnapshot.create(last.get_tile(), last.get_cell(), rotation)
	_pending_rotation = rotation
	_revalidate_line()
	preview_changed.emit()
	return rotation


## Commits the assembled line as one atomic move (ADR-011 sections 5 and 7).
##
## Returns the commit result, so a caller can report a refusal. ADR-011 section 5
## leaves the board, ledger, windows, history, deck, and turn completely unchanged
## when the line is refused, and the player keeps their tiles and may reassemble:
## the staged line is therefore kept on a refusal and cleared only on success
## (ADR-011 section 11).
func commit_line() -> LineResult:
	if not is_human_turn():
		return null
	if _staged.is_empty():
		notice.emit("Assemble a line first")
		return null
	if not _staged_valid:
		notice.emit(_staged_reason)
		preview_changed.emit()
		return null

	var result: LineResult = _commit_line(TurnEnums.HUMAN_PLAYER_ID, _staged)
	if result == null or not result.was_committed():
		_staged_valid = false
		_staged_reason = _line_reason_text(result)
		preview_changed.emit()
		return result

	_clear_staged()
	state_changed.emit()
	return result


## Discards the pending line without touching the turn, the deck, or the board.
func cancel_staged() -> void:
	if not is_human_turn():
		return
	_clear_staged()
	preview_changed.emit()
	notice.emit("Line cancelled")


## Returns deck tiles to the pot and draws the same number of replacements,
## consuming the human's whole turn (ADR-011 section 6).
##
## Returns how many tiles were swapped, or -1 when the swap was refused. A
## refusal leaves the player with their tiles and the turn open, which is what
## section 6 requires when the pot cannot supply the whole amount; a swap cannot
## place a tile and cannot score.
func request_swap(tile_ids: Array[StringName]) -> int:
	return _request_swap_for(TurnEnums.HUMAN_PLAYER_ID, tile_ids)


## Returns true when the human may end their turn.
##
## ADR-011 section 7 removes the explicit end-turn action: a turn is exactly one
## move, so committing a line or resolving a swap is what ends it. This always
## returns false and exists only so a caller built against ADR-010's action gets
## the correct answer instead of a stale one.
func can_end_turn() -> bool:
	return false


## Refuses the removed end-turn action (ADR-011 section 7).
##
## ADR-010 section 4's explicit end-turn action no longer exists, so this cannot
## close a turn. It reports that instead of doing nothing silently, so a caller
## built against the old action learns the rule rather than appearing to hang.
func end_human_turn() -> void:
	if _session == null or _session.is_over():
		return
	if not TurnManager.is_awaiting_human_action(_session):
		return
	notice.emit("A turn is one move: commit a line or swap")


# --- Presentation compatibility commands (ADR-010 surface, line semantics) --


## Stages the selected deck tile at `cell`.
##
## Retained under the name the current board input calls, with ADR-011 section 11
## semantics: each tap adds one tile to the pending line rather than previewing a
## lone placement, which section 1 no longer allows. The presentation pass that
## owns the staging interface should call `stage_tile` directly.
func preview_placement(cell: Vector2i) -> void:
	if not is_human_turn():
		return
	var tile: TileDefinition = human_tile()
	if tile == null:
		notice.emit("Your deck is empty")
		return
	stage_tile(tile.tile_id, cell)


## Rotates the tile the pending line last took, or the next staged rotation.
func rotate_pending() -> void:
	rotate_staged()


## Commits the assembled line. The return type stays `PlacementResult` so the
## existing screen keeps compiling; `commit_line()` is the line-shaped command.
func confirm_pending() -> PlacementResult:
	var result: LineResult = commit_line()
	if result == null or not result.was_committed():
		return null
	return _anchor_view(result, 0)


## Discards the assembled line.
func cancel_pending() -> void:
	cancel_staged()


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


## Returns every tile of the pending line, in staging order (ADR-011 section 11).
##
## This is what the board draws as the uncommitted line. A copy is returned, so
## the view cannot mutate the pending line.
func staged_snapshots() -> Array[TileSnapshot]:
	return _staged.duplicate()


## Returns how many tiles the pending line holds.
func staged_count() -> int:
	return _staged.size()


## Returns the cells of the pending line, in staging order.
func staged_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for staged: TileSnapshot in _staged:
		cells.append(staged.get_cell())
	return cells


## Returns whether the pending line is a legal whole move (ADR-011 sections 1-4).
func is_line_valid() -> bool:
	return _staged_valid


## Returns why the pending line is not legal, or an empty string.
func line_reason() -> String:
	return _staged_reason


## Returns the first tile of the pending line, or null when nothing is staged.
##
## The cell a one-tile mark is drawn at, and the address a refusal names.
func pending_snapshot() -> TileSnapshot:
	if _staged.is_empty():
		return null
	return _staged[0]


## Returns whether the pending line is legal under the name the HUD already reads.
func is_pending_valid() -> bool:
	return _staged_valid


## Returns why the pending line is not legal, under the name the HUD already reads.
func pending_reason() -> String:
	return _staged_reason


## Returns the rotation the active-tile panel shows.
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


## Returns true while a line is assembled and awaiting confirmation.
##
## ADR-011 section 11: a pending line only becomes a committed move on explicit
## confirm, so the UI needs to know whether one is outstanding.
func has_pending() -> bool:
	return not _staged.is_empty()


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


## Commits one whole line for `player_id`, then resolves the turn
## (ADR-011 sections 5 and 7).
##
## The two steps are paired exactly as the domain tests pair them:
## `MoveCommitter.commit_line` performs the atomic whole-line board-and-score
## write (ADR-011 section 5) and `TurnManager.resolve` closes the turn, because a
## turn is one move (ADR-011 section 7). A refused line never reaches resolution,
## so an illegal move cannot consume a turn (ADR-003 section 5).
func _commit_line(player_id: StringName, staged: Array[TileSnapshot]) -> LineResult:
	var result: LineResult = MoveCommitter.commit_line(_session, player_id, staged)
	if result == null or not result.was_committed():
		return result

	var phase: int = TurnManager.resolve(_session, result)
	line_committed.emit(result, phase)
	move_committed.emit(_anchor_view(result, phase), phase)
	if not result.score_events.is_empty():
		score_awarded.emit(result.score_events, result.primary_cell())
	_after_state_change()
	return result


## Commits one swap for `player_id`, then resolves the turn (ADR-011 sections 6
## and 7).
##
## Returns how many tiles were swapped, or -1 when the swap was refused. A
## refusal leaves the turn open because it changed nothing, so this cannot consume
## a turn.
func _request_swap_for(player_id: StringName, tile_ids: Array[StringName]) -> int:
	if _session == null or _session.is_over():
		return -1
	if player_id == TurnEnums.HUMAN_PLAYER_ID:
		if not TurnManager.is_awaiting_human_action(_session):
			return -1
	elif not TurnManager.is_awaiting_ai_action(_session):
		return -1

	var swapped: int = _session.request_swap(player_id, tile_ids)
	if swapped <= 0:
		if player_id == TurnEnums.HUMAN_PLAYER_ID:
			notice.emit("The pot cannot supply that swap")
		return -1

	_clear_staged()
	var phase: int = TurnManager.resolve_swap(_session, swapped)
	swap_committed.emit(swapped, phase)
	state_changed.emit()
	_after_state_change()
	return swapped


## Builds the placement-shaped view of a committed line that the older presentation
## signal carries.
##
## Presentation compatibility only: the board tile layer marks one cell for a
## committed move, and the anchor cell is that cell. Every other field is the
## line's own, so a consumer of `move_committed` still sees the move identifier,
## the awarded events, and the full changed-cell set.
func _anchor_view(result: LineResult, turn_phase: int) -> PlacementResult:
	if result == null:
		return null
	var view: PlacementResult = PlacementResult.create_accepted(
		result.primary_cell(), result.anchor_snapshot(), result.changed_cells
	)
	view.move_id = result.move_id
	view.score_events = result.score_events
	return view


## Re-validates the pending line as a whole move (ADR-011 sections 1 to 4).
func _revalidate_line() -> void:
	if _staged.is_empty():
		_staged_valid = false
		_staged_reason = ""
		return

	var result: LineResult = LineValidator.validate(_get_board_safe(), _staged)
	if result != null and result.accepted:
		_staged_valid = true
		_staged_reason = ""
		return

	_staged_valid = false
	_staged_reason = _line_reason_text(result)


## Clears the pending line and returns rotation to the base orientation.
func _clear_staged() -> void:
	_staged = [] as Array[TileSnapshot]
	_staged_valid = false
	_staged_reason = ""
	_pending_rotation = 0
	_pending_cell = Vector2i(BoardEnums.OPENING_MIN, BoardEnums.OPENING_MIN)


## Returns the board, or a throwaway empty board before a match exists.
func _get_board_safe() -> BoardState:
	if _session == null:
		return BoardState.create()
	return _session.get_board()


## Returns a player-facing sentence for a refusal reason.
##
## Wording only: the rule itself is the `PlacementRejection` value supplied by
## `LineValidator`, so no rule is restated here (AGENTS.md section 19). The four
## ADR-011 values are named against the section that authorises them.
func _line_reason_text(result: LineResult) -> String:
	if result == null:
		return "That move is not available"
	match result.rejection:
		PlacementEnums.PlacementRejection.LONE_TILE:
			return "A line needs at least two tiles"
		PlacementEnums.PlacementRejection.MIXED_ORIENTATION:
			return "A line goes in one row or one column"
		PlacementEnums.PlacementRejection.LINE_GAP:
			return "A line cannot have a gap"
		PlacementEnums.PlacementRejection.NO_REPEATED_RANK:
			return "The line must contain a pair"
		PlacementEnums.PlacementRejection.OUT_OF_BOUNDS:
			return "Outside the board"
		PlacementEnums.PlacementRejection.CELL_OCCUPIED:
			return "That cell is already taken"
		PlacementEnums.PlacementRejection.OPENING_CELL_REQUIRED:
			return "The first line goes in the centre"
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


## Plays one opponent move, which is the rival's whole turn (ADR-011 section 7).
##
## The AI never reaches the board directly: it returns a proposal and the commit
## path validates, commits, and resolves it exactly as a human move is resolved,
## so there is one commit path for both players (ADR-005 section 11, ADR-007
## section 4, ADR-011 section 5).
##
## ADR-011 section 12 retargets AI move generation to one line per candidate, and
## that pass has not run yet. The existing generator still proposes one coordinate
## and rotation, so `LineAssembler` completes that proposal into the shortest
## legal line through the proposed cell: the proposal is kept exactly as the
## coordinator revalidated it, and only the partner tile the proposal needs to be
## a legal move is added (ADR-011 sections 1 and 3). Nothing here chooses the
## line's shape or its score.
##
## Because a turn is one move, this commits once and the turn closes. A rival who
## cannot form a legal line and cannot swap (section 6) has its turn ended through
## the domain boundary, so it never leaves the match waiting.
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
		# ADR-010 section 4: a player holding no tiles has no legal move, so the
		# turn ends rather than stalling the match.
		_finish_ai_turn()
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

	# ADR-010 sections 3 and 4: the tile the decision was made with is armed here,
	# so the rival commits through exactly the same path as the human and a
	# proposal decided for one deck tile can never be committed with another.
	var decided: TileDefinition = _ai.decided_tile()
	if decided == null or not _session.set_active_tile(TurnEnums.AI_PLAYER_ID, decided):
		notice.emit("Rival could not play a move")
		TurnManager.fail_recovery(_session, TurnEnums.EndReason.RULES_FAILURE)
		_after_state_change()
		return

	# ADR-011 sections 1 to 4: complete the proposal into a legal line.
	var staged: Array[TileSnapshot] = LineAssembler.shortest_line_from(
		_session.get_board(), deck, decided, decision.cell, decision.rotation
	)
	if staged.is_empty():
		# The proposal was legal under ADR-010 and is not a legal line under
		# ADR-011 section 3. ADR-011 section 12 owns the generator that must stop
		# proposing such a move, so until that pass runs the rival takes the
		# section 6 escape hatch instead of committing an illegal move
		# (ADR-005 section 2) or stalling the match.
		_finish_ai_turn()
		return

	var result: LineResult = _commit_line(TurnEnums.AI_PLAYER_ID, staged)
	if result != null and result.was_committed():
		return

	# ADR-005 section 11: the coordinator already revalidated the proposal and
	# retried at most once against the current revision, so a refusal here is an
	# AI implementation failure. It enters ADR-003's recoverable error state
	# rather than substituting an illegal move or silently changing difficulty.
	notice.emit("Rival could not play a move")
	TurnManager.fail_recovery(_session, TurnEnums.EndReason.RULES_FAILURE)
	_after_state_change()


## Ends the rival's turn when it has no move, swapping first when it can
## (ADR-011 sections 6, 7, and 9).
##
## ADR-011 section 9 keeps the match alive while the pot can still supply a swap,
## so the rival swaps its whole deck (returning every tile and drawing the same
## number) rather than passing, and only a pot that cannot cover the swap ends the
## turn with nothing played. The turn boundary itself stays the domain's.
func _finish_ai_turn() -> void:
	var deck: Array[TileDefinition] = _session.deck_for(TurnEnums.AI_PLAYER_ID)
	var ids: Array[StringName] = []
	for tile: TileDefinition in deck:
		ids.append(tile.tile_id)
	if not ids.is_empty() and _session.request_swap(TurnEnums.AI_PLAYER_ID, ids) > 0:
		_set_ai_thinking(false)
		TurnManager.resolve_swap(_session, ids.size())
		_after_state_change()
		return

	# No line and no swap: the turn cannot be played. ADR-010 section 4's
	# automatic handover ends it, and the match continues until both players are
	# out of tiles (ADR-010 section 7, kept by ADR-011 section 9).
	_set_ai_thinking(false)
	var turn_state: TurnState = _session.get_turn_state()
	turn_state.last_skip_reason = TurnEnums.SkipReason.NO_TILE_AVAILABLE
	TurnManager.resolve_swap(_session, 0)
	_after_state_change()


## Reports a decision that carried no committable move, and closes the turn.
##
## ADR-005 section 2 requires the structured refusal to be reported rather than
## replaced with an illegal fallback, and ADR-005 section 9 forbids acting on a
## cancelled analysis at all. ADR-005 section 11 sends an AI implementation
## failure to ADR-003's recoverable error state instead of substituting a move.
##
## ADR-011 section 12 owns the generator that must propose only legal lines, so
## until that pass runs a proposal that is not a legal line is reported as
## structured and the rival's turn is closed through `_finish_ai_turn` rather than
## leaving the match waiting on a move that will not come.
func _report_unplayable_decision(decision: AiDecision) -> void:
	if decision != null and decision.is_cancelled():
		# The match moved on (a restart, a difficulty change, or the node being
		# freed), so the turn is not closed here and nothing is reported.
		return

	if decision == null or not decision.is_no_legal_move():
		notice.emit("Rival could not choose a move")
		TurnManager.fail_recovery(_session, TurnEnums.EndReason.RULES_FAILURE)
		_set_ai_thinking(false)
		_after_state_change()
		return

	# ADR-011 sections 6 and 9: a rival with no legal line swaps if it can, and a
	# turn that cannot be played at all is closed rather than left waiting.
	notice.emit("Rival has no legal move")
	_finish_ai_turn()


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

