extends SceneTree
## Runs real container layout across frames; the synchronous unit harness cannot
## expose a resize queue that never drains. Uses only its own temporary save.
## godot --headless --path . --script res://tools/validate_resume_layout.gd

class ObservedScreen extends GameScreen:
	var fit_calls: int = 0
	var layout_overflow: bool = false

	func _fit_deck_width() -> void:
		fit_calls += 1
		# Fail instead of hanging the test runner on the old resize feedback loop.
		if fit_calls > 128:
			layout_overflow = true
			return
		super._fit_deck_width()

var failures: int = 0
var assertions: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)


func _settle(screen: GameScreen, label: String) -> void:
	for frame: int in range(8):
		await process_frame
	_check(not screen.layout_overflow, label + ": container resize queue must settle")
	var calls: int = screen.fit_calls
	for frame: int in range(4):
		await process_frame
	_check(screen.fit_calls == calls, label + ": no continuing resize oscillation")
	var board_width: float = screen.deck_bar.size.x
	_check(absf(screen.deck_panel.custom_minimum_size.x - board_width) <= 1.0,
		label + ": rack must fill the available width independently of board zoom")
	_check(screen.deck_view.size.x > 0.0 and screen.deck_view.size.y > 0.0,
		label + ": hand has a usable layout")


func _run() -> void:
	var save_path: String = "user://test_resume_layout_%d.json" % OS.get_process_id()
	var original := GameSessionController.new()
	original.save_path = save_path
	_check(original.start_new_match(&"resume-layout-regression", 4242), "fixture starts")
	original.free()

	root.size = Vector2i(540, 960)
	var controller := GameSessionController.new()
	controller.save_path = save_path
	# Keep the fixture on the human turn while exercising layout and input.
	controller.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(controller)
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	screen.set_script(ObservedScreen)
	root.add_child(screen)
	screen.attach_controller(controller)
	_check(controller.resume_match(), "saved match resumes")
	await _settle(screen, "Resume 540x960")
	_check(controller.get_match_id() == &"resume-layout-regression", "Resume retains saved identity")
	_check(screen.deck_view.deck_size() == controller.human_deck().size(), "resumed hand is rendered")
	var tile_id: StringName = controller.human_deck()[0].tile_id
	screen.deck_view.tile_selected.emit(tile_id)
	_check(screen.deck_view.selected_tile_id() == tile_id, "tile selection responds after Resume")

	for viewport_size: Vector2i in [Vector2i(360, 800), Vector2i(540, 1200), Vector2i(1280, 720), Vector2i(540, 960)]:
		for zoom: float in [BoardView.OVERVIEW_ZOOM, BoardView.CLOSE_ZOOM, 1.5]:
			screen.fit_calls = 0
			root.size = viewport_size
			screen.board_view.zoom = zoom
			screen.board_view.resync()
			screen._fit_deck_width()
			await _settle(screen, "%s zoom %s" % [viewport_size, zoom])
	controller.clear_saved_match()
	screen.free()
	controller.free()
	print("[resume-layout] %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
