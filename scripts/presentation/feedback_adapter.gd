class_name FeedbackAdapter
extends Node

## Reports the number of sound cues loaded during startup, so the splash can
## show real progress rather than a timed animation.
signal audio_preload_progress(completed: int, total: int)
signal audio_preload_completed

## The platform feedback service: haptics and sound, the two channels ADR-008
## section 5 calls the platform feedback adapter (Milestone 8,
## docs/sections/05-mobile-ux.md sections 5 and 6).
##
## Both channels are OPTIONAL by specification: the game must be fully playable
## with them off, so every call here is a no-op when its own channel is disabled
## and no rule, score, or turn path depends on a cue having fired. Nothing in this
## file reads game state or decides anything - it is told that a moment happened
## and chooses a vibration length and a sound for it.
##
## Sound is the second channel, wired the same way haptics are: one short one-shot
## per cue under `res://assets/audio/`, loaded ONCE when this node enters the tree
## and cached, then played on a small pool of `AudioStreamPlayer` children of this
## node. No autoload holds them, because a service in a global is exactly what
## ADR-008 section 6 forbids and the screen already holds this adapter by
## injection.
##
## The screen calls player-action cues when a human gesture resolves. Deal-card
## sounds are the exception: both human and rival refill animations call them as
## each card leaves the pot, because those visible flights deserve the same cue.
##
## It is created by `AppRoot` and injected into the screen (ADR-008 section 5),
## so no scene script reaches for a global and a headless screen simply has no
## adapter attached.

## Project setting that turns haptics off for a whole build.
##
## Read with a `true` default, so a project that never sets it gets the cues and
## nothing has to be written to project.godot for the normal case.
const SETTING_PATH: String = "feedback/haptics"

## Cue lengths in milliseconds.
##
## Short by design: these confirm a gesture the player already made, so they
## should read as a tap rather than an alarm. The refusal cue is the longest
## because it is the one carrying new information - the move did not happen.
const CUE_SELECT_MS: int = 8
const CUE_PLACE_MS: int = 22
const CUE_SCORE_MS: int = 40
const CUE_REFUSE_MS: int = 55
const CUE_MATCH_END_MS: int = 120

## Project setting that turns cue sound off for a whole build.
##
## Read with a `true` default, so a project that never sets it still hears the
## game, and kept separate from `feedback/haptics` because the two channels answer
## different wishes: a player may want a phone in their pocket to stay silent
## while the vibrations still confirm their tap, and the reverse.
const AUDIO_SETTING_PATH: String = "feedback/audio"

## Cue names, used as the keys of the two tables below.
##
## Constants rather than loose strings so a cue method, its entry in `CUE_SOUNDS`,
## and its entry in `CUE_VOLUMES_DB` cannot drift apart without a code change.
const CUE_SELECT: String = "select"
const CUE_PLACE: String = "place"
const CUE_SCORE: String = "score"
const CUE_REFUSE: String = "refuse"
const CUE_MATCH_END: String = "match_end"
const CUE_DEAL_CARD: String = "deal_card"
const CUE_TILE_FLIP: String = "tile_flip"

## The sound file behind each cue, loaded once in `_ready` and cached here.
##
## The cues are short one-shots loaded and cached once. A cue pointed at an empty
## string is silent ON PURPOSE: a missing or absent sound is a
## correct outcome for a cue that nothing suitable was found for, so it must read
## as a quiet no-op rather than as a fault the player can hear or the log reports.
const CUE_SOUNDS: Dictionary = {
	CUE_SELECT: "res://assets/audio/sfx_select_card_touch.wav",
	CUE_PLACE: "res://assets/audio/sfx_place_card_felt.wav",
	CUE_SCORE: "res://assets/audio/sfx_score_chime.wav",
	CUE_REFUSE: "res://assets/audio/sfx_refuse_dull_tap.wav",
	CUE_MATCH_END: "res://assets/audio/sfx_match_end_resolve.wav",
	CUE_DEAL_CARD: "res://assets/audio/deal-tile.mp3",
	CUE_TILE_FLIP: "res://assets/audio/tile-pop.mp3",
}

