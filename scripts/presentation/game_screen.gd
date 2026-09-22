class_name GameScreen
extends Control

## The playable screen: board, HUD, active tile, and feedback
## (ADR-008 sections 4, 5, 7, 8, and 9).
##
## Presentation only. It renders whatever the injected `GameSessionController`
## reports and forwards player intents to it; it never validates a placement,
## never scores, and never advances a turn (AGENTS.md sections 6 and 19).
##
## Every displayed value arrives from a controller signal, so the HUD cannot
## drift away from authoritative state and there is no polling in `_process`.
##
## The controller is injected by `AppRoot` (ADR-008 section 5) rather than
## fetched from a global, and it is injected after this node is ready, so
## `attach_controller` performs the wiring.

## Score popup colours per category.
const POKER_COLOR: Color = Color(1.0, 0.86, 0.42, 1.0)
const EDGE_COLOR: Color = Color(0.52, 0.78, 1.0, 1.0)
const CLUSTER_COLOR: Color = Color(0.55, 0.94, 0.62, 1.0)

## Vertical gap between stacked popups so simultaneous awards stay readable.
const POPUP_STAGGER: float = 26.0

## Human-readable names for the two Phase 1 players.
const HUMAN_LABEL: String = "You"
const AI_LABEL: String = "Rival"

## Rival-turn messages. The thinking message is shown only while the opponent
## analysis state reports that it is thinking (ADR-005 section 9), so the text
## cannot claim work that is not happening.
const RIVAL_THINKING_TEXT: String = "Rival is thinking..."
const RIVAL_WAITING_TEXT: String = "Rival is choosing a move..."

@onready var board_view: BoardView = %BoardView
@onready var board_input: BoardInputController = %BoardInputController
@onready var active_tile_view: ActiveTileView = %ActiveTileView
@onready var deck_view: DeckView = %DeckView
@onready var rotate_button: Button = %RotateButton
@onready var confirm_button: Button = %ConfirmButton
@onready var cancel_button: Button = %CancelButton
@onready var swap_button: Button = %SwapButton
@onready var swap_confirm_button: Button = %SwapConfirmButton
@onready var swap_cancel_button: Button = %SwapCancelButton
@onready var restart_button: Button = %RestartButton
@onready var human_score_value: Label = %HumanScoreValue
@onready var ai_score_value: Label = %AiScoreValue
@onready var turn_indicator: Label = %TurnIndicator
@onready var remaining_tiles_label: Label = %RemainingTilesLabel
@onready var status_label: Label = %StatusLabel
@onready var floating_scores: FloatingScores = %FloatingScores
@onready var summary_overlay: Control = %SummaryOverlay
@onready var summary_title: Label = %SummaryTitle
@onready var summary_body: Label = %SummaryBody

## The application-layer controller this screen drives, or null before boot.
var controller: GameSessionController = null

## Deck tiles the player has marked to return in the swap they are assembling
## (ADR-011 section 6). Presentation-only: the swap is submitted as a whole, and
## a refused swap leaves both this set and the deck untouched.
var _swap_tiles: Array[StringName] = []

## True while the screen is collecting the swap set rather than the pending line.
var _swap_mode: bool = false

## Identity of the deck tile currently being dragged onto the board, or an empty
## name when no drag is in flight (AGENTS.md section 8).
##
## Presentation-only: a drag stages nothing until it is released over a cell the
## controller accepts, and a refused release leaves this empty and the deck
## untouched (ADR-011 section 5).
var _drag_tile_id: StringName = &""


func _ready() -> void:
	_bind_nodes()
	_setup_input()
	_setup_buttons()
	if summary_overlay != null:
		summary_overlay.visible = false
	_apply_swap_controls()
	_refresh_all()


