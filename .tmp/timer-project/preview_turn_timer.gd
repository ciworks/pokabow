extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i.ZERO
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	root.add_child(screen)
	var controller := GameSessionController.new()
	controller.save_path = "user://timer_preview_only.json"
	screen.attach_controller(controller)
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, false)
	for dimensions: Vector2i in [Vector2i(540, 960), Vector2i(360, 800), Vector2i(1280, 720)]:
		root.size = dimensions
		controller.start_new_match(&"timer-preview", 4242, AiEnums.Difficulty.EASY)
		await create_timer(0.6).timeout
		for seconds: int in [30, 20, 10, 1, 0]:
			var turn: TurnState = controller.get_session().get_turn_state()
			controller.update_turn_clock(turn.deadline_unix_seconds - seconds)
			await create_timer(0.35).timeout
			await RenderingServer.frame_post_draw
			var filename: String = "C:/Users/chima/development/polkabow/.tmp/timer-%dx%d-%02d.png" % [dimensions.x, dimensions.y, seconds]
			root.get_texture().get_image().save_png(filename)
			print(filename)
		print("TIMEOUT TOAST: ", screen._toast_label.text)
		controller.update_turn_clock(controller.get_session().get_turn_state().deadline_unix_seconds - 10.0)
		var art: Control = screen.ai_score_panel.get_node("AiScoreBox")
		var origin: Vector2 = art.position
		await create_timer(0.08).timeout
		print("RIVAL SHAKE OFFSET: ", art.position - origin)
		await create_timer(0.3).timeout
		print("RIVAL SHAKE RESTORED: ", art.position.is_equal_approx(origin))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/Users/chima/development/polkabow/.tmp/timer-%dx%d-rival-10.png" % [dimensions.x, dimensions.y])
	controller.clear_saved_match()
	screen.free()
	controller.free()
	quit()
