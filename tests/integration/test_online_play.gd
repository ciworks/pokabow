extends "res://tests/harness/test_case.gd"

func _new_match() -> Dictionary:
	return OnlineRules.execute({"action": "create", "matchId": "online-test", "seed": 42})

func test_private_views_and_opposite_seats() -> void:
	var result: Dictionary = _new_match()
	check(result.has("snapshot"), "server creates a complete restorable match")
	if not result.has("snapshot"):
		return
	var a: Dictionary = result.views.human
	var b: Dictionary = result.views.ai
	check_eq(a.hand.size(), DeckRules.DEFAULT_DECK_SIZE, "first player receives their hand")
	check_eq(b.hand.size(), DeckRules.DEFAULT_DECK_SIZE, "second player receives their hand")
	for tile: Dictionary in b.hand:
		check(not JSON.stringify(a).contains(String(tile.tile_id)), "opponent tile identity never appears in the first player's view")
	for key: String in ["seed", "tile_source", "decks", "snapshot"]:
		check(not a.has(key), "public projection omits " + key)
	check_eq(a.potTiles.size(), a.remainingTiles, "online view contains every undrawn tile face")
	check_eq(a.potTiles, b.potTiles, "both seats receive the same public pot inventory")
	for face: Dictionary in a.potTiles:
		check(not face.has("tile_id"), "online pot inventory omits generated IDs and draw order")
		check_eq(face.edges.size(), TileEnums.EDGE_COUNT, "online inventory includes each tile's four edges")
	a["matchId"] = "online-test"
	b["matchId"] = "online-test"
	var view_a: OnlineSessionView = OnlineSessionView.from_response(a)
	var view_b: OnlineSessionView = OnlineSessionView.from_response(b)
	check_eq(view_a.get_turn_state().active_player_id, &"human", "first account owns the opening turn")
	check_eq(view_b.get_turn_state().active_player_id, &"ai", "second account sees their opponent opening")
	check_eq(view_b.deck_count(&"human"), DeckRules.DEFAULT_DECK_SIZE, "both clients use the existing own-hand gestures")
	check_eq(view_b.deck_count(&"ai"), 0, "opponent hand is not synthesized")
	check_eq(view_b.opponent_tile_count, DeckRules.DEFAULT_DECK_SIZE, "public opponent count is retained without revealing tiles")
	check_eq(view_a.remaining_tile_faces().size(), view_a.remaining_tile_count(), "online client keeps the public pot inventory")
	var hud_controller := OnlineGameController.new()
	hud_controller._session = view_b
	check_eq(hud_controller.opponent_deck_count(), DeckRules.DEFAULT_DECK_SIZE, "HUD receives only the public opponent count")
	hud_controller.free()
	b["opponentTileCount"] = 2
	check_eq(OnlineSessionView.from_response(b).opponent_tile_count, 2, "depleted opponent hand updates its public count")

func test_authoritative_swap_turns_timeout_and_resignation() -> void:
	var initial: Dictionary = _new_match()
	var before: String = JSON.stringify(initial.snapshot)
	var refused: Dictionary = OnlineRules.execute({"action": "swap", "seat": "ai", "snapshot": initial.snapshot, "tileIds": [initial.views.ai.hand[0].tile_id]})
	check_eq(refused.get("error"), "NOT_YOUR_TURN", "out-of-turn actions are refused")
	check_eq(JSON.stringify(initial.snapshot), before, "rejected commands do not mutate input")
	var swap: Dictionary = OnlineRules.execute({"action": "swap", "seat": "human", "snapshot": initial.snapshot, "tileIds": [initial.views.human.hand[0].tile_id]})
	check(swap.has("snapshot"), "owned tile swap is accepted")
	check_eq(swap.snapshot.turn.active_player_id, "ai", "swap hands over play")
	check_eq(swap.snapshot.ledger.events.size(), 0, "swap awards no points")
	var timeout: Dictionary = OnlineRules.execute({"action": "timeout", "snapshot": swap.snapshot})
	check(timeout.has("snapshot"), "timeout succeeds: %s" % str(timeout.get("error", "")))
	if not timeout.has("snapshot"):
		return
	check_eq(timeout.snapshot.turn.active_player_id, "human", "timeout passes exactly one turn")
	check_eq(timeout.snapshot.decks, swap.snapshot.decks, "timeout spends no tiles")
	var ended: Dictionary = OnlineRules.execute({"action": "resign", "seat": "ai", "snapshot": timeout.snapshot})
	check_eq(ended.snapshot.outcome, TurnEnums.MatchOutcome.HUMAN_WIN, "opponent resignation produces a win")
	ended.views.ai["matchId"] = "online-test"
	check_eq(OnlineSessionView.from_response(ended.views.ai).get_outcome(), TurnEnums.MatchOutcome.AI_WIN, "resigning account sees a loss")

