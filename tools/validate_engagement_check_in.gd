extends Node
## Run as a scene so the project's autoloads are available.

class ObservedClient extends AchievementApiClient:
	var catalog_refreshes: int = 0
	func fetch_catalog() -> void:
		catalog_refreshes += 1


func _ready() -> void:
	var client := ObservedClient.new()
	add_child(client)
	client.access_token = "test-token"
	var announced: Array = []
	client.newly_unlocked.connect(func(ids: Array) -> void: announced.append_array(ids))
	var details: Array = [{
		"id": "first_login", "name": "First Login",
		"description": "Visit Pokabow with your account for the first time.",
		"badgeKey": "milestone"
	}]
	_complete(client, {"day": "2026-10-20", "unlockedDetails": details})
	assert(announced.size() == 1, "New engagement unlock reaches the toast signal")
	assert(announced[0].description == details[0].description, "Description reaches the toast")
	assert(client.catalog_refreshes == 1, "New activity refreshes progress")
	_complete(client, {"day": "2026-10-20", "unlockedDetails": []})
	assert(announced.size() == 1, "Repeated check-in does not reannounce")
	assert(client.catalog_refreshes == 1, "Repeated same-day check-in does not refetch the catalog")
	_complete(client, {"day": "2026-10-21", "unlockedDetails": []})
	assert(client.catalog_refreshes == 2, "A new UTC day refreshes progress")
	print("[engagement check-in QA] toast detail and catalog refresh pass")
	get_tree().quit()


func _complete(client: AchievementApiClient, response: Dictionary) -> void:
	var request := HTTPRequest.new()
	client.add_child(request)
	client._check_in_request_active = true
	client._on_check_in_completed(
		HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(),
		JSON.stringify(response).to_utf8_buffer(), request, "test-token"
	)
