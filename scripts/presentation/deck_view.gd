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
## AGENTS.md section 8 asks for tap, drag, valid-placement highlighting, and
## rotation. Tap is a `tile_selected` report, and a tap on the tile the row already
## draws as selected is a `tile_rotation_requested` report instead: the row turns
## the tile the player tapped again rather than re-selecting it. A press that
## travels past `DRAG_THRESHOLD` becomes a drag instead: this row then reports the
## tile, the pointer, and the release, and the screen turns those into staging
## commands. The row itself never decides where a tile may land, so the drag path
## and the tap path reach the board through exactly the same application commands.
##
## The row is laid out by the screen's containers and this control draws inside
## whatever rectangle that layout gives it, so it never states a pixel position
## of its own (ADR-008 section 8).
##
## Hit-testing uses the drawn tile centers, extending each target through the
## surrounding deck space up to the midpoint between neighboring tiles.

## Emitted when the player taps a deck tile, with that tile's identity.
signal tile_selected(tile_id: StringName)

## Emitted when the player taps a deck tile while the row is in mark mode
## (ADR-011 section 6: the tiles a swap would return).
signal tile_toggled(tile_id: StringName)

## Emitted when the player taps the tile this row already draws as selected and the
## application controller reports that tile as armed, which asks for it to be turned
## one quarter-turn before it is staged.
##
## A tap on the row's own fallback selection - the first tile, shown as selected
## while nothing is armed - is a selection rather than a rotation, so the deck's
## first tile can still be armed by tapping it.
##
## Rotation is real staged state: it lives on the immutable `TileSnapshot` a
## staging command creates, so the row reports the request and the screen forwards
## it to the application controller rather than keeping a rotation of its own. The
## request is the release of a press that never became a drag, so a press that goes
## on to drag the tile onto the board stages it at the rotation the player chose
## here instead of turning it on the way (AGENTS.md section 8: one gesture, one
## intent).
signal tile_rotation_requested(tile_id: StringName)

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

## Reserve a full hand's width even when tiles leave the deck.
const LAYOUT_SLOT_COUNT: int = 6

## Compact separation on the 540px logical canvas (4px at 360px device width).
const GAP: float = 6.0

## Minimum vertical padding; horizontal space is divided into equal gaps.
const PADDING: float = 8.0

## Thickness of a swap-marked tile's outline, in pixels.
const MARKED_OUTLINE: float = 3.0

## Outline colour of a tile marked for the swap, so a marked tile is never
## mistaken for the tile the next staging command takes.
const MARKED_COLOR: Color = Color("#F4C86A")

## Inner inset of the swap-marked outline, in pixels.
const MARKED_INSET: float = 3.0

## Width and height of a deck tile while it is being dragged.
const DRAG_SCALE: float = 0.9

## Semi-transparent border drawn over the tile the player has armed.
const SELECTED_TILE_HIGHLIGHT: Texture2D = preload("res://assets/tiles/tile_highlight.png")

## Exponential easing keeps slot changes smooth even when a finger reverses direction.
const SLOT_SHIFT_SMOOTHNESS: float = 14.0
const SLOT_SHIFT_EPSILON: float = 0.005

## How far a press must travel before it is a drag rather than a tap, in pixels.
##
## A finger rolls a few pixels on every touch, so without a threshold every tap
## would start a drag. The value is deliberately larger than that jitter and far
## smaller than one tile, so a deliberate drag starts immediately.
const DRAG_THRESHOLD: float = 8.0

## A glimmer crosses a resting tile at three times the original one-second speed.
const GLIMMER_DURATION: float = 1.0 / 3.0
const GLIMMER_DELAY_MIN: float = 0.35
const GLIMMER_DELAY_MAX: float = 1.4

## The player's tiles, in deck order.
var _deck: Array[TileDefinition] = []

## Local rack order, including staged tiles and empty slots after a commit.
## This is presentation state; tile ownership remains with the controller.
var _slots: Array[StringName] = []

## Temporary order while a dragged tile is over the rack. Only a rack drop commits it.
var _preview_slots: Array[StringName] = []
var _has_insert_preview: bool = false

