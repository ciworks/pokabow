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

## Outline drawn around the panel of the player whose turn it is (ADR-008
## section 4). Presentation only: it reports the turn the controller already
## owns and decides nothing itself.
const TURN_HIGHLIGHT_COLOR: Color = Color(1.0, 0.87, 0.30, 1.0)

## Thickness of the turn highlight outline, in pixels.
const TURN_HIGHLIGHT_WIDTH: int = 3

@onready var board_view: BoardView = %BoardView
@onready var board_input: BoardInputController = %BoardInputController
@onready var available_tiles_label: Label = %AvailableTilesLabel
@onready var tile_pile_view: TilePileView = %TilePileView
@onready var deal_layer: DealLayer = %DealLayer
@onready var deck_view: DeckView = %DeckView
@onready var rotate_button: Button = %RotateButton
@onready var confirm_button: Button = %ConfirmButton
@onready var cancel_button: Button = %CancelButton
@onready var swap_button: Button = %SwapButton
@onready var swap_confirm_button: Button = %SwapConfirmButton
@onready var swap_cancel_button: Button = %SwapCancelButton
@onready var restart_button: Button = %RestartButton
@onready var difficulty_picker: OptionButton = %DifficultyPicker
@onready var human_score_value: Label = %HumanScoreValue
@onready var ai_score_value: Label = %AiScoreValue
@onready var human_score_panel: PanelContainer = %HumanScorePanel
@onready var ai_score_panel: PanelContainer = %AiScorePanel
@onready var turn_indicator: Label = %TurnIndicator
@onready var status_label: Label = %StatusLabel
@onready var floating_scores: FloatingScores = %FloatingScores
@onready var summary_overlay: Control = %SummaryOverlay
@onready var summary_title: Label = %SummaryTitle
@onready var summary_body: Label = %SummaryBody
@onready var recovery_overlay: Control = %RecoveryOverlay
@onready var recovery_body: Label = %RecoveryBody
@onready var recovery_restart_button: Button = %RecoveryRestartButton

## The application-layer controller this screen drives, or null before boot.
var controller: GameSessionController = null

## The un-highlighted score-panel style, captured from the scene before any
## highlight is applied, so a panel returns to exactly the look it was authored
## with rather than falling back to the engine's default panel.
var _base_panel_style: StyleBox = null

## Cached highlighted style, built once from `_base_panel_style` because the HUD
## refreshes on every state change.
var _highlight_panel_style: StyleBox = null

## Deck identities the row has already drawn, so `_refresh_deck` can tell which
## tiles are new and deal only those.
##
## The set only ever grows. A tile that leaves the row because it was staged comes
## back when it is un-staged or the line is cancelled, and dealing it a second time
## would read as a second deal rather than as the same tile returning.
var _known_deck_ids: Array[StringName] = []

## Identities concealed in the row while the deal animation flies them in, in the
## order they were dealt.
var _dealing_ids: Array[StringName] = []

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

## The staged board cell the current board gesture began on, or
## `BoardMetrics.NO_CELL` when that gesture did not begin on a staged tile.
##
## A board gesture is resolved on release rather than on the press, so this is what
## the press recorded: released on the same cell it began on turns that tile,
## released on another cell moves it there, and released off the board takes it out
## of the line. Presentation-only - it records where a gesture started, and every
## outcome still goes through an application command.
var _move_from_cell: Vector2i = BoardMetrics.NO_CELL