## Per-cue gain in decibels.
##
## Every value is negative, because a positive `volume_db` clips and one-shots
## belong between -24 and 0. The select tick is the quietest of the six on
## purpose: it fires on every deck tap, so it has to survive repetition. The
## placement thud carries the most weight, because it is the sound that says the
## move happened.
const CUE_VOLUMES_DB: Dictionary = {
	CUE_SELECT: -14.0,
	CUE_PLACE: -7.0,
	CUE_SCORE: -10.0,
	CUE_REFUSE: -9.0,
	CUE_MATCH_END: -7.0,
	# Halved the current amplitude from -12.5 dB, adding about 6 dB attenuation.
	CUE_DEAL_CARD: -18.5,
	# Quarter amplitude after a 75% reduction from the cue's nominal 0 dB level.
	CUE_TILE_FLIP: -18.0,
}

## How many players the sound pool holds.
##
## Not one, because several cues can land inside the same frame: the screen plays
## one score popup per award, and each popup cues the score sound, so a good move
## asks for three or four chimes before the next frame is drawn. On a single
## player each `play()` would cut the chime before it, which hears as a clipped
## click rather than a reward; a pool gives each of those calls its own player so
## they stack and decay the way the popups do. Past six voices the cursor wraps
## onto the oldest player, which is harmless here: nothing queued is longer than
## about a second.
const VOICE_POOL_SIZE: int = 6

## Whether haptics are on. Defaults to the project setting, and can be changed at
## runtime so a settings screen can offer a switch without a rebuild.
var haptics_enabled: bool = true

## Whether cue sound is on. Defaults to the project setting, and can be changed at
## runtime, so a settings screen can offer sound beside vibration.
var audio_enabled: bool = true

## Loaded cue streams, keyed by cue name, built once in `_ready`.
##
## A plain `Dictionary` holding `AudioStream` or `null`: a cue with no sound is a
## legitimate cached state, not an error, which is what keeps sound optional.
var _streams: Dictionary = {}

## The players that make the noise, all children of this node (ADR-008 section 5:
## the adapter owns its own platform presentation and nothing reaches for a
## global to find it).
var _players: Array[AudioStreamPlayer] = []

## Which player the next cue takes. Round-robin, so a burst of awards spreads
## across the pool instead of replaying over the first voice.
var _next_voice: int = 0
var _audio_loading: bool = false
var _audio_loaded: bool = false


func _ready() -> void:
	haptics_enabled = bool(ProjectSettings.get_setting(SETTING_PATH, true))
	audio_enabled = bool(ProjectSettings.get_setting(AUDIO_SETTING_PATH, true))
	_build_audio()


## Turns the cues on or off at runtime.
##
## Turning them off is always safe: no rule path reads this, so a match plays
## identically. That is what makes haptics optional rather than required
## (docs/sections/05-mobile-ux.md section 6).
func set_haptics_enabled(enabled: bool) -> void:
	haptics_enabled = enabled


## Returns whether cues are currently firing.
func is_haptics_enabled() -> bool:
	return haptics_enabled


## Turns cue sound on or off at runtime, mirroring `set_haptics_enabled`.
##
## Turning it off is safe for the same reason haptics are: no rule path reads it,
## so a match plays identically and a cue simply stops making a noise. Turning it
## back on reuses whatever `_ready` already cached, so nothing is loaded while the
## player is mid-tap, and a cue that had no sound stays silent.
func set_audio_enabled(enabled: bool) -> void:
	audio_enabled = enabled


## Returns whether cue sounds are currently playing.
func is_audio_enabled() -> bool:
	return audio_enabled


## The player chose a deck tile.
func cue_select() -> void:
	_vibrate(CUE_SELECT_MS)
	_play_cue(CUE_SELECT)


## A tile joined the pending line, or a line was committed.
func cue_place() -> void:
	_vibrate(CUE_PLACE_MS)
	_play_cue(CUE_PLACE)


## A move was awarded points.
func cue_score() -> void:
	_vibrate(CUE_SCORE_MS)
	_play_cue(CUE_SCORE)


## A gesture was refused and nothing changed.
func cue_refuse() -> void:
	_vibrate(CUE_REFUSE_MS)
	_play_cue(CUE_REFUSE)