## Resolves every scene node this screen drives.
##
## `@onready` already does this when `_ready` runs, but the composition root
## attaches the controller to a screen that may be added to the tree in the same
## operation, so binding here as well means the screen can never be wired while
## its node references are still null. It is idempotent: assigning the same node
## twice changes nothing.
func _bind_nodes() -> void:
	board_view = get_node_or_null("%BoardView") as BoardView
	board_input = get_node_or_null("%BoardInputController") as BoardInputController
	active_tile_view = get_node_or_null("%ActiveTileView") as ActiveTileView
	deck_view = get_node_or_null("%DeckView") as DeckView
	rotate_button = get_node_or_null("%RotateButton") as Button
	confirm_button = get_node_or_null("%ConfirmButton") as Button
	cancel_button = get_node_or_null("%CancelButton") as Button
	swap_button = get_node_or_null("%SwapButton") as Button
	swap_confirm_button = get_node_or_null("%SwapConfirmButton") as Button
	swap_cancel_button = get_node_or_null("%SwapCancelButton") as Button
	restart_button = get_node_or_null("%RestartButton") as Button
	human_score_value = get_node_or_null("%HumanScoreValue") as Label
	ai_score_value = get_node_or_null("%AiScoreValue") as Label
	turn_indicator = get_node_or_null("%TurnIndicator") as Label
	remaining_tiles_label = get_node_or_null("%RemainingTilesLabel") as Label
	status_label = get_node_or_null("%StatusLabel") as Label
	floating_scores = get_node_or_null("%FloatingScores") as FloatingScores
	summary_overlay = get_node_or_null("%SummaryOverlay") as Control
	summary_title = get_node_or_null("%SummaryTitle") as Label
	summary_body = get_node_or_null("%SummaryBody") as Label


## Wires the screen to its controller and renders the first frame.
##
## Called by `AppRoot` after both nodes are in the tree (ADR-008 section 5).
func attach_controller(controller_ref: GameSessionController) -> void:
	if controller_ref == null:
		push_error("GameScreen.attach_controller: a controller is required.")
		return
	_bind_nodes()
	controller = controller_ref
	# Wiring runs here as well as in `_ready`, and both calls are idempotent.
	# A host may add this screen to the tree in the same operation that attaches
	# the controller (ADR-008 section 5), and `_ready` is not guaranteed to have
	# run by then, so a screen that wired itself only in `_ready` would leave the
	# deck row and the board input silently dead: no tap would stage a tile and
	# no tap would mark a swap tile. The input wiring is therefore reachable from
	# the path that actually composes the screen, exactly as `_bind_nodes` is.
	_setup_input()
	_setup_buttons()
	if not controller.session_started.is_connected(_on_session_started):
		controller.session_started.connect(_on_session_started)
		controller.state_changed.connect(_refresh_all)
		controller.preview_changed.connect(_refresh_preview)
		controller.line_committed.connect(_on_line_committed)
		controller.score_awarded.connect(_on_score_awarded)
		controller.match_ended.connect(_on_match_ended)
		controller.notice.connect(_on_notice)
		controller.ai_thinking_changed.connect(_on_ai_thinking_changed)
	_refresh_all()


## Connects the board's gesture signals. Gestures only ever produce a staging
## intent; committing stays an explicit button press (ADR-008 section 8).
##
## Idempotent and null-safe: it runs from `_ready` and from `attach_controller`,
## and a missing node is reported rather than dereferenced, because an error
## raised here must not be able to stop the deck row from being wired.
##
## Gating is deliberately not set here. `_refresh_all` is the only authority for
## whether the board accepts input, because it reads the turn phase from the
## controller; this clears input only for a screen that has no controller yet,
## so running the wiring again after the controller is attached cannot freeze a
## live board.
func _setup_input() -> void:
	if board_input == null:
		push_error("GameScreen._setup_input: the board input controller is missing.")
		return
	board_input.board_view = board_view
	if controller == null:
		board_input.enabled = false
	_connect_once(board_input.cell_tapped, _on_cell_tapped)
	_connect_once(board_input.cell_dragged, _on_cell_dragged)


## Connects the action controls and the deck row (ADR-011 sections 6 and 11).
##
## There is no end-turn control: ADR-011 section 7 makes a turn exactly one move,
## so committing the line or submitting the swap is what passes play. Rotate acts
## on the staged line, Confirm commits it whole, Cancel returns every staged tile
## to the deck, and Swap opens the swap set.
##
## Idempotent and null-safe, and the deck row is connected BEFORE the side
## controls. Staging a line and marking a swap both begin with a tap on that row,
## so it is the one connection the screen cannot do without: wiring it first
## means nothing that happens to the controls above it can leave the player
## unable to stage a tile or mark a swap.
func _setup_buttons() -> void:
	_connect_deck_view()
	_connect_button(rotate_button, _on_rotate_pressed)
	_connect_button(confirm_button, _on_confirm_pressed)
	_connect_button(cancel_button, _on_cancel_pressed)
	_connect_button(swap_button, _on_swap_pressed)
	_connect_button(swap_confirm_button, _on_swap_confirm_pressed)
	_connect_button(swap_cancel_button, _on_swap_cancel_pressed)
	_connect_button(restart_button, _on_restart_pressed)


