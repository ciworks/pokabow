class_name DeckView
extends Control

## The human's hand: a horizontal, selectable spread of deck tiles under the
## board (ADR-010 sections 4 and 12; AGENTS.md section 8).
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
## AGENTS.md section 8 asks for tap, drag, and valid-placement highlighting.
## Tap is a `tile_selected` report. A press that travels past `DRAG_THRESHOLD`
## becomes a drag instead: this row then reports the tile, the pointer, and the
## release, and the screen turns those into staging commands. The row itself never
## decides where a tile may land, so the drag path and the tap path reach the
## board through exactly the same application commands.
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

## Emitted once when a press on a deck tile has travelled past `DRAG_THRESHOLD`,
## with the tile being dragged and the pointer that started the drag.
##
## AGENTS.md section 8 requires drag as a first-class mobile gesture. This is the
## gesture start; `tile_dragged` follows it while the pointer moves and
## `tile_drop_requested` or `tile_drag_cancelled` ends it.
signal tile_drag_started(tile_id: StringName, pointer: Vector2)

## Emitted while a drag is in flight, with the pointer position in this row's
## local coordinates. The screen converts it to a board cell through
## `BoardMetrics`, so the row never needs to know the board's geometry.
signal tile_dragged(tile_id: StringName, pointer: Vector2)

## Emitted when the player releases a drag, with the tile and the pointer position
## in this row's local coordinates. Whether the release is a legal drop is the
## screen's question, not this row's.
signal tile_drop_requested(tile_id: StringName, pointer: Vector2)

## Emitted when a drag ends without a release over the row: off-turn gating, a
## lost focus, or a cancellation. The screen clears any drag it was showing.
signal tile_drag_cancelled(tile_id: StringName)

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

## Opacity of the row's copy of a tile that is being dragged, so the row still
## shows the tile is held while the board shows where it would land.
const DRAGGED_ALPHA: float = 0.45

## How far a press must travel before it is a drag rather than a tap, in pixels.
##
## A finger rolls a few pixels on every touch, so without a threshold every tap
## would start a drag. The value is deliberately larger than that jitter and far
## smaller than one tile, so a deliberate drag starts immediately.
const DRAG_THRESHOLD: float = 8.0

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

## True between a press landing on a tile and its release. A press is a tap until
## it travels past `DRAG_THRESHOLD`, at which point it becomes a drag.
var _pressing: bool = false

## Where the current press started, in this control's coordinates.
var _press_point: Vector2 = Vector2.ZERO

## Index of the tile the current press landed on; -1 when it landed off a tile.
var _press_index: int = -1

## True between a drag gesture starting and its release or cancellation.
var _dragging: bool = false

## Index of the tile being dragged; -1 while no drag is in flight.
var _drag_index: int = -1

## Last pointer position reported for the drag, in this control's coordinates.
var _drag_point: Vector2 = Vector2.ZERO


## Accepts taps and drags, so the row can arm a placement.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


## Drops a gesture that can no longer finish.
##
## Leaving the tree ends every gesture this row owns: a drag is cancelled, never
## resolved, so a row that is torn down mid-drag cannot stage a tile.
func _exit_tree() -> void:
	cancel_drag()


## Cancels a drag when the row stops being visible, because a gesture the player
## cannot see the source of must not be able to finish over the board.
func _notification(what: int) -> void:
	if what != NOTIFICATION_VISIBILITY_CHANGED:
		return
	if not is_visible_in_tree():
		cancel_drag()


## Replaces the drawn deck and the selected tile (ADR-010 section 10).
##
## `tiles` is the human's deck in deal order; `selected_id` is the tile the
## application controller reports as armed, or an empty name when none is. The row
## never keeps its own idea of which tile is armed: the application layer owns
## that choice, so a redraw cannot disagree with the next placement.
##
## A drag in flight is abandoned here, because the deck it was dragging from no
## longer exists in the shape the drag described. The press that started it is
## deliberately left alone: reporting a tap re-renders the deck, and a gesture
## that is still a tap must not be torn down by its own redraw.
func set_deck(tiles: Array[TileDefinition], selected_id: StringName = &"") -> void:
	_abandon_drag()
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
##
## Locking cancels a drag in flight, so an off-turn drag is refused rather than
## left able to report a drop (AGENTS.md section 8 gating).
func set_locked(locked: bool) -> void:
	if _locked == locked:
		return
	_locked = locked
	if locked:
		cancel_drag()
	queue_redraw()


