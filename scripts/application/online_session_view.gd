class_name OnlineSessionView
extends GameSessionState
## Presentation projection only. No bag order, seed, opponent hand or local commits.
var pot_count: int = 0
var pot_faces: Array[Dictionary] = []
var opponent_tile_count: int = 0

static func from_response(data: Dictionary) -> OnlineSessionView:
	var view: OnlineSessionView = OnlineSessionView.new()
	view._match_id = StringName(data.matchId)
	view._board = BoardState.create()
	view._rules = ScoringRules.create_default()
	view._deck_rules = DeckRules.create_default()
	view._scored_hand_ids = ScoredHandSet.create()
	for hand_id: String in data.get("scoredHandIds", []):
		view._scored_hand_ids.add(StringName(hand_id))
	view._decks = _empty_decks()
	for tile_data: Dictionary in data.get("hand", []):
		var tile: TileDefinition = TileDefinition.from_dto(TileDto.from_dictionary(tile_data))
		if tile == null or not tile.is_valid():
			return null
		view._decks[TurnEnums.HUMAN_PLAYER_ID].append(tile)
	var snapshots: Array[TileSnapshot] = []
	for placed: Dictionary in data.get("board", []):
		var tile: TileDefinition = TileDefinition.from_dto(TileDto.from_dictionary(placed.tile))
		if tile == null or not tile.is_valid():
			return null
		snapshots.append(TileSnapshot.create(tile, Vector2i(int(placed.cell[0]), int(placed.cell[1])), int(placed.rotation)))
	if not snapshots.is_empty() and not view._board.commit_tiles(snapshots):
		return null
	var ledger: Dictionary = data.get("ledger", {}).duplicate(true)
	for event: Dictionary in ledger.get("events", []):
		event.player_id = local_seat(String(event.player_id), String(data.seat))
	view._ledger = ScoreLedger.from_dictionary(ledger)
	view._turn_state = TurnState.create()
	view._turn_state.phase = int(data.turn.phase)
	view._turn_state.turn_number = int(data.turn.turn_number)
	view._turn_state.active_player_id = local_seat(String(data.turn.active_player_id), String(data.seat))
	view._outcome = int(data.outcome)
	if String(data.seat) == "ai" and view._outcome in [TurnEnums.MatchOutcome.HUMAN_WIN, TurnEnums.MatchOutcome.AI_WIN]:
		view._outcome = TurnEnums.MatchOutcome.AI_WIN if view._outcome == TurnEnums.MatchOutcome.HUMAN_WIN else TurnEnums.MatchOutcome.HUMAN_WIN
	view._end_reason = int(data.endReason)
	view.pot_count = int(data.remainingTiles)
	for raw_face: Variant in data.get("potTiles", []):
		if raw_face is Dictionary:
			view.pot_faces.append((raw_face as Dictionary).duplicate(true))
	view.opponent_tile_count = maxi(0, int(data.get("opponentTileCount", 0)))
	for entry: Dictionary in data.get("history", []):
		var record: Dictionary = entry.duplicate(true)
		record.player_id = local_seat(String(record.player_id), String(data.seat))
		view._history.append(ScoringMove.from_dictionary(record))
	return view

static func local_seat(seat: String, own_seat: String) -> StringName:
	return TurnEnums.HUMAN_PLAYER_ID if seat == own_seat else TurnEnums.AI_PLAYER_ID

func remaining_tile_count() -> int:
	return pot_count

func remaining_tile_faces() -> Array[Dictionary]:
	return pot_faces.duplicate(true)