## Connects the deck row's two taps: the selection that names the tile the next
## board tap stages, and the toggle that collects a swap set (ADR-011 sections 6
## and 11).
func _connect_deck_view() -> void:
	if deck_view == null:
		push_error("GameScreen._connect_deck_view: the deck row is missing.")
		return
	_connect_once(deck_view.tile_selected, _on_deck_tile_selected)
	_connect_once(deck_view.tile_toggled, _on_deck_tile_toggled)
	# The drag path (AGENTS.md section 8) is additive: it reaches the same
	# staging command as a tap, and every one of these four reports is routed
	# through the controller rather than through a rule read here.
	_connect_once(deck_view.tile_drag_started, _on_deck_tile_drag_started)
	_connect_once(deck_view.tile_dragged, _on_deck_tile_dragged)
	_connect_once(deck_view.tile_drop_requested, _on_deck_tile_drop_requested)
	_connect_once(deck_view.tile_drag_cancelled, _on_deck_tile_drag_cancelled)


## Connects one action button, tolerating a missing node rather than raising.
func _connect_button(button: Button, handler: Callable) -> void:
	if button == null:
		return
	_connect_once(button.pressed, handler)


## Connects `signal_ref` to `handler` exactly once.
##
## Both `_ready` and `attach_controller` run the wiring, so a plain `connect`
## would make one gesture stage two tiles and mark a swap tile twice.
func _connect_once(signal_ref: Signal, handler: Callable) -> void:
	if not signal_ref.is_connected(handler):
		signal_ref.connect(handler)


## Stages the selected deck tile at `cell` as one tile of the pending line
## (ADR-011 section 11).
##
## A board gesture only ever appends to the pending line; it never writes to the
## board, and it never commits. Committing stays an explicit confirm press
## (ADR-008 section 8).
## Stages the tile for a board tap.
##
## A deck drag owns the pointer while it is in flight, so a board tap that arrives
## mid-drag is ignored: a drag must not stage a tile from the board path as well as
## from its own drop.
func _on_cell_tapped(cell: Vector2i) -> void:
	if controller == null:
		return
	if not String(_drag_tile_id).is_empty():
		return
	stage_at(cell)


## Stages the tile for a board gesture that moved onto a new cell.
##
## A deck drag owns the pointer while it is in flight, so board drags are ignored
## then: the deck row consumes its own gesture, and this guard is the second half
## of that, because a drag that started in the row must not also stage a tile from
## the board path and end up staging twice.
func _on_cell_dragged(cell: Vector2i) -> void:
	if controller == null:
		return
	if not String(_drag_tile_id).is_empty():
		return
	stage_at(cell)


## Stages the player's selected deck tile at `cell`, or reports the refusal.
##
## The line's legality is never decided here: the controller re-validates the
## whole line on every staging command and this only reports which tile it took
## (AGENTS.md section 19). Nothing is written to the board, and nothing commits:
## ADR-011 section 5 keeps board, ledger, and history untouched until Confirm.
##
## Tapping a cell the pending line already holds takes that tile back out, so a
## mistap is undone without cancelling the whole line.
func stage_at(cell: Vector2i) -> bool:
	if controller == null:
		return false
	if controller.staged_cells().has(cell):
		controller.unstage_tile(cell)
		_refresh_all()
		return false
	var tile: TileDefinition = controller.human_tile()
	if tile == null:
		_refresh_all()
		return false
	var staged: bool = controller.stage_tile(tile.tile_id, cell)
	# The row is drawn from the controller, so the tile the next board tap stages
	# is always the tile the row shows as selected, and a refused stage cannot
	# leave the row showing something the application layer did not accept.
	_refresh_all()
	return staged


## Rotates the staged tile one quarter-turn, updating the pending line without
## writing to the board (ADR-011 section 11).
func _on_rotate_pressed() -> void:
	if controller == null:
		return
	controller.rotate_staged()