## Returns true while a drag gesture is in flight.
func is_dragging() -> bool:
	return _dragging


## Returns the index of the tile being dragged, or -1 when no drag is in flight.
func dragging_index() -> int:
	return _drag_index


## Returns the last pointer position reported for the drag, in local coordinates.
func drag_point() -> Vector2:
	return _drag_point


## Ends a drag that was not released over the row: the screen calls this when a
## drop is refused, and the row calls it when the gesture is cancelled.
##
## `notify` is false when the screen is clearing a drag it already knows about, so
## a refusal cannot echo back as a second cancellation.
func set_dragging(dragging: bool, notify: bool = false) -> void:
	if dragging:
		return
	cancel_drag(notify)


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
##
## The tile being dragged is ghosted in place rather than removed: the board draws
## the real ghost at the cell under the pointer, so this copy is dimmed to read as
## picked up, and a drag that is currently off the board never makes the row look
## as if it lost a tile.
func _draw() -> void:
	if _deck.is_empty():
		return
	for index: int in range(_deck.size()):
		var rect: Rect2 = tile_rect(index, _deck.size(), size)
		if not TilePainter.is_drawable(rect):
			continue
		if index == _drag_index:
			TilePainter.paint_tile(
				self,
				rect,
				TileSnapshot.create(_deck[index], BoardMetrics.NO_CELL, 0),
				DRAGGED_ALPHA
			)
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


## Turns a gesture on the row into a selection, a swap mark, or a drag.
##
## Mouse and touch are handled through `InputEventMouse` because Godot emulates
## mouse input from touch by default, so one path covers both and a desktop drag
## exercises exactly the code a finger does (AGENTS.md section 8).
##
## The gesture starts as a tap. It only becomes a drag once it has travelled
## `DRAG_THRESHOLD`, which is what keeps a finger's jitter from being read as a
## drag and cancelling the tap the player meant.
##
## The locked check comes first in every branch, which is what gates the row
## off-turn (ADR-008 section 8).
func _gui_input(event: InputEvent) -> void:
	if _locked:
		return
	if event is InputEventMouseButton:
		_handle_button(event)
		return
	if event is InputEventMouseMotion:
		_handle_motion(event)


## Routes a press to the press handler and a release to the release handler.
func _handle_button(event: InputEventMouseButton) -> void:
	var button: InputEventMouseButton = event
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_handle_press(button)
		return
	_handle_release(button)


## Reports the tap and remembers where the finger landed.
##
## The tap is reported on the press, not on the release, because a tap is decided
## the moment a finger touches a tile. A press that then travels past
## `DRAG_THRESHOLD` is not an undone tap: it continues as a drag of the same tile,
## and both paths reach the same staging command, so nothing is staged twice.
##
## The gesture is consumed because the board listens for unhandled pointer input:
## a deck gesture that stayed unhandled would also reach `BoardInputController`,
## which would read the same finger as a board drag.
func _handle_press(button: InputEventMouseButton) -> void:
	_consume()
	_pressing = true
	_press_point = button.position
	_press_index = _index_at(button.position, _deck.size(), size)
	if _press_index < 0:
		return
	if _mark_mode:
		tile_toggled.emit(_deck[_press_index].tile_id)
		return
	if _press_index != _selected_index:
		_selected_index = _press_index
		queue_redraw()
	tile_selected.emit(_deck[_press_index].tile_id)


