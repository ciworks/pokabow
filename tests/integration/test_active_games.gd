extends "res://tests/harness/test_case.gd"

func test_hub_prioritises_one_game_and_keeps_other_games_reachable() -> void:
	var packed: PackedScene = load("res://scenes/hub/hub_screen.tscn") as PackedScene
	if not check(packed != null, "the hub scene must load"):
		return
	var hub: HubScreen = packed.instantiate() as HubScreen
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(hub)
	var requested: Array[Dictionary] = []
	hub.resume_game_requested.connect(
		func(kind: String, id: String, path: String) -> void:
			requested.append({"kind": kind, "id": id, "path": path})
	)
	var games: Array[Dictionary] = [
		{
			"kind": "ai", "id": "saved-ai", "path": "user://saved-ai.json",
			"opponent": "AI Rival", "score": "You 8  |  AI Rival 3",
		},
		{
			"kind": "online", "id": "online-42", "path": "",
			"opponent": "Taylor", "score": "You 12  |  Taylor 9",
		},
	]
	hub.set_active_games(games)
	var list: VBoxContainer = hub.get_node("%ActiveGameList") as VBoxContainer
	check_eq(list.get_child_count(), 1, "the hub shows one prioritised active game")
	check(hub.find_child("MoreActive", true, false).visible, "the other active game links to the full list")
	var first_card: Node = list.get_child(0)
	check(first_card.find_child("Opponent", true, false) == null, "active game cards omit the redundant opponent title")
	check_eq(_labels_with_text(first_card, "AI Rival"), 0, "the AI opponent does not get a separate line")
	check_eq(_labels_with_text(first_card, "You 8 · AI Rival 3"), 1, "the score still identifies both players")
	check_not_null(first_card.find_child("Score", true, false), "the score still identifies both players")
	check_eq((first_card.find_child("Status", true, false) as Label).text, "RESUMABLE",
		"the Resume card omits the redundant Active prefix")
	check(first_card.find_child("ActiveDot", true, false) == null,
		"the Resume card omits the redundant active marker")
	var resume: Button = first_card.find_child("Resume", true, false) as Button
	check_not_null(resume, "the prioritised active game has a Resume button")
	if resume != null:
		resume.pressed.emit()
	check_eq(requested.size(), 1, "only the selected game is requested")
	if not requested.is_empty():
		check_eq(requested[0].get("kind"), "ai", "the selected game type is retained")
		check_eq(requested[0].get("id"), "saved-ai", "the selected match identity is retained")
		check_eq(requested[0].get("path"), "user://saved-ai.json", "the selected save path is retained")
	hub.set_active_games([games[1]])
	var online_card: Node = list.get_child(0)
	check(online_card.find_child("Opponent", true, false) == null,
		"online active games also omit the separate opponent line")
	check_eq(_labels_with_text(online_card, "Taylor"), 0,
		"the online opponent does not get a separate line")
	check_eq(_labels_with_text(online_card, "You 12 · Taylor 9"), 1,
		"the online score still identifies both players")
	hub.free()


func test_completed_match_cards_show_opponent_once_in_the_score() -> void:
	var entry: Dictionary = {
		"kind": "online", "id": "finished-42", "opponent": "Player_283282",
		"finished_at": "2026-10-23T12:00:00",
		"result": {"outcome": TurnEnums.MatchOutcome.HUMAN_WIN,
			"human_score": 18, "ai_score": 12},
	}
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var hub: HubScreen = load("res://scenes/hub/hub_screen.tscn").instantiate() as HubScreen
	tree.root.add_child(hub)
	hub.set_recent_match(entry)
	var recent: Node = hub.find_child("RecentResultRow", true, false)
	check_not_null(recent, "the hub shows the latest completed match")
	check(not (hub.get_node("%ActiveGamesPanel") as Control).visible and
		(hub.get_node("%RecentMatchPanel") as Control).visible,
		"completed-only tables do not show an empty active panel")
	if recent != null:
		check_eq((recent.find_child("RecentOutcome", true, false) as Label).text, "WIN",
			"the result card shows the outcome without the Latest Result prefix")
		check_eq(_labels_with_text(recent, "Player_283282"), 0,
			"the hub does not repeat the opponent on its own line")
		check_eq(_labels_with_text(recent, "You 18 · Player_283282 12"), 1,
			"the hub score still identifies both players")
	entry["result"]["outcome"] = TurnEnums.MatchOutcome.AI_WIN
	hub.set_recent_match(entry)
	check_eq((hub.find_child("RecentOutcome", true, false) as Label).text, "LOSS",
		"losses also omit the Latest Result prefix")
	check_eq(_labels_with_text(hub.find_child("RecentResultRow", true, false), "Player_283282"), 0,
		"a loss does not add a separate opponent line on the hub")
	hub.free()

	var tables := MatchTablesScreen.new()
	tree.root.add_child(tables)
	tables.set_records([], [entry])
	check_eq(_labels_with_text(tables, "Player_283282"), 0,
		"the completed table does not repeat the opponent on its own line")
	check_eq(_labels_with_text(tables, "You 18 · Player_283282 12"), 1,
		"the completed table score still identifies both players")
	tables.free()


func _labels_with_text(root: Node, value: String) -> int:
	var count: int = 0
	for node: Node in root.find_children("*", "Label", true, false):
		if (node as Label).text == value:
			count += 1
	return count
