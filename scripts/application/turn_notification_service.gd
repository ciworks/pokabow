extends Node
## Device-local turn alerts for online matches. Remote delivery requires a server push service.

signal preference_changed(enabled: bool)
signal turn_alert_due(opponent_name: String)

const SETTINGS_PATH := "user://turn_notifications.cfg"
const CHANNEL_ID := "online_turns"
const NOTIFICATION_ID := 7401

var enabled: bool = false
var _scheduler: NotificationScheduler
var _initialized: bool = false
var _last_match_key: String = ""
var _last_version: int = -1
var _last_active_seat: String = ""


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		enabled = bool(config.get_value("notifications", "enabled", false))
	if not is_available():
		return
	_scheduler = NotificationScheduler.new()
	add_child(_scheduler)
	_scheduler.initialization_completed.connect(_on_initialized)
	_scheduler.post_notifications_permission_denied.connect(_on_permission_denied)
	_scheduler.initialize()


func is_available() -> bool:
	return (OS.has_feature("android") or OS.has_feature("ios")) \
		and Engine.has_singleton(NotificationScheduler.PLUGIN_SINGLETON_NAME)


func set_enabled(value: bool) -> bool:
	if value and not is_available():
		return false
	if enabled == value:
		return true
	enabled = value
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("notifications", "enabled", enabled)
	var error: Error = config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save notification preference: %s" % error_string(error))
	preference_changed.emit(enabled)
	if not enabled:
		if _initialized:
			_scheduler.cancel(NOTIFICATION_ID)
	elif _initialized:
		_request_permission_if_needed()
	return true


func observe_online_state(data: Dictionary, account_id: String) -> void:
	var match_id: String = String(data.get("matchId", ""))
	var seat: String = String(data.get("seat", ""))
	var turn: Dictionary = data.get("turn", {})
	if match_id.is_empty() or seat.is_empty() or turn.is_empty():
		return
	var key: String = "%s:%s" % [account_id, match_id]
	var version: int = int(data.get("version", -1))
	var active_seat: String = String(turn.get("active_player_id", ""))
	var previous_was_opponent: bool = _last_match_key == key and _last_version >= 0 \
		and _last_active_seat != seat and not _last_active_seat.is_empty()
	var is_new_own_turn: bool = previous_was_opponent and version > _last_version \
		and active_seat == seat and String(data.get("status", "")) == "active" \
		and int(turn.get("phase", -1)) in [TurnEnums.MatchPhase.TURN_START, TurnEnums.MatchPhase.AWAIT_ACTION]
	if _last_match_key != key or version >= _last_version:
		_last_match_key = key
		_last_version = version
		_last_active_seat = active_seat
	if is_new_own_turn and enabled:
		var opponent: Dictionary = data.get("opponent", {})
		var opponent_name: String = String(opponent.get("displayName", "Your opponent"))
		turn_alert_due.emit(opponent_name)
		if _initialized and _scheduler.has_post_notifications_permission():
			_schedule_turn_alert(opponent_name)


func _on_initialized() -> void:
	var channel := NotificationChannel.new().set_id(CHANNEL_ID).set_name("Your turn") \
		.set_description("Online match turn alerts").set_importance(NotificationChannel.Importance.DEFAULT)
	var channel_result: Error = _scheduler.create_notification_channel(channel)
	_initialized = channel_result in [OK, ERR_ALREADY_EXISTS] \
		or (OS.has_feature("ios") and channel_result == ERR_UNAVAILABLE)
	if _initialized and enabled:
		_request_permission_if_needed()


func _request_permission_if_needed() -> void:
	if not _scheduler.has_post_notifications_permission():
		_scheduler.request_post_notifications_permission()


func _on_permission_denied(_permission_name: String) -> void:
	set_enabled(false)


func _schedule_turn_alert(opponent_name: String) -> void:
	var notification := NotificationData.new().set_id(NOTIFICATION_ID).set_channel_id(CHANNEL_ID) \
		.set_title("Pokabow · Your turn").set_content("%s has played. Your turn is ready!" % opponent_name) \
		.set_delay(1)
	var error: Error = _scheduler.schedule(notification)
	if error != OK:
		push_warning("Could not schedule turn alert: %s" % error_string(error))
