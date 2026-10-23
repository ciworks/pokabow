extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(390,844)
	var suite: TestCase = load("res://tests/integration/test_game_screen.gd").new()
	var screen: GameScreen = suite._host_screen()
	for i: int in range(8):
		await process_frame
	var view := screen.summary_overlay as MatchEndPresentation
	print("Reduced motion: ", AccessibilitySettings.reduced_motion())
	var session: GameSessionState = screen.controller.get_session()
	session.finish(TurnEnums.MatchOutcome.HUMAN_WIN, TurnEnums.EndReason.TILE_SOURCE_EXHAUSTED)
	var begin: int = Time.get_ticks_msec()
	screen.controller._after_state_change()
	var frames: int = 0
	var spark_frames: int = 0
	var pulse_max: float = 0
	var samples: Array[float] = [0.0,0.15,0.4,0.65,0.9]
	var sample: int = 0
	while Time.get_ticks_msec() - begin < 1100:
		await RenderingServer.frame_post_draw
		frames += 1
		if view._accents[0].sparkle_alpha > 0.1:
			spark_frames += 1
		pulse_max = maxf(pulse_max, view._accents[0].pulse)
		if sample < samples.size() and (Time.get_ticks_msec()-begin)/1000.0 >= samples[sample]:
			print("Frame ", frames, " wall ms=",Time.get_ticks_msec()-begin," timeline=",view._elapsed," opacity=",view._card.self_modulate.a," pulse=",view._accents[0].pulse," sparkles=",view._accents[0].sparkle_alpha)
			sample += 1
		await process_frame
	print("Rendered frames=",frames," visible sparkle frames=",spark_frames," maximum pulse=",pulse_max)
	screen.free()
	quit()
