class_name RewardedAdController
extends Node
## Starts an authenticated AdMob reward session and waits for verified wallet credit.

signal status_received(data: Dictionary)
signal progress(message: String)
signal notice(message: String)
signal credited
signal authentication_required

var access_token: String = ""
var account_id: String = ""
var _request: HTTPRequest
var _ad: RewardedAd
var _loader: RewardedAdLoader
var _load_callback: RewardedAdLoadCallback
var _content_callback: FullScreenContentCallback
var _reward_listener: OnUserEarnedRewardListener
var _init_listener: OnInitializationCompleteListener
var _poll: Timer
var _unlock: Timer
var _generation: int = 0
var _earned: bool = false
var _poll_count: int = 0
var _earned_at_msec: int = 0
var _busy: bool = false
var _load_waiting: bool = false


func _ready() -> void:
	_poll = Timer.new()
	_poll.wait_time = 3.0
	_poll.timeout.connect(_poll_status)
	add_child(_poll)
	_unlock = Timer.new()
	_unlock.one_shot = true
	_unlock.timeout.connect(refresh_status)
	add_child(_unlock)


func set_credentials(token: String, user_id: String) -> void:
	if token == access_token and user_id == account_id:
		return
	_generation += 1
	if _request != null:
		_request.cancel_request()
		_request.queue_free()
		_request = null
	_destroy_ad()
	_poll.stop()
	_poll.wait_time = 3.0
	_unlock.stop()
	_busy = false
	_load_waiting = false
	_earned = false
	access_token = token
	account_id = user_id


func refresh_status() -> void:
	if access_token.is_empty() or account_id.is_empty() or _request != null:
		return
	_send("GET", "/gems/rewarded-ad/status")


func request_ad() -> void:
	if _busy or _request != null:
		return
	if access_token.is_empty() or account_id.is_empty():
		notice.emit("Sign in to watch a rewarded ad.")
		return
	var unit_id := _unit_id()
	if unit_id.is_empty() or not Engine.has_singleton("PoingGodotAdMob") or \
			not Engine.has_singleton("PoingGodotAdMobRewardedAd"):
		notice.emit("Rewarded ads are unavailable on this device.")
		return
	_busy = true
	_earned = false
	progress.emit("Preparing your ad…")
	_send("POST", "/gems/rewarded-ad/session")


func _unit_id() -> String:
	if OS.get_name() == "Android":
		return String(ProjectSettings.get_setting("pokabow/ads_android_rewarded_unit_id", ""))
	if OS.get_name() == "iOS":
		return String(ProjectSettings.get_setting("pokabow/ads_ios_rewarded_unit_id", ""))
	return ""


func _send(method: String, path: String) -> void:
	_request = HTTPRequest.new()
	_request.timeout = 15.0
	add_child(_request)
	var generation := _generation
	_request.request_completed.connect(_on_response.bind(_request, path, generation))
	var error := _request.request(ApiConfiguration.api_base_url() + path,
		PackedStringArray(["Authorization: Bearer %s" % access_token]),
		HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET)
	if error != OK:
		_request.queue_free()
		_request = null
		_busy = false
		notice.emit("Could not connect to the ad service. Try again.")


func _on_response(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, request: HTTPRequest, path: String, generation: int) -> void:
	request.queue_free()
	if _request == request:
		_request = null
	if generation != _generation:
		return
	if code == 401:
		_busy = false
		authentication_required.emit()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if path.ends_with("/status"):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and parsed is Dictionary:
			var status := parsed as Dictionary
			if not _busy or not bool(status.get("available", true)):
				status_received.emit(status)
			_schedule_unlock(status)
			if _earned and not bool(status.get("available", true)) and status.get("nextAvailableAtUnix") != null:
				_earned = false
				_busy = false
				_poll.stop()
				_poll.wait_time = 3.0
				credited.emit()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not parsed is Dictionary:
		_busy = false
		if code == 429 and parsed is Dictionary:
			notice.emit("Today's ad reward has already been used.")
			refresh_status()
		else:
			notice.emit("Could not start the ad. Try again.")
		return
	var session_id := String((parsed as Dictionary).get("sessionId", ""))
	if session_id.is_empty():
		_busy = false
		notice.emit("Could not start the ad. Try again.")
		return
	_load_ad(session_id, generation)


