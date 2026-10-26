extends Node

var failures: PackedStringArray = PackedStringArray()
var assertions: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await test_verified_rival_waits_in_overview_then_reveals_its_move()
	print("[verified-ai] assertions: %d failures: %d" % [assertions, failures.size()])
	for failure: String in failures:
		print("[verified-ai] FAIL " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func check(condition: bool, message: String) -> bool:
	assertions += 1
	if not condition:
		failures.append(message)
	return condition


func check_eq(actual: Variant, expected: Variant, message: String) -> bool:
	return check(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func test_verified_rival_waits_in_overview_then_reveals_its_move() -> void:
	var created: Dictionary = OnlineRules.execute({"action": "create", "matchId": "verified-presentation", "seed": 42})
	if not check(created.has("snapshot"), "fixture creates a match"):
		return
	var session: GameSessionState = GameSessionState.from_snapshot(
		MatchSnapshotDto.from_dictionary(created.snapshot), ScoringRules.create_default(),
		load(GameSessionController.TILE_RULES_RESOURCE))
	var candidates: Array = LegalMoveGenerator.generate_with_report(
		session.get_board(), session.deck_for(TurnEnums.HUMAN_PLAYER_ID), {}, 1)
	if not check(not candidates.is_empty(), "fixture has an opening line"):
		return
	var line: AiMoveCandidate = candidates[0]
	var placements: Array = []
	for tile: TileSnapshot in line.snapshots:
		placements.append({"tileId": String(tile.get_tile_id()), "x": tile.get_cell().x,
			"y": tile.get_cell().y, "rotation": tile.get_rotation()})
	var human: Dictionary = OnlineRules.execute({"action": "place", "snapshot": created.snapshot,
		"seat": "human", "placements": placements})
	if not check(human.has("snapshot"), "server accepts the opening line"):
		return
	var rival: Dictionary = OnlineRules.execute({"action": "ai_move", "snapshot": human.snapshot,
		"seat": "ai", "difficulty": AiEnums.Difficulty.EASY})
	if not check(rival.has("snapshot"), "server commits a rival move"):
		return

	var opening: Dictionary = _response(created.views.human, 1)
	var result: Dictionary = _response(rival.views.human, 2)
	var api: OnlineGameApiClient = OnlineGameApiClient.new()
	api.connected = true
	api.match_id = "verified-presentation"
	api.state = opening
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	get_tree().root.add_child(screen)
	var controller: VerifiedAiGameController = VerifiedAiGameController.new()
	screen.add_child(controller)
	await get_tree().process_frame
	await get_tree().process_frame
	screen.attach_controller(controller)
	controller.attach_client(api)
	screen.board_view.set_close_view(true)
	check(screen.board_view.zoom > BoardView.OVERVIEW_ZOOM,
		"fixture starts zoomed in")
	for tile: TileSnapshot in line.snapshots:
		check(controller.stage_tile(tile.get_tile_id(), tile.get_cell(), tile.get_rotation()),
			"human tile stages")
	var before: int = controller.get_session().move_count()
	controller.commit_line()
	check(controller._awaiting_result, "submission waits for the server's decision")
	check(screen.board_view.zoom > BoardView.OVERVIEW_ZOOM,
		"submission keeps the close view")
	check(not controller.is_human_turn(), "input is locked during the pause")
	controller.apply_response(result)
	check_eq(controller.get_session().move_count(), before + 1,
		"the human line appears before the rival line")
	check_eq(controller.get_session().get_ledger().total_for(TurnEnums.HUMAN_PLAYER_ID),
		OnlineSessionView.from_response(_response(human.views.human, 2)).get_ledger().total_for(TurnEnums.HUMAN_PLAYER_ID),
		"human points come from the authoritative score events")
	check_eq(controller.get_session().get_ledger().total_for(TurnEnums.AI_PLAYER_ID), 0,
		"rival points remain hidden during human feedback")
	check_eq(controller.remaining_tiles(), int(human.views.human.remainingTiles),
		"the tile pot reflects only the completed human turn")
	check_eq(controller.remaining_tile_faces().size(), controller.remaining_tiles(),
		"the temporary pot inventory matches its count")
	check(screen.board_view.zoom > BoardView.OVERVIEW_ZOOM,
		"human score and Gems appear in the close view")
	check(not controller._presentation_waiting, "thinking has not begun before human feedback settles")
	check(screen.gem_travel_layer.active_flights() > 0,
		"human Gems travel before the board zooms out")
	screen._process(0.0)
	check(screen.board_view.zoom > BoardView.OVERVIEW_ZOOM,
		"board waits for the Gem flight")
	screen.gem_travel_layer._process(100.0)
	check(screen.gem_pot_view.total() > 0, "human Gems arrive before the zoom out")
	screen.board_view.reveal_layer._process(100.0)
	screen.floating_scores.clear_all()
	for attempt: int in range(4):
		screen.deal_layer._process(100.0)
		await get_tree().process_frame
		screen._process(0.0)
		if controller._presentation_waiting:
			break
	check_eq(screen.board_view.zoom, BoardView.OVERVIEW_ZOOM,
		"board zooms out after human score and Gems settle")
	check(controller._presentation_waiting, "thinking begins after the zoom out")
	check_eq(controller._presentation_timer.wait_time, VerifiedAiGameController.MIN_THINKING_SECONDS,
		"thinking pause lasts three seconds")
	check_eq(screen.turn_indicator.text, GameScreen.RIVAL_THINKING_TEXT,
		"turn indicator explains the pause")
	check_eq(controller.get_session().move_count(), before + 1,
		"rival move remains hidden through thinking")
	controller._presentation_timer.stop()
	controller._on_presentation_pause_elapsed()
	check_eq(controller.get_session().move_count(), before + 2,
		"human and rival lines appear from the authoritative response")
	check_eq(screen.board_view.zoom, BoardView.OVERVIEW_ZOOM,
		"new server board stays in full overview")
	check(screen.rival_move_layer.is_playing(), "rival tiles fly to their actual cells")
	check(controller.ai_score() > 0, "fixture rival earned authoritative points")
	check_eq(int(screen.ai_score_value.text), 0,
		"rival score stays at its previous value while tiles travel")
	check_eq(screen.rival_move_layer._snapshots.size(),
		controller.get_session().last_move().placements.size(),
		"flight shows every tile in the rival's line")
	screen.rival_move_layer._process(screen.rival_move_layer.placement_duration() + 0.01)
	check_eq(int(screen.ai_score_value.text), controller.ai_score(),
		"rival points appear when its tiles land")
	check(screen.gem_travel_layer.active_flights() > 0,
		"rival Gems start only after its tiles land")
	check(not controller._presentation_waiting, "thinking pause ends after reveal")
	screen.free()
	api.free()


func _response(view: Dictionary, version: int) -> Dictionary:
	var data: Dictionary = view.duplicate(true)
	data.merge({"matchId": "verified-presentation", "version": version, "status": "active",
		"deadline": null, "serverTime": 1000.0,
		"opponent": {"displayName": "AI Rival", "connected": true}})
	return data
