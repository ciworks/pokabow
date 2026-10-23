extends Node
## Result Share visibility, action wiring and responsive footer.

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)


func _result(outcome: int) -> MatchResult:
	var value := MatchResult.new()
	value.outcome = outcome
	value.end_reason = TurnEnums.EndReason.TILE_SOURCE_EXHAUSTED
	value.human_score = 12
	value.ai_score = 8
	return value


func _run() -> void:
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	add_child(screen)
	get_tree().root.size_changed.disconnect(screen._fit_canvas)
	get_tree().root.content_scale_size = Vector2i.ZERO
	var results := screen.summary_overlay as MatchEndPresentation
	results.play(_result(TurnEnums.MatchOutcome.HUMAN_WIN))
	_check(results.can_share_win() and results._share_button.visible, "Human win offers Share")
	_check(results._share_button.icon != null, "Share has an icon")
	var requests: Array[int] = []
	results.share_requested.connect(func() -> void: requests.append(1))
	results._share_button.pressed.emit()
	_check(requests.size() == 1, "Share button emits request")
	if not Engine.has_singleton(Share.PLUGIN_SINGLETON_NAME):
		_check(results._share_feedback.visible, "Unavailable native share gives feedback")
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(390, 844), Vector2i(540, 960)]:
		get_tree().root.size = dimensions
		await get_tree().process_frame
		results._fit_layout()
		await get_tree().process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check(bounds.encloses(results._share_button.get_global_rect()), "Share fits %s" % dimensions)
		_check(results._share_button.size.y >= 48, "Share touch height %s" % dimensions)
	results.set_share_capture_mode(true)
	_check(not results._footer.visible, "Screenshot omits bottom actions")
	results.set_share_capture_mode(false)
	_check(results._footer.visible, "Actions return after screenshot")
	for outcome: int in [TurnEnums.MatchOutcome.AI_WIN, TurnEnums.MatchOutcome.DRAW, TurnEnums.MatchOutcome.INCOMPLETE]:
		results.clear()
		results.play(_result(outcome))
		_check(not results.can_share_win() and not results._share_button.visible, "Share hidden for outcome %d" % outcome)
	screen.queue_free()
	print("[Result Share QA] %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