## Fractional visual slot positions, eased toward the committed or preview order.
var _slot_positions: Dictionary = {}

## Index of the tile drawn as selected; -1 when the deck is empty.
var _selected_index: int = -1

## Identity the application controller reports as armed, as handed to `set_deck`.
##
## The drawn selection falls back to the first tile when the controller reports no
## armed tile, and that fallback has not been armed by anything: a tap on it must
## still select it, or the deck's first tile could never be staged. Keeping the
## armed identity is how the row tells the two apart, so a rotation is only ever
## reported for a tile the application layer really holds.
var _armed_id: StringName = &""

## Quarter-turn the selected tile is drawn at, supplied by the screen from the
## application controller. The row never keeps a rotation of its own, so the tile
## it draws and the tile the next staging command commits cannot disagree.
var _pending_rotation: int = 0

## Identities the row must not draw yet, because the deal animation is still
## flying them in (ADR-008 section 4).
##
## A concealed tile keeps its slot in the row and is simply not painted, so the
## tiles that have already landed never shift as the rest arrive, and a dealt tile
## is never visible in two places at once.
var _concealed: Array[StringName] = []

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

## Index of the already-selected tile the current press landed on; -1 otherwise.
##
## This press is a rotation request, and it is reported on its release: the same
## press may still travel past `DRAG_THRESHOLD`, and a drag stages the tile rather
## than turning it.
var _rotate_index: int = -1

## True between a drag gesture starting and its release or cancellation.
var _dragging: bool = false

## Index of the tile being dragged; -1 while no drag is in flight.
var _drag_index: int = -1

## Last pointer position reported for the drag, in this control's coordinates.
var _drag_point: Vector2 = Vector2.ZERO

var _glimmer_rng := RandomNumberGenerator.new()
var _glimmer_timer: Timer
var _glimmer_tile_id: StringName = &""
var _last_glimmer_tile_id: StringName = &""
var _glimmer_elapsed: float = 0.0


## Accepts taps and drags, so the row can arm a placement.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_process(false)
	_glimmer_rng.randomize()
	_glimmer_timer = Timer.new()
	_glimmer_timer.one_shot = true
	_glimmer_timer.timeout.connect(_start_random_glimmer)
	add_child(_glimmer_timer)
	_schedule_glimmer_if_needed()


## Eases all visible and reserved tiles toward their current slot targets.
func _process(delta: float) -> void:
	var redraw_needed: bool = false
	var slots: Array[StringName] = _layout_slots()
	var blend: float = 1.0 - exp(-SLOT_SHIFT_SMOOTHNESS * delta)
	var moving: bool = false
	for index: int in range(slots.size()):
		var tile_id: StringName = slots[index]
		if String(tile_id).is_empty():
			continue
		var current: float = float(_slot_positions.get(tile_id, index))
		var target: float = float(index)
		var next: float = lerpf(current, target, blend)
		if absf(target - next) <= SLOT_SHIFT_EPSILON:
			next = target
		else:
			moving = true
		_slot_positions[tile_id] = next
		if next != current:
			redraw_needed = true
	if not String(_glimmer_tile_id).is_empty():
		if not _can_glimmer(_glimmer_tile_id):
			_finish_glimmer()
		else:
			_glimmer_elapsed += delta
			if _glimmer_elapsed >= GLIMMER_DURATION:
				_finish_glimmer()
			else:
				redraw_needed = true
	if not moving and String(_glimmer_tile_id).is_empty():
		set_process(false)
	if redraw_needed:
		queue_redraw()


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
		if _glimmer_timer != null:
			_glimmer_timer.stop()
		_glimmer_tile_id = &""
	else:
		_schedule_glimmer_if_needed()