## The platform feedback service, injected by `AppRoot`, or null when there is
## none (Milestone 8).
##
## Optional by design: every cue is null-safe and no rule path reads it, so a
## screen without an adapter - the headless tests - behaves identically minus the
## vibration (docs/sections/05-mobile-ux.md section 6).
var feedback: FeedbackAdapter = null


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
	available_tiles_label = get_node_or_null("%AvailableTilesLabel") as Label
	tile_pile_view = get_node_or_null("%TilePileView") as TilePileView
	deal_layer = get_node_or_null("%DealLayer") as DealLayer
	deck_view = get_node_or_null("%DeckView") as DeckView
	rotate_button = get_node_or_null("%RotateButton") as Button
	confirm_button = get_node_or_null("%ConfirmButton") as Button
	cancel_button = get_node_or_null("%CancelButton") as Button
	swap_button = get_node_or_null("%SwapButton") as Button
	swap_confirm_button = get_node_or_null("%SwapConfirmButton") as Button
	swap_cancel_button = get_node_or_null("%SwapCancelButton") as Button
	restart_button = get_node_or_null("%RestartButton") as Button
	difficulty_picker = get_node_or_null("%DifficultyPicker") as OptionButton
	human_score_value = get_node_or_null("%HumanScoreValue") as Label
	ai_score_value = get_node_or_null("%AiScoreValue") as Label
	human_score_panel = get_node_or_null("%HumanScorePanel") as PanelContainer
	ai_score_panel = get_node_or_null("%AiScorePanel") as PanelContainer
	turn_indicator = get_node_or_null("%TurnIndicator") as Label
	# Captured once and before any highlight is applied, so the authored panel
	# look survives: clearing an override outright would drop the panel back to
	# the engine default instead of the scene's style.
	if _base_panel_style == null and human_score_panel != null:
		_base_panel_style = human_score_panel.get_theme_stylebox("panel")
	status_label = get_node_or_null("%StatusLabel") as Label
	floating_scores = get_node_or_null("%FloatingScores") as FloatingScores
	summary_overlay = get_node_or_null("%SummaryOverlay") as Control
	summary_title = get_node_or_null("%SummaryTitle") as Label
	summary_body = get_node_or_null("%SummaryBody") as Label
	recovery_overlay = get_node_or_null("%RecoveryOverlay") as Control
	recovery_body = get_node_or_null("%RecoveryBody") as Label
	recovery_restart_button = get_node_or_null("%RecoveryRestartButton") as Button


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
		controller.preview_changed.connect(_refresh_staging)
		controller.line_committed.connect(_on_line_committed)
		controller.score_awarded.connect(_on_score_awarded)
		controller.match_ended.connect(_on_match_ended)
		controller.notice.connect(_on_notice)
		controller.ai_thinking_changed.connect(_on_ai_thinking_changed)
		controller.recovery_failed.connect(_on_recovery_failed)
	_refresh_all()


## Injects the platform feedback service (Milestone 8, ADR-008 section 5).
##
## Separate from `attach_controller` because feedback is presentational and
## optional: a screen driven without one still plays, it just does not vibrate.
func attach_feedback_adapter(adapter: FeedbackAdapter) -> void:
	feedback = adapter


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
	# A board drag repositions a tile the line already holds; it never pulls a tile
	# out of the hand, so the only way a deck tile reaches the board is still a drag
	# that began on the deck row (ADR-011 section 11).
	_connect_once(board_input.cell_dragged, _on_cell_dragged)
	# The release carries where the finger came off the board, which is how a
	# gesture that began on a pending tile and ended off the board is recognised as
	# a removal of that one tile from the line (ADR-011 section 11).
	_connect_once(board_input.pointer_released, _on_pointer_released)


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
	_connect_button(recovery_restart_button, _on_recovery_restart_pressed)
	_setup_difficulty_picker()


## Connects the deck row's two taps: the selection that names the tile the next
## board tap stages, and the toggle that collects a swap set (ADR-011 sections 6
## and 11).
func _connect_deck_view() -> void:
	if deck_view == null:
		push_error("GameScreen._connect_deck_view: the deck row is missing.")
		return
	_connect_once(deck_view.tile_selected, _on_deck_tile_selected)
	_connect_once(deck_view.tile_toggled, _on_deck_tile_toggled)
	# A second tap on the already-selected tile turns it before it is staged. The
	# row reports the request and the controller owns the rotation, so the tile the
	# row draws is the tile the next staging command commits (AGENTS.md section 19).
	_connect_once(deck_view.tile_rotation_requested, _on_deck_tile_rotation_requested)
	# The drag path (AGENTS.md section 8) is additive: it reaches the same
	# staging command as a tap, and every one of these four reports is routed
	# through the controller rather than through a rule read here.
	_connect_once(deck_view.tile_drag_started, _on_deck_tile_drag_started)
	_connect_once(deck_view.tile_dragged, _on_deck_tile_dragged)
	_connect_once(deck_view.tile_drop_requested, _on_deck_tile_drop_requested)
	_connect_once(deck_view.tile_drag_cancelled, _on_deck_tile_drag_cancelled)
	# A deal that could not start because the row had not been given its rectangle
	# yet is retried from the row's own resize report (ADR-008 sections 4 and 5).
	_connect_once(deck_view.resized, _on_deck_row_resized)


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