func _load_ad(session_id: String, generation: int) -> void:
	_load_waiting = true
	_load_callback = RewardedAdLoadCallback.new()
	_load_callback.on_ad_loaded = func(ad: RewardedAd) -> void:
		if generation != _generation or not _load_waiting:
			ad.destroy()
			return
		_load_waiting = false
		_ad = ad
		var options := ServerSideVerificationOptions.new()
		options.user_id = account_id
		options.custom_data = session_id
		ad.set_server_side_verification_options(options)
		_content_callback = FullScreenContentCallback.new()
		_content_callback.on_ad_dismissed_full_screen_content = func() -> void:
			if generation == _generation:
				_on_ad_closed()
		_content_callback.on_ad_failed_to_show_full_screen_content = func(_error: AdError) -> void:
			if generation == _generation:
				_on_ad_closed()
		ad.full_screen_content_callback = _content_callback
		_reward_listener = OnUserEarnedRewardListener.new()
		_reward_listener.on_user_earned_reward = func(item: RewardedItem) -> void:
			if generation == _generation:
				_on_reward_earned(item)
		ad.show(_reward_listener)
	_load_callback.on_ad_failed_to_load = func(_error: LoadAdError) -> void:
		if generation == _generation and _load_waiting:
			_load_waiting = false
			_busy = false
			notice.emit("An ad is not available right now. Try again later.")
	_loader = RewardedAdLoader.new()
	if ResultInterstitial._sdk_initialized:
		_loader.load(_unit_id(), AdRequest.new(), _load_callback)
	else:
		_init_listener = OnInitializationCompleteListener.new()
		_init_listener.on_initialization_complete = func(_status: InitializationStatus) -> void:
			if generation == _generation and _load_waiting:
				ResultInterstitial._sdk_initialized = true
				_loader.load(_unit_id(), AdRequest.new(), _load_callback)
		MobileAds.initialize(_init_listener)
	get_tree().create_timer(20.0).timeout.connect(func() -> void:
		if generation == _generation and _load_waiting:
			_load_waiting = false
			_busy = false
			notice.emit("The ad took too long to load. Try again."))


func _on_reward_earned(_item: RewardedItem) -> void:
	_earned = true
	_earned_at_msec = Time.get_ticks_msec()
	_poll_count = 0
	_poll.wait_time = 3.0
	_poll.start()
	refresh_status()
	progress.emit("Checking your Gem reward…")


func _on_ad_closed() -> void:
	_destroy_ad()
	if not _earned:
		var generation := _generation
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if generation == _generation and not _earned:
				_busy = false
				notice.emit("No reward earned. You can try again."))


func _destroy_ad() -> void:
	if _ad != null:
		_ad.destroy()
		_ad = null
	_loader = null
	_load_callback = null
	_content_callback = null
	_reward_listener = null
	_init_listener = null


func _poll_status() -> void:
	if not _earned:
		_poll.stop()
		return
	_poll_count += 1
	if Time.get_ticks_msec() - _earned_at_msec >= 2 * 60 * 60 * 1000:
		_poll.stop()
		_poll.wait_time = 3.0
		_earned = false
		_busy = false
		notice.emit("Could not confirm the Gem reward. You can try again.")
		return
	if _poll_count == 30:
		_poll.wait_time = 30.0
		_poll.start()
		notice.emit("Gem confirmation is taking longer than expected.")
	refresh_status()


func _schedule_unlock(status: Dictionary) -> void:
	_unlock.stop()
	var next: Variant = status.get("nextAvailableAtUnix")
	if next == null:
		return
	var seconds := float(next) - Time.get_unix_time_from_system()
	if seconds > 0.0:
		_unlock.start(minf(seconds + 1.0, 86400.0))