## Replaces the drawn deck, the selected tile, and its rotation
## (ADR-010 section 10).
##
## `tiles` contains the available tiles; `held_tiles` also includes staged tiles
## whose rack slots must remain reserved. `selected_id` is the tile the
## application controller reports as armed, or an empty name when none is; and
## `rotation` is the quarter-turn that tile would be staged at, so the player can
## see the tile turn in the row instead of only once it is on the board. The row
## never keeps its own idea of which tile is armed or how far it is turned: the
## application layer owns both, so a redraw cannot disagree with the next
## placement.
##
## Keep an active press or drag when a poll hands us the same tile identities in
## the same order. A changed hand cancels the gesture before its indices can
## refer to different tiles.
func set_deck(
	tiles: Array[TileDefinition], selected_id: StringName = &"", rotation: int = 0,
	held_tiles: Array[TileDefinition] = []
) -> void:
	if not _same_deck_ids(tiles):
		cancel_drag()
	_deck = []
	for tile: TileDefinition in tiles:
		if tile != null:
			_deck.append(tile)
	_sync_slots(held_tiles if not held_tiles.is_empty() else tiles)
	_prune_marked()
	_pending_rotation = posmod(rotation, TileEnums.ROTATION_COUNT)
	_armed_id = selected_id
	# A tile is drawn as selected only when the application layer reports that
	# exact tile as armed. There is deliberately no fallback to the deck's first
	# tile: straight after a deal nothing has been chosen yet, and drawing tile 0
	# as selected invited a board tap that staged a tile the player never picked.
	# The player's own tap is what selects, which is the gesture this row reports
	# as `tile_selected`.
	_selected_index = _index_of(_deck, selected_id)
	if not String(_glimmer_tile_id).is_empty() and not _can_glimmer(_glimmer_tile_id):
		_finish_glimmer()
	else:
		_schedule_glimmer_if_needed()
	queue_redraw()


func _same_deck_ids(tiles: Array[TileDefinition]) -> bool:
	if tiles.size() != _deck.size():
		return false
	for index: int in range(tiles.size()):
		if tiles[index] == null or _deck[index].tile_id != tiles[index].tile_id:
			return false
	return true


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


## Returns the quarter-turn the selected tile is drawn at.
##
## This is exactly the rotation `_draw` passes into the snapshot it paints, so a
## test can prove the row renders the rotation the controller reports without
## reading a pixel buffer. The row is never the authority for the value: compare
## it against `GameSessionController.pending_rotation()`.
func selected_rotation() -> int:
	return _pending_rotation


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
	# A tile the row does not hold leaves nothing selected rather than falling
	# back to the deck's first tile: the selection names the armed tile, and a
	# tile that is not in hand is not armed.
	var index: int = _index_of(_deck, tile_id)
	if index == _selected_index:
		return
	_selected_index = index
	if not String(_glimmer_tile_id).is_empty() and not _can_glimmer(_glimmer_tile_id):
		_finish_glimmer()
	else:
		_schedule_glimmer_if_needed()
	queue_redraw()


## Sets the tiles this row must not draw yet, because the deal animation is still
## flying them in. The screen owns that set: it conceals a fresh tile while it is
## in flight and clears it once the layer reports the tile has landed.
func set_concealed(tile_ids: Array[StringName]) -> void:
	if _concealed == tile_ids:
		return
	_concealed = tile_ids.duplicate()
	if not String(_glimmer_tile_id).is_empty() and not _can_glimmer(_glimmer_tile_id):
		_finish_glimmer()
	else:
		_schedule_glimmer_if_needed()
	queue_redraw()


## Returns the identities the row is currently concealing.
func concealed_ids() -> Array[StringName]:
	return _concealed.duplicate()


## Returns the GLOBAL rectangle of one tile in the drawn row.
##
## The deal animation needs the place a tile will land, measured the same way the
## row draws it, so this shares `tile_rect` rather than re-deriving the layout and
## a flight can never aim at a rectangle the row does not use.
func tile_global_rect(index: int) -> Rect2:
	var local: Rect2 = tile_rect_at(index)
	if local.size == Vector2.ZERO:
		return Rect2()
	return get_global_transform() * local


## Resolve by identity so a changing rack still receives a tile in its own slot.
func tile_global_rect_for(tile_id: StringName) -> Rect2:
	return tile_global_rect(_index_of(_deck, tile_id))


