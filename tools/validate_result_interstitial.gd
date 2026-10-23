extends Node
## Checks result-exit routing without asking the native SDK to serve an ad.

class InitializationProbe extends ResultInterstitial:
	var initialization_requested: bool = false
	var loads: int = 0

	func _start_sdk_initialization() -> void:
		initialization_requested = true

	func _load_ad(_unit_id: String, _request_generation: int) -> void:
		loads += 1

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
	result.end_reason = TurnEnums.EndReason.BOARD_FULL
	return result


func _run() -> void:
	_check(ResultInterstitial.is_eligible(_result(TurnEnums.MatchOutcome.HUMAN_WIN)), "win can show an ad")
	_check(ResultInterstitial.is_eligible(_result(TurnEnums.MatchOutcome.AI_WIN)), "loss can show an ad")
	_check(not ResultInterstitial.is_eligible(_result(TurnEnums.MatchOutcome.DRAW)), "draw skips the ad")
	_check(not ResultInterstitial.is_eligible(_result(TurnEnums.MatchOutcome.INCOMPLETE)), "incomplete match skips the ad")
	ResultInterstitial._sdk_initialized = false
	var initializing_ad := InitializationProbe.new()
	initializing_ad._prepare_available_unit(ResultInterstitial.ANDROID_TEST_UNIT_ID)
	_check(initializing_ad.initialization_requested and initializing_ad.loads == 0,
		"interstitial load waits for Mobile Ads initialization")
	initializing_ad._initialization_listener.on_initialization_complete.call(InitializationStatus.new())
	_check(initializing_ad.loads == 1,
		"interstitial load begins after initialization completes")
	initializing_ad.dispose()
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	add_child(screen)
	var exits: Array[int] = []
	screen.hub_requested.connect(func() -> void: exits.append(1))
	(screen.summary_overlay as MatchEndPresentation).play(_result(TurnEnums.MatchOutcome.HUMAN_WIN))
	# A stand-in ad verifies that navigation waits for the dismiss callback.
	screen._result_interstitial._ad = InterstitialAd.new(123456)
	screen.summary_hub_button.pressed.emit()
	_check(exits.is_empty() and screen.summary_hub_button.disabled,
		"loaded ad keeps the result screen until dismissed")
	screen.summary_hub_button.pressed.emit()
	_check(exits.is_empty(), "repeat tap cannot exit during an ad")
	screen._result_interstitial._on_ad_closed()
	_check(exits.is_empty(), "dismissal does not navigate inside the ad callback")
	await get_tree().process_frame
	_check(exits.size() == 1, "dismissal returns to the hub once")
	screen._result_interstitial._on_ad_closed()
	await get_tree().process_frame
	_check(exits.size() == 1, "duplicate dismissal cannot exit twice")
	screen.queue_free()
	await get_tree().process_frame
	var stalled_screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	add_child(stalled_screen)
	var stalled_exits: Array[int] = []
	stalled_screen.hub_requested.connect(func() -> void: stalled_exits.append(1))
	stalled_screen._result_interstitial._ad = InterstitialAd.new(123457)
	stalled_screen.summary_hub_button.pressed.emit()
	_check(stalled_exits.is_empty(), "a pending show waits briefly for the plugin")
	await get_tree().create_timer(ResultInterstitial.SHOW_ACK_TIMEOUT_SECONDS + 0.2).timeout
	_check(stalled_exits.size() == 1, "missing show callback returns to the hub")
	stalled_screen.queue_free()
	await get_tree().process_frame
	var no_ad_screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	add_child(no_ad_screen)
	var fallback_exits: Array[int] = []
	no_ad_screen.hub_requested.connect(func() -> void: fallback_exits.append(1))
	(no_ad_screen.summary_overlay as MatchEndPresentation).play(_result(TurnEnums.MatchOutcome.AI_WIN))
	no_ad_screen.summary_hub_button.pressed.emit()
	_check(fallback_exits.size() == 1, "missing ad never blocks returning to the hub")
	no_ad_screen.queue_free()
	print("[Result interstitial QA] %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