## Records where a board press began, so the release that ends it can be read as one
## whole gesture (AGENTS.md section 8).
##
## A board press deliberately does NOT stage a deck tile. Placing a tile from the
## hand is a gesture that starts on the hand - the player drags a deck tile onto the
## board - so the tile that lands on a cell is always one the player picked up.
## Staging from a bare board tap let a tap on any cell spend a tile the player never
## chose, which is why that path was removed.
##
## A press that begins on a tile the pending line holds picks that tile up, and
## `_on_pointer_released` decides what became of it: released where it started turns
## it, released elsewhere on the board moves it there, released off the board takes
## it out of the line. Nothing is decided here, because at press time the gesture
## could still become any of the three.
##
## A board gesture only ever touches the pending line; it never writes to the board
## and never commits. Committing stays an explicit confirm press (ADR-008 section 8).
##
## A deck drag owns the pointer while it is in flight, so a board press that arrives
## mid-drag is ignored.
func _on_cell_tapped(cell: Vector2i) -> void:
	if controller == null:
		return
	if not String(_drag_tile_id).is_empty():
		return
	_move_from_cell = cell if controller.staged_cells().has(cell) else BoardMetrics.NO_CELL


## Follows a board gesture, showing where the tile the gesture picked up would land.
## Resolving the gesture is the release's job, not this one.
##
## A deck drag owns the pointer while it is in flight, so a board drag that arrives
## mid-drag is ignored. A gesture that began on a staged tile previews that tile
## moving; a gesture that began anywhere else picked up nothing, so it previews
## nothing. This never stages, moves, or removes anything: it only draws, which is
## what makes a refused reposition change nothing at all (ADR-011 section 5).
func _on_cell_dragged(cell: Vector2i) -> void:
	if controller == null:
		return
	if not String(_drag_tile_id).is_empty():
		return
	if _move_from_cell == BoardMetrics.NO_CELL:
		return
	_refresh_staged_drag(cell)


## Stages the player's selected deck tile at `cell`, or reports the refusal.
##
## The line's legality is never decided here: the controller re-validates the
## whole line on every staging command and this only reports which tile it took
## (AGENTS.md section 19). Nothing is written to the board, and nothing commits:
## ADR-011 section 5 keeps board, ledger, and history untouched until Confirm.
##
## A `cell` the pending line already holds is refused rather than replaced: a drop
## cannot land on a cell its own line occupies, so a staged tile is never silently
## overwritten. A tile leaves the line only by being dragged off the board or by
## Cancel.
func stage_at(cell: Vector2i) -> bool:
	if controller == null:
		return false
	if controller.staged_cells().has(cell):
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
	# The cue follows the result, so a refused stage tells the finger nothing
	# changed rather than confirming a placement that did not happen.
	if staged:
		_cue_place()
	else:
		_cue_refuse()
	return staged


## Turns the one pending tile standing on `cell` a quarter-turn (ADR-011
## section 11).
##
## Rotation is real staged state rather than decoration: it lives on the staged
## snapshot, and the edge and scoring rules read the rotated edges, so turning a
## pending tile is a change to the move the player is about to commit. Nothing is
## written to the board here, and nothing commits.
##
## The rotation applies only to tiles staged this turn, because the controller
## rotates the snapshot it holds for that cell. A cell the player committed on an
## earlier move has no snapshot in the pending line, so a tap there stages nothing
## and no committed tile can ever be turned (ADR-011 section 5).
func rotate_staged_at(cell: Vector2i) -> bool:
	if controller == null:
		return false
	var rotation: int = controller.rotate_staged_at(cell)
	_refresh_all()
	return rotation >= 0


## Turns the already-selected deck tile a quarter-turn (ADR-011 section 11).
##
## The request arrives when the player taps the tile the row is already drawing as
## selected. It is forwarded to the controller rather than applied here, because
## the rotation belongs to the tile the application layer has armed, and the row is
## then re-rendered from what the controller reports. It deliberately does not
## re-select the tile: `select_deck_tile` returns the pending rotation to the base
## orientation, so re-selecting would undo the very rotation the player asked for.
##
## The tile named by the row is checked against the armed tile first, so a stale
## request cannot turn a tile the player has since moved on from. Nothing is staged
## and nothing is written: the rotation takes effect when the tile is staged.
func _on_deck_tile_rotation_requested(tile_id: StringName) -> void:
	if controller == null:
		return
	if controller.selected_deck_tile_id() != tile_id:
		_refresh_deck()
		return
	controller.rotate_selected_deck_tile()
	_refresh_all()


