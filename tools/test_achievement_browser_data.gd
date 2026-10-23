extends Node
## Checks catalogue normalization without creating visual nodes or contacting the API.

func _ready() -> void:
	var browser := AchievementBrowser.new()
	browser.set_rows([
		{"id": &"edge_cluster", "name": &"Edge Cluster", "unlocked": false},
		{"id": "first_hand", "name": "First Hand", "unlocked": true},
	])
	var ok: bool = browser.rows.size() == 2
	ok = ok and browser.rows[0].id == "edge_cluster"
	ok = ok and browser.group_for(browser.rows[0]) == "Edge Matching"
	ok = ok and browser._badge_key_for(browser.rows[0]) == "edge_cluster"
	if not ok:
		push_error("Achievement browser did not normalize the edge_cluster catalogue row")
	browser.free()
	get_tree().quit(0 if ok else 1)