## Commits the whole pending line as one move (ADR-011 sections 5, 7, and 11).
func _on_confirm_pressed() -> void:
	if controller == null:
		return
	controller.commit_line()


## Returns every staged tile to the deck without touching the turn or the board
## (ADR-011 section 11).
func _on_cancel_pressed() -> void:
	if controller == null:
		return
	controller.cancel_staged()


## Opens the swap set, clearing the pending line first (ADR-011 section 6).
##
## A swap cannot place a tile, so opening it cancels the pending line rather than
## leaving it staged behind the swap. Cancelling the pending line touches neither
## the deck nor the turn, so the player simply re-stages afterwards if they
## change their mind.
func _on_swap_pressed() -> void:
	if controller == null or not controller.is_human_turn():
		return
	controller.cancel_staged()
	_swap_mode = true
	_swap_tiles = [] as Array[StringName]
	deck_view.set_mark_mode(true)
	_refresh_all()


## Submits the marked set as one swap, which consumes the whole turn
## (ADR-011 section 6).
##
## A refusal leaves the marked set and the deck as they were, so the player can
## adjust and retry; the controller reports why through `notice`.
func _on_swap_confirm_pressed() -> void:
	if controller == null:
		return
	if _swap_tiles.is_empty():
		_set_status("Tap at least one tile to swap")
		return
	var swapped: int = controller.request_swap(_swap_tiles)
	if swapped > 0:
		_close_swap_mode()
		return
	# Refused: the tiles are kept and the turn stays open, so the swap set stays
	# open for the player to adjust.
	_refresh_all()


## Closes the swap set without submitting it, keeping the player's tiles.
func _on_swap_cancel_pressed() -> void:
	if _swap_mode:
		_close_swap_mode()
		_refresh_all()
		_set_status("Swap cancelled")
		return
	_refresh_all()


## Writes one line of feedback under the active tile.
##
## ADR-011 section 11 leaves the wording to presentation while the rule stays in
## the application layer, so this only displays a sentence it is handed.
func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


## Leaves swap mode and clears every mark, on both the screen and the row.
func _close_swap_mode() -> void:
	_swap_mode = false
	_swap_tiles = [] as Array[StringName]
	if deck_view != null:
		deck_view.set_mark_mode(false)
	_apply_swap_controls()


## Shows only the swap controls that belong to the current mode.
##
## Swap opens the set and the confirm/cancel pair closes it, so the three are
## never all on screen at once: one control is open on any mobile viewport.
func _apply_swap_controls() -> void:
	if swap_button != null:
		swap_button.visible = not _swap_mode
	if swap_confirm_button != null:
		swap_confirm_button.visible = _swap_mode
	if swap_cancel_button != null:
		swap_cancel_button.visible = _swap_mode


## Returns true while the screen is collecting the swap set (ADR-011 section 6).
func is_swap_mode() -> bool:
	return _swap_mode


## Returns the tiles the player has marked to return, in the order they were
## marked. Empty when no swap is being assembled.
func swap_tiles() -> Array[StringName]:
	return _swap_tiles.duplicate()


## Marks or unmarks one deck tile for the swap (ADR-011 section 6).
func _on_deck_tile_toggled(tile_id: StringName) -> void:
	if not _swap_mode:
		return
	if _swap_tiles.has(tile_id):
		_swap_tiles.erase(tile_id)
		deck_view.set_marked(tile_id, false)
	else:
		_swap_tiles.append(tile_id)
		deck_view.set_marked(tile_id, true)
	_refresh_status()


## Arms one of the human's deck tiles (ADR-010 section 12).
##
## Selecting a deck tile names the tile the next staging command takes from the
## deck (ADR-011 section 11), so this is how the player chooses which tile joins
## the pending line. The selection is forwarded to the controller, which is where
## a tile is armed; the screen only reports the player's choice.
func _on_deck_tile_selected(tile_id: StringName) -> void:
	if controller == null:
		return
	if _swap_mode:
		_on_deck_tile_toggled(tile_id)
		return
	controller.select_deck_tile(tile_id)
	# The row is re-rendered from the controller either way, so a refused
	# selection cannot leave it showing a tile the application layer has not
	# armed.
	_refresh_deck()


# --- Deck drag onto the board (AGENTS.md section 8) -------------------------


