class_name DeckView
extends Control

## The human's hand: a horizontal, selectable spread of deck tiles under the
## board (ADR-010 sections 4 and 12).
##
## ADR-010 section 12 makes the deck a horizontal spread of tiles under the board
## and makes selecting a deck tile the action that arms a placement. This control
## is that row.
##
## AGENTS.md section 19 and ADR-008 section 4 keep presentation out of the rules,
## so this view does one job: it draws the tiles it is handed and reports which
## one the player tapped. It does not read a rule, does not evaluate legality,
## does not score, and does not decide whether the row is interactive: the screen
## supplies both the tiles and the interactivity, and the screen forwards the
## selection to the application controller, which is the only place a tile is
## armed (ADR-008 section 7).
##
## The row is laid out by the screen's containers and this control draws inside
## whatever rectangle that layout gives it, so it never states a pixel position
## of its own (ADR-008 section 8).
##
## Drawing and hit-testing share one geometry function, `tile_rect`, so a tap can
## never land on a different tile from the one drawn under the finger.

## Emitted when the player taps a deck tile, with that tile's identity.
signal tile_selected(tile_id: StringName)

## Emitted when the player taps a deck tile while the row is in mark mode
## (ADR-011 section 6: the tiles a swap would return).
signal tile_toggled(tile_id: StringName)

## Gap between tiles as a fraction of one tile's width.
const GAP_RATIO: float = 0.10

## Air left inside the control so tiles never touch the panel edge.
const PADDING: float = 8.0

## How far the selected tile is lifted, as a fraction of the tile's height.
const SELECTED_LIFT_RATIO: float = 0.06

## Thickness of the selected tile's outline, in pixels.
const SELECTED_OUTLINE: float = 3.0

## Selection outline colour. Presentation only, like the tile palette.
const SELECTED_COLOR: Color = Color(1.0, 0.86, 0.42, 1.0)

## Outline colour of a tile marked for the swap, so a marked tile is never
## mistaken for the tile the next staging command takes.
const MARKED_COLOR: Color = Color(0.52, 0.78, 1.0, 1.0)

## Inner inset of the marked outline, in pixels, so the two outlines can both be
## read on one tile.
const MARKED_INSET: float = 3.0

## The player's tiles, in deck order.
var _deck: Array[TileDefinition] = []

## Index of the tile drawn as selected; -1 when the deck is empty.
var _selected_index: int = -1

## True while the row rejects taps, because it is not the player's turn.
var _locked: bool = true

## True while the row collects a set of tiles instead of one selection
## (ADR-011 section 6).
var _mark_mode: bool = false

## Identities the player has marked for the swap, filtered to the drawn deck on
## every redraw so a marked tile that left the deck is never drawn as marked.
var _marked: Array[StringName] = []


## Accepts taps, so the row can arm a placement.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


## Replaces the drawn deck and the selected tile (ADR-010 section 10).
##
## `tiles` is the human's deck in deal order; `selected_id` is the tile the
## application controller reports as armed, or an empty name when none is. The row
## never keeps its own idea of which tile is armed: the application layer owns
## that choice, so a redraw cannot disagree with the next placement.
func set_deck(tiles: Array[TileDefinition], selected_id: StringName = &"") -> void:
	_deck = []
	for tile: TileDefinition in tiles:
		if tile != null:
			_deck.append(tile)
	_prune_marked()
	_selected_index = _index_of(_deck, selected_id)
	if _selected_index < 0 and not _deck.is_empty():
		# Nothing is armed yet, so the deck's first tile is the one a placement
		# would commit and the one drawn as selected.
		_selected_index = 0
	queue_redraw()


## Returns how many tiles the row is showing.
func deck_size() -> int:
	return _deck.size()


## Returns the identity of the selected tile, or an empty name when the row is
## empty. The row is never the authority for this: compare it against the
## controller when a test needs to know which tile a placement would commit.
func selected_tile_id() -> StringName:
	if _selected_index < 0 or _selected_index >= _deck.size():
		return &""
	return _deck[_selected_index].tile_id


## Returns true while the row rejects taps (not the player's turn).
func is_locked() -> bool:
	return _locked


## Enables or disables interaction. A locked row still draws the deck, because
## what the player holds is not a secret from them (ADR-010 section 10).
func set_locked(locked: bool) -> void:
	_locked = locked
	queue_redraw()


## Selects `tile_id` in the drawn row without emitting `tile_selected`.
##
## Used by the screen when the selection came from somewhere else, so the row
## always reflects the tile the application layer has armed.
func set_selected(tile_id: StringName) -> void:
	var index: int = _index_of(_deck, tile_id)
	if index < 0:
		# The tile is no longer held (it was just committed), so fall back to the
		# first remaining tile rather than pointing past the deck.
		index = 0 if not _deck.is_empty() else -1
	if index == _selected_index:
		return
	_selected_index = index
	queue_redraw()


## Draws the tile row, the selection outline, and any swap marks.
##
## While the row is collecting a swap set it draws no selection and no lift: the
## tiles a swap returns are a set of marks (ADR-011 section 6), no tile is armed
## for a staging that a whole-turn swap would consume, and an un-lifted row makes
## the drawn tile exactly the shape and place the finger has to hit.
func _draw() -> void:
	if _deck.is_empty():
		return
	for index: int in range(_deck.size()):
		var rect: Rect2 = tile_rect(index, _deck.size(), size)
		if not TilePainter.is_drawable(rect):
			continue
		if index == _selected_index and not _mark_mode:
			rect = _lifted(rect)
			# TilePainter reads a tile's visible edges from a snapshot, so the
			# row draws the identical face the board would commit (ADR-006
			# section 5, ADR-010 section 12).
			TilePainter.paint_tile(
				self, rect, TileSnapshot.create(_deck[index], BoardMetrics.NO_CELL, 0)
			)
			draw_rect(rect, SELECTED_COLOR, false, SELECTED_OUTLINE)
			_draw_mark(index, rect)
			continue
		TilePainter.paint_tile(
			self, rect, TileSnapshot.create(_deck[index], BoardMetrics.NO_CELL, 0)
		)
		_draw_mark(index, rect)


