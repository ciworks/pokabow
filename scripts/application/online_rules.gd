class_name OnlineRules
extends RefCounted
## Trusted server adapter. Account IDs map to the two existing domain seats;
## neither seat is driven by AI. Full snapshots never leave the server.

static func execute(request: Dictionary) -> Dictionary:
	var session: GameSessionState
	var rules: TileGenerationRules = load(GameSessionController.TILE_RULES_RESOURCE)
	var action: String = String(request.get("action", ""))
	if action == "create":
		session = GameSessionState.create(StringName(request.matchId), int(request.seed), ScoringRules.create_default(), rules)
		if session == null:
			return {"error": "RULES_FAILURE"}
		TurnManager.setup(session)
	else:
		session = GameSessionState.from_snapshot(MatchSnapshotDto.from_dictionary(request.get("snapshot", {})), ScoringRules.create_default(), rules)
		if session == null:
			return {"error": "RULES_FAILURE"}
		if session.is_over():
			return {"error": "MATCH_FINISHED"}
		var seat: StringName = StringName(request.get("seat", ""))
		if action == "resign":
			if not TurnManager.resign(session, seat):
				return {"error": "INVALID_PLAYER"}
		elif action == "ai_move":
			if seat != TurnEnums.AI_PLAYER_ID or not TurnManager.is_awaiting_ai_action(session):
				return {"error": "NOT_AI_TURN"}
			var ai_error: String = _play_server_ai(session, int(request.get("difficulty", -1)))
			if not ai_error.is_empty():
				return {"error": ai_error}
		elif seat != session.get_turn_state().active_player_id:
			return {"error": "NOT_YOUR_TURN"}
		elif action == "place":
			var staged: Array[TileSnapshot] = []
			for placement: Dictionary in request.get("placements", []):
				var tile: TileDefinition = session.deck_tile(seat, StringName(placement.tileId))
				if tile == null:
					return {"error": "TILE_NOT_AVAILABLE"}
				staged.append(TileSnapshot.create(tile, Vector2i(int(placement.x), int(placement.y)), int(placement.rotation)))
			var result: LineResult = MoveCommitter.commit_line(session, seat, staged)
			if result == null or not result.was_committed():
				return {"error": "INVALID_MOVE" if result == null else result.get_rejection_name()}
			TurnManager.resolve(session, result)
		elif action == "swap":
			var ids: Array[StringName] = []
			for tile_id: String in request.get("tileIds", []):
				ids.append(StringName(tile_id))
			var swapped: int = session.request_swap(seat, ids)
			if swapped <= 0:
				return {"error": "INVALID_SWAP"}
			TurnManager.resolve_swap(session, swapped)
		else:
			return {"error": "INVALID_ACTION"}
	# Skip an impossible turn by the same rule as local play, with no client
	# allowed to assert that no move exists.
	if not session.is_over():
		var active: StringName = session.get_turn_state().active_player_id
		if LegalMoveGenerator.generate_with_report(session.get_board(), session.deck_for(active), {}, 1).is_empty():
			TurnManager.resolve_no_valid_move(session)
	if not session.verify_tile_conservation().is_empty():
		return {"error": "RULES_FAILURE"}
	return {"snapshot": session.to_snapshot().to_dictionary(), "views": {
		"human": view_for(session, TurnEnums.HUMAN_PLAYER_ID),
		"ai": view_for(session, TurnEnums.AI_PLAYER_ID),
	}}

static func _play_server_ai(session: GameSessionState, difficulty: int) -> String:
	if not AiEnums.is_valid_difficulty(difficulty):
		return "INVALID_DIFFICULTY"
	var deck: Array[TileDefinition] = session.deck_for(TurnEnums.AI_PLAYER_ID)
	if not deck.is_empty():
		var coordinator: AiCoordinator = AiCoordinator.create(difficulty)
		var cancellation := AiCancellationToken.new()
		cancellation.deadline_msec = Time.get_ticks_msec() + 12000
		var decision: AiDecision = coordinator.choose_move(session, deck, cancellation)
		if decision == null:
			return "AI_DECISION_FAILED"
		if decision.has_line():
			for tile: TileSnapshot in decision.line:
				if not session.holds_deck_tile(TurnEnums.AI_PLAYER_ID, tile.get_tile_id()) \
					or not session.set_active_tile(TurnEnums.AI_PLAYER_ID, tile.get_tile()):
					return "INVALID_AI_LINE"
			var result: LineResult = MoveCommitter.commit_line(session, TurnEnums.AI_PLAYER_ID, decision.line)
			if result == null or not result.was_committed():
				return "INVALID_AI_LINE"
			TurnManager.resolve(session, result)
			return ""
		if not decision.is_swap_move():
			return "AI_DECISION_FAILED"
	var supply: int = session.remaining_tile_count()
	var offer: Array[StringName] = []
	for index: int in range(mini(deck.size(), supply)):
		offer.append(deck[index].tile_id)
	var swapped: int = session.request_swap(TurnEnums.AI_PLAYER_ID, offer) if not offer.is_empty() else 0
	TurnManager.resolve_swap(session, swapped)
	return ""

static func view_for(session: GameSessionState, seat: StringName) -> Dictionary:
	var board: Array = []
	for cell: Vector2i in session.get_board().get_occupied_cells():
		var tile: TileSnapshot = session.get_board().get_tile(cell)
		board.append({"tile": tile.get_tile().to_dto().to_dictionary(), "cell": [cell.x, cell.y], "rotation": tile.get_rotation()})
	var hand: Array = []
	for tile: TileDefinition in session.deck_for(seat):
		hand.append(tile.to_dto().to_dictionary())
	var dto: MatchSnapshotDto = session.to_snapshot()
	return {
		"board": board, "hand": hand, "seat": String(seat),
		"opponentTileCount": session.deck_count(TurnEnums.opponent_of(seat)),
		"remainingTiles": session.remaining_tile_count(),
		"potTiles": session.remaining_tile_faces(),
		"turn": dto.turn, "ledger": dto.ledger, "scoredHandIds": dto.scored_hand_ids,
		"outcome": dto.outcome, "endReason": dto.end_reason,
		"history": dto.history, "result": MatchResult.build(session).to_dictionary(),
	}