## Ends a press: a drag asks for a drop, and a gesture that never became a drag
## has already been reported as a tap.
##
## The drop is reported without a cancellation, so one release cannot arrive as
## two endings. Where the drop landed, and whether it may land there at all, is
## the screen's question, so a release over the deck row itself simply lands off
## the board and changes nothing.
func _handle_release(button: InputEventMouseButton) -> void:
	if not _pressing and not _dragging:
		return
	_consume()
	_pressing = false
	if not _dragging:
		return
	var dragged_id: StringName = _dragged_tile_id()
	_dragging = false
	_drag_index = -1
	_drag_point = button.position
	if not String(dragged_id).is_empty():
		tile_drop_requested.emit(dragged_id, button.position)
	queue_redraw()


## Promotes a held press to a drag once it has travelled far enough, and reports
## the movement while a drag is in flight.
func _handle_motion(event: InputEventMouseMotion) -> void:
	var motion: InputEventMouseMotion = event
	if not _pressing and not _dragging:
		return
	if not _dragging:
		_consume()
		_start_drag(motion.position)
		return
	if _drag_index < 0 or _drag_index >= _deck.size():
		cancel_drag()
		return
	_consume()
	_drag_point = motion.position
	tile_dragged.emit(_deck[_drag_index].tile_id, motion.position)


## Marks the gesture as taken, so a deck drag cannot also be read as board input
## (ADR-008 section 8: one gesture, one intent).
##
## Guarded against a control that is not in a viewport yet, which is how the
## headless harness drives this row.
func _consume() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	viewport.set_input_as_handled()


## Begins a drag when the press has travelled past `DRAG_THRESHOLD`.
##
## Mark mode collects a swap set rather than staging a tile, so a drag is not a
## swap gesture and does not start while marks are being collected.
func _start_drag(point: Vector2) -> void:
	if _mark_mode:
		return
	if _press_index < 0 or _press_index >= _deck.size():
		return
	if point.distance_to(_press_point) < DRAG_THRESHOLD:
		return
	if not _deck[_press_index].is_valid():
		return
	_dragging = true
	_drag_index = _press_index
	_drag_point = point
	queue_redraw()
	tile_drag_started.emit(_deck[_drag_index].tile_id, point)


## Ends a drag without reporting a drop, leaving the deck untouched.
##
## Called when the whole gesture is abandoned: the row was locked, the row left
## the tree, it stopped being visible, or the screen refused the release. It ends
## the press as well, because nothing of that gesture may survive. `notify`
## decides whether the screen is told, so clearing a drag the screen already ended
## cannot loop.
func cancel_drag(notify: bool = true) -> void:
	_pressing = false
	_press_index = -1
	var dragged_id: StringName = _dragged_tile_id()
	var was_dragging: bool = _dragging
	_abandon_drag()
	if was_dragging and notify and not String(dragged_id).is_empty():
		tile_drag_cancelled.emit(dragged_id)


## Clears the drag half of the gesture while leaving the press intact.
##
## A press is a tap until it travels past `DRAG_THRESHOLD`, and reporting that tap
## re-renders the deck, so the redraw must be able to let go of an abandoned drag
## without destroying a gesture that is still live.
func _abandon_drag() -> void:
	if not _dragging and _drag_index == -1:
		return
	_dragging = false
	_drag_index = -1
	queue_redraw()


## Returns the identity of the tile being dragged, or an empty name.
func _dragged_tile_id() -> StringName:
	if _drag_index < 0 or _drag_index >= _deck.size():
		return &""
	return _deck[_drag_index].tile_id


## Collects or releases taps as swap marks rather than selections
## (ADR-011 section 6).
##
## Entering or leaving mark mode clears the marks: a marked set belongs to one
## swap attempt, and the screen re-reads what the row holds when it submits. It
## also cancels a drag, because mark mode is not a staging gesture.
func set_mark_mode(enabled: bool) -> void:
	if _mark_mode == enabled:
		return
	_mark_mode = enabled
	cancel_drag()
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


## Returns the rectangle of a deck tile in this control's local coordinates, or
## an empty rectangle when the index is not drawn. For diagnostics and tests.
func tile_rect_at(index: int) -> Rect2:
	return tile_rect(index, _deck.size(), size)


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
