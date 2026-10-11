class_name ConfettiLayer
extends Control

## Confetti falling over the screen while the final summary is on it.
##
## Decoration and nothing else: this layer holds no rule, awards no point, and
## advances no turn. The screen owns the trigger, so the stream runs because a
## match ended rather than because this layer decided one had.
##
## The pieces are a fixed pool. One that falls past the bottom is sent back above
## the top with fresh values, so the stream keeps falling for as long as the
## summary is up without allocating anything per frame.
##
## It is drawn UNDER the summary panel and ignores the pointer, so the panel that
## reports who won stays readable and keeps every tap.

## Pieces in the stream. Enough to read as a stream on a 1280x720 screen without
## the draw call becoming the frame's cost.
const PIECE_COUNT: int = 150

## Vertical speed of a piece, in pixels per second.
const FALL_SPEED_MIN: float = 130.0
const FALL_SPEED_MAX: float = 320.0

## Sideways speed of a piece's baseline, in pixels per second.
const DRIFT_SPEED: float = 42.0

## Sideways sway: amplitude in pixels, rate in radians per second.
const SWAY_AMPLITUDE: float = 24.0
const SWAY_RATE_MIN: float = 1.0
const SWAY_RATE_MAX: float = 2.4

## A piece's size in pixels, upright, before its own rotation.
const PIECE_SIZE: Vector2 = Vector2(9.0, 15.0)

## Rotation speed, in radians per second.
const SPIN_RATE: float = 4.0

## How far outside the screen a piece is recycled, in pixels, so a piece is never
## seen appearing or vanishing at an edge in view.
const MARGIN: float = 40.0

## The celebration palette. Deliberately not the edge palette: those four colours
## mean "edge match" on the board, and a decoration must not borrow that meaning.
const COLORS: Array[Color] = [
	Color(1.0, 0.84, 0.29, 1.0),
	Color(1.0, 1.0, 1.0, 1.0),
	Color(0.95, 0.29, 0.34, 1.0),
	Color(0.29, 0.78, 0.94, 1.0),
	Color(0.44, 0.86, 0.53, 1.0),
	Color(0.72, 0.55, 0.95, 1.0),
]

## Fixed seed, so the same moment always celebrates the same way.
const SEED: int = 20261003


## One piece of confetti.
##
## `base_x` is the middle of the piece's sway; the drawn x adds the sway on top,
## so drifting and swaying stay independent of each other.
class Piece:
	var base_x: float = 0.0
	var y: float = 0.0
	var fall: float = 0.0
	var drift: float = 0.0
	var sway_phase: float = 0.0
	var sway_rate: float = 0.0
	var rotation: float = 0.0
	var spin: float = 0.0
	var color: Color = Color.WHITE


var _pieces: Array[Piece] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _playing: bool = false


func _ready() -> void:
	# Decoration: the summary panel underneath keeps every tap and every drag.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A play may have been requested before this node entered the tree, so the
	# flag decides rather than an unconditional stop.
	set_process(_playing)


## Returns true while confetti is on screen.
func is_playing() -> bool:
	return _playing


## Starts the stream.
##
## Reduced motion: falling confetti is the whole animation this layer exists to
## play, so with it switched on there is nothing to show and the layer stays
## empty. The summary reports the same result either way.
func play() -> void:
	if AccessibilitySettings.reduced_motion():
		clear()
		return
	if _playing:
		return
	_rng.seed = SEED
	_pieces = [] as Array[Piece]
	for index: int in range(PIECE_COUNT):
		# Spread over the screen, so the first frame already reads as a stream
		# rather than as one row of pieces at the top.
		_pieces.append(_new_piece(true))
	_playing = true
	set_process(true)
	queue_redraw()


## Stops the stream and drops every piece.
##
## The screen calls this when a match starts, so a celebration can never outlive
## the summary it belongs to.
func clear() -> void:
	if not _playing and _pieces.is_empty():
		return
	_playing = false
	_pieces = [] as Array[Piece]
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	if not _playing:
		return
	for piece: Piece in _pieces:
		_advance(piece, delta)
	queue_redraw()


func _draw() -> void:
	if not _playing:
		return
	for piece: Piece in _pieces:
		_draw_piece(piece)


## Draws one piece as a rectangle turned about its own centre.
##
## The four corners are rotated here rather than through `draw_set_transform`, so
## this loop never leaves a transform behind for whatever draws after it.
func _draw_piece(piece: Piece) -> void:
	var half: Vector2 = PIECE_SIZE * 0.5
	var centre := Vector2(piece.base_x + sin(piece.sway_phase) * SWAY_AMPLITUDE, piece.y)
	var corners := PackedVector2Array(
		[
			centre + Vector2(-half.x, -half.y).rotated(piece.rotation),
			centre + Vector2(half.x, -half.y).rotated(piece.rotation),
			centre + Vector2(half.x, half.y).rotated(piece.rotation),
			centre + Vector2(-half.x, half.y).rotated(piece.rotation),
		]
	)
	draw_colored_polygon(corners, piece.color)


## Moves one piece by one frame, recycling it once it is out of view.
func _advance(piece: Piece, delta: float) -> void:
	piece.y += piece.fall * delta
	piece.base_x += piece.drift * delta
	piece.sway_phase += piece.sway_rate * delta
	piece.rotation += piece.spin * delta
	if piece.y - PIECE_SIZE.y > size.y + MARGIN:
		_respawn(piece)
		return
	_wrap_horizontally(piece)


## Keeps a drifting piece on the screen by moving it a whole screen-wide span
## sideways, which leaves its own drift and sway untouched.
func _wrap_horizontally(piece: Piece) -> void:
	var span: float = maxf(size.x, 1.0) + MARGIN * 2.0
	if piece.base_x < -MARGIN:
		piece.base_x += span
	elif piece.base_x > size.x + MARGIN:
		piece.base_x -= span


## Returns a piece with fresh random values.
func _new_piece(spread: bool) -> Piece:
	var piece: Piece = Piece.new()
	_randomise(piece, spread)
	return piece


## Sends one piece back above the top with new values.
func _respawn(piece: Piece) -> void:
	_randomise(piece, false)


## Gives `piece` a new set of random values.
##
## `spread` places it somewhere down the screen instead of above the top, which
## is only wanted for the pieces the first frame starts with.
func _randomise(piece: Piece, spread: bool) -> void:
	var screen: Vector2 = Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	piece.fall = _rng.randf_range(FALL_SPEED_MIN, FALL_SPEED_MAX)
	piece.drift = _rng.randf_range(-DRIFT_SPEED, DRIFT_SPEED)
	piece.sway_phase = _rng.randf_range(0.0, TAU)
	piece.sway_rate = _rng.randf_range(SWAY_RATE_MIN, SWAY_RATE_MAX)
	piece.rotation = _rng.randf_range(0.0, TAU)
	piece.spin = _rng.randf_range(-SPIN_RATE, SPIN_RATE)
	piece.color = COLORS[_rng.randi_range(0, COLORS.size() - 1)]
	piece.base_x = _rng.randf_range(-MARGIN, screen.x + MARGIN)
	if spread:
		piece.y = _rng.randf_range(-MARGIN, screen.y + MARGIN)
	else:
		# Staggered above the top, so a recycled batch does not arrive as one row.
		piece.y = -MARGIN - _rng.randf_range(0.0, screen.y * 0.4)