## Rotates the tile the pending line last took one quarter-turn, updating the
## pending line without writing to the board (ADR-011 section 11).
func _on_rotate_pressed() -> void:
	if controller == null:
		return
	controller.rotate_staged()


## Resolves a board press on release: the release is what decides what became of the
## tile the press picked up (AGENTS.md section 8).
##
## Three outcomes, all of them adjustments to the pending line. Released on the cell
## it began on turns that tile a quarter-turn, which is the tap-to-turn gesture.
## Released on a different board cell moves that tile there, which is what lets an
## unconfirmed tile be repositioned. Released off the board takes that one tile back
## out of the line, which is how a mistapped tile is recovered.
##
## A release that picked up nothing does nothing at all, and neither does one that
## ends a deck drag: a deck drag owns the pointer and its own drop decides what
## happens. No outcome writes to the board, the deck, or the turn (ADR-011
## section 5).
func _on_pointer_released(cell: Vector2i) -> void:
	if controller == null:
		return
	if not String(_drag_tile_id).is_empty():
		# A deck drag owns the pointer, and its own drop decides what happens.
		return
	var origin: Vector2i = _move_from_cell
	_move_from_cell = BoardMetrics.NO_CELL
	_clear_staged_drag()
	if origin == BoardMetrics.NO_CELL:
		return
	if not controller.staged_cells().has(origin):
		return
	if cell == BoardMetrics.NO_CELL:
		controller.unstage_tile(origin)
		_refresh_all()
		return
	if cell == origin:
		rotate_staged_at(origin)
		return
	if controller.move_staged_at(origin, cell):
		_refresh_all()
		return
	# The destination is refused, so the tile stays exactly where it was and the
	# line is redrawn to show it still standing there (ADR-011 section 5).
	_refresh_all()


## Commits the whole pending line as one move (ADR-011 sections 5, 7, and 11).
##
## The cue follows the commit result rather than the press: a refused line is
## reported by the controller, so the buzz confirms what actually happened
## instead of what the player hoped for.
func _on_confirm_pressed() -> void:
	if controller == null:
		return
	var result: LineResult = controller.commit_line()
	if _line_was_committed(result):
		_cue_place()
	else:
		_cue_refuse()


## Returns true when a commit attempt actually wrote the line to the board.
func _line_was_committed(result: LineResult) -> bool:
	return result != null and result.was_committed()


# --- Platform feedback (Milestone 8, docs/sections/05-mobile-ux.md section 6) --
#
# Every cue is null-safe, because the adapter is optional and a screen driven
# without one must still play. The cues are called at the moment a HUMAN gesture
# resolved, never from a controller signal: `line_committed` and `score_awarded`
# fire for the rival's move too, and buzzing the player's phone for an action
# they did not take would tell them nothing.


## The player chose a deck tile.
func _cue_select() -> void:
	if feedback != null:
		feedback.cue_select()


## A tile joined the pending line, or the player's line was committed.
func _cue_place() -> void:
	if feedback != null:
		feedback.cue_place()


## A refused gesture changed nothing.
func _cue_refuse() -> void:
	if feedback != null:
		feedback.cue_refuse()


## The player was awarded points.
func _cue_score() -> void:
	if feedback != null:
		feedback.cue_score()


## The match reached an end condition.
func _cue_match_end() -> void:
	if feedback != null:
		feedback.cue_match_end()


## Returns true when a score-event list was awarded to the human.
##
## The ledger records who was credited, so this reads the award rather than
## inferring the owner from whose turn it is: a rival's reply can score while the
## screen is already showing the human's phase.
func _award_was_human(events: Array) -> bool:
	for raw: Variant in events:
		if raw is ScoreEvent:
			return (raw as ScoreEvent).player_id == TurnEnums.HUMAN_PLAYER_ID
	return false


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
	if controller.select_deck_tile(tile_id):
		_cue_select()
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
##
## The board gesture state is cleared here as well, so a turn that passes mid-gesture
## cannot leave a stale origin behind for a later release to act on.
func _end_drag() -> void:
	_drag_tile_id = &""
	_move_from_cell = BoardMetrics.NO_CELL
	if board_view != null:
		board_view.clear_drag()
	if deck_view != null:
		# The row is told without notifying back, so one release cannot arrive
		# as two endings.
		deck_view.set_dragging(false, false)


