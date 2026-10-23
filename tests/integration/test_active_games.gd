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
	check(first_card.find_child("Rival", true, false) == null, "active game cards omit the redundant opponent title")
	check_not_null(first_card.find_child("Score", true, false), "the score still identifies both players")
	var resume: Button = first_card.find_child("Resume", true, false) as Button
	check_not_null(resume, "the prioritised active game has a Resume button")
	if resume != null:
		resume.pressed.emit()
	check_eq(requested.size(), 1, "only the selected game is requested")
	if not requested.is_empty():
		check_eq(requested[0].get("kind"), "ai", "the selected game type is retained")
		check_eq(requested[0].get("id"), "saved-ai", "the selected match identity is retained")
		check_eq(requested[0].get("path"), "user://saved-ai.json", "the selected save path is retained")
	hub.free()
