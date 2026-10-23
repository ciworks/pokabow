extends SceneTree
## Run by the API's smoke-online-http.mjs against disposable test accounts.
var endpoint: String = ""
var failures: int = 0

class WireQueue extends MatchmakingApiClient:
	var endpoint: String
	func _send_http(http: HTTPRequest, url: String, headers: PackedStringArray, method: int, body: String) -> int:
		return http.request(url.replace(ApiConfiguration.api_base_url(), endpoint), headers, method, body)

class WireGame extends OnlineGameApiClient:
	var endpoint: String
	func _send_http(http: HTTPRequest, url: String, headers: PackedStringArray, method: int, body: String) -> int:
		return http.request(url.replace(ApiConfiguration.api_base_url(), endpoint), headers, method, body)

func _initialize() -> void:
	_run.call_deferred()

func _wait_until(condition: Callable) -> bool:
	var end: int = Time.get_ticks_msec() + 20000
	while not bool(condition.call()) and Time.get_ticks_msec() < end:
		await create_timer(0.05).timeout
	if not bool(condition.call()):
		push_error("Online HTTP smoke timed out")
		quit(1)
		return false
	return true

func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	endpoint = data.endpoint
	var queues: Array[WireQueue] = []
	var clients: Array[WireGame] = []
	var controllers: Array[OnlineGameController] = []
	for user: Dictionary in data.players:
		var queue: WireQueue = WireQueue.new()
		queue.endpoint = endpoint
		root.add_child(queue)
		queue.set_credentials(user.token, user.id)
		queue.start_search()
		queues.append(queue)
	if not await _wait_until(func() -> bool: return queues[0].state == "matched" and queues[1].state == "matched"):
		return
	for queue: WireQueue in queues:
		queue.ready_up()
	if not await _wait_until(func() -> bool: return queues[0].state == "playing" and queues[1].state == "playing"):
		return
	for i: int in range(2):
		var client: WireGame = WireGame.new()
		client.endpoint = endpoint
		root.add_child(client)
		client.set_credentials(data.players[i].token, data.players[i].id)
		client.start(String(queues[i].lobby.matchId))
		clients.append(client)
	if not await _wait_until(func() -> bool: return not clients[0].state.is_empty() and not clients[1].state.is_empty()):
		return
	for client: WireGame in clients:
		var controller: OnlineGameController = OnlineGameController.new()
		root.add_child(controller)
		controller.attach_client(client)
		controllers.append(controller)
	var actor: int = 0 if controllers[0].is_human_turn() else 1
	var screen: GameScreen = load("res://scenes/game/game_screen.tscn").instantiate()
	root.size = Vector2i(360, 800)
	root.add_child(screen)
	screen.attach_controller(controllers[actor])
	screen.set_player_display_name("Online player")
	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate_with_report(controllers[actor].get_board(), controllers[actor].human_deck(), {}, 1)
	if candidates.is_empty():
		push_error("Smoke fixture has no opening move")
		quit(1)
		return
	for tile: TileSnapshot in candidates[0].snapshots:
		controllers[actor].stage_tile(tile.get_tile_id(), tile.get_cell(), tile.get_rotation())
	controllers[actor].commit_line()
	if not await _wait_until(func() -> bool: return int(clients[0].state.version) > 1 and int(clients[1].state.version) > 1):
		return
	if JSON.stringify(clients[0].state.board) != JSON.stringify(clients[1].state.board):
		push_error("Clients disagree about the accepted board")
		quit(1)
		return
	if data.get("capture", false):
		await create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(String(data.capturePath))
	clients[actor].stop()
	clients[actor].start(String(queues[actor].lobby.matchId))
	if not await _wait_until(func() -> bool: return clients[actor].connected):
		return
	controllers[1 - actor].resign()
	if not await _wait_until(func() -> bool: return controllers[0].is_over() and controllers[1].is_over()):
		return
	print("[online HTTP] PASS: two accounts, ready handshake, accepted placement, identical boards, reconnect, resignation")
	for client: WireGame in clients:
		client._clear_resume()
	screen.free()
	for controller: OnlineGameController in controllers:
		controller.free()
	for client: WireGame in clients:
		client.free()
	for queue: WireQueue in queues:
		queue.free()
	quit(0)
