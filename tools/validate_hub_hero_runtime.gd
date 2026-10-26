extends Node

var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var previous: bool = AccessibilitySettings.reduced_motion()
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, false)
	var hub: HubScreen = load("res://scenes/hub/hub_screen.tscn").instantiate()
	get_tree().root.add_child(hub)
	await get_tree().process_frame
	var hero: AnimatedHubHero = hub.get_node("%Hero") as AnimatedHubHero
	_check(hero != null, "Hub uses the animated hero")
	if hero != null:
		hero._process(0.0)
		hero._cooldowns = [0.0, 999.0, 999.0]
		hero._process(0.016)
		_check(hero._tweens[0] != null, "Expired interval creates a tile bounce")
		(hero._tweens[0] as Tween).custom_step(0.08)
		_check(hero._offsets[0] > 0.0, "Ace rises when its randomized interval expires")
		hub._on_reduced_motion_toggled(true)
		_check(hero._offsets[0] == 0.0, "Reduced motion immediately returns the tile to rest")
		_check(hero._tweens[0] == null, "Reduced motion stops the active bounce")
		for index: int in [1, 2]:
			hero.set_motion_enabled(true)
			hero._bounce(index)
			(hero._tweens[index] as Tween).custom_step(0.08)
			_check(hero._offsets[index] > 0.0, "Tile %d rises independently" % index)
			hero.set_motion_enabled(false)
			_check(hero._offsets[index] == 0.0, "Tile %d returns to its original position" % index)
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, previous)
	hub.queue_free()
	print("[hub hero runtime] %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
