extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(540, 960)
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame
	var layer: FloatingScores = screen.floating_scores
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, false)
	layer.spawn(Vector2(270, 450), 148)
	var label: Label = layer.get_child(0)
	var animations: Array[Tween] = get_processed_tweens()
	for animation: Tween in animations:
		animation.pause()
		animation.custom_step(0.12)
	assert(label.modulate.a < 0.7, "score briefly dims for its flash")
	for animation: Tween in animations:
		animation.custom_step(0.17)
	assert(label.modulate.a > 0.9, "score returns to full visibility")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.tmp/score-popup-preview.png")
	for animation: Tween in animations:
		animation.custom_step(1.0)
	await process_frame
	await process_frame
	assert(layer.active_count() == 0, "animated score disappears")
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, true)
	layer.spawn(Vector2(530, 10), 12345)
	label = layer.get_child(0)
	var start: Vector2 = label.position
	animations = get_processed_tweens()
	for animation: Tween in animations:
		animation.pause()
		animation.custom_step(0.3)
	assert(label.position.x >= 0.0 and label.get_rect().end.x <= layer.size.x, "large total stays within the screen")
	assert(label.position == start and label.modulate.a == 1.0, "reduced motion holds without flashing or moving")
	for animation: Tween in animations:
		animation.custom_step(1.0)
	await process_frame
	await process_frame
	assert(layer.active_count() == 0, "reduced-motion score disappears")
	print("POPUP VISUAL CHECK PASS: flash, disappearance, large-total bounds, reduced motion")
	quit()