## Returns the pending line's snapshot on `cell`, or null when the line holds none.
func _staged_snapshot_at(cell: Vector2i) -> TileSnapshot:
	if controller == null:
		return null
	for snapshot: TileSnapshot in controller.staged_snapshots():
		if snapshot != null and snapshot.get_cell() == cell:
			return snapshot
	return null


## Draws the tile a board gesture has picked up, snapped to `cell` with the verdict
## for dropping it there. It only draws: the move itself happens on release.
##
## The verdict is the controller's own answer for this exact move, so the board
## cannot promise a landing the move command would then refuse (AGENTS.md
## section 19).
func _refresh_staged_drag(cell: Vector2i) -> void:
	if board_view == null:
		return
	var snapshot: TileSnapshot = _staged_snapshot_at(_move_from_cell)
	if snapshot == null:
		board_view.clear_drag()
		return
	var moved: TileSnapshot = TileSnapshot.create(
		snapshot.get_tile(), cell, snapshot.get_rotation()
	)
	board_view.show_drag(moved, cell, controller.can_move_staged_at(_move_from_cell, cell))


## Removes the tile a board gesture was drawing, leaving the line untouched.
func _clear_staged_drag() -> void:
	if board_view != null:
		board_view.clear_drag()


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
	# The chosen opponent must survive a new match. `start_new_match` does not
	# clear the difficulty, but the player's choice still has to outlive the
	# restart, and this is the one place a fresh match begins (Milestone 6).
	var difficulty: int = controller.ai_difficulty()
	controller.start_new_match()
	controller.set_ai_difficulty(difficulty)


## Fills the difficulty control and wires it to the opponent policy.
##
## The control owns no policy: it shows the difficulty the controller reports and
## reports the player's choice straight to the controller, so the value shown and
## the value in force cannot disagree (AGENTS.md section 19). The list is built
## from `AiEnums.Difficulty`, so the three phases of ADR-005 sections 4 to 6 are
## exactly the three the player can pick.
##
## Idempotent, because the screen wires itself from both `_ready` and
## `attach_controller`: a second call must not double the list.
func _setup_difficulty_picker() -> void:
	if difficulty_picker == null:
		return
	if difficulty_picker.item_count == 0:
		for value: int in AiEnums.Difficulty.values():
			difficulty_picker.add_item(_difficulty_label(value), value)
	_connect_once(difficulty_picker.item_selected, _on_difficulty_selected)


## Returns the player-facing name of one difficulty (ADR-005 sections 4 to 6).
func _difficulty_label(value: int) -> String:
	match value:
		AiEnums.Difficulty.EASY:
			return "Easy"
		AiEnums.Difficulty.MEDIUM:
			return "Medium"
		AiEnums.Difficulty.HARD:
			return "Hard"
	return AiEnums.difficulty_name(value)


## Forwards the player's choice to the controller, which owns the policy.
##
## The change is safe mid-match: the controller cancels an analysis in flight and
## re-schedules the rival under the new policy, so switching cannot strand it
## (ADR-005 section 9).
func _on_difficulty_selected(index: int) -> void:
	if controller == null or difficulty_picker == null:
		return
	controller.set_ai_difficulty(difficulty_picker.get_item_id(index))
	_refresh_difficulty()


## Shows the difficulty actually in force, so the control can never display a
## policy the opponent is not using.
func _refresh_difficulty() -> void:
	if controller == null or difficulty_picker == null:
		return
	var index: int = difficulty_picker.get_item_index(controller.ai_difficulty())
	if index >= 0 and index != difficulty_picker.selected:
		difficulty_picker.select(index)


func _on_session_started() -> void:
	if summary_overlay != null:
		summary_overlay.visible = false
	# A match that starts (or resumes) supersedes any recovery panel: the player
	# has resolved the failure, so the panel must not sit over live play.
	if recovery_overlay != null:
		recovery_overlay.visible = false
	if floating_scores != null:
		floating_scores.clear_all()
	# A new or resumed match has no assembled swap, so the set is closed rather
	# than carried into a deck that no longer holds those tiles.
	_close_swap_mode()
	_refresh_all()


