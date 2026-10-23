extends TestCase


func test_tactile_hand_ripple_and_chip_clear_with_reveal() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var layer := ScoreRevealLayer.new()
	layer.state = BoardRenderState.new()
	layer.state.board_rect = Rect2(0, 0, 480, 480)
	tree.root.add_child(layer)
	var previous: bool = AccessibilitySettings.reduced_motion()
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, false)
	var event: ScoreEvent = ScoreEvent.create(&"ripple", &"move", &"human", ScoringEnums.ScoreCategory.POKER_HAND, 10, [Vector2i(5, 5), Vector2i(6, 5)], {"category": "PAIR"})
	layer.reveal([event])
	layer._process(0.08)
	check(layer.state.zoom_for(Vector2i(5, 5)) > 1.0, "first tile lifts during the ripple")
	check_eq(layer.state.zoom_for(Vector2i(6, 5)), 1.0, "next tile waits for its stagger")
	check(ScoreRevealLayer.BOUNCE_ZOOM_RATIO <= 0.1, "ripple keeps the tile lift restrained")
	check(layer.ripple_duration() > 0.0, "Gem travel can wait for the hand cue")
	layer._process(1.0)
	check(not layer.is_processing() and layer.state.cell_zoom.is_empty(), "completed ripple settles all tiles")
	check(layer.has_marks(), "hand trace holds after the tile motion")
	layer.reveal([event])
	layer._process(0.2)
	layer.reveal([])
	check(not layer.has_marks() and layer.state.cell_zoom.is_empty(), "empty move clears the trace and tile scales")
	event.evidence["category"] = "FULL_HOUSE"
	layer.reveal([event])
	check(layer._has_chip, "Full House receives the chip stamp")
	layer.clear_reveal()
	check(not layer._has_chip, "clearing the reveal removes the chip")
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, true)
	layer.reveal([event])
	check(not layer.is_processing() and layer.ripple_duration() == 0.0, "reduced motion suppresses travel delay and tile lift")
	check(layer.has_marks() and layer._has_chip, "reduced motion preserves the hand trace and label")
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, false)
	event.category = ScoringEnums.ScoreCategory.EDGE_CLUSTER
	layer.reveal([event])
	check(not layer.has_marks() and not layer._has_chip, "edge-only awards do not show a poker-hand cue")
	layer.clear_reveal()
	layer.free()
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, previous)


func test_gems_wait_for_the_ripple_before_travelling() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var flight := GemTravelLayer.new()
	tree.root.add_child(flight)
	var arrival: Dictionary = {"count": 0}
	flight.play(Vector2(100, 100), Vector2(200, 20), 4,
		func() -> void: arrival["count"] += 1, ScoreRevealLayer.TRACE_DURATION)
	check_eq(flight.active_flights(), 1, "award is queued while the hand ripple plays")
	check(float(flight._flights[0]["elapsed"]) < 0.0, "Gem motion starts after the hand cue")
	flight._process(ScoreRevealLayer.TRACE_DURATION * 0.5)
	check_eq(arrival["count"], 0, "pot does not increment during the hand cue")
	flight._process(ScoreRevealLayer.TRACE_DURATION + GemTravelLayer.DURATION)
	check_eq(arrival["count"], 1, "pot increments once the delayed Gems arrive")
	flight.free()