## Outlines one tile when it is marked for the swap (ADR-011 section 6).
func _draw_mark(index: int, rect: Rect2) -> void:
	if not is_marked(_deck[index].tile_id):
		return
	draw_rect(rect.grow(-MARKED_INSET), MARKED_COLOR, false, SELECTED_OUTLINE)


## Reports a tap as a selection, or as a swap mark in mark mode, and ignores it
## while locked.
##
## ADR-011 section 6 lets a swap return any number of deck tiles, so mark mode
## collects a set instead of one selection. The locked check comes first in both
## modes, which is what gates the row off-turn (ADR-008 section 8).
func _gui_input(event: InputEvent) -> void:
	if _locked:
		return
	if not (event is InputEventMouseButton):
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var index: int = _index_at(button.position, _deck.size(), size)
	if index < 0:
		return
	if _mark_mode:
		tile_toggled.emit(_deck[index].tile_id)
		return
	if index != _selected_index:
		_selected_index = index
		queue_redraw()
	tile_selected.emit(_deck[index].tile_id)


## Collects or releases taps as swap marks rather than selections
## (ADR-011 section 6).
##
## Entering or leaving mark mode clears the marks: a marked set belongs to one
## swap attempt, and the screen re-reads what the row holds when it submits.
func set_mark_mode(enabled: bool) -> void:
	if _mark_mode == enabled:
		return
	_mark_mode = enabled
	_marked.clear()
	queue_redraw()


## Returns true while taps are collected as swap marks.
func is_mark_mode() -> bool:
	return _mark_mode


## Draws or clears the swap mark on one deck tile.
##
## The screen drives this from its own set of returned tiles, so the drawn marks
## and the submitted set cannot disagree. An identity the row does not hold is
## dropped rather than drawn.
func set_marked(tile_id: StringName, marked: bool) -> void:
	var found: bool = is_marked(tile_id)
	if marked == found:
		return
	if marked:
		if _index_of(_deck, tile_id) < 0:
			return
		_marked.append(tile_id)
	else:
		_marked.erase(tile_id)
	queue_redraw()


## Returns how many deck tiles the row is drawing as marked.
func marked_count() -> int:
	return _marked.size()


## Returns a copy of the marked identities, in the order they were marked.
func marked_ids() -> Array[StringName]:
	return _marked.duplicate()


## Clears every swap mark without leaving mark mode.
func clear_marks() -> void:
	if _marked.is_empty():
		return
	_marked.clear()
	queue_redraw()


## Returns true when `tile_id` is currently marked for the swap.
func is_marked(tile_id: StringName) -> bool:
	return _marked.has(tile_id)


## Drops marks for tiles the row no longer holds, so a deck change cannot leave a
## stale mark behind.
func _prune_marked() -> void:
	if _marked.is_empty():
		return
	var kept: Array[StringName] = []
	for tile_id: StringName in _marked:
		if _index_of(_deck, tile_id) >= 0:
			kept.append(tile_id)
	_marked = kept


## Returns the pixel rectangle of one tile in a row of `count` tiles.
##
## Pure geometry, so drawing and hit-testing cannot disagree and a test can check
## the layout without a rendered frame.
static func tile_rect(index: int, count: int, available: Vector2) -> Rect2:
	if count <= 0 or index < 0 or index >= count:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var inner: Vector2 = Vector2(
		maxf(available.x - PADDING * 2.0, 0.0), maxf(available.y - PADDING * 2.0, 0.0)
	)
	var hint: Vector2 = Vector2(
		inner.x / (float(count) + GAP_RATIO * float(count - 1)), inner.y
	)
	if hint.x <= 0.0 or hint.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var tile_size: float = minf(hint.x, hint.y)
	var gap: float = tile_size * GAP_RATIO
	var row_width: float = tile_size * float(count) + gap * float(count - 1)
	var origin: Vector2 = Vector2(
		PADDING + maxf((inner.x - row_width) * 0.5, 0.0),
		PADDING + maxf((inner.y - tile_size) * 0.5, 0.0)
	)
	return Rect2(origin + Vector2((tile_size + gap) * float(index), 0.0), Vector2(tile_size, tile_size))


## Returns the index of the tile containing `point`, or -1.
##
## The selection lift is deliberately ignored: the player taps where the tile is
## drawn, so the hit box stays the un-lifted rectangle and the band the lift
## uncovers remains a miss.
static func _index_at(point: Vector2, count: int, available: Vector2) -> int:
	for index: int in range(count):
		if tile_rect(index, count, available).has_point(point):
			return index
	return -1


## Returns the drawn rectangle with the selected tile's slight lift applied.
static func _lifted(rect: Rect2) -> Rect2:
	return Rect2(
		rect.position - Vector2(0.0, rect.size.y * SELECTED_LIFT_RATIO), rect.size
	)


## Returns the index of a tile identity in `tiles`, or -1.
static func _index_of(tiles: Array[TileDefinition], tile_id: StringName) -> int:
	if String(tile_id).is_empty():
		return -1
	for index: int in range(tiles.size()):
		if tiles[index] != null and tiles[index].tile_id == tile_id:
			return index
	return -1
