extends TestCase

const SAVE_PATH: String = "user://test_turn_timer.json"


func _controller() -> GameSessionController:
	var controller := GameSessionController.new()
	controller.save_path = SAVE_PATH
	controller.start_new_match(&"turn-timer-test", 4242, AiEnums.Difficulty.EASY)
	return controller


func _release(controller: GameSessionController) -> void:
	controller.clear_saved_match()
	controller.free()


func test_each_player_has_sixty_seconds_before_timeout() -> void:
	var controller := _controller()
	var turn: TurnState = controller.get_session().get_turn_state()
	for player: StringName in [TurnEnums.HUMAN_PLAYER_ID, TurnEnums.AI_PLAYER_ID]:
		check_eq(turn.active_player_id, player, "expected player starts their turn")
		check_eq(controller.turn_seconds_left(), 60, "turn starts with sixty seconds")
		var deadline: float = turn.deadline_unix_seconds
		controller.update_turn_clock(deadline - 30.0)
		check_eq(turn.active_player_id, player, "turn does not expire after thirty seconds")
		check_eq(controller.turn_seconds_left(), 30, "thirty seconds remain at halfway")
		controller.update_turn_clock(deadline - 0.01)
		check_eq(turn.active_player_id, player, "player keeps the full final second")
		controller.update_turn_clock(deadline)
		check_eq(turn.active_player_id, TurnEnums.opponent_of(player), "turn passes at sixty seconds")
	_release(controller)


func test_timeout_discards_preview_without_scoring_or_consuming_tiles() -> void:
	var controller := _controller()
	var session: GameSessionState = controller.get_session()
	var turn: TurnState = session.get_turn_state()
	var deck: Array[TileDefinition] = controller.human_deck()
	controller.stage_tile(deck[0].tile_id, Vector2i(5, 5))
	check(controller.has_pending(), "a tile is staged")
	var passed: Array[StringName] = []
	controller.turn_passed.connect(func(player: StringName) -> void: passed.append(player))
	controller.update_turn_clock(turn.deadline_unix_seconds - 0.01)
	check_eq(controller.turn_seconds_left(), 1, "last fractional second keeps one segment")
	check(controller.is_human_turn(), "the final second still belongs to the human")
	controller.update_turn_clock(turn.deadline_unix_seconds)
	check(not controller.has_pending(), "timeout clears the unconfirmed line")
	check_eq(controller.get_board().occupied_count(), 0, "timeout commits no tiles")
	check_eq(controller.human_score(), 0, "timeout scores nothing")
	check_eq(controller.human_deck(), deck, "the held deck is preserved")
	check_eq(session.move_count(), 0, "timeout records no placement")
	check_eq(turn.active_player_id, TurnEnums.AI_PLAYER_ID, "AI receives the turn")
	check_eq(turn.turn_number, 2, "exactly one handover")
	check_eq(controller.turn_seconds_left(), 60, "next player receives a fresh clock")
	check_eq(passed, [TurnEnums.HUMAN_PLAYER_ID], "the pass event fires once")
	_release(controller)


func test_repeated_timeouts_alternate_and_do_not_end_the_match() -> void:
	var controller := _controller()
	var turn: TurnState = controller.get_session().get_turn_state()
	for index: int in range(6):
		controller.update_turn_clock(turn.deadline_unix_seconds)
		check_eq(turn.turn_number, index + 2, "every timeout advances one turn")
		check_eq(turn.active_player_id, TurnEnums.AI_PLAYER_ID if index % 2 == 0 else TurnEnums.HUMAN_PLAYER_ID, "ownership alternates")
		check_eq(controller.turn_seconds_left(), 60, "every turn gets 60 seconds")
	check(not controller.is_over(), "timeouts add no early end rule")
	_release(controller)


func test_late_commit_is_rejected_and_next_turn_is_not_consumed() -> void:
	var controller := _controller()
	var session: GameSessionState = controller.get_session()
	var move: AiMoveCandidate = LegalMoveGenerator.generate(controller.get_board(), controller.human_deck())[0]
	for tile: TileSnapshot in move.snapshots:
		controller.stage_tile(tile.get_tile_id(), tile.get_cell(), tile.get_rotation())
	session.get_turn_state().deadline_unix_seconds = Time.get_unix_time_from_system() - 1.0
	var result: LineResult = controller.commit_line()
	check(result == null or not result.was_committed(), "a late click cannot commit")
	check_eq(session.move_count(), 0, "late proposal scores nothing")
	check_eq(session.get_turn_state().turn_number, 2, "expiry passes once")
	controller.update_turn_clock()
	check_eq(session.get_turn_state().turn_number, 2, "another frame cannot repeat expiry")
	_release(controller)


