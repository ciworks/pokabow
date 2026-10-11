class_name BoardInputController
extends Node

## Turns pointer gestures over the board into placement intents
## (ADR-008 section 8).
##
## Responsibilities, and only these:
## - convert a pointer position to a board cell, using `BoardMetrics`;
## - treat tap and drag as the same placement-preview intent;
## - route mouse and touch through one path, so desktop development input
##   exercises exactly the code touch screens use;
## - gate tile intents to the human action phase, while allowing navigation.
##
## It never commits a move. Committing is an explicit confirm handled by the
## application layer, so a stray tap can never end a turn (ADR-008 section 8:
## never commit a move directly from input).

## A press landed on a board cell.
signal cell_tapped(cell: Vector2i)

## A press moved onto a different board cell while held.
signal cell_dragged(cell: Vector2i)

## A press was released, anywhere. Carries the cell under the pointer, or
## `BoardMetrics.NO_CELL` when the release happened off the board.
signal pointer_released(cell: Vector2i)

## Navigation or a canceled touch abandons the tile preview without dropping it.
signal gesture_canceled

## The board this controller hit-tests. Injected by the screen that owns both.
var board_view: BoardView = null

## True only while the human may place a tile (ADR-008 section 8).
var enabled: bool = false

## True between a press and its release.
var _pressing: bool = false
var _pan_gesture: bool = false
var _last_position := Vector2.ZERO
var _touch_index: int = -1
var _touches: Dictionary[int, Vector2] = {}
var _pinching: bool = false

## The cell where the current press started.
var _press_cell: Vector2i = BoardMetrics.NO_CELL

## The cell the most recent press landed on, or `BoardMetrics.NO_CELL` when that
## press started off the board.
##
## `_press_cell` is re-targeted while a drag moves and is cleared on release, so it
## cannot answer "where did this gesture start". This keeps the origin readable
## until the next press, which is what lets the screen pair a release against the
## tile the gesture began on. Reading it is how a press on a pending tile that is
## released off the board is recognised as a removal rather than a placement.
var _press_origin_cell: Vector2i = BoardMetrics.NO_CELL


## Capture an accepted touch through release, even when it moves over other UI.
## New touches still begin in _unhandled_input so menus retain priority.
func _input(event: InputEvent) -> void:
	if board_view == null:
		return
	if event is InputEventScreenTouch and _touches.has(event.index):
		_handle_touch(event)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_handle_touch_drag(event)


func _unhandled_input(event: InputEvent) -> void:
	if board_view == null:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
		return
	# Godot's synthesized mouse events must not replay the same touch gesture.
	if event is InputEventMouse and event.device == -1:
		return
	if event is InputEventMouseButton and _touch_index == -1:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
			_handle_press(button.position, button.pressed)
		return
	if event is InputEventScreenDrag:
		_handle_touch_drag(event)
		return
	if event is InputEventMouseMotion and _touch_index == -1:
		var motion: InputEventMouseMotion = event
		if _pressing:
			_handle_move(motion.position)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed and not event.canceled:
		if _touches.has(event.index) or not board_view.global_visible_rect().has_point(event.position):
			return
		if _touches.is_empty() and _pressing:
			return
		_touches[event.index] = event.position
		if _touches.size() == 1 and not _pinching:
			_touch_index = event.index
			_handle_press(event.position, true)
		elif not _pinching:
			_pinching = true
			_cancel_tile_gesture()
		_consume()
		return
	if not _touches.has(event.index):
		return
	if event.canceled:
		_pinching = true
		_cancel_tile_gesture()
	elif not _pinching and event.index == _touch_index:
		_handle_press(event.position, false)
	_touches.erase(event.index)
	# After a pinch, remaining fingers cannot turn into tile taps or drags.
	if _touches.is_empty():
		reset()
	_consume()


func _handle_touch_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	if _pinching and _touches.size() >= 2:
		var points: Array[Vector2] = _touches.values()
		var previous_midpoint: Vector2 = (points[0] + points[1]) * 0.5
		var previous_distance: float = points[0].distance_to(points[1])
		_touches[event.index] = event.position
		points = _touches.values()
		var midpoint: Vector2 = (points[0] + points[1]) * 0.5
		var distance: float = points[0].distance_to(points[1])
		if previous_distance > 1.0 and distance > 1.0:
			board_view.pinch_by(distance / previous_distance, previous_midpoint, midpoint)
	else:
		_touches[event.index] = event.position
		if not _pinching:
			_handle_move(event.position)
	_consume()


func _cancel_tile_gesture() -> void:
	_pressing = false
	_pan_gesture = false
	_press_cell = BoardMetrics.NO_CELL
	_press_origin_cell = BoardMetrics.NO_CELL
	board_view.clear_drag()
	gesture_canceled.emit()


## Begins or ends a press at `position`.
## `pressed` is the raw button/touch state.
func _handle_press(position: Vector2, pressed: bool) -> void:
	if pressed:
		if _pressing:
			return
		var cell: Vector2i = board_view.cell_at_global(position)
		if cell == BoardMetrics.NO_CELL:
			# A press that starts off the board is not a placement gesture, and it
			# forgets the previous origin so a release cannot be paired with a
			# press that started somewhere else.
			_press_origin_cell = BoardMetrics.NO_CELL
			return
		_pressing = true
		_press_cell = cell
		_press_origin_cell = cell
		_pan_gesture = not enabled or not board_view.is_staged_cell(cell)
		_last_position = position
		if not _pan_gesture:
			cell_tapped.emit(cell)
		_consume()
		return

	if not _pressing:
		return
	var released_cell: Vector2i = board_view.cell_at_global(position)
	_pressing = false
	_press_cell = BoardMetrics.NO_CELL
	if not _pan_gesture and enabled:
		pointer_released.emit(released_cell)
	_pan_gesture = false
	_consume()


## Returns the cell the current or most recent press landed on, or
## `BoardMetrics.NO_CELL` when that press started off the board.
##
## The release report carries only where the pointer was let go, so a caller that
## has to reason about the gesture as a whole - "this press began on a pending tile
## and ended off the board" - reads the origin from here. The gesture controller
## never interprets that pairing itself: it reports the two ends and lets the screen
## route them (ADR-008 section 4).
func press_origin_cell() -> Vector2i:
	return _press_origin_cell


## Reports a drag onto a new cell, once per cell change.
func _handle_move(position: Vector2) -> void:
	if not _pressing:
		return
	if _pan_gesture:
		board_view.pan_by(position - _last_position)
		_last_position = position
		_consume()
		return
	if not enabled:
		reset()
		return
	var cell: Vector2i = board_view.cell_at_global(position)
	if cell == BoardMetrics.NO_CELL or cell == _press_cell:
		return
	_press_cell = cell
	cell_dragged.emit(cell)
	_consume()


## Stops the handled gesture from reaching anything else.
func _consume() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


## Clears any in-flight press, so disabling input cannot leave a stuck gesture.
func reset() -> void:
	_touches.clear()
	_pinching = false
	_pan_gesture = false
	_touch_index = -1
	_pressing = false
	_press_cell = BoardMetrics.NO_CELL
	_press_origin_cell = BoardMetrics.NO_CELL