## Draws the tile row and any swap marks.
##
## While the row is collecting a swap set it draws no selection: the tiles a swap
## returns are a set of marks (ADR-011 section 6), no tile is armed for a staging
## that a whole-turn swap would consume.
##
## A dragged tile leaves its slot vacant; the screen draws the moving copy.
##
## The selected tile is drawn at `_pending_rotation`, so tapping it again is
## visibly a turn rather than a change the player only sees once the tile is on the
## board. The rotation shown is the one a staging command would apply, because the
## screen supplies it from the application controller (AGENTS.md section 19).
func _draw() -> void:
	if _deck.is_empty():
		return
	for index: int in range(_deck.size()):
		var rect: Rect2 = tile_rect_at(index)
		if not TilePainter.is_drawable(rect):
			continue
		# A tile the deal animation is still flying in is drawn only by that
		# layer, so it is never painted twice in one frame. The slot is reserved
		# either way: `tile_rect` lays the row out from the count, so the tiles
		# that have landed do not shift as the rest arrive.
		if _concealed.has(_deck[index].tile_id):
			continue
		if index == _drag_index:
			continue
		TilePainter.paint_tile_shadow(self, rect)
		if index == _selected_index and not _mark_mode:
			# TilePainter reads a tile's visible edges from a snapshot, so the
			# row draws the identical face the board would commit, at the
			# rotation the player has turned it to (ADR-006 section 5,
			# ADR-010 section 12).
			TilePainter.paint_tile(
				self, rect, TileSnapshot.create(_deck[index], BoardMetrics.NO_CELL, _pending_rotation)
			)
			draw_texture_rect(SELECTED_TILE_HIGHLIGHT, rect, false)
			_draw_mark(index, rect)
			continue
		TilePainter.paint_tile(
			self, rect, TileSnapshot.create(_deck[index], BoardMetrics.NO_CELL, 0)
		)
		_draw_mark(index, rect)
		if _deck[index].tile_id == _glimmer_tile_id:
			TilePainter.paint_tile_glimmer(
				self, rect, _glimmer_elapsed / GLIMMER_DURATION
			)


## Outlines one tile when it is marked for the swap (ADR-011 section 6).
func _draw_mark(index: int, rect: Rect2) -> void:
	if not is_marked(_deck[index].tile_id):
		return
	draw_rect(rect.grow(-MARKED_INSET), MARKED_COLOR, false, MARKED_OUTLINE)


## Returns true only while this tile is resting visibly in the hand.
func _can_glimmer(tile_id: StringName) -> bool:
	if not is_inside_tree() or not is_visible_in_tree() or _mark_mode:
		return false
	var index: int = _index_of(_deck, tile_id)
	return (
		index >= 0
		and index != _selected_index
		and index != _drag_index
		and not _concealed.has(tile_id)
	)


## Starts the next glimmer after a random pause, only if a resting tile exists.
func _schedule_glimmer_if_needed() -> void:
	if _glimmer_timer == null or _glimmer_timer.time_left > 0.0:
		return
	if not String(_glimmer_tile_id).is_empty() or _eligible_glimmer_ids().is_empty():
		return
	_glimmer_timer.start(_glimmer_rng.randf_range(GLIMMER_DELAY_MIN, GLIMMER_DELAY_MAX))


## Chooses a random resting tile, avoiding an immediate repeat when possible.
func _start_random_glimmer() -> void:
	var choices: Array[StringName] = _eligible_glimmer_ids()
	if choices.size() > 1:
		choices.erase(_last_glimmer_tile_id)
	if choices.is_empty():
		return
	_glimmer_tile_id = choices[_glimmer_rng.randi_range(0, choices.size() - 1)]
	_glimmer_elapsed = 0.0
	set_process(true)
	queue_redraw()


## Ends the sweep and starts a randomized pause before another tile glimmers.
func _finish_glimmer() -> void:
	if String(_glimmer_tile_id).is_empty():
		return
	_last_glimmer_tile_id = _glimmer_tile_id
	_glimmer_tile_id = &""
	_glimmer_elapsed = 0.0
	_schedule_glimmer_if_needed()
	queue_redraw()