func test_swap_starts_a_fresh_clock_and_late_ai_callback_cannot_play() -> void:
	var controller := _controller()
	var turn: TurnState = controller.get_session().get_turn_state()
	controller.update_turn_clock(turn.deadline_unix_seconds - 3.0)
	var ids: Array[StringName] = [controller.human_deck()[0].tile_id]
	check_eq(controller.request_swap(ids), 1, "ordinary swap succeeds")
	check_eq(controller.turn_seconds_left(), 60, "swap resets the next clock")
	turn.deadline_unix_seconds = Time.get_unix_time_from_system() - 1.0
	controller._on_ai_think_timeout()
	check(controller.is_human_turn(), "expired AI turn passes to human")
	check_eq(controller.get_session().move_count(), 0, "late AI callback cannot place")
	_release(controller)


func test_save_resume_preserves_deadline_and_expires_only_the_absent_turn() -> void:
	var controller := _controller()
	var turn: TurnState = controller.get_session().get_turn_state()
	turn.deadline_unix_seconds = Time.get_unix_time_from_system() + 12.0
	controller.update_turn_clock()
	controller.save_match()
	var resumed := GameSessionController.new()
	resumed.save_path = SAVE_PATH
	check(resumed.resume_match(), "timed save resumes")
	check_eq(resumed.get_session().get_turn_state().deadline_unix_seconds, turn.deadline_unix_seconds, "resume preserves the deadline")
	check(resumed.turn_seconds_left() <= 12 and resumed.turn_seconds_left() > 10, "resume does not grant 60 seconds")
	resumed.get_session().get_turn_state().deadline_unix_seconds = Time.get_unix_time_from_system() - 600.0
	resumed.save_match()
	var expired := GameSessionController.new()
	expired.save_path = SAVE_PATH
	check(expired.resume_match(), "expired save resumes")
	check_eq(expired.get_session().get_turn_state().turn_number, 2, "ten minutes away expires only the current turn")
	check_eq(expired.turn_seconds_left(), 60, "next player gets a full new turn")
	_release(expired)
	resumed.free()
	controller.free()


func test_old_saves_default_to_full_time_and_bad_clock_values_are_rejected() -> void:
	var controller := _controller()
	var dto: MatchSnapshotDto = controller.get_session().to_snapshot()
	dto.turn.erase("remaining_seconds")
	dto.turn.erase("deadline_unix_seconds")
	check(dto.is_valid(), "legacy saves without a clock remain valid")
	var restored: GameSessionState = GameSessionState.from_snapshot(dto, ScoringRules.create_default(), load(GameSessionController.TILE_RULES_RESOURCE))
	check_not_null(restored, "legacy save restores")
	if restored != null:
		check_eq(restored.get_turn_state().remaining_seconds, 60.0, "legacy turn receives full time")
	for bad: Variant in [-1.0, 61.0, "60", INF, NAN]:
		dto.turn["remaining_seconds"] = bad
		check(not dto.is_valid(), "malformed remaining time is rejected")
	_release(controller)


func test_stopped_match_ignores_clock_and_domain_refuses_early_timeout() -> void:
	var controller := _controller()
	var session: GameSessionState = controller.get_session()
	TurnManager.resolve_timeout(session)
	check_eq(session.get_turn_state().turn_number, 1, "unexpired turn cannot be forfeited")
	check(not TurnManager.elapse_turn(session, -1.0), "negative elapsed time is ignored")
	check(TurnManager.elapse_turn(session, 100.0), "elapsed time clamps at zero")
	TurnManager.resolve_timeout(session)
	check_eq(session.get_turn_state().remaining_seconds, 60.0, "excess elapsed time cannot consume the next turn")
	TurnManager.fail_recovery(session, TurnEnums.EndReason.RULES_FAILURE)
	controller.update_turn_clock(Time.get_unix_time_from_system() + 1000.0)
	check_eq(controller.turn_seconds_left(), 0, "stopped match has no timer")
	check_eq(session.get_turn_state().turn_number, 2, "stopped match cannot hand over")
	_release(controller)


func test_timer_border_loses_equal_lengths_and_disappears_at_zero() -> void:
	var outline := TurnTimerOutline.new()
	outline.size = Vector2(240, 70)
	outline.set_seconds_left(60)
	var full_length: float = _length(outline.remaining_path())
	for seconds: int in range(60, 0, -1):
		outline.set_seconds_left(seconds)
		check(absf(_length(outline.remaining_path()) - full_length * seconds / 60.0) < 0.01, "each second removes an equal perimeter segment")
	outline.set_seconds_left(0)
	check(outline.remaining_path().is_empty(), "no yellow remains at zero")
	outline.free()


func _length(path: PackedVector2Array) -> float:
	var result: float = 0.0
	for index: int in range(1, path.size()):
		result += path[index - 1].distance_to(path[index])
	return result
