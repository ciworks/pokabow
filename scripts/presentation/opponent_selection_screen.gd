class_name OpponentSelectionScreen
extends Control

## Brief pre-match reveal. Matchmaking is not available yet, so the screen picks
## a packaged portrait from the selected difficulty and reports a local AI.
signal opponent_selected(difficulty: int, rival_portrait: Texture2D)

const FAST_INTERVAL: float = 0.045
const SLOW_INTERVAL: float = 0.34
const RESULT_HOLD_SECONDS: float = 0.55
const RIVAL_ROOT: String = "res://assets/board/characters/rival"
const FALLBACK_PORTRAIT: Texture2D = preload("res://assets/board/characters/avatar_default_rival.png")
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "webp"]
# Legacy shared portraits remain the final fallback until the difficulty folders
# receive their own artwork.
const RIVAL_PORTRAITS: Array[Texture2D] = [
	preload("res://assets/board/characters/rival/ab69a1c9-018b-49ae-b455-780fd781812d.png"),
	preload("res://assets/board/characters/rival/a4f15a59-1dd7-4334-9904-ab44c80acbf4.png"),
	preload("res://assets/board/characters/rival/a480cb6c-9fda-4743-b08e-5ad20820f83a.png"),
	preload("res://assets/board/characters/rival/93c5a576-3c10-48d3-bc42-167992ed19d5.png"),
	preload("res://assets/board/characters/rival/b19f17d8-7856-4533-8c00-ea7bd3745eb6.png"),
	preload("res://assets/board/characters/rival/e7dac3c9-4d3a-4993-b692-fd8ebc8c3716.png"),
	preload("res://assets/board/characters/rival/e91437f5-b572-45af-9226-8a140cc98068.png"),
	preload("res://assets/board/characters/rival/ededa72e-42f4-4d64-b9b9-ed579a90002c.png"),
]

@onready var rival_portrait: TextureRect = %RivalPortrait
@onready var status_label: Label = %StatusLabel
@onready var difficulty_picker: OptionButton = %DifficultyPicker
@onready var start_button: Button = %StartButton
@onready var rival_name_label: Label = %RivalName

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _difficulty: int = AiEnums.DEFAULT_DIFFICULTY
var _rival_portraits: Array[Texture2D] = [] as Array[Texture2D]
var _spin_index: int = 0
var _spin_steps: int = 0
var _spin_ticks: int = 0
var _spin_elapsed: float = 0.0
var _current_interval: float = FAST_INTERVAL
var _result_hold: float = 0.0
var _spinning: bool = false
var _started: bool = false
var _emitted: bool = false


func _ready() -> void:
	_rng.randomize()
	for difficulty: int in AiEnums.Difficulty.values():
		difficulty_picker.add_item(_difficulty_label(difficulty), difficulty)
	difficulty_picker.select(difficulty_picker.get_item_index(_difficulty))
	difficulty_picker.item_selected.connect(_on_difficulty_selected)
	start_button.pressed.connect(_begin_spin)
	rival_name_label.text = "%s AI" % _difficulty_label(_difficulty).to_upper()
	rival_portrait.texture = FALLBACK_PORTRAIT


func _process(delta: float) -> void:
	if not _started or _emitted:
		return
	if not _spinning:
		_result_hold -= delta
		if _result_hold <= 0.0:
			_emitted = true
			opponent_selected.emit(_difficulty, _rival_portraits[_spin_index])
		return

	_spin_elapsed += delta
	while _spin_elapsed >= _current_interval and _spinning:
		_spin_elapsed -= _current_interval
		_spin_index = (_spin_index + 1) % _rival_portraits.size()
		_spin_ticks += 1
		rival_portrait.texture = _rival_portraits[_spin_index]
		var progress: float = clampf(float(_spin_ticks) / float(_spin_steps), 0.0, 1.0)
		var ease_out: float = 1.0 - pow(1.0 - progress, 3.0)
		_current_interval = lerpf(FAST_INTERVAL, SLOW_INTERVAL, ease_out)
		if _spin_ticks >= _spin_steps:
			_spinning = false
			_result_hold = RESULT_HOLD_SECONDS
			status_label.text = "%s AI rival selected" % _difficulty_label(_difficulty)
			rival_name_label.text = "%s AI" % _difficulty_label(_difficulty).to_upper()


func _on_difficulty_selected(index: int) -> void:
	_difficulty = difficulty_picker.get_item_id(index)


func _begin_spin() -> void:
	if _started:
		return
	_difficulty = difficulty_picker.get_item_id(difficulty_picker.selected)
	_rival_portraits = _load_difficulty_portraits(_difficulty)
	if _rival_portraits.is_empty():
		_rival_portraits.append(FALLBACK_PORTRAIT)
		push_warning("OpponentSelectionScreen: no rival portraits found; using the default rival.")
	_spin_index = _rng.randi_range(0, _rival_portraits.size() - 1)
	# Two full passes show every available portrait; the random remainder selects
	# the final portrait uniformly from the selected difficulty's set.
	_spin_steps = _rival_portraits.size() * 2 + _rng.randi_range(0, _rival_portraits.size() - 1)
	_spin_ticks = 0
	_spin_elapsed = 0.0
	_current_interval = FAST_INTERVAL
	_spinning = true
	_started = true
	difficulty_picker.disabled = true
	start_button.disabled = true
	rival_portrait.texture = _rival_portraits[_spin_index]
	status_label.text = "Choosing a %s AI rival..." % _difficulty_label(_difficulty)
	rival_name_label.text = "SELECTING..."


func _load_difficulty_portraits(difficulty: int) -> Array[Texture2D]:
	var portraits: Array[Texture2D] = _load_portraits(_difficulty_folder(difficulty))
	if portraits.is_empty():
		# Use the existing shared art until difficulty-specific images are imported.
		portraits = _load_portraits(RIVAL_ROOT)
	if portraits.is_empty():
		portraits.append_array(RIVAL_PORTRAITS)
	return portraits


func _load_portraits(folder: String) -> Array[Texture2D]:
	var portraits: Array[Texture2D] = [] as Array[Texture2D]
	var directory: DirAccess = DirAccess.open(folder)
	if directory == null:
		return portraits
	var files: PackedStringArray = directory.get_files()
	files.sort()
	for file_name: String in files:
		if not IMAGE_EXTENSIONS.has(file_name.get_extension().to_lower()):
			continue
		var image: Texture2D = load(folder.path_join(file_name)) as Texture2D
		if image != null:
			portraits.append(image)
	return portraits


func _difficulty_folder(difficulty: int) -> String:
	match difficulty:
		AiEnums.Difficulty.EASY:
			return RIVAL_ROOT.path_join("easy")
		AiEnums.Difficulty.MEDIUM:
			return RIVAL_ROOT.path_join("medium")
		AiEnums.Difficulty.HARD:
			return RIVAL_ROOT.path_join("difficult")
	return RIVAL_ROOT.path_join("easy")


func _difficulty_label(difficulty: int) -> String:
	match difficulty:
		AiEnums.Difficulty.EASY:
			return "Easy"
		AiEnums.Difficulty.MEDIUM:
			return "Medium"
		AiEnums.Difficulty.HARD:
			return "Hard"
	return "Easy"
