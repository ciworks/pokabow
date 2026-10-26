extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var created: Dictionary = OnlineRules.execute({"action": "create", "matchId": "verified-ai-test", "seed": 4217})
	if created.has("error"):
		push_error("Could not create server AI test match: %s" % created.error)
		quit(1)
		return
	var snapshot: Dictionary = created.snapshot
	for difficulty: int in AiEnums.Difficulty.values():
		var session: GameSessionState = GameSessionState.from_snapshot(
			MatchSnapshotDto.from_dictionary(snapshot), ScoringRules.create_default(),
			load(GameSessionController.TILE_RULES_RESOURCE))
		if session == null:
			push_error("Could not restore server AI match")
			quit(1)
			return
		session.get_turn_state().active_player_id = TurnEnums.AI_PLAYER_ID
		var before: int = session.get_turn_state().turn_number
		var error: String = OnlineRules._play_server_ai(session, difficulty)
		if not error.is_empty() or session.get_turn_state().turn_number <= before:
			push_error("Server AI difficulty %d did not complete a legal turn: %s" % [difficulty, error])
			quit(1)
			return
	print("[verified AI rules] Easy, Medium and Hard completed legal server-owned turns")
	quit()
