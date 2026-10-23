extends Node

var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var tree := get_tree()
	tree.root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	tree.root.content_scale_size = Vector2i.ZERO
	var view := MatchEndPresentation.new()
	for name: String in ["ConfettiLayer", "SummaryTitle", "SummaryBody", "SummaryHubButton"]:
		var child: Control = Button.new() if name == "SummaryHubButton" else (Label.new() if name != "ConfettiLayer" else Control.new())
		child.name = name
		view.add_child(child)
	tree.root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view._portraits[1].texture = load("res://assets/ui/modern_tabletop/avatars/rivals/rival_02.tres")
	var result := MatchResult.new()
	result.outcome = TurnEnums.MatchOutcome.HUMAN_WIN
	result.end_reason = TurnEnums.EndReason.TILE_SOURCE_EXHAUSTED
	result.human_score = 128
	result.ai_score = 96
	result.move_count = 42
	result.terms = {
		String(TurnEnums.HUMAN_PLAYER_ID): {"poker": 90, "edge": 26, "cluster": 12},
		String(TurnEnums.AI_PLAYER_ID): {"poker": 70, "edge": 18, "cluster": 8},
	}
	view._title.text = "You win!"
	view._body.text = "No tiles remained · 42 moves"
	view.play(result, GemPotRules.projected_payout(result, 86))
	for dimensions: Vector2i in [Vector2i(390, 844), Vector2i(360, 800), Vector2i(320, 568)]:
		tree.root.size = dimensions
		await tree.process_frame
		await tree.process_frame
		view._fit_layout()
		await tree.process_frame
		var bounds := Rect2(Vector2.ZERO, view.size)
		_check(view._reward_card.visible, "Gem panel visible for online result")
		_check(view._reward_values[0].text == "+96", "Winner amount")
		_check(view._reward_values[1].text == "+10", "Consolation amount")
		_check(bounds.encloses(view._button.get_global_rect()), "Hub action remains visible")
		_check(bounds.encloses(view._share_button.get_global_rect()), "Share action remains visible")
		_check(view._content.size.x <= view._scroll.size.x + 1.0, "No horizontal overflow")
		if dimensions.y >= 800:
			_check(view._content.size.y <= view._scroll.size.y + 1.0, "Standard viewport needs no scroll")
		if dimensions == Vector2i(390, 844) and not OS.get_environment("GEM_RESULTS_CAPTURE").is_empty():
			await RenderingServer.frame_post_draw
			_check(tree.root.get_texture().get_image().save_png(OS.get_environment("GEM_RESULTS_CAPTURE")) == OK, "Capture saved")
	result.outcome = TurnEnums.MatchOutcome.DRAW
	view.play(result, GemPotRules.projected_payout(result, 86))
	_check(view._reward_values[0].text == "+53" and view._reward_values[1].text == "+53", "Draw shows equal shares")
	result.outcome = TurnEnums.MatchOutcome.AI_WIN
	result.end_reason = TurnEnums.EndReason.RESIGNATION
	view.play(result, GemPotRules.projected_payout(result, 86))
	_check(view._reward_values[0].text == "+0" and view._reward_values[1].text == "+86", "Resignation shows pot only")
	view.play(result)
	_check(not view._reward_card.visible, "AI result hides Gem panel")
	print("[Gem results] %d failures" % failures)
	tree.quit(0 if failures == 0 else 1)
