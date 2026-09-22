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
## - stay silent unless the human owns the action phase.
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

## The board this controller hit-tests. Injected by the screen that owns both.
var board_view: BoardView = null

## True only while the human may place a tile (ADR-008 section 8).
var enabled: bool = false

## True between a press and its release.
var _pressing: bool = false

## The cell where the current press started.
var _press_cell: Vector2i = BoardMetrics.NO_CELL


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or board_view == null:
		return
	if event is InputEventScreenTouch:
		_handle_press(event.position, event.pressed)
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
			_handle_press(button.position, button.pressed)
		return
	if event is InputEventScreenDrag:
		_handle_move(event.position)
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if _pressing:
			_handle_move(motion.position)


## Begins or ends a press at `position`.
## `pressed` is the raw button/touch state.
func _handle_press(position: Vector2, pressed: bool) -> void:
	if pressed:
		var cell: Vector2i = board_view.cell_at_global(position)
		if cell == BoardMetrics.NO_CELL:
			# A press that starts off the board is not a placement gesture.
			return
		_pressing = true
		_press_cell = cell
		cell_tapped.emit(cell)
		_consume()
		return

	var released_cell: Vector2i = board_view.cell_at_global(position)
	_pressing = false
	_press_cell = BoardMetrics.NO_CELL
	pointer_released.emit(released_cell)
	_consume()


## Reports a drag onto a new cell, once per cell change.
func _handle_move(position: Vector2) -> void:
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
	_pressing = false
	_press_cell = BoardMetrics.NO_CELL
