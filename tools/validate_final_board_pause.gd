extends Node
## Scene-based check of the final move-to-results handoff.

var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _capture(name: String) -> void:
	var folder: String = OS.get_environment("FINAL_BOARD_QA_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(folder.path_join(name + ".png")) == OK,
		"capture saved: " + name)


func _run() -> void:
	var suite: TestCase = load("res://tests/integration/test_game_screen.gd").new()
	for method: String in [
		"test_results_mark_the_winner_without_sweeping_panels",
		"test_the_summary_panel_shows_the_final_breakdown_and_restarts",
		"test_rival_final_move_finishes_before_results_cover_board",
	]:
		suite.call(method)
	for message: String in suite.failures:
		_check(false, message)
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	add_child(screen)
	var controller := GameSessionController.new()
	controller.save_path = "user://final_board_pause_qa.json"
	screen.add_child(controller)
	screen.attach_controller(controller)
	controller.start_new_match("final-board-pause-qa", 42)
	var session: GameSessionState = controller.get_session()
	session.finish(TurnEnums.MatchOutcome.HUMAN_WIN, TurnEnums.EndReason.BOARD_FULL)
	screen._on_match_ended(MatchResult.build(session))
	_check(not screen.summary_overlay.visible, "player's final board remains visible")
	_check(not screen._final_board_pause_timer.is_stopped(), "final board pause timer starts")
	_check(screen.human_score_value.text == str(controller.human_score())
		and screen.ai_score_value.text == str(controller.ai_score()), "final scores stay visible during the pause")
	_check(not screen.board_input.enabled, "finished match cannot accept moves during the pause")
	await get_tree().create_timer(GameScreen.FINAL_BOARD_PAUSE_SECONDS * 0.5).timeout
	_check(not screen.summary_overlay.visible, "results remain hidden during the board pause")
	await _capture("final-board-pause")
	await get_tree().create_timer(GameScreen.FINAL_BOARD_PAUSE_SECONDS * 0.6).timeout
	_check(screen.summary_overlay.visible, "results open after the board pause")
	await _capture("final-board-results")
	controller.start_new_match("final-board-pause-restart", 43)
	session = controller.get_session()
	session.finish(TurnEnums.MatchOutcome.AI_WIN, TurnEnums.EndReason.BOARD_FULL)
	screen._on_match_ended(MatchResult.build(session))
	_check(not screen.summary_overlay.visible, "rival result also pauses")
	controller.start_new_match("final-board-pause-cancel", 44)
	_check(screen._final_board_pause_timer.is_stopped() and screen._pending_match_result == null,
		"new match cancels pending results")
	await get_tree().create_timer(GameScreen.FINAL_BOARD_PAUSE_SECONDS + 0.1).timeout
	_check(not screen.summary_overlay.visible, "old result never covers a new match")
	session = controller.get_session()
	session.finish(TurnEnums.MatchOutcome.AI_WIN, TurnEnums.EndReason.RESIGNATION)
	screen._on_match_ended(MatchResult.build(session))
	_check(screen.summary_overlay.visible, "resignation result opens immediately")
	screen.queue_free()
	print("[Final board pause QA] %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
