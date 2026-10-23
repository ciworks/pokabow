extends SceneTree

class DiagnosticController extends GameSessionController:
	func autosave() -> bool:
		return true
	func _skip_human_turn_without_move() -> void:
		print("CHECK MOVES start ", Time.get_ticks_msec())
		super._skip_human_turn_without_move()
		print("CHECK MOVES end ", Time.get_ticks_msec())
	func _after_state_change() -> void:
		print("AFTER STATE start ", Time.get_ticks_msec())
		super._after_state_change()
		print("AFTER STATE end ", Time.get_ticks_msec())

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var controller := DiagnosticController.new()
	controller.save_path = "res://.tmp-resume-copy.json"
	controller.session_started.connect(func() -> void: print("RESTORED ", Time.get_ticks_msec()))
	root.add_child(controller)
	print("SCREEN load start ", Time.get_ticks_msec())
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	root.add_child(screen)
	print("SCREEN attach start ", Time.get_ticks_msec())
	screen.attach_controller(controller)
	print("SCREEN attached ", Time.get_ticks_msec())
	print("RESUME start ", Time.get_ticks_msec())
	var ok: bool = controller.resume_match()
	print("RESUME end ", ok, " ", Time.get_ticks_msec())
	for second: int in range(10):
		await create_timer(1.0).timeout
		print("HEARTBEAT ", second, " ", Time.get_ticks_msec())
	screen.free()
	controller.free()
	quit(0 if ok else 1)