## Drops an active glimmer as soon as its tile is selected, concealed, or lifted.
func _stop_glimmer_if_unavailable() -> void:
	if not String(_glimmer_tile_id).is_empty() and not _can_glimmer(_glimmer_tile_id):
		_finish_glimmer()
	else:
		_schedule_glimmer_if_needed()


## Returns visible, resting tiles that may receive a glimmer.
func _eligible_glimmer_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	if not is_inside_tree() or not is_visible_in_tree() or _mark_mode:
		return result
	for index: int in range(_deck.size()):
		var tile_id: StringName = _deck[index].tile_id
		if index == _selected_index or index == _drag_index or _concealed.has(tile_id):
			continue
		result.append(tile_id)
	return result


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


## Keeps a deck gesture alive after the pointer leaves this control.
##
## `_gui_input` is bounded by the row's rectangle. A drag onto the board necessarily
## leaves that rectangle, so the viewport-level path continues tracking the same
## mouse/touch gesture until its release. Converting the event back to row-local
## coordinates keeps slot hit-testing and screen drop mapping on the same geometry.
func _input(event: InputEvent) -> void:
	if _locked or (not _pressing and not _dragging):
		return
	if event is InputEventMouseMotion:
		var local_event: InputEvent = make_input_local(event)
		if local_event is InputEventMouseMotion:
			_handle_motion(local_event)
			_consume()
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index != MOUSE_BUTTON_LEFT or button.pressed:
			return
		var local_event: InputEvent = make_input_local(event)
		if local_event is InputEventMouseButton:
			_handle_release(local_event)
			_consume()


## Routes a press to the press handler and a release to the release handler.
func _handle_button(event: InputEventMouseButton) -> void:
	var button: InputEventMouseButton = event
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_handle_press(button)
		return
	_handle_release(button)


## Reports the selection, or marks the press as a rotation of the selected tile.
##
## The selection is reported on the press, not on the release, because it is
## decided the moment a finger touches a tile. A press that then travels past
## `DRAG_THRESHOLD` is not an undone tap: it continues as a drag of the same tile,
## and both paths reach the same staging command, so nothing is staged twice.
##
## A press on the tile the row already draws as selected is the rotation gesture
## instead, and it is deliberately not reported here: the same press may still
## become a drag onto the board, and the drop stages the tile at the rotation the
## player chose. It is reported on the release, when the press is known to have
## stayed a tap.
##
## The gesture is consumed because the board listens for unhandled pointer input:
## a deck gesture that stayed unhandled would also reach `BoardInputController`,
## which would read the same finger as a board drag.
func _handle_press(button: InputEventMouseButton) -> void:
	_consume()
	_pressing = true
	_press_point = button.position
	# Cleared first, so a press that is not a rotation can never inherit the mark
	# of an earlier one and report a turn the player did not ask for.
	_rotate_index = -1
	var slot: int = _index_at_current(button.position)
	var slots: Array[StringName] = _layout_slots()
	_press_index = _index_of(_deck, slots[slot]) if slot >= 0 else -1
	if _press_index < 0:
		return
	if _mark_mode:
		tile_toggled.emit(_deck[_press_index].tile_id)
		return
	if _press_index != _selected_index or not _is_armed(_press_index):
		# Either a different tile than the one drawn as selected, or the drawn
		# selection is the row's own fallback, which nothing has armed yet: both
		# are a selection, so the first tap on the deck's first tile still arms it.
		_selected_index = _press_index
		_stop_glimmer_if_unavailable()
		queue_redraw()
		tile_selected.emit(_deck[_press_index].tile_id)
		return
	_rotate_index = _press_index


## Ends a press: a drag asks for a drop, and a gesture that never became a drag is
## either the tap already reported on its press or a rotation request.
##
## The drop is reported without a cancellation, so one release cannot arrive as
## two endings. Where the drop landed, and whether it may land there at all, is
## the screen's question, including insertion into the deck row.
func _handle_release(button: InputEventMouseButton) -> void:
	if not _pressing and not _dragging:
		return
	_consume()
	_pressing = false
	if not _dragging:
		_report_rotation()
		return
	var dragged_id: StringName = _dragged_tile_id()
	_dragging = false
	_drag_index = -1
	_drag_point = button.position
	if not String(dragged_id).is_empty():
		tile_drop_requested.emit(dragged_id, button.position)
	queue_redraw()