## Begins a drag of one deck tile onto the board.
##
## AGENTS.md section 8 asks for drag as a first-class mobile gesture. The drag is
## additive: it reaches the same staging command a tap does, and the tap flow is
## untouched.
##
## A drag is refused outright when the human may not act, so an off-turn gesture
## cannot stage anything (ADR-008 section 8).
func _on_deck_tile_drag_started(tile_id: StringName, _pointer: Vector2) -> void:
	if controller == null or not controller.is_human_turn():
		_refuse_drag(tile_id)
		return
	if _swap_mode:
		_refuse_drag(tile_id)
		return
	_drag_tile_id = tile_id
	if board_view != null:
		board_view.clear_drag()


## Follows a drag: the tile is drawn snapped to the cell under the pointer, and
## that cell is marked with a legal or illegal treatment.
##
## The cell comes from `BoardMetrics` through the board view, which is the same
## mapping the board draws with, so the ghost always sits on the cell it will land
## on. The verdict is the controller's answer for this tile at this cell, so the
## screen shows a rule result rather than computing one (AGENTS.md section 19).
func _on_deck_tile_dragged(tile_id: StringName, pointer: Vector2) -> void:
	if controller == null or String(_drag_tile_id).is_empty():
		return
	if tile_id != _drag_tile_id:
		return
	var cell: Vector2i = board_cell_at(pointer)
	if cell == BoardMetrics.NO_CELL:
		# Off the board there is no target, so nothing is drawn to mislead the
		# player about where a release would land.
		board_view.clear_drag()
		return
	board_view.show_drag(_drag_snapshot(cell), cell, can_drop_at(tile_id, cell))


## Ends a drag on release: the tile is staged at the cell under the pointer when
## the controller accepts it there, and otherwise nothing changes at all.
##
## AGENTS.md section 8's release rule, and ADR-011 section 5's atomicity rule: a
## refused drop leaves the board, the ledger, the history, the deck, and the
## pending line exactly as they were, because a drag never staged anything on the
## way here. Only an accepted drop reaches `stage_at`, which is the same command
## the tap path calls.
func _on_deck_tile_drop_requested(tile_id: StringName, pointer: Vector2) -> void:
	if controller == null or String(_drag_tile_id).is_empty():
		return
	if tile_id != _drag_tile_id:
		return
	var cell: Vector2i = board_cell_at(pointer)
	var accepted: bool = can_drop_at(tile_id, cell)
	_end_drag()
	if cell == BoardMetrics.NO_CELL:
		return
	if not accepted:
		return
	# A tap reports the tile on the press, and that press is what started this
	# drag, so the tile is normally armed already; arming is only needed when a
	# drag arrives without one. Neither call happens twice, so a drop cannot clear
	# a rotation the player set on the pending line.
	if controller.selected_deck_tile_id() != tile_id:
		if not controller.select_deck_tile(tile_id):
			return
	# The same staging command the tap flow uses, with the same following
	# redraw, so a drop and a tap cannot produce different lines.
	stage_at(cell)


## Ends a drag that was abandoned before a release, leaving everything unchanged.
func _on_deck_tile_drag_cancelled(tile_id: StringName) -> void:
	if String(_drag_tile_id).is_empty():
		return
	if tile_id != _drag_tile_id:
		return
	_end_drag()


## Returns the board cell under a pointer position reported by the deck row.
##
## The row works in its own local coordinates, so the point is converted to global
## coordinates first and the cell is then read through the board's own
## `BoardMetrics` mapping. One geometry source, so a drop lands on the cell the
## ghost was drawn over.
func board_cell_at(pointer: Vector2) -> Vector2i:
	if board_view == null:
		return BoardMetrics.NO_CELL
	if deck_view == null:
		return board_view.cell_at_global(pointer)
	return board_view.cell_at_global(deck_view.get_global_transform() * pointer)


## Returns whether the controller would accept a drop of `tile_id` at `cell`.
##
## The answer is entirely the controller's, so the highlight cannot promise a drop
## the staging command would then refuse, and the screen never reads a rule
## (AGENTS.md section 19). An off-board pointer has no cell at all, which is the
## one case the screen answers itself.
func can_drop_at(tile_id: StringName, cell: Vector2i) -> bool:
	if controller == null:
		return false
	if cell == BoardMetrics.NO_CELL:
		return false
	return controller.would_accept_stage(tile_id, cell)


