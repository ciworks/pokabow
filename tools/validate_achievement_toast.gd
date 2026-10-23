extends Control
## Run as a scene so project autoloads and the shared theme are available.

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_window().content_scale_size = Vector2i.ZERO
	for dimensions: Vector2i in [Vector2i(540, 960), Vector2i(360, 800), Vector2i(320, 568)]:
		get_window().size = dimensions
		await get_tree().process_frame
		var toast := AchievementToast.new()
		add_child(toast)
		toast.show_achievement(
			"perfect_match", "Perfect Match",
			"You matched every suit and edge in a 5 card hand!", "perfect_match"
		)
		await get_tree().process_frame
		var card: PanelContainer = toast.get_node("AchievementToastCard")
		var copy: VBoxContainer = card.get_child(0).get_child(1)
		var name_label: Label = copy.get_node("AchievementName")
		var description: Label = copy.get_node("AchievementDescription")
		print("[achievement toast QA] viewport=%s card=%s toast=%s" % [dimensions, card.size, toast.size])
		assert(card.size.y <= 125.0, "Achievement banner is too tall at %s" % dimensions)
		assert(card.position.x >= 0.0 and card.position.x + card.size.x <= dimensions.x,
			"Achievement banner exceeds viewport at %s" % dimensions)
		assert(name_label.text == "Perfect Match", "Achievement name is missing")
		assert(description.text == "You matched every suit and edge in a 5 card hand!",
			"Achievement description is missing")
		toast.queue_free()
		await get_tree().process_frame
	print("[achievement toast QA] compact banner and description pass at three phone sizes")
	get_tree().quit()
