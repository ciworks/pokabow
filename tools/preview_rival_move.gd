extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _capture(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.tmp/rival-move-%s.png" % label)

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = Vector2i(540, 960)
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	root.add_child(screen)
	var controller := GameSessionController.new()
	controller.save_path = "user://rival_move_preview_%d.json" % OS.get_process_id()
	controller.process_mode = Node.PROCESS_MODE_DISABLED
	screen.add_child(controller)
	screen.attach_controller(controller)
	controller.start_new_match(&"rival-preview", 4242, AiEnums.Difficulty.EASY)
	await create_timer(3.0).timeout
	var turn: TurnState = controller.get_session().get_turn_state()
	turn.active_player_id = TurnEnums.AI_PLAYER_ID
	turn.phase = TurnEnums.MatchPhase.AWAIT_ACTION
	screen._refresh_all()
	await _capture("before")
	controller._on_ai_think_timeout()
	var layer: RivalMoveLayer = screen.rival_move_layer
	layer.set_process(false)
	if not layer.is_playing():
		push_error("Expected actual AI decision to start a move animation")
		controller.clear_saved_match()
		quit(1)
		return
	print("AI animated %d committed tiles and %d replacements" % [layer._snapshots.size(), layer._refill_count])
	await _capture("departing")
	layer._process(0.18)
	await _capture("flight-backs")
	layer._process(0.16)
	await _capture("flight-faces")
	layer._process(layer.placement_duration() - layer._elapsed + 0.01)
	await _capture("placed")
	layer._process(0.18)
	await _capture("refilling")
	root.size = Vector2i(360, 800)
	await _capture("refilling-360x800")
	layer._process(layer.total_duration())
	await _capture("complete-360x800")
	controller.clear_saved_match()
	screen.free()
	print("RIVAL MOVE PREVIEW COMPLETE")
	quit()