## Reports a press that landed on the already-selected tile as a rotation request.
##
## This is the release half of the rotation gesture, and it is the only place the
## request is made: a press that became a drag must stage the tile instead. The
## request names the tile this row draws as selected, so the screen can check it
## against the tile the application layer has armed and refuse a stale one, and the
## mark is cleared either way so one gesture can never turn a tile twice.
func _report_rotation() -> void:
	var index: int = _rotate_index
	_rotate_index = -1
	if index < 0 or index >= _deck.size() or index != _selected_index:
		return
	if not _is_armed(index):
		return
	tile_rotation_requested.emit(_deck[index].tile_id)


## Returns true when the tile drawn at `index` is the tile the controller armed.
##
## The row reports a rotation only for an armed tile: a tile the row merely draws
## as selected is not the application layer's choice, so turning it would have no
## effect the player could see or that a later staging command would honour.
func _is_armed(index: int) -> bool:
	if index < 0 or index >= _deck.size():
		return false
	if String(_armed_id).is_empty():
		return false
	return _deck[index].tile_id == _armed_id


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
	_stop_glimmer_if_unavailable()
	# A drag stages the tile, so it must not also turn it: the rotation the player
	# chose in the row is the rotation the drop stages.
	_rotate_index = -1
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
	_rotate_index = -1
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
	clear_insert_preview()
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
	_stop_glimmer_if_unavailable()
	_schedule_glimmer_if_needed()
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
	if index < 0 or index >= _deck.size():
		return Rect2()
	var slots: Array[StringName] = _layout_slots()
	var tile_id: StringName = _deck[index].tile_id
	var target_slot: int = slots.find(tile_id)
	if target_slot < 0:
		return Rect2()
	var visual_slot: float = float(_slot_positions.get(tile_id, target_slot))
	return _tile_rect_at_slot(visual_slot, slots.size(), size)


## Preserve surviving identities in their slots. Refill uses the vacant slots.
func _sync_slots(held_tiles: Array[TileDefinition]) -> void:
	var prior_slots: Array[StringName] = _slots.duplicate()
	if held_tiles.is_empty():
		_slots.clear()
		_preview_slots.clear()
		_has_insert_preview = false
		_slot_positions.clear()
		set_process(false)
		return
	for index: int in range(_slots.size()):
		if _index_of(held_tiles, _slots[index]) < 0:
			_slots[index] = &""
	for tile: TileDefinition in held_tiles:
		if tile == null or _slots.has(tile.tile_id):
			continue
		var vacancy: int = _slots.find(&"")
		if vacancy >= 0:
			_slots[vacancy] = tile.tile_id
		else:
			_slots.append(tile.tile_id)
	var present: Dictionary = {}
	for index: int in range(_slots.size()):
		var tile_id: StringName = _slots[index]
		if String(tile_id).is_empty():
			continue
		present[tile_id] = true
		if not _slot_positions.has(tile_id):
			_slot_positions[tile_id] = float(index)
	for raw: Variant in _slot_positions.keys():
		if not present.has(raw):
			_slot_positions.erase(raw)
	if _has_insert_preview and _slots != prior_slots:
		clear_insert_preview()


## Returns the order currently being animated, without exposing a mutable copy.
func _layout_slots() -> Array[StringName]:
	return _preview_slots if _has_insert_preview else _slots


## Resolves a pointer against the currently drawn slot centers, including tiles
## that are still easing into a new order.
func _index_at_current(point: Vector2) -> int:
	var slots: Array[StringName] = _layout_slots()
	if slots.is_empty() or not Rect2(Vector2.ZERO, size).has_point(point):
		return -1
	var centers: Array[float] = []
	for index: int in range(slots.size()):
		var tile_id: StringName = slots[index]
		var visual_slot: float = float(_slot_positions.get(tile_id, index)) if not String(tile_id).is_empty() else float(index)
		centers.append(_tile_rect_at_slot(visual_slot, slots.size(), size).get_center().x)
	for index: int in range(slots.size() - 1):
		if point.x < (centers[index] + centers[index + 1]) * 0.5:
			return index
	return slots.size() - 1


