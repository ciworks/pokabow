extends Node
## Runs as a scene so project autoloads are available.

var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _result(outcome: int) -> MatchResult:
	var result := MatchResult.new()
	result.outcome = outcome
	return result

func _view() -> MatchEndPresentation:
	var view := MatchEndPresentation.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for name: String in ["SummaryTitle", "SummaryBody", "SummaryHubButton", "ConfettiLayer"]:
		var child: Control = Button.new() if name == "SummaryHubButton" else Label.new()
		child.name = name
		view.add_child(child)
	add_child(view)
	return view

func _run() -> void:
	var view := _view()
	view.play(_result(TurnEnums.MatchOutcome.HUMAN_WIN))
	await get_tree().create_timer(0.95).timeout
	_check(view._animation == null, "Entrance finishes")
	_check(view._accent_animation != null and view._accent_animation.is_running(), "Winner accent continues")
	await get_tree().create_timer(1.0).timeout
	_check(view._accents[0].pulse > 0.5, "Player ring pulses after entrance")
	_check(view._accents[0].sparkle_alpha > 0.0, "Player sparkles recur")
	var running_loop: Tween = view._accent_animation
	view.play(_result(TurnEnums.MatchOutcome.HUMAN_WIN))
	_check(view._accent_animation == running_loop, "Duplicate result keeps the current loop")
	await get_tree().create_timer(2.4).timeout
	_check(view._accents[0].pulse > 0.5, "Ring pulses in the next cycle")
	view.hide()
	_check(view._accent_animation == null, "Hiding cancels the loop")
	view.play(_result(TurnEnums.MatchOutcome.AI_WIN))
	await get_tree().create_timer(1.95).timeout
	_check(view._accents[1].pulse > 0.5, "Rival ring pulses after entrance")
	_check(view._accents[1].sparkle_alpha == 0.0, "Rival has no sparkles")
	view.clear()
	_check(view._accent_animation == null, "Clear cancels the loop")
	var previous: Variant = ProjectSettings.get_setting(AccessibilitySettings.REDUCED_MOTION_PATH, false)
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, true)
	view.play(_result(TurnEnums.MatchOutcome.HUMAN_WIN))
	_check(view._animation == null and view._accent_animation == null, "Reduced motion has no animation")
	_check(view._accents[0].sparkle_alpha < 0.001, "Reduced motion has no sparkles")
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, previous)
	view.queue_free()
	print("[Result accent QA] %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
