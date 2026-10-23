extends Node
## Run as a scene so the project's autoloads and game screen are available.

var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var previous_dark: bool = AppearanceSettings.dark_mode
	if OS.get_environment("RESIGN_QA_DARK") == "1":
		AppearanceSettings.dark_mode = true
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	add_child(screen)
	var controller := GameSessionController.new()
	controller.save_path = "user://resign_design_qa.json"
	screen.add_child(controller)
	screen.attach_controller(controller)
	controller.start_new_match("resign-design-qa", 42)
	var dialog := screen.get_node("ResignConfirmationDialog") as Control
	var nav: GameBottomNavigation = screen.bottom_navigation
	_check(not nav.buttons.has(&"Share"), "Gameplay bar has no Share action")
	_check(nav.get_node("Actions").get_child(3) == nav.buttons[&"Resign"], "Resign follows Swap")
	_check(not nav.buttons[&"Resign"].disabled, "Resign is available in an active match")
	var flag_icon := nav.buttons[&"Resign"].get_node_or_null("Content/IconSurface/IconCenter/Icon") as TextureRect
	_check(flag_icon != null and flag_icon.texture != null, "Resign displays the flag icon")
	nav.buttons[&"Resign"].pressed.emit()
	_check(dialog.visible, "Resign opens the themed confirmation")
	var capture_path := OS.get_environment("RESIGN_QA_CAPTURE")
	if not capture_path.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(get_viewport().get_texture().get_image().save_png(capture_path) == OK, "Preview captured")
	_check(dialog.find_child("KeepPlayingButton", true, false).custom_minimum_size.y >= 48, "Cancel is a mobile touch target")
	_check(dialog.find_child("ConfirmResignButton", true, false).custom_minimum_size.y >= 48, "Confirm is a mobile touch target")
	(dialog.find_child("KeepPlayingButton", true, false) as Button).pressed.emit()
	_check(not dialog.visible and not controller.is_over(), "Keep playing dismisses without resigning")
	screen._on_resign_pressed()
	(dialog.find_child("ResignScrim", true, false) as Button).pressed.emit()
	_check(not dialog.visible and not controller.is_over(), "Outside tap dismisses without resigning")
	screen._on_resign_pressed()
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	dialog._input(escape)
	_check(not dialog.visible and not controller.is_over(), "Escape dismisses without resigning")
	screen._on_resign_pressed()
	(dialog.find_child("ConfirmResignButton", true, false) as Button).pressed.emit()
	_check(not dialog.visible and controller.is_over(), "Confirm resign ends the match")
	_check(controller.get_session().get_outcome() == TurnEnums.MatchOutcome.AI_WIN, "Rival wins after resignation")
	_check(screen.summary_overlay.visible, "Resignation shows the results screen")
	_check(nav.buttons[&"Resign"].disabled, "Resign is disabled after the match")
	screen._on_resign_pressed()
	_check(not dialog.visible, "Resign cannot reopen after the match")
	screen.queue_free()
	AppearanceSettings.dark_mode = previous_dark
	print("[Resign design QA] %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