## Previews insertion at the pointer's horizontal position. Other tiles ease
## aside to open the slot while the dragged tile remains under the pointer.
func preview_insert_at(tile_id: StringName, point: Vector2) -> bool:
	if _locked or _mark_mode or not point.is_finite() or not Rect2(Vector2.ZERO, size).has_point(point):
		clear_insert_preview()
		return false
	var next_slots: Array[StringName] = _layout_slots().duplicate()
	var origin: int = next_slots.find(tile_id)
	if origin < 0:
		clear_insert_preview()
		return false
	var boundary: int = next_slots.size()
	for index: int in range(next_slots.size()):
		if point.x < _tile_rect_at_slot(float(index), next_slots.size(), size).get_center().x:
			boundary = index
			break
	next_slots.remove_at(origin)
	if boundary > origin:
		boundary -= 1
	next_slots.insert(boundary, tile_id)
	if next_slots == _slots:
		clear_insert_preview()
		return true
	if not _has_insert_preview or next_slots != _preview_slots:
		_preview_slots = next_slots
		_has_insert_preview = true
		set_process(true)
		queue_redraw()
	return true


## Abandons the temporary order and eases every tile back to its saved position.
func clear_insert_preview() -> void:
	if not _has_insert_preview:
		return
	_preview_slots.clear()
	_has_insert_preview = false
	set_process(true)
	queue_redraw()


## Commits the live preview when the dragged tile is released inside the rack.
func insert_tile_at(tile_id: StringName, point: Vector2) -> bool:
	if not preview_insert_at(tile_id, point):
		return false
	if _has_insert_preview:
		_slots = _preview_slots.duplicate()
		_preview_slots.clear()
		_has_insert_preview = false
		set_process(true)
		queue_redraw()
	return true


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
	if index < 0 or index >= count:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	return _tile_rect_at_slot(float(index), count, available)


static func _tile_rect_at_slot(slot: float, count: int, available: Vector2) -> Rect2:
	if count <= 0 or slot < 0.0 or slot > float(count - 1):
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	# Size against a full hand, not the remaining tiles. The background keeps
	# its screen-defined dimensions and fewer tiles retain the same square size.
	var slot_count: int = maxi(count, LAYOUT_SLOT_COUNT)
	var hint: Vector2 = Vector2(
		(available.x - GAP * float(slot_count - 1)) / float(slot_count),
		maxf(available.y - PADDING * 2.0, 0.0)
	)
	if hint.x <= 0.0 or hint.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var tile_size: float = floorf(minf(hint.x, hint.y))
	var gap: float = (available.x - tile_size * float(slot_count)) / float(slot_count - 1)
	var row_width: float = tile_size * float(count) + gap * float(count - 1)
	var origin := Vector2((available.x - row_width) * 0.5, (available.y - tile_size) * 0.5)
	return Rect2(origin + Vector2((tile_size + gap) * slot, 0.0), Vector2(tile_size, tile_size))


## Uses the full row height and divides horizontal gaps at tile-center midpoints.
## Outer tiles own the space to the row edges; a single tile owns the whole row.
## Points outside the row and rows with no drawable tiles remain misses.
static func _index_at(point: Vector2, count: int, available: Vector2) -> int:
	if count <= 0 or not Rect2(Vector2.ZERO, available).has_point(point):
		return -1
	if not tile_rect(0, count, available).has_area():
		return -1
	for index: int in range(count - 1):
		var center: float = tile_rect(index, count, available).get_center().x
		var next_center: float = tile_rect(index + 1, count, available).get_center().x
		if point.x < (center + next_center) * 0.5:
			return index
	return count - 1


## Returns the index of a tile identity in `tiles`, or -1.
static func _index_of(tiles: Array[TileDefinition], tile_id: StringName) -> int:
	if String(tile_id).is_empty():
		return -1
	for index: int in range(tiles.size()):
		if tiles[index] != null and tiles[index].tile_id == tile_id:
			return index
	return -1
