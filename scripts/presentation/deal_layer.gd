class_name DealLayer
extends Control

## Deals freshly drawn tiles from the bag's pile into their places in the deck row,
## then turns each one over to show its face (AGENTS.md section 8).
##
## This layer draws an animation and nothing else: it holds no deck, no rule, and
## no count. The screen owns the trigger and measures both ends of the flight, so
## the layer can never disagree with what the row or the pile is showing.
##
## One tile's animation has three phases, and the row draws none of them:
##
##   1. flight - the tile travels from the pile to its place, still face down, so
##      a dealt tile reads as arriving rather than as a row appearing;
##   2. hold   - it rests face down in its place for `HOLD` seconds;
##   3. turn   - it turns over about its vertical axis, showing its back for the
##      first half of the turn and its face for the second.
##
## The row conceals a tile until this layer reports the turn has finished, so a
## tile is never painted twice in one frame and a tile's face is never shown before
## its own turn completes.
##
## Every tile is drawn through `TilePainter`, so a tile in flight is the same
## object as the tile that lands.

## Seconds between one tile starting its flight and the next.
##
## The timings below are the whole speed of a deal: `STAGGER` spaces the tiles out,
## `FLIGHT` is one tile's travel, and `HOLD` plus `FLIP` are the turn that reveals
## a tile's face.
const STAGGER: float = 0.1125

## Seconds one tile takes to travel.
const FLIGHT: float = 0.375

## Seconds a tile rests face down in its place before it turns over.
const HOLD: float = 1.0

## Seconds one tile's turn takes.
const FLIP: float = 0.32

## How far a tile rises above the straight line between the two ends, in pixels.
const ARC_LIFT: float = 44.0

## Size a tile starts at, as a fraction of the size it lands at.
const START_SCALE: float = 0.55

## Emitted whenever another tile finishes turning face up, with that count. The
## screen uses it to stop concealing those tiles in the row.
signal progressed(revealed: int)

## Emitted once, after the last tile has turned over.
signal finished

var _tiles: Array[TileDefinition] = []
var _to: Array[Rect2] = []
var _from: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0
var _revealed: int = 0
var _playing: bool = false


func _ready() -> void:
	# Decorative: pointer events pass straight through to the board and the row.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A deal may have been requested before this node entered the tree, so the
	# flag decides rather than an unconditional stop.
	set_process(_playing)


## Returns true while any tile is still being dealt or turned over.
func is_playing() -> bool:
	return _playing


## Returns how many dealt tiles have finished turning face up.
func revealed_count() -> int:
	return _revealed


## Starts a deal.
##
## `origin` and `destinations` are in GLOBAL coordinates, so the screen can
## measure the pile and the row without knowing this layer's own rectangle; they
## are converted to local space here. Does nothing when the two lists disagree in
## length, because a tile with no destination has nowhere to land.
func deal(
	tiles: Array[TileDefinition], origin: Vector2, destinations: Array[Rect2]
) -> void:
	_tiles = tiles.duplicate()
	_from = _to_local(origin)
	_to = [] as Array[Rect2]
	for rect: Rect2 in destinations:
		_to.append(Rect2(_to_local(rect.position), rect.size))
	_elapsed = 0.0
	_revealed = 0
	_playing = not _tiles.is_empty() and _tiles.size() == _to.size()
	set_process(_playing)
	queue_redraw()
	if _playing and AccessibilitySettings.reduced_motion():
		# Reduced motion: every tile is simply already in its place. The flight,
		# the hold and the turn are the whole animation this layer exists to
		# play, so with them gone there is nothing to draw and the layering
		# above this one is left to show the deck. The row is unconcealed from a
		# deferred call rather than from inside `deal`, so this method never
		# re-enters the screen's own handler while it is still setting up.
		_playing = false
		set_process(false)
		call_deferred("_finish_deal_immediately")


## Drops an in-flight deal at once, revealing nothing further.
##
## The screen calls this when the row is rebuilt for a state the deal no longer
## describes, so a stale animation can never outlive the deck it was drawn from.
func cancel() -> void:
	if not _playing and _tiles.is_empty():
		return
	_playing = false
	_tiles = [] as Array[TileDefinition]
	_to = [] as Array[Rect2]
	_revealed = 0
	_elapsed = 0.0
	set_process(false)
	queue_redraw()


