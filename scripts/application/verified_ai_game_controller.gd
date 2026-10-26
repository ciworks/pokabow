class_name VerifiedAiGameController
extends OnlineGameController
## AI match whose seed, moves and result are owned by the authenticated API.

signal presentation_wait_started
signal presentation_wait_finished
signal human_presentation_ready

const MIN_THINKING_SECONDS: float = 3.0

var _verified_difficulty: int = AiEnums.DEFAULT_DIFFICULTY
var _verified_reward_difficulty: int = AiEnums.Difficulty.EASY
var _presentation_waiting: bool = false
var _awaiting_result: bool = false
var _awaiting_reveal: bool = false
var _presentation_timer: Timer
var _queued_response: Dictionary = {}


func _ready() -> void:
	_presentation_timer = Timer.new()
	_presentation_timer.one_shot = true
	_presentation_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_presentation_timer)
	_presentation_timer.timeout.connect(_on_presentation_pause_elapsed)

func apply_response(data: Dictionary) -> void:
	_verified_difficulty = clampi(int(data.get("difficulty", AiEnums.DEFAULT_DIFFICULTY)), 0, 2)
	_verified_reward_difficulty = clampi(int(data.get("rewardDifficulty", AiEnums.Difficulty.EASY)), 0, 2)
	if _awaiting_reveal or _presentation_waiting:
		if int(data.get("version", -1)) <= _version:
			return
		_queued_response = data.duplicate(true)
		return
	if _awaiting_result:
		if not String(data.get("error", "")).is_empty():
			_awaiting_result = false
		elif int(data.get("version", -1)) <= _version:
			return
		else:
			_awaiting_result = false
			var projection: Dictionary = _human_only_projection(data)
			if not projection.is_empty():
				if _apply_human_projection(projection):
					_queued_response = data.duplicate(true)
					_awaiting_reveal = true
					human_presentation_ready.emit()
					return
			var old_count: int = _session.move_count() if _session != null else 0
			super.apply_response(data)
			if _session != null and _session.move_count() > old_count and \
					_session.last_move().player_id == TurnEnums.HUMAN_PLAYER_ID:
				human_presentation_ready.emit()
			return
	super.apply_response(data)


func commit_line() -> LineResult:
	var was_pending: bool = client != null and client.has_pending_command()
	var result: LineResult = super.commit_line()
	if not was_pending and client != null and client.has_pending_command():
		_awaiting_result = true
	return result


func request_swap(tile_ids: Array[StringName]) -> int:
	var was_pending: bool = client != null and client.has_pending_command()
	var count: int = super.request_swap(tile_ids)
	if not was_pending and client != null and client.has_pending_command():
		_awaiting_result = true
	return count


func is_human_turn() -> bool:
	return not (_awaiting_result or _awaiting_reveal or _presentation_waiting) and super.is_human_turn()


func start_rival_reveal_delay() -> void:
	if _presentation_timer == null or not _awaiting_reveal or _presentation_waiting:
		return
	_awaiting_reveal = false
	_presentation_waiting = true
	_presentation_timer.start(MIN_THINKING_SECONDS)
	presentation_wait_started.emit()


func _on_presentation_pause_elapsed() -> void:
	if not _presentation_waiting or _queued_response.is_empty():
		return
	var response: Dictionary = _queued_response.duplicate(true)
	_finish_presentation_wait()
	super.apply_response(response)
	presentation_wait_finished.emit()


func _finish_presentation_wait() -> void:
	_presentation_waiting = false
	_queued_response.clear()
	if _presentation_timer != null:
		_presentation_timer.stop()


