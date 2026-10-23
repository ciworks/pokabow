class_name ResultInterstitial
extends RefCounted
## Owns one preloaded AdMob interstitial for a completed win or loss.

signal finished

const ANDROID_TEST_UNIT_ID: String = "ca-app-pub-3940256099942544/1033173712"
const IOS_TEST_UNIT_ID: String = "ca-app-pub-3940256099942544/4411468910"
const SHOW_ACK_TIMEOUT_SECONDS: float = 5.0
const DISMISS_TIMEOUT_SECONDS: float = 90.0

static var _sdk_initialized: bool = false

var _ad: InterstitialAd
var _loader: InterstitialAdLoader
var _initialization_listener: OnInitializationCompleteListener
var _load_callback: InterstitialAdLoadCallback
var _content_callback: FullScreenContentCallback
var _generation: int = 0
var _load_started: bool = false
var _awaiting_exit: bool = false
var _ad_shown: bool = false
var _disposed: bool = false


static func is_eligible(result: MatchResult) -> bool:
	return result != null and result.outcome in [
		TurnEnums.MatchOutcome.HUMAN_WIN, TurnEnums.MatchOutcome.AI_WIN
	]


func prepare(result: MatchResult) -> void:
	reset()
	if _disposed or not is_eligible(result):
		return
	var unit_id: String = ""
	if OS.get_name() == "Android":
		unit_id = String(ProjectSettings.get_setting(
			"pokabow/ads_android_interstitial_unit_id", ANDROID_TEST_UNIT_ID))
	elif OS.get_name() == "iOS":
		unit_id = String(ProjectSettings.get_setting(
			"pokabow/ads_ios_interstitial_unit_id", IOS_TEST_UNIT_ID))
	else:
		return
	if (unit_id.is_empty() or not Engine.has_singleton("PoingGodotAdMob")
			or not Engine.has_singleton("PoingGodotAdMobInterstitialAd")):
		return
	_prepare_available_unit(unit_id)


func _prepare_available_unit(unit_id: String) -> void:
	var request_generation: int = _generation
	if _sdk_initialized:
		_load_ad(unit_id, request_generation)
		return
	_initialization_listener = OnInitializationCompleteListener.new()
	_initialization_listener.on_initialization_complete = func(_status: InitializationStatus) -> void:
		if _disposed or request_generation != _generation:
			return
		_sdk_initialized = true
		_initialization_listener = null
		_load_ad(unit_id, request_generation)
	_start_sdk_initialization()


func _start_sdk_initialization() -> void:
	MobileAds.initialize(_initialization_listener)


func _load_ad(unit_id: String, request_generation: int) -> void:
	if _disposed or request_generation != _generation or _load_started:
		return
	_load_started = true
	_load_callback = InterstitialAdLoadCallback.new()
	_load_callback.on_ad_loaded = func(ad: InterstitialAd) -> void:
		if _disposed or request_generation != _generation:
			ad.destroy()
			return
		_ad = ad
		_content_callback = FullScreenContentCallback.new()
		_content_callback.on_ad_showed_full_screen_content = _on_ad_shown
		_content_callback.on_ad_dismissed_full_screen_content = _on_ad_closed
		_content_callback.on_ad_failed_to_show_full_screen_content = func(error: AdError) -> void:
			push_warning("Result interstitial could not show: " + error.message)
			_on_ad_closed()
		_ad.full_screen_content_callback = _content_callback
	_load_callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		if not _disposed and request_generation == _generation:
			push_warning("Result interstitial could not load: " + error.message)
	_loader = InterstitialAdLoader.new()
	_loader.load(unit_id, AdRequest.new(), _load_callback)


## Returns false when navigation should continue without an ad.
func show_if_ready() -> bool:
	if _disposed or _ad == null or _awaiting_exit:
		return false
	_awaiting_exit = true
	_ad_shown = false
	_watch_for_missing_callback(SHOW_ACK_TIMEOUT_SECONDS, false)
	_ad.show()
	return true


func _on_ad_shown() -> void:
	if not _awaiting_exit or _disposed:
		return
	_ad_shown = true
	_watch_for_missing_callback(DISMISS_TIMEOUT_SECONDS, true)


func _watch_for_missing_callback(seconds: float, shown: bool) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var request_generation: int = _generation
	tree.create_timer(seconds).timeout.connect(
		func() -> void:
			if _disposed or request_generation != _generation or not _awaiting_exit:
				return
			if _ad_shown != shown:
				return
			push_warning("Result interstitial stopped responding; returning to hub.")
			_on_ad_closed(), CONNECT_ONE_SHOT)


func _on_ad_closed() -> void:
	var should_finish: bool = _awaiting_exit and not _disposed
	reset()
	if should_finish:
		# Keep navigation outside the plugin's dismissal/failure callback.
		call_deferred("_emit_finished")


func _emit_finished() -> void:
	if not _disposed:
		finished.emit()


func reset() -> void:
	_generation += 1
	_load_started = false
	_awaiting_exit = false
	_ad_shown = false
	if _ad != null:
		_ad.destroy()
		_ad = null
	_loader = null
	_initialization_listener = null
	_load_callback = null
	_content_callback = null


func dispose() -> void:
	_disposed = true
	reset()
