extends Node
## Focused scene smoke test for server progression projection and profile display.

const ProgressionClient = preload("res://scripts/infrastructure/progression_api_client.gd")

func _ready() -> void:
	var profile: ProfileScreen = (load("res://scenes/profile/profile_screen.tscn") as PackedScene).instantiate()
	add_child(profile)
	profile.set_progression({
		"experience": 200, "level": 2, "levelStartExperience": 100,
		"nextLevelExperience": 300, "onlineTier": "Provisional", "ratedMatches": 2
	})
	assert(profile._progression_level_label.text == "Level 2")
	assert(profile._progression_xp_label.text == "100 / 200 XP to Level 3")
	assert(profile._progression_bar.value == 100.0)
	assert(profile._progression_tier_label.text == "Provisional online")
	for width: int in [320, 360, 390]:
		get_tree().root.size = Vector2i(width, 800)
		await get_tree().process_frame
		await get_tree().process_frame
		assert(profile._progression_level_label.get_line_count() == 1, "Level label must stay horizontal at %dpx" % width)
		assert(profile._progression_tier_label.get_line_count() == 1, "Online tier must stay horizontal at %dpx" % width)
		assert(profile._progression_level_label.size.x >= profile._progression_level_label.get_combined_minimum_size().x,
			"Level label must fit within the progression card at %dpx" % width)
	var client: ProgressionClient = ProgressionClient.new()
	add_child(client)
	client.access_token = "test-token"
	client.account_id = "test-account"
	var response: Array[Dictionary] = []
	client.received.connect(func(data: Dictionary) -> void: response.append(data))
	var request := HTTPRequest.new()
	client.add_child(request)
	client._request = request
	client._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(),
		JSON.stringify({"experience": 200, "level": 2, "levelStartExperience": 100,
		"nextLevelExperience": 300, "onlineTier": "Provisional"}).to_utf8_buffer(),
		request, "test-token", "test-account")
	assert(response.size() == 1)
	assert(client.current.level == 2)
	var lobby_suite: RefCounted = load("res://tests/integration/test_matchmaking.gd").new()
	lobby_suite.test_search_pairs_and_keeps_the_lobby_alive()
	assert(lobby_suite.failures.is_empty(), "Matchmaking lobby tier assertion failed")
	print("[progression QA] profile and API projection pass")
	get_tree().quit()