## Returns the deck tile the row is dragging, as a snapshot at `cell`, or null
## when there is nothing to draw.
##
## Built through `TileSnapshot`, the same immutable type the board commits, so the
## ghost is the tile that would actually be placed, at the cell it would be placed
## on.
func _drag_snapshot(cell: Vector2i) -> TileSnapshot:
	if controller == null:
		return null
	var tile: TileDefinition = _deck_tile(_drag_tile_id)
	if tile == null:
		return null
	return TileSnapshot.create(tile, cell, controller.pending_rotation())


## Returns one of the human's held tiles by identity, or null.
func _deck_tile(tile_id: StringName) -> TileDefinition:
	if controller == null:
		return null
	if String(tile_id).is_empty():
		return null
	for tile: TileDefinition in controller.human_deck():
		if tile != null and tile.tile_id == tile_id:
			return tile
	return null


## Ends the drag in thought and on screen, leaving the deck and the board alone.
func _end_drag() -> void:
	_drag_tile_id = &""
	if board_view != null:
		board_view.clear_drag()
	if deck_view != null:
		# The row is told without notifying back, so one release cannot arrive
		# as two endings.
		deck_view.set_dragging(false, false)


## Refuses a drag that started when the human may not act, clearing any drag the
## screen was showing (ADR-008 section 8: off-turn input is gated).
##
## The drag is ended in thought, on the board, and in the row, so an off-turn
## gesture leaves nothing behind and stages nothing.
func _refuse_drag(_tile_id: StringName) -> void:
	_drag_tile_id = &""
	if board_view != null:
		board_view.clear_drag()
	if deck_view != null:
		deck_view.set_dragging(false, false)
		deck_view.cancel_drag(false)
	# The status line is deliberately left alone: `_refresh_status` already says
	# whose turn it is, and an off-turn drag is refused rather than announced.


func _on_restart_pressed() -> void:
	if controller == null:
		return
	controller.start_new_match()


func _on_session_started() -> void:
	if summary_overlay != null:
		summary_overlay.visible = false
	if floating_scores != null:
		floating_scores.clear_all()
	# A new or resumed match has no assembled swap, so the set is closed rather
	# than carried into a deck that no longer holds those tiles.
	_close_swap_mode()
	_refresh_all()


func _on_notice(text: String) -> void:
	if status_label != null:
		status_label.text = text


## Renders the opponent's analysis state (ADR-005 section 9).
##
## The screen holds no copy of the flag: it re-renders from the controller, so
## the message can never disagree with the authoritative thinking state.
func _on_ai_thinking_changed(_thinking: bool) -> void:
	_refresh_status()


## Redraws the board over every cell the committed line wrote
## (ADR-011 sections 1 and 5).
##
## ADR-011 section 1 makes the move a whole line, so the mark covers the line
## rather than one cell, and the line commits as one atomic write: the board is
## re-read from authoritative state after the marks are placed.
func _on_line_committed(result: LineResult, _turn_phase: int) -> void:
	if result == null:
		return
	if controller != null:
		board_view.set_board(controller.get_board())
	board_view.mark_committed_line(result.staged_cells())
	# The committed line must not also be drawn as pending. The controller emits
	# `state_changed` immediately after this signal, which re-renders every HUD
	# value and the deck row from the post-commit state.
	board_view.clear_preview()


## Plays one popup per committed score event, in the deterministic order the
## ledger recorded them (ADR-008 section 9).
func _on_score_awarded(events: Array, cell: Vector2i) -> void:
	if floating_scores == null:
		return
	var anchor: Vector2 = _popup_anchor(cell)
	for index: int in range(events.size()):
		var event: ScoreEvent = events[index]
		if event == null:
			continue
		var offset: Vector2 = Vector2(0.0, -POPUP_STAGGER * float(index))
		floating_scores.spawn(anchor + offset, _popup_text(event), _popup_color(event))


## Shows the final summary panel.
func _on_match_ended(result: MatchResult) -> void:
	if summary_overlay == null or result == null:
		return
	summary_title.text = _summary_title(result)
	summary_body.text = _summary_body(result)
	summary_overlay.visible = true
	_refresh_all()


