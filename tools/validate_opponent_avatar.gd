extends Node
## Checks matched-lobby portrait replacement and fallback without contacting the API.

func _ready() -> void:
	var screen: OpponentSelectionScreen = (load("res://scenes/hub/opponent_selection_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	screen.select_online()
	var fallback: Texture2D = screen.rival_portrait.texture
	var image := Image.create(195, 195, false, Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE)
	var avatar: Texture2D = ImageTexture.create_from_image(image)
	screen.set_online_opponent_portrait(avatar)
	screen._on_matchmaking_changed("matched", "Opponent found", {"opponent": {"displayName": "Other player"}, "canReady": true})
	assert(screen.rival_portrait.texture == avatar, "Matched opponent avatar should replace the fallback")
	screen._on_matchmaking_changed("playing", "Opening match", {"opponent": {"displayName": "Other player"}})
	assert(screen.rival_portrait.texture == avatar, "Avatar should remain visible during handoff")
	screen._on_matchmaking_changed("failed", "Opponent left", {})
	assert(screen.rival_portrait.texture == fallback, "Missing opponent should restore the fallback")
	screen.set_online_opponent_portrait(null)
	assert(screen.rival_portrait.texture == fallback, "No account avatar should keep the fallback")
	print("[opponent avatar QA] lobby portrait and fallback pass")
	get_tree().quit()
