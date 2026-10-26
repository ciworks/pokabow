extends Node
## Scene-level check for read-only onboarding, navigation and compact layouts.

var failures: Array[String] = []
var assertions: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var hub: HubScreen = load("res://scenes/hub/hub_screen.tscn").instantiate()
	add_child(hub)
	var replay_requests: Array[String] = []
	hub.tutorial_requested.connect(func() -> void: replay_requests.append("tutorial"))
	hub.get_node("%HowToPlayButton").pressed.emit()
	_check(replay_requests == ["tutorial"], "hub How to play requests one tutorial replay")
	hub.queue_free()
	await get_tree().process_frame
	var screen: TutorialScreen = load("res://scenes/tutorial/tutorial_screen.tscn").instantiate()
	add_child(screen)
	await get_tree().process_frame
	_check(screen.lesson_count() == 12, "the guide has an introduction and eleven lessons")
	_check(screen.step_index() == 0, "first page is the welcome")
	_check("no time limit" in String(TutorialScreen.LESSONS[9]["body"]).to_lower(),
		"turn lesson explains that moves have no time limit")
	_check("NO TIME LIMIT" in (screen.find_child("ExampleTurn", true, false) as Label).text,
		"example turn strip has no countdown")
	_check((screen.get_node("PageMargin/Page/GuideCard") as Control).visible,
		"guide card appears on the welcome page")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(360, 800), Vector2i(540, 960)]:
		get_window().size = dimensions
		await get_tree().process_frame
		await get_tree().process_frame
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var card: Control = screen.get_node("PageMargin/Page/GuideCard")
		var next: Control = card.find_child("NextButton", true, false) as Control
		var exit: Control = screen.find_child("ExitButton", true, false) as Control
		_check(card.get_global_rect().end.y <= viewport_size.y + 1.0,
			"guide stays within %s screen" % dimensions)
		_check(next.get_global_rect().end.y <= viewport_size.y + 1.0,
			"Next stays within %s screen" % dimensions)
		_check(exit.get_global_rect().end.x <= viewport_size.x + 1.0,
			"Exit stays within %s screen" % dimensions)
		_check(next.size.y >= 48.0 and exit.size.y >= 48.0,
			"navigation has minimum touch height at %s" % dimensions)
	screen.request_exit()
	_check(screen.get_node("ExitLayer").visible, "Exit opens the choice sheet")
	(screen.find_child("KeepLearning", true, false) as Button).pressed.emit()
	_check(not screen.get_node("ExitLayer").visible, "Keep learning returns to the lesson")
	screen.next_step()
	_check(screen.step_index() == 1, "Next advances past the welcome")
	screen.previous_step()
	_check(screen.step_index() == 0, "Back returns to welcome")
	var choices: Array[String] = []
	screen.finished.connect(func(choice: String) -> void: choices.append(choice))
	for i: int in range(screen.lesson_count()):
		screen.next_step()
	_check(choices == ["complete"], "finishing emits one completion choice")
	print("[tutorial] assertions: %d failures: %d" % [assertions, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
