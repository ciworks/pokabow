extends TestCase

const SAVE_PATH: String = "user://test_turn_timer.json"

func _controller() -> GameSessionController:
	var controller := GameSessionController.new()
	controller.save_path = SAVE_PATH
	controller.start_new_match(&"untimed-turn-test", 4242, AiEnums.Difficulty.EASY)
	return controller

func _release(controller: GameSessionController) -> void:
	controller.clear_saved_match()
	controller.free()

func test_elapsed_time_and_stale_deadlines_never_pass_a_turn() -> void:
	var controller := _controller()
	var session: GameSessionState = controller.get_session()
	var turn: TurnState = session.get_turn_state()
	turn.deadline_unix_seconds = Time.get_unix_time_from_system() - 600.0
	turn.remaining_seconds = 0.0
	var tile: TileDefinition = controller.human_deck()[0]
	controller.stage_tile(tile.tile_id, Vector2i(5, 5))
	check(controller.has_pending(), "opening line is staged")
	controller.update_turn_clock(Time.get_unix_time_from_system() + 3600.0)
	check_eq(turn.active_player_id, TurnEnums.HUMAN_PLAYER_ID, "elapsed time does not pass the turn")
	check_eq(turn.turn_number, 1, "elapsed time does not advance turn number")
	check(controller.has_pending(), "elapsed time preserves the staged line")
	check_eq(turn.deadline_unix_seconds, 0.0, "legacy deadline is discarded")
	check_eq(controller.turn_seconds_left(), 0, "no countdown remains")
	_release(controller)

func test_move_remains_legal_after_an_old_deadline() -> void:
	var controller := _controller()
	var session: GameSessionState = controller.get_session()
	var move: AiMoveCandidate = LegalMoveGenerator.generate(controller.get_board(), controller.human_deck())[0]
	for tile: TileSnapshot in move.snapshots:
		controller.stage_tile(tile.get_tile_id(), tile.get_cell(), tile.get_rotation())
	session.get_turn_state().deadline_unix_seconds = Time.get_unix_time_from_system() - 1.0
	var result: LineResult = controller.commit_line()
	check(result != null and result.was_committed(), "a legal move commits after a legacy deadline")
	check_eq(session.move_count(), 1, "one placement is recorded")
	_release(controller)

func test_save_resume_keeps_the_pending_player_without_a_clock() -> void:
	var controller := _controller()
	controller.get_session().get_turn_state().deadline_unix_seconds = Time.get_unix_time_from_system() - 600.0
	controller.save_match()
	var resumed := GameSessionController.new()
	resumed.save_path = SAVE_PATH
	check(resumed.resume_match(), "legacy timed save resumes")
	if resumed.get_session() != null:
		var turn: TurnState = resumed.get_session().get_turn_state()
		check_eq(turn.active_player_id, TurnEnums.HUMAN_PLAYER_ID, "the same player retains the move")
		check_eq(turn.turn_number, 1, "resume does not pass the turn")
		check_eq(turn.deadline_unix_seconds, 0.0, "resume clears the old deadline")
		check_eq(turn.remaining_seconds, 0.0, "resume clears the old countdown")
	_release(resumed)
	controller.free()

func test_legacy_timeout_entry_points_are_inert() -> void:
	var controller := _controller()
	var session: GameSessionState = controller.get_session()
	check(not TurnManager.elapse_turn(session, 100000.0), "elapsed time cannot end a turn")
	check_eq(TurnManager.resolve_timeout(session), TurnEnums.MatchPhase.AWAIT_ACTION,
		"legacy timeout leaves the action phase unchanged")
	check_eq(session.get_turn_state().turn_number, 1, "legacy timeout cannot advance play")
	_release(controller)