## Rebuilds every HUD value and the board from authoritative state.
##
## A drag in flight is abandoned first: an authoritative change means the deck or
## the turn moved under the gesture, so the ghost it was drawing can no longer be
## trusted (AGENTS.md section 8).
func _refresh_all() -> void:
	_end_drag()
	var has_controller: bool = controller != null
	var board: BoardState = null
	if has_controller:
		board = controller.get_board()
	board_view.set_board(board)

	if not has_controller:
		board_input.enabled = false
		active_tile_view.clear()
		deck_view.set_deck([] as Array[TileDefinition])
		deck_view.set_locked(true)
		_set_interactive(false)
		turn_indicator.text = ""
		remaining_tiles_label.text = ""
		status_label.text = ""
		return

	var human_turn: bool = controller.is_human_turn()
	board_view.set_human_turn(human_turn)
	board_input.enabled = human_turn
	_set_interactive(human_turn)

	human_score_value.text = str(controller.human_score())
	ai_score_value.text = str(controller.ai_score())
	remaining_tiles_label.text = "Tiles left: %d" % controller.remaining_tiles()

	if controller.is_over():
		turn_indicator.text = "Match over"
	elif human_turn:
		turn_indicator.text = "Your turn"
	else:
		turn_indicator.text = "Rival's turn"

	_refresh_active_tile()
	_refresh_deck()
	_refresh_status()
	_refresh_preview()


## Redraws the human's deck row and its selection (ADR-010 section 12,
## ADR-011 sections 6 and 11).
##
## Both values come from the controller, so the row can never disagree with the
## tile the next staging command takes: the deck is what the human holds and the
## selection is what the application layer has armed (ADR-010 sections 4 and 10).
## Off-turn the row is locked, which is what stops a deck tile being staged while
## the opponent holds the turn (ADR-008 section 8).
func _refresh_deck() -> void:
	if controller == null:
		deck_view.set_mark_mode(false)
		deck_view.set_deck([] as Array[TileDefinition])
		deck_view.set_locked(true)
		return
	deck_view.set_deck(controller.human_deck(), controller.selected_deck_tile_id())
	deck_view.set_locked(not controller.is_human_turn())


## Shows or hides the active tile and its rotation.
func _refresh_active_tile() -> void:
	if controller == null:
		active_tile_view.clear()
		return
	var tile: TileDefinition = controller.human_tile()
	if tile == null:
		active_tile_view.clear()
		return
	active_tile_view.set_tile(tile, controller.pending_rotation())


## Shows the whole pending line on the board, or clears it
## (ADR-011 sections 11 and 5).
##
## Every staged tile is drawn, with one validity verdict for the line as a whole:
## the verdict comes from the controller, which got it from `LineValidator`, so
## the board never decides legality itself (AGENTS.md section 19).
func _refresh_preview() -> void:
	if controller == null or not controller.has_pending():
		board_view.clear_preview()
		_refresh_status()
		return
	board_view.show_line(
		controller.staged_snapshots(),
		controller.is_line_valid(),
		controller.line_reason()
	)
	_refresh_status()


## Chooses the one-line instruction or refusal shown under the tile.
##
## ADR-011 section 7 removed the explicit end-turn action, so the screen names
## the two ways a turn can finish: commit the line, or swap.
func _refresh_status() -> void:
	if controller == null:
		_set_status("")
		return
	if controller.is_over():
		_set_status("")
		return
	if not controller.is_human_turn():
		_set_status(
			RIVAL_THINKING_TEXT if controller.is_ai_thinking() else RIVAL_WAITING_TEXT
		)
		return
	if _swap_mode:
		if _swap_tiles.is_empty():
			_set_status("Tap at least one tile to return")
		else:
			_set_status("Returning %d tile(s)" % _swap_tiles.size())
		return
	if controller.has_pending():
		if controller.is_line_valid():
			_set_status("Tap Confirm to place the line")
		else:
			_set_status(controller.line_reason())
		return
	_set_status("Tap tiles to build a line, or Swap")


