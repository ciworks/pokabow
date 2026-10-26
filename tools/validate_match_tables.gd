extends Control

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func verify(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func capture(label: String) -> void:
	var folder: String = OS.get_environment("MATCH_TABLES_QA_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	verify(get_viewport().get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK,
		"capture saved: " + label)


func _run() -> void:
	get_window().size = Vector2i(360, 800)
	get_window().content_scale_size = Vector2i(540, 1200)
	var account := "qa-match-tables"
	var result := {
		"outcome": TurnEnums.MatchOutcome.HUMAN_WIN,
		"end_reason": TurnEnums.EndReason.TILE_SOURCE_EXHAUSTED,
		"human_score": 61, "ai_score": 55, "move_count": 42,
		"terms": {"human": {"poker": 45, "edge": 12, "cluster": 4},
			"ai": {"poker": 40, "edge": 10, "cluster": 5}},
	}
	verify(MatchHistoryStore.add(account, "qa-win", "ai", "Alex", result), "completed match saved")
	verify(MatchHistoryStore.add(account, "qa-win", "ai", "Alex", result), "duplicate accepted idempotently")
	verify(not MatchHistoryStore.add(account, "qa-active", "ai", "Alex", {"outcome": TurnEnums.MatchOutcome.IN_PROGRESS}), "unfinished match rejected")
	verify(MatchHistoryStore.entries("qa-other-account").is_empty(), "history is account scoped")
	var completed: Array[Dictionary] = MatchHistoryStore.entries(account)
	verify(completed.size() == 1, "one record after duplicate completion")
	var hub: HubScreen = load("res://scenes/hub/hub_screen.tscn").instantiate()
	add_child(hub)
	hub.set_active_games([{"kind": "ai", "id": "qa-active", "path": "user://qa-active.json",
		"opponent": "Maya", "score": "You 42 · Maya 38", "status_label": "YOUR TURN"}])
	hub.set_recent_match(completed[0])
	await get_tree().process_frame
	await capture("hub-tables")
	verify(hub.get_node("%ActiveGameList").get_child_count() == 1, "hub shows one active row")
	verify(hub.find_child("RecentResultRow", true, false).visible, "hub shows recent result")
	var active_panel := hub.get_node("%ActiveGamesPanel") as PanelContainer
	var result_panel := hub.get_node("%RecentMatchPanel") as PanelContainer
	verify(active_panel.visible and result_panel.visible and active_panel.get_parent() == result_panel.get_parent(),
		"resumable and completed games use separate sibling panels")
	verify(hub.get_node("%RecentResultRow").get_parent() == result_panel,
		"completed result belongs to its own panel")
	verify(result_panel.get_global_rect().position.y > active_panel.get_global_rect().end.y,
		"visible canvas gap separates the two game panels")
	var header := hub.get_node("%ActiveGamesHeader") as HBoxContainer
	var panel := active_panel
	var title := hub.get_node("%ActiveGamesTitle") as Label
	var view_all := hub.find_child("ViewAllTables", true, false) as Button
	verify(header.get_parent() == panel.get_parent() and title.get_parent() == header
		and view_all.get_parent() == header, "tables heading and View all sit above the activity card")
	hub.set_active_games([])
	await get_tree().process_frame
	verify(not active_panel.visible and result_panel.visible,
		"completed-only tables show only their own panel")
	hub.set_active_games([
		{"kind": "ai", "id": "qa-active", "path": "user://qa-active.json",
			"opponent": "Maya", "score": "You 42 · Maya 38", "status_label": "YOUR TURN"},
		{"kind": "online", "id": "qa-other", "path": "",
			"opponent": "Jordan", "score": "You 17 · Jordan 20", "status_label": "RESUMABLE"},
	])
	await get_tree().process_frame
	verify(hub.get_node("%ActiveGameList").get_child_count() == 1,
		"multiple active matches keep the compact card")
	var play_style := (hub.get_node("%PlayButton") as Button).get_theme_stylebox("normal") as StyleBoxFlat
	verify(play_style.bg_color == Color("#F4C86A"), "Play Now remains honey with active matches")
	verify(title.get_global_rect().end.x < view_all.get_global_rect().position.x
		and header.get_global_rect().end.y <= panel.get_global_rect().position.y,
		"View all is right of the heading and both are outside the panel")
	await capture("hub-tables-multiple")
	for width: int in [320, 390, 540]:
		get_window().size = Vector2i(width, 800)
		await get_tree().process_frame
		verify(title.get_global_rect().end.x < view_all.get_global_rect().position.x
			and view_all.get_global_rect().end.x <= panel.get_global_rect().end.x + 1,
			"tables heading and View all fit at %dpx" % width)
	get_window().size = Vector2i(360, 800)
	await get_tree().process_frame
	var chosen: Array[String] = []
	hub.completed_match_requested.connect(func(kind: String, id: String) -> void: chosen.append(kind + ":" + id))
	var details: Button = hub.find_child("Details", true, false) as Button
	verify(details != null, "details affordance exists")
	if details != null:
		details.pressed.emit()
	verify(chosen == ["ai:qa-win"], "details routes to the exact completed match")
	var active_suite: TestCase = load("res://tests/integration/test_active_games.gd").new()
	active_suite.test_hub_prioritises_one_game_and_keeps_other_games_reachable()
	active_suite.test_completed_match_cards_show_opponent_once_in_the_score()
	verify(active_suite.failures.is_empty(), "active-game routing regression passes")
	var history := MatchTablesScreen.new()
	hub.hide()
	add_child(history)
	history.set_records([], completed)
	verify(history.show_detail("ai", "qa-win"), "stored result opens")
	verify(history.find_child("Share", true, false) == null or history._share_button.visible, "winning result may be shared")
	verify(history._content.find_children("*", "Label", true, false).any(func(label: Label) -> bool: return label.text == "61"), "detail uses stored final score")
	var rival_avatar := history._content.find_child("RivalAvatar", true, false) as TextureRect
	verify(rival_avatar is FramedPlayerAvatar and rival_avatar.material is ShaderMaterial,
		"completed match rival portrait uses circular crop")
	await get_tree().process_frame
	await capture("match-details")
	var photo := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	photo.fill(Color.RED)
	var photo_path := "user://qa-rival-avatar.png"
	verify(photo.save_png(ProjectSettings.globalize_path(photo_path)) == OK, "uploaded rival fixture saved")
	var loss: Dictionary = completed[0].duplicate(true)
	loss["id"] = "qa-loss"
	loss["avatar_path"] = photo_path
	loss["result"]["outcome"] = TurnEnums.MatchOutcome.AI_WIN
	history.set_records([], [loss])
	verify(history.show_detail("ai", "qa-loss"), "rival win detail opens")
	rival_avatar = history._content.find_child("RivalAvatar", true, false) as TextureRect
	verify(rival_avatar != null and rival_avatar.texture is ImageTexture and rival_avatar.material is ShaderMaterial,
		"uploaded rival portrait is circular on rival win detail")
	await get_tree().process_frame
	await capture("rival-win-details")
	history.show_list()
	rival_avatar = history._content.find_child("RivalAvatar", true, false) as TextureRect
	verify(rival_avatar != null and rival_avatar.texture is ImageTexture and rival_avatar.material is ShaderMaterial,
		"uploaded rival portrait is circular in the match list")
	verify(not history.show_detail("ai", "unknown"), "unknown result does not open")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(photo_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MatchHistoryStore.path_for(account)))
	print("MATCH TABLES: %d failures" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