func _on_notice(text: String) -> void:
	if status_label != null:
		status_label.text = text


## Shows the recovery panel when a saved match could not be restored
## (Milestone 7, ADR-003 section 7).
##
## This is deliberately a decision rather than an automatic restart. The save is
## still on disk and is the last valid transaction, so the player is told what
## happened and chooses when to move on rather than having their match replaced
## without a word. Everything behind the panel stays frozen: no session exists,
## so every command is already refused, and the panel blocks the pointer.
func _on_recovery_failed(reason: String) -> void:
	if recovery_overlay == null:
		return
	if recovery_body != null:
		recovery_body.text = (
			"Your saved match has not been changed and is still on this device, "
			+ "but it could not be reopened: %s.\n"
			+ "Starting a fresh match will replace it."
		) % reason
	recovery_overlay.visible = true
	_refresh_all()


## Starts a fresh match from the recovery panel, replacing the unreadable save.
func _on_recovery_restart_pressed() -> void:
	if controller == null:
		return
	controller.start_new_match()


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
		# The committed tiles may have formed or grown a same-colour region, so
		# the persistent outlines are re-read from the post-commit board here
		# rather than waiting for the refresh that follows this signal.
		_refresh_clusters()
	board_view.mark_committed_line(result.staged_cells())
	# The committed line must not also be drawn as pending. The controller emits
	# `state_changed` immediately after this signal, which re-renders every HUD
	# value and the deck row from the post-commit state.
	board_view.clear_preview()


## Plays one popup per committed score event, in the deterministic order the
## ledger recorded them (ADR-008 section 9).
func _on_score_awarded(events: Array, cell: Vector2i) -> void:
	# The board marks what actually scored - the matching boundaries and the
	# paying clusters - from the same event list the popups read, so a mark and
	# the points beside it can never describe different awards (AGENTS.md
	# section 8, Milestone 8).
	if board_view != null:
		board_view.show_score_reveal(events)
		if board_view.debug_overlay != null:
			# Diagnostics read the same committed events the reveal does, so the
			# overlay cannot report an award the ledger did not record.
			board_view.debug_overlay.set_last_events(events)
	# Cued only for the player's own award. The controller emits this for the
	# rival's move too, so without the check the player's phone would buzz for
	# points they did not score.
	if _award_was_human(events):
		_cue_score()
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
	_cue_match_end()
	summary_title.text = _summary_title(result)
	summary_body.text = _summary_body(result)
	summary_overlay.visible = true
	_refresh_all()


## Outlines `panel` in the turn colour, or restores its authored look.
##
## The highlight reports a turn the controller already owns, so it can never
## disagree with `TurnIndicator` (AGENTS.md section 19). The outlined style is
## built from the panel's own, so the highlight keeps the panel's shape, padding,
## and corner radius instead of restating them here.
func _apply_turn_highlight(panel: PanelContainer, active: bool) -> void:
	if panel == null or _base_panel_style == null:
		return
	if not active:
		panel.add_theme_stylebox_override("panel", _base_panel_style)
		return
	if _highlight_panel_style == null:
		_highlight_panel_style = _build_highlight_style()
	if _highlight_panel_style != null:
		panel.add_theme_stylebox_override("panel", _highlight_panel_style)


