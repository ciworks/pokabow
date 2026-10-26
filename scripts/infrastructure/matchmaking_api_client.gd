class_name MatchmakingApiClient
extends Node
## Queue, readiness and handoff to the authoritative online match.
signal changed(state: String, message: String, lobby: Dictionary)
signal authentication_required
signal earnings_status_changed(status: Dictionary)

const RULES_VERSION: String = "pokabow-v3"
const POLL_SECONDS: float = 2.0
var access_token: String = ""
var account_id: String = ""
var state: String = "idle"
var message: String = "Find another player for an online lobby."
var lobby: Dictionary = {}
var _ticket_id: String = ""
var _join_id: String = ""
var _wanted: bool = false
var _leaving: bool = false
var _backgrounded: bool = false
var _delay: float = 0.0
var _backoff: float = POLL_SECONDS
var _request: HTTPRequest = null
var _kind: String = ""
var _ready_wanted: bool = false
var earnings_status: Dictionary = {}
var _earnings_request: HTTPRequest = null

func ready_up() -> void:
	if state != "matched" or not bool(lobby.get("canReady", false)):
		return
	_ready_wanted = true
	_delay = 0.0
	_advance()


func set_credentials(token: String, user_id: String) -> void:
	var token_changed: bool = token != access_token
	if token != access_token and _request != null:
		_request.cancel_request()
		_request.queue_free()
		_request = null
	if user_id != account_id:
		_reset()
		account_id = user_id
	access_token = token
	if token_changed and not token.is_empty():
		refresh_earnings_status()
	_delay = 0.0
	_advance()


func refresh_earnings_status() -> void:
	if access_token.is_empty() or _earnings_request != null:
		return
	_earnings_request = HTTPRequest.new()
	_earnings_request.timeout = 8.0
	add_child(_earnings_request)
	_earnings_request.request_completed.connect(_earnings_completed.bind(_earnings_request))
	var error: int = _send_http(_earnings_request, ApiConfiguration.api_base_url() + "/gems/online-earnings",
		PackedStringArray(["Authorization: Bearer %s" % access_token]), HTTPClient.METHOD_GET, "")
	if error != OK:
		_earnings_request.queue_free()
		_earnings_request = null


func _earnings_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		request: HTTPRequest) -> void:
	if request != _earnings_request:
		return
	_earnings_request = null
	request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		earnings_status = parsed
		earnings_status_changed.emit(earnings_status)


func start_search() -> void:
	if _wanted or _leaving:
		return
	_ready_wanted = false
	_wanted = true
	_delay = 0.0
	_join_id = _uuid()
	_ticket_id = ""
	_backoff = POLL_SECONDS
	_publish("connecting", "Connecting to matchmaking...")
	_advance()
	if access_token.is_empty():
		authentication_required.emit()


func leave() -> void:
	if not _wanted and not _leaving:
		return
	_wanted = false
	_leaving = true
	lobby = {}
	_publish("leaving", "Leaving matchmaking...")
	_delay = 0.0
	# An in-flight join may already have succeeded. Let its reply identify the
	# ticket, then cancel that ticket instead of abandoning a server-side search.
	_advance()


func _process(delta: float) -> void:
	_delay = maxf(0.0, _delay - delta)
	if _delay == 0.0:
		_advance()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_backgrounded = true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_backgrounded = false
		_delay = 0.0
		_advance()


func _advance() -> void:
	if _request != null or _backgrounded or _delay > 0.0 or (not _wanted and not _leaving):
		return
	if access_token.is_empty():
		if _leaving:
			_finish_leave()
		elif state != "authentication":
			_publish("authentication", "Sign in to find an opponent.")
		return
	if _leaving and _ticket_id.is_empty() and not _join_id.is_empty():
		_send("cancel_request", "/requests/%s" % _join_id, HTTPClient.METHOD_DELETE)
	elif _ticket_id.is_empty():
		_send("current", "/tickets/current", HTTPClient.METHOD_GET)
	elif _leaving:
		_send("cancel", "/tickets/%s" % _ticket_id, HTTPClient.METHOD_DELETE)
	elif _ready_wanted:
		_send("ready", "/tickets/%s/ready" % _ticket_id, HTTPClient.METHOD_POST)
	else:
		_send("heartbeat", "/tickets/%s/heartbeat" % _ticket_id, HTTPClient.METHOD_POST)