## The match reached an end condition.
func cue_match_end() -> void:
	_vibrate(CUE_MATCH_END_MS)
	_play_cue(CUE_MATCH_END)


## A card left the pot for either player's hand.
func cue_deal_card() -> void:
	_play_cue(CUE_DEAL_CARD)


## Plays the sound as a dealt tile starts turning face up.
func cue_tile_flip() -> void:
	_play_cue(CUE_TILE_FLIP)


func cue_duration_seconds(cue: String) -> float:
	var stream: AudioStream = _streams.get(cue) as AudioStream
	return 0.0 if stream == null else stream.get_length()


## Fires one handheld vibration, or does nothing when haptics are off.
##
## `Input.vibrate_handheld` is a no-op on a platform with no vibrator, so this
## needs no platform check: the same line runs on desktop development and on a
## phone, and desktop development simply feels nothing.
func _vibrate(duration_ms: int) -> void:
	if not haptics_enabled:
		return
	if duration_ms <= 0:
		return
	Input.vibrate_handheld(duration_ms)


## Plays one cue's sound, or does nothing when sound is off, the cue has no sound,
## or that sound did not load.
##
## Deliberately independent of `_vibrate`: the two channels never gate each other,
## so a build with sound off still buzzes and a device with no vibrator still
## speaks. The non-playing cases are the whole of "sound is optional" - the caller
## in the screen is unaffected, and no gameplay path can tell whether a sound came
## out.
func _play_cue(cue: String) -> void:
	if not audio_enabled:
		return
	var stream: AudioStream = _streams.get(cue) as AudioStream
	if stream == null:
		return
	var player: AudioStreamPlayer = _take_voice()
	if player == null:
		return
	player.stream = stream
	player.volume_db = float(CUE_VOLUMES_DB.get(cue, 0.0))
	player.play()


## Creates the voice pool and loads every cue sound, once.
##
## Called from `_ready`, never from a cue: a cue fires while the player is tapping
## and loading a resource inside that call would stall the frame the tap landed
## in. The pool is built here too so the cue path only ever assigns and plays.
func _build_audio() -> void:
	if _audio_loading or _audio_loaded:
		return
	_audio_loading = true
	if _players.is_empty():
		for index: int in VOICE_POOL_SIZE:
			var player: AudioStreamPlayer = AudioStreamPlayer.new()
			player.name = "CueVoice%d" % index
			add_child(player)
			_players.append(player)
	var total: int = CUE_SOUNDS.size()
	var completed: int = 0
	for cue: String in CUE_SOUNDS:
		var path: String = String(CUE_SOUNDS[cue])
		var stream: AudioStream = _load_cue_stream(path)
		_streams[cue] = stream
		completed += 1
		audio_preload_progress.emit(completed, total)
		if completed < total:
			await get_tree().process_frame
	_audio_loading = false
	_audio_loaded = true
	audio_preload_completed.emit()


## Loads one cue sound as an `AudioStream`, or `null` when there is nothing to
## play.
##
## Prefers the imported resource, then falls back to source MP3 bytes if needed.
## Missing or stripped assets cache as `null` and play silence.
func _load_cue_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null and path.get_extension().to_lower() == "mp3":
		stream = _load_mp3_source(path)
	return stream


## Uses the source MP3 bytes when the imported resource is not available.
func _load_mp3_source(path: String) -> AudioStream:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes: PackedByteArray = file.get_buffer(int(file.get_length()))
	file.close()
	if bytes.is_empty():
		return null
	var stream: AudioStreamMP3 = AudioStreamMP3.new()
	stream.data = bytes
	return stream


## Hands out the next player in the pool and advances the cursor.
##
## Round-robin rather than "the first idle voice", so a voice still ringing out is
## only reused after the pool has gone all the way round: overlapping score chimes
## each get their own player and none of them cuts off the one before it.
func _take_voice() -> AudioStreamPlayer:
	if _players.is_empty():
		return null
	var voice: int = _next_voice % _players.size()
	_next_voice = (voice + 1) % _players.size()
	return _players[voice]