## Returns a copy of the authored panel style carrying the turn outline.
##
## A `StyleBoxFlat`'s minimum size includes its border, so the border is taken
## out of the content margins it replaces. Without that the HUD would nudge a
## few pixels sideways every time the turn changed hands.
func _build_highlight_style() -> StyleBox:
	if _base_panel_style == null:
		return null
	var highlighted: StyleBox = _base_panel_style.duplicate() as StyleBox
	if highlighted is StyleBoxFlat:
		var flat: StyleBoxFlat = highlighted as StyleBoxFlat
		flat.border_color = TURN_HIGHLIGHT_COLOR
		flat.set_border_width_all(TURN_HIGHLIGHT_WIDTH)
		flat.content_margin_left = maxf(flat.content_margin_left - TURN_HIGHLIGHT_WIDTH, 0.0)
		flat.content_margin_right = maxf(flat.content_margin_right - TURN_HIGHLIGHT_WIDTH, 0.0)
		flat.content_margin_top = maxf(flat.content_margin_top - TURN_HIGHLIGHT_WIDTH, 0.0)
		flat.content_margin_bottom = maxf(flat.content_margin_bottom - TURN_HIGHLIGHT_WIDTH, 0.0)
	return highlighted


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
	_refresh_clusters()
	# The development overlay reads the same authoritative state the board draws
	# (AGENTS.md section 17). It is handed the controller rather than reaching for
	# one, and it stays hidden unless the debug setting or its toggle key is used.
	if board_view.debug_overlay != null:
		board_view.debug_overlay.controller = controller

	if not has_controller:
		board_input.enabled = false
		deck_view.set_deck([] as Array[TileDefinition])
		deck_view.set_locked(true)
		_set_interactive(false)
		turn_indicator.text = ""
		available_tiles_label.text = ""
		status_label.text = ""
		_apply_turn_highlight(human_score_panel, false)
		_apply_turn_highlight(ai_score_panel, false)
		return

	var human_turn: bool = controller.is_human_turn()
	board_view.set_human_turn(human_turn)
	board_input.enabled = human_turn
	_set_interactive(human_turn)

	human_score_value.text = str(controller.human_score())
	_refresh_difficulty()
	ai_score_value.text = str(controller.ai_score())
	# The panel of the player whose turn it is carries the outline, so the mark
	# always means "this player may act now". A finished match highlights neither
	# (ADR-008 section 4).
	var over: bool = controller.is_over()
	_apply_turn_highlight(human_score_panel, human_turn and not over)
	_apply_turn_highlight(ai_score_panel, not human_turn and not over)
	available_tiles_label.text = "Tiles available: %d" % controller.remaining_tiles()

	if controller.is_over():
		turn_indicator.text = "Match over"
	elif human_turn:
		turn_indicator.text = "Your turn"
	else:
		turn_indicator.text = "Rival's turn"

	_refresh_deck()
	_refresh_status()
	_refresh_preview()


## Redraws the human's deck row, its selection, and that tile's rotation
## (ADR-010 section 12, ADR-011 sections 6 and 11).
##
## All three values come from the controller, so the row can never disagree with
## the tile the next staging command takes: the deck is what the human holds, the
## selection is what the application layer has armed, and the rotation is the
## quarter-turn that tile would be staged at (ADR-010 sections 4 and 10). Passing
## the rotation is what makes a tap on the selected tile visibly turn it in the row
## instead of only showing up once the tile is on the board.
## Off-turn the row is locked, which is what stops a deck tile being staged while
## the opponent holds the turn (ADR-008 section 8).
func _refresh_deck() -> void:
	if controller == null:
		deck_view.set_mark_mode(false)
		deck_view.set_deck([] as Array[TileDefinition])
		deck_view.set_locked(true)
		deck_view.set_concealed([] as Array[StringName])
		_known_deck_ids = []
		_dealing_ids = []
		return
	var deck: Array[TileDefinition] = controller.unstaged_human_deck()
	deck_view.set_deck(
		deck,
		controller.selected_deck_tile_id(),
		controller.pending_rotation()
	)
	deck_view.set_locked(not controller.is_human_turn())
	_sync_tile_pile()
	_deal_new_tiles(deck)


## Shows the bag's pile in the tiles-remaining panel (ADR-008 section 4).
##
## The pile and the number beside it are read from the same figure, so the stack
## can never disagree with the count the panel spells out.
func _sync_tile_pile() -> void:
	if tile_pile_view == null or controller == null:
		return
	tile_pile_view.set_tile_count(controller.remaining_tiles())