## The API commits both turns atomically. Present the server-recorded human move
## first, withholding the rival's board cells, awards and replacement draw until
## the close-view feedback and thinking pause have finished.
func _human_only_projection(data: Dictionary) -> Dictionary:
	if _session == null:
		return {}
	var history: Array = data.get("history", [])
	if history.size() != _session.move_count() + 2:
		return {}
	var human_move: ScoringMove = ScoringMove.from_dictionary(history[history.size() - 2])
	var rival_move: ScoringMove = ScoringMove.from_dictionary(history.back())
	if human_move.player_id != TurnEnums.HUMAN_PLAYER_ID or rival_move.player_id != TurnEnums.AI_PLAYER_ID:
		return {}
	var projection: Dictionary = data.duplicate(true)
	var rival_cells: Dictionary = {}
	for placement: ScoringMove.Placement in rival_move.placements:
		rival_cells[placement.cell] = true
	var human_board: Array = []
	for placed: Dictionary in projection.board:
		var cell: Vector2i = Vector2i(int(placed.cell[0]), int(placed.cell[1]))
		if not rival_cells.has(cell):
			human_board.append(placed)
	projection.board = human_board
	projection.history.pop_back()
	var human_events: Array = []
	for event: Dictionary in projection.ledger.events:
		if String(event.move_id) != String(rival_move.move_id):
			human_events.append(event)
	projection.ledger.events = human_events
	projection.turn.active_player_id = "ai"
	projection.turn.phase = TurnEnums.MatchPhase.AWAIT_ACTION
	projection.turn.turn_number = rival_move.move_number
	projection.outcome = TurnEnums.MatchOutcome.IN_PROGRESS
	projection.endReason = TurnEnums.EndReason.NONE
	projection.status = "active"
	projection.opponentTileCount = opponent_deck_count()
	var rival_refill: int = maxi(0, int(data.opponentTileCount) -
		(opponent_deck_count() - rival_move.placements.size()))
	projection.remainingTiles = int(data.remainingTiles) + rival_refill
	var pot_faces: Array[Dictionary] = (_session as OnlineSessionView).pot_faces.duplicate(true)
	var old_hand_ids: Dictionary = {}
	for tile: TileDefinition in _session.deck_for(TurnEnums.HUMAN_PLAYER_ID):
		old_hand_ids[tile.tile_id] = true
	for tile_data: Dictionary in data.hand:
		if old_hand_ids.has(StringName(String(tile_data.tile_id))):
			continue
		var matching_index: int = -1
		for index: int in range(pot_faces.size()):
			if _same_visible_face(pot_faces[index], tile_data):
				matching_index = index
				break
		if matching_index >= 0:
			pot_faces.remove_at(matching_index)
	if pot_faces.size() != int(projection.remainingTiles):
		return {}
	projection.potTiles = pot_faces
	return projection


func _same_visible_face(left: Dictionary, right: Dictionary) -> bool:
	return int(left.get("rank", -1)) == int(right.get("rank", -2)) and \
		int(left.get("face_color", -1)) == int(right.get("face_color", -2)) and \
		int(left.get("suit", -1)) == int(right.get("suit", -2)) and \
		left.get("edges", []) == right.get("edges", [])


func _apply_human_projection(data: Dictionary) -> bool:
	var next: OnlineSessionView = OnlineSessionView.from_response(data)
	if next == null:
		return false
	var old_events: Dictionary = {}
	for event: ScoreEvent in _session.get_ledger().get_events():
		old_events[event.event_id] = true
	_session = next
	_clear_staged()
	_select_next_unstaged_tile()
	update_turn_clock()
	state_changed.emit()
	preview_changed.emit()
	var awards: Array[ScoreEvent] = []
	for event: ScoreEvent in next.get_ledger().get_events():
		if not old_events.has(event.event_id):
			awards.append(event)
	if not awards.is_empty():
		score_awarded.emit(awards, awards[0].cells[0] if not awards[0].cells.is_empty() else Vector2i.ZERO)
	return true

func set_ai_difficulty(difficulty: int) -> void:
	if client == null or not AiEnums.is_valid_difficulty(difficulty):
		return
	client.submit({"action": "difficulty", "difficulty": difficulty})

func ai_difficulty() -> int:
	return _verified_difficulty

func ai_gem_difficulty() -> int:
	return _verified_reward_difficulty