## Enables the tile controls only when the human may act.
##
## ADR-011 section 7 makes a turn one move, so every control here belongs to the
## single move the turn allows: Rotate, Confirm, and Cancel act on the pending
## line, and Swap is the alternative move of section 6. All four are gated by the
## same turn condition, and none of them is a hand-over.
func _set_interactive(enabled: bool) -> void:
	rotate_button.disabled = not enabled
	confirm_button.disabled = not enabled
	cancel_button.disabled = not enabled
	swap_button.disabled = not enabled
	# The swap set belongs to the player's own turn, so it is closed as soon as
	# they may no longer act: a locked row must never keep collecting marks.
	if not enabled:
		_close_swap_mode()
		# A drag belongs to the player's own turn too, so it is abandoned when
		# the turn passes rather than left drawable over the board (AGENTS.md
		# section 8: off-turn input is refused).
		_end_drag()
	if swap_confirm_button != null:
		swap_confirm_button.disabled = not enabled
	if swap_cancel_button != null:
		swap_cancel_button.disabled = not enabled
	_apply_swap_controls()


## Returns where a popup for `cell` should appear, in this screen's coordinates.
func _popup_anchor(cell: Vector2i) -> Vector2:
	var global_rect: Rect2 = board_view.global_board_rect()
	var cell_global: Vector2 = BoardMetrics.cell_rect(
		global_rect, cell, BoardEnums.BOARD_WIDTH
	).get_center()
	return floating_scores.get_global_transform().affine_inverse() * cell_global


## Returns the popup caption for one committed event.
func _popup_text(event: ScoreEvent) -> String:
	match event.category:
		ScoringEnums.ScoreCategory.POKER_HAND:
			var hand: String = String(event.evidence.get("category", ""))
			return "+%d %s" % [event.points, _prettify(hand)]
		ScoringEnums.ScoreCategory.EDGE_MATCH:
			return "+%d Edge" % event.points
		ScoringEnums.ScoreCategory.EDGE_CLUSTER:
			return "+%d Cluster" % event.points
	return "+%d" % event.points


## Returns the popup colour for one committed event.
func _popup_color(event: ScoreEvent) -> Color:
	match event.category:
		ScoringEnums.ScoreCategory.POKER_HAND:
			return POKER_COLOR
		ScoringEnums.ScoreCategory.EDGE_MATCH:
			return EDGE_COLOR
		ScoringEnums.ScoreCategory.EDGE_CLUSTER:
			return CLUSTER_COLOR
	return Color.WHITE


## Turns an event's machine-readable category name into a readable caption.
func _prettify(raw: String) -> String:
	if raw.is_empty():
		return "Score"
	return raw.to_lower().capitalize()


## Returns the summary heading for a finished match (ADR-003 section 8).
func _summary_title(result: MatchResult) -> String:
	if result.is_incomplete():
		return "Match incomplete"
	if result.is_draw():
		return "It's a draw"
	if result.winner_id() == TurnEnums.HUMAN_PLAYER_ID:
		return "You win"
	return "%s wins" % AI_LABEL


## Returns the summary detail: totals, breakdown, and how the match ended.
func _summary_body(result: MatchResult) -> String:
	var human: Dictionary = result.terms_for(TurnEnums.HUMAN_PLAYER_ID)
	var ai: Dictionary = result.terms_for(TurnEnums.AI_PLAYER_ID)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s %d   -   %s %d" % [HUMAN_LABEL, result.human_score, AI_LABEL, result.ai_score])
	lines.append(
		"%s: poker %d, edges %d, clusters %d" % [
			HUMAN_LABEL,
			int(human.get("poker", 0)),
			int(human.get("edge", 0)),
			int(human.get("cluster", 0)),
		]
	)
	lines.append(
		"%s: poker %d, edges %d, clusters %d" % [
			AI_LABEL,
			int(ai.get("poker", 0)),
			int(ai.get("edge", 0)),
			int(ai.get("cluster", 0)),
		]
	)
	lines.append(
		"%s after %d move(s); %d tiles left" % [
			_end_reason_text(result.end_reason),
			result.move_count,
			result.tiles_remaining,
		]
	)
	return "\n".join(lines)


## Returns a short readable description of why the match ended.
func _end_reason_text(reason: int) -> String:
	match reason:
		TurnEnums.EndReason.BOARD_FULL:
			return "The board filled up"
		TurnEnums.EndReason.TILE_SOURCE_EXHAUSTED:
			return "No tiles remained"
		TurnEnums.EndReason.RULES_FAILURE:
			return "A rules error stopped play"
	return "The match ended"