## Flies the tiles this row has not drawn before from the bag's pile into the row
## (AGENTS.md section 8).
##
## A deck only gains tiles at match setup and at the refill that follows a
## committed line, so the deal is triggered by the row gaining a tile rather than
## by the screen deciding that a deal should happen: what the row ends up showing
## is always exactly what the application layer reports.
##
## Nothing is recorded as dealt until a flight has actually been requested, so a
## deal that cannot start yet is retried by a later refresh instead of being lost.
## That matters at boot: the composition root attaches the controller before the
## containers have given the row its rectangle, and a tile measured at that moment
## has nowhere to land (ADR-008 sections 4 and 5).
##
## A deal already in flight is left to finish. The deck only gains tiles at setup
## and at a turn boundary, so two flights cannot realistically overlap.
func _deal_new_tiles(deck: Array[TileDefinition]) -> void:
	var fresh: Array[StringName] = []
	for tile: TileDefinition in deck:
		if not _known_deck_ids.has(tile.tile_id):
			fresh.append(tile.tile_id)
	if fresh.is_empty():
		return
	if deal_layer == null or tile_pile_view == null:
		# Nothing can draw a flight, so the tiles are taken as already dealt
		# rather than re-checked on every refresh.
		_known_deck_ids.append_array(fresh)
		return
	if deal_layer.is_playing():
		return

	# Concealed before the row has drawn them, so a tile that is about to be dealt
	# cannot flash into place for a frame and then fly in.
	deck_view.set_concealed(fresh)

	var tiles: Array[TileDefinition] = []
	var destinations: Array[Rect2] = []
	for index: int in range(deck.size()):
		if not fresh.has(deck[index].tile_id):
			continue
		var target: Rect2 = deck_view.tile_global_rect(index)
		if target.size == Vector2.ZERO:
			# The containers have not given the row its rectangle yet, so a tile
			# has nowhere to land. Nothing is recorded as dealt and the tiles stay
			# concealed: the row's own `resized` report brings the deal back here
			# once there is a rectangle to aim at.
			return
		tiles.append(deck[index])
		destinations.append(target)

	_known_deck_ids.append_array(fresh)
	_dealing_ids = fresh
	if not deal_layer.progressed.is_connected(_on_deal_progressed):
		deal_layer.progressed.connect(_on_deal_progressed)
	deal_layer.deal(tiles, tile_pile_view.stack_origin_global(), destinations)


## Reveals each dealt tile once the animation reports its turn has finished, so the
## row and the animation never both draw the same tile and no face is shown before
## that tile's own turn has completed.
func _on_deal_progressed(revealed: int) -> void:
	var remaining: Array[StringName] = []
	for index: int in range(_dealing_ids.size()):
		if index >= revealed:
			remaining.append(_dealing_ids[index])
	deck_view.set_concealed(remaining)
	if remaining.is_empty():
		_dealing_ids = []


## Re-attempts a deal that could not start because the row was not laid out yet.
##
## The composition root may attach the controller before the containers have
## sized the row, and a deal measured at that moment has no destination to aim
## at. The row reports its first real size here, which is the earliest moment the
## opening hand can be dealt in (ADR-008 sections 4 and 5).
func _on_deck_row_resized() -> void:
	if controller == null:
		return
	_deal_new_tiles(controller.unstaged_human_deck())


## Keeps the deck row and board preview in sync after staging.
func _refresh_staging() -> void:
	_refresh_deck()
	_refresh_preview()


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
	_refresh_rotation_hint()
	_refresh_status()


## Marks, on the tile the rotate command acts on, which of its four edges
## currently match the committed tile across them (AGENTS.md section 8).
##
## The verdicts come from the controller, which read them from the domain
## edge-match rule, so the marks report the adjacencies the board already holds
## and the screen predicts nothing (AGENTS.md sections 2 and 19). ADR-011
## section 11 rotates one tile of the pending line and the preview layer outlines
## that same last staged tile, so the hint is published for it.
##
## A hint is only meaningful while a line is staged, and `show_line` has just
## dropped any previous one, so an empty line clears the marks rather than
## leaving the last tile's verdicts behind.
func _refresh_rotation_hint() -> void:
	if controller == null:
		board_view.clear_edge_matches()
		return
	var cells: Array[Vector2i] = controller.staged_cells()
	if cells.is_empty():
		board_view.clear_edge_matches()
		return
	var target: Vector2i = cells[cells.size() - 1]
	board_view.show_edge_matches(target, controller.staged_edge_matches(target))


## Shows the persistent outlines of every same-colour edge region the committed
## board holds (AGENTS.md section 8, docs/sections/05-mobile-ux.md section 4).
##
## The clusters are enumerated by the controller with `EdgeClusterScorer`, so the
## board outlines the regions the rules recognise instead of detecting them itself
## (AGENTS.md section 19). Pushed from the same refresh that re-reads the board, so
## an outline can never describe a placement that is no longer there.
func _refresh_clusters() -> void:
	if controller == null:
		board_view.show_clusters([] as Array)
		return
	board_view.show_clusters(controller.current_edge_clusters())


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
	_set_status("Drag a tile from your hand to the board, or Swap")


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