func test_accepted_placement_matches_domain_and_rejects_forged_tiles() -> void:
	var initial: Dictionary = _new_match()
	var session: GameSessionState = GameSessionState.from_snapshot(MatchSnapshotDto.from_dictionary(initial.snapshot),
		ScoringRules.create_default(), load(GameSessionController.TILE_RULES_RESOURCE))
	var moves: Array = LegalMoveGenerator.generate_with_report(session.get_board(), session.deck_for(&"human"), {}, 1)
	check(not moves.is_empty(), "fixture has a legal opening")
	if moves.is_empty():
		return
	var candidate: AiMoveCandidate = moves[0]
	var placements: Array = []
	for tile: TileSnapshot in candidate.snapshots:
		placements.append({"tileId": String(tile.get_tile_id()), "x": tile.get_cell().x, "y": tile.get_cell().y, "rotation": tile.get_rotation()})
	var result: Dictionary = OnlineRules.execute({"action": "place", "snapshot": initial.snapshot, "seat": "human", "placements": placements})
	check(result.has("snapshot"), "legal placement accepted by server")
	var expected: LineResult = MoveCommitter.commit_line(session, &"human", candidate.snapshots)
	check_eq(result.snapshot.ledger, session.get_ledger().to_dictionary(), "server scoring exactly matches local domain")
	check_eq(result.snapshot.board.size(), expected.staged_count(), "all line tiles commit together")
	placements[0].tileId = initial.views.ai.hand[0].tile_id
	check_eq(OnlineRules.execute({"action": "place", "snapshot": initial.snapshot, "seat": "human", "placements": placements}).get("error"), "TILE_NOT_AVAILABLE", "opponent tiles cannot be played")

class FakeApi extends OnlineGameApiClient:
	var sent: Array[Dictionary] = []
	func _send_http(_http: HTTPRequest, url: String, _headers: PackedStringArray, method: int, body: String) -> int:
		sent.append({"url": url, "method": method, "body": body})
		return OK
	func complete(code: int, data: Dictionary, result: int = HTTPRequest.RESULT_SUCCESS) -> void:
		_completed(result, code, PackedStringArray(), JSON.stringify(data).to_utf8_buffer(), _request, _request_kind)

func _response() -> Dictionary:
	var data: Dictionary = _new_match().views.human
	data.merge({"matchId": "test-match", "version": 1, "status": "active", "deadline": 1060.0, "serverTime": 1000.0, "opponent": {"displayName": "Rival", "connected": true}})
	return data

func test_client_retries_same_command_and_locks_input() -> void:
	var api: FakeApi = FakeApi.new()
	api.set_credentials("token", "online-test-user")
	api.start("test-match")
	api._process(0.0)
	api.complete(200, _response())
	var controller: OnlineGameController = OnlineGameController.new()
	controller.attach_client(api)
	check(controller.is_human_turn(), "fresh own turn allows input")
	check(api.submit({"action": "swap", "tileIds": [controller.human_deck()[0].tile_id]}), "command queues")
	check(not controller.is_human_turn(), "pending command locks input")
	api._process(0.0)
	var original_body: String = api.sent.back().body
	api.complete(0, {}, HTTPRequest.RESULT_CANT_CONNECT)
	check(not controller.is_human_turn(), "disconnected client cannot change committed state")
	api._process(2.0)
	check_eq(api.sent.back().body, original_body, "retry preserves command ID and expected version")
	api.complete(409, _response())
	check(not api.has_pending_command(), "authoritative conflict clears rejected command")
	check(controller.is_human_turn(), "fresh conflict state allows correcting a move")
	controller._seconds_at_sync = 0.0
	controller.update_turn_clock()
	check_eq(controller.turn_number(), 1, "client clock never advances the server turn")
	check(not controller.is_human_turn(), "zero clock blocks local input")
	check_eq(controller.match_snapshot_dictionary(), {}, "online match cannot enter local snapshot sync")
	api._clear_resume()
	controller.free()
	api.free()

func test_game_screen_uses_online_controller_and_keeps_resign_available() -> void:
	var api: FakeApi = FakeApi.new()
	api.connected = true
	api.state = _response()
	var controller: OnlineGameController = OnlineGameController.new()
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	screen.add_child(controller)
	screen.attach_controller(controller)
	controller.attach_client(api)
	check_eq(screen.human_score_value.text, "0", "screen draws the server score")
	check_eq(controller.human_deck_count(), DeckRules.DEFAULT_DECK_SIZE, "screen receives the private hand")
	check(not screen.get_node("%RestartButton").visible, "online game cannot restart locally")
	check(screen.get_node("%ResignButton").visible, "online resignation remains available")
	check(not controller._ai_scheduled, "opponent never runs a local AI")
	screen.free()
	api.free()
