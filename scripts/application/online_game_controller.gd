class_name OnlineGameController
extends GameSessionController
## Reuses board gestures and previews; all committed changes come from the API.
var client: OnlineGameApiClient
var _version: int = -1
var opponent_name: String = "Opponent"
var opponent_connected: bool = true
var gem_settlement: Dictionary = {}
var gem_settlement_status: String = "none"
var gem_policy_version: String = "gem-pot-v1"
var gem_earnings: Dictionary = {}

func attach_client(api: OnlineGameApiClient) -> void:
	client = api
	client.received.connect(apply_response)
	client.connection_changed.connect(_connection_changed)
	if not client.state.is_empty():
		apply_response(client.state)

func apply_response(data: Dictionary) -> void:
	var previous_settlement: Dictionary = gem_settlement
	gem_settlement = data.get("gemSettlement", {}) if data.get("gemSettlement") is Dictionary else {}
	gem_settlement_status = String(data.get("gemSettlementStatus", "ineligible"))
	gem_policy_version = String(data.get("gemPolicyVersion", "gem-pot-v1"))
	gem_earnings = data.get("gemEarnings", {}) if data.get("gemEarnings") is Dictionary else {}
	opponent_name = String(data.opponent.displayName)
	opponent_connected = bool(data.opponent.connected)
	var next_version: int = int(data.version)
	if next_version == _version:
		update_turn_clock()
		state_changed.emit()
		if _session != null and _session.is_over() and previous_settlement != gem_settlement:
			match_ended.emit(MatchResult.build(_session))
		return
	var next: OnlineSessionView = OnlineSessionView.from_response(data)
	if next == null:
		notice.emit("Could not read the online match. Reconnecting...")
		return
	var first: bool = _session == null
	var old_events: Dictionary = {}
	if _session != null:
		for event: ScoreEvent in _session.get_ledger().get_events():
			old_events[event.event_id] = true
	_session = next
	_version = next_version
	_clear_staged()
	_select_next_unstaged_tile()
	update_turn_clock()
	if first:
		session_started.emit()
	state_changed.emit()
	preview_changed.emit()
	if not first:
		var events: Array[ScoreEvent] = []
		for event: ScoreEvent in next.get_ledger().get_events():
			if not old_events.has(event.event_id):
				events.append(event)
		if not events.is_empty():
			score_awarded.emit(events, events[0].cells[0] if not events[0].cells.is_empty() else Vector2i.ZERO)
	if next.is_over():
		match_ended.emit(MatchResult.build(next))

func _connection_changed(_connected: bool, message: String) -> void:
	if not message.is_empty():
		notice.emit(message)
	state_changed.emit()

func update_turn_clock(_now_unix: float = -1.0) -> void:
	super.update_turn_clock(_now_unix)

func is_human_turn() -> bool:
	return client != null and client.connected and not client.has_pending_command() and super.is_human_turn()

func commit_line() -> LineResult:
	if not is_human_turn() or not _staged_valid:
		return null
	var placements: Array = []
	for tile: TileSnapshot in _staged:
		placements.append({"tileId": String(tile.get_tile_id()), "x": tile.get_cell().x, "y": tile.get_cell().y, "rotation": tile.get_rotation()})
	if client.submit({"action": "place", "placements": placements}):
		state_changed.emit()
	return null

func request_swap(tile_ids: Array[StringName]) -> int:
	if not is_human_turn() or tile_ids.is_empty():
		return -1
	if client.submit({"action": "swap", "tileIds": tile_ids}):
		state_changed.emit()
		return tile_ids.size()
	return -1

func resign() -> bool:
	if client == null or is_over():
		return false
	var sent: bool = client.submit({"action": "resign"})
	state_changed.emit()
	return sent

func _notification(_what: int) -> void:
	pass

func start_new_match(_match_id: StringName = &"", _seed_value: int = 0, _ai_difficulty: int = -1) -> bool:
	return false

func resume_match() -> bool:
	return false

func save_match() -> bool:
	return false

func autosave() -> bool:
	return false

func clear_saved_match() -> void:
	pass

func export_fixture() -> bool:
	return false

func match_snapshot_dictionary() -> Dictionary:
	return {}

func _schedule_ai_move(delay_override: float = -1.0) -> void:
	pass

func opponent_deck_count() -> int:
	return (_session as OnlineSessionView).opponent_tile_count if _session is OnlineSessionView else 0