func _send(kind: String, path: String, method: int, payload: Dictionary = {}) -> void:
	_kind = kind
	_request = HTTPRequest.new()
	_request.timeout = 8.0
	add_child(_request)
	_request.request_completed.connect(_completed.bind(_request, kind))
	var headers := PackedStringArray(["Authorization: Bearer %s" % access_token])
	if method == HTTPClient.METHOD_POST:
		headers.append("Content-Type: application/json")
	var error: int = _send_http(_request, ApiConfiguration.api_base_url() + "/matchmaking" + path,
		headers, method, JSON.stringify(payload) if method == HTTPClient.METHOD_POST else "")
	if error != OK:
		_request.queue_free()
		_request = null
		_retry()


func _send_http(request: HTTPRequest, url: String, headers: PackedStringArray, method: int, body: String) -> int:
	return request.request(url, headers, method, body)


func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
	request: HTTPRequest, kind: String) -> void:
	if request != _request:
		return
	_request = null
	request.queue_free()
	if code == 401:
		access_token = ""
		_publish("authentication", "Reconnecting your account...")
		authentication_required.emit()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code >= 500 or code == 429:
		_retry()
		return
	if code == 404:
		if _leaving:
			_finish_leave()
		else:
			_fail("Online matchmaking is unavailable. Please try again later.")
		return
	if code == 409 and kind == "ready":
		_ready_wanted = false
		_delay = POLL_SECONDS
		_publish("reconnecting", "The lobby changed. Checking your opponent...")
		return
	if code != 200:
		_fail("Couldn't join matchmaking. Please try again.")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		_retry()
		return
	_backoff = POLL_SECONDS
	if kind == "ready":
		_ready_wanted = false
	if kind == "current":
		var current: Variant = parsed.get("ticket")
		if current == null:
			if _leaving:
				_finish_leave()
			else:
				_send("join", "/tickets", HTTPClient.METHOD_POST, {"requestId": _join_id, "rulesVersion": RULES_VERSION})
			return
		if not current is Dictionary:
			_retry()
			return
		parsed = current
	if not parsed.get("ticketId") is String or String(parsed.get("ticketId", "")).is_empty():
		_retry()
		return
	_ticket_id = parsed.ticketId
	if _leaving:
		if kind in ["cancel", "cancel_request"]:
			_finish_leave()
		else:
			_advance()
		return
	if not _wanted:
		return
	var status: String = String(parsed.get("status", ""))
	match status:
		"searching":
			_publish("searching", "Looking for another player...")
		"matched", "playing":
			var found: Variant = parsed.get("lobby")
			if not found is Dictionary or not found.get("opponent") is Dictionary:
				_retry()
				return
			if status == "playing":
				_wanted = false
				_publish("playing", "Opening your online match...", found)
			elif bool(found.get("canReady", false)):
				var tier: String = String((found.get("opponent") as Dictionary).get("onlineTier", ""))
				var tier_detail: String = " · %s online tier" % tier if not tier.is_empty() else ""
				_publish("matched", "Waiting for your opponent%s to get ready." % tier_detail if bool(found.get("ready", false)) else "Opponent found%s! Ready for a live match?" % tier_detail, found)
			else:
				_publish("matched", "Opponent found. Online play is not enabled on this server yet.", found)
		"expired":
			_fail("Your search expired. Find an opponent again.")
		"opponent_left":
			_fail("Your opponent left the lobby. Find another player.")
		"cancelled":
			_finish_leave()
		_:
			_retry()
			return
	_delay = POLL_SECONDS


func authentication_failed(text: String) -> void:
	access_token = ""
	if _request != null:
		_request.cancel_request()
		_request.queue_free()
		_request = null
	_fail(text)


func _retry() -> void:
	_delay = _backoff
	_backoff = minf(8.0, _backoff * 2.0)
	_publish("leaving" if _leaving else "reconnecting",
		"Finishing your cancellation..." if _leaving else "Connection lost. Reconnecting...")


func _fail(text: String) -> void:
	_ready_wanted = false
	_wanted = false
	_leaving = false
	_ticket_id = ""
	_publish("failed", text)


func _finish_leave() -> void:
	_ready_wanted = false
	_wanted = false
	_leaving = false
	_ticket_id = ""
	_join_id = ""
	_publish("idle", "Find another player for an online lobby.")


func _publish(next: String, text: String, found: Dictionary = {}) -> void:
	state = next
	message = text
	lobby = found
	changed.emit(state, message, lobby)


func _reset() -> void:
	if _request != null:
		_request.cancel_request()
		_request.queue_free()
		_request = null
	_finish_leave()


func _exit_tree() -> void:
	if _request != null:
		_request.cancel_request()


static func _uuid() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var value: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [value.substr(0, 8), value.substr(8, 4), value.substr(12, 4), value.substr(16, 4), value.substr(20, 12)]