## Completes a deal at once, for a player who has asked for reduced motion.
##
## Reports every tile as revealed and then as finished, exactly as the tail of
## `_process` would, so the row unconceals the whole deck in one step and the
## screen's own completion path still runs. Reporting rather than drawing is
## deliberate: the row remains the single source of the deck's appearance, so a
## reduced-motion deal shows the same deck the animated one ends on.
func _finish_deal_immediately() -> void:
	_playing = false
	set_process(false)
	_revealed = _tiles.size()
	queue_redraw()
	progressed.emit(_revealed)
	finished.emit()


func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	var revealed: int = _count_revealed()
	if revealed != _revealed:
		_revealed = revealed
		progressed.emit(_revealed)
	if _elapsed >= _total_duration():
		_playing = false
		set_process(false)
		_revealed = _tiles.size()
		progressed.emit(_revealed)
		queue_redraw()
		finished.emit()
		return
	queue_redraw()


func _draw() -> void:
	if not _playing:
		return
	for index: int in range(_tiles.size()):
		var target: Rect2 = _to[index]
		var start: float = float(index) * STAGGER
		if _elapsed <= start:
			# Not this tile's turn to leave the pile yet.
			continue
		var landed_at: float = start + FLIGHT
		if _elapsed < landed_at:
			_draw_flight(target, (_elapsed - start) / FLIGHT)
			continue
		var turn_at: float = landed_at + HOLD
		if _elapsed < turn_at:
			# Waiting its turn, in place and still face down.
			TilePainter.paint_tile_back(self, target)
			continue
		var turn_progress: float = (_elapsed - turn_at) / FLIP
		if turn_progress >= 1.0:
			# Turned over: the row draws its face from here on.
			continue
		_draw_turn(index, target, turn_progress)


## Draws a tile on its way from the pile to its place, still face down.
func _draw_flight(target: Rect2, progress: float) -> void:
	var eased: float = _ease_out(progress)
	var centre: Vector2 = _from.lerp(target.get_center(), eased)
	centre.y -= ARC_LIFT * sin(PI * eased)
	var size_at: Vector2 = target.size * lerpf(START_SCALE, 1.0, eased)
	TilePainter.paint_tile_back(self, Rect2(centre - size_at * 0.5, size_at))


## Draws a tile part-way through turning over.
##
## The turn is a horizontal squash about the tile's centre: the back narrows to
## nothing over the first half and the face widens back out over the second, which
## is what reads as a card turning over rather than as one image replacing another.
## The width is floored at half a pixel so the tile never collapses to nothing the
## frame it passes edge-on.
func _draw_turn(index: int, target: Rect2, progress: float) -> void:
	var closing: bool = progress < 0.5
	var width: float = (1.0 - progress * 2.0) if closing else ((progress - 0.5) * 2.0)
	var half: Vector2 = Vector2(maxf(target.size.x * width, 0.5), target.size.y) * 0.5
	var rect: Rect2 = Rect2(target.get_center() - half, half * 2.0)
	if closing:
		TilePainter.paint_tile_back(self, rect)
		return
	TilePainter.paint_tile(
		self, rect, TileSnapshot.create(_tiles[index], BoardMetrics.NO_CELL, 0)
	)


## Returns how many tiles have finished turning face up.
func _count_revealed() -> int:
	var revealed: int = 0
	for index: int in range(_tiles.size()):
		if _elapsed >= _turn_done_at(index):
			revealed += 1
	return revealed


## Returns the moment one tile has finished turning face up.
func _turn_done_at(index: int) -> float:
	return float(index) * STAGGER + FLIGHT + HOLD + FLIP


## Returns the moment the last tile has finished turning face up.
func _total_duration() -> float:
	return float(_tiles.size() - 1) * STAGGER + FLIGHT + HOLD + FLIP


## Returns a decelerating 0-1 curve, so a tile eases into its place.
static func _ease_out(value: float) -> float:
	var clamped: float = clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - clamped, 3.0)


## Converts a GLOBAL point into this control's local drawing space.
##
## `Control` has no `to_local` (that belongs to Node2D and Node3D), and every
## drawing primitive works in local coordinates, so the inverse of this item's
## canvas transform is what turns the screen's global measurements into points
## `_draw` can use.
func _to_local(global_point: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * global_point
