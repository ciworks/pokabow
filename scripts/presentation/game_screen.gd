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
@onready var end_turn_button: Button = %EndTurnButton
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


func _ready() -> void:
	_bind_nodes()
	_setup_input()
	_setup_buttons()
	if summary_overlay != null:
		summary_overlay.visible = false
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
	end_turn_button = get_node_or_null("%EndTurnButton") as Button
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
	if not controller.session_started.is_connected(_on_session_started):
		controller.session_started.connect(_on_session_started)
		controller.state_changed.connect(_refresh_all)
		controller.preview_changed.connect(_refresh_preview)
		controller.move_committed.connect(_on_move_committed)
		controller.score_awarded.connect(_on_score_awarded)
		controller.match_ended.connect(_on_match_ended)
		controller.notice.connect(_on_notice)
		controller.ai_thinking_changed.connect(_on_ai_thinking_changed)
	_refresh_all()


## Connects the board's gesture signals. Gestures only ever produce a placement
## intent; committing stays an explicit button press (ADR-008 section 8).
func _setup_input() -> void:
	board_input.board_view = board_view
	board_input.enabled = false
	board_input.cell_tapped.connect(_on_cell_tapped)
	board_input.cell_dragged.connect(_on_cell_dragged)


func _setup_buttons() -> void:
	rotate_button.pressed.connect(_on_rotate_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	deck_view.tile_selected.connect(_on_deck_tile_selected)


func _on_cell_tapped(cell: Vector2i) -> void:
	if controller == null:
		return
	controller.preview_placement(cell)


func _on_cell_dragged(cell: Vector2i) -> void:
	if controller == null:
		return
	controller.preview_placement(cell)


func _on_rotate_pressed() -> void:
	if controller == null:
		return
	controller.rotate_pending()


func _on_confirm_pressed() -> void:
	if controller == null:
		return
	controller.confirm_pending()


func _on_cancel_pressed() -> void:
	if controller == null:
		return
	controller.cancel_pending()


## Ends the human's turn, keeping any unplaced tiles (ADR-010 section 4).
##
## ADR-010 section 4 makes ending a turn an explicit action available throughout
## the action phase, so this is what closes a multi-placement turn; a placement
## never closes it.
func _on_end_turn_pressed() -> void:
	if controller == null:
		return
	controller.end_human_turn()


## Arms one of the human's deck tiles (ADR-010 section 12).
##
## Selecting a deck tile is what a placement is armed with (ADR-010 section 4),
## so this is the only way the player chooses which of their tiles to commit. The
## selection is forwarded to the controller, which is where a tile is armed; the
## screen only reports the player's choice.
func _on_deck_tile_selected(tile_id: StringName) -> void:
	if controller == null:
		return
	controller.select_deck_tile(tile_id)
	# The row is re-rendered from the controller either way, so a refused
	# selection cannot leave it showing a tile the application layer has not
	# armed.
	_refresh_deck()


func _on_restart_pressed() -> void:
	if controller == null:
		return
	controller.start_new_match()


func _on_session_started() -> void:
	if summary_overlay != null:
		summary_overlay.visible = false
	if floating_scores != null:
		floating_scores.clear_all()
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


## Redraws the board at the cell the move just committed.
func _on_move_committed(result: PlacementResult, _turn_phase: int) -> void:
	if result == null:
		return
	board_view.mark_committed(result.cell)


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
func _refresh_all() -> void:
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


## Redraws the human's deck row and its selection (ADR-010 section 12).
##
## Both values come from the controller, so the row can never disagree with the
## tile the next placement would commit: the deck is what the human holds and the
## selection is what the application layer has armed (ADR-010 sections 4 and 10).
func _refresh_deck() -> void:
	if controller == null:
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


## Shows board-level preview state, or clears it.
func _refresh_preview() -> void:
	if controller == null or not controller.has_pending():
		board_view.clear_preview()
		_refresh_status()
		return
	board_view.show_preview(
		controller.pending_snapshot(),
		controller.is_pending_valid(),
		controller.pending_reason()
	)
	_refresh_status()


## Chooses the one-line instruction or refusal shown under the tile.
func _refresh_status() -> void:
	if controller == null:
		status_label.text = ""
		return
	if controller.is_over():
		status_label.text = ""
		return
	if not controller.is_human_turn():
		status_label.text = (
			RIVAL_THINKING_TEXT if controller.is_ai_thinking() else RIVAL_WAITING_TEXT
		)
		return
	if controller.has_pending():
		if controller.is_pending_valid():
			status_label.text = "Tap Confirm to place"
		else:
			status_label.text = controller.pending_reason()
		return
	# ADR-010 sections 3 and 4: a placement no longer ends the turn, so the
	# screen states how the turn finishes rather than leaving the player waiting
	# for a hand-over that only the end-turn action causes.
	status_label.text = "Tap a highlighted cell, or End Turn"


## Enables the tile controls only when the human may act.
##
## ADR-010 section 4 keeps end-turn available throughout the action phase,
## including before any tile has been placed, so it is gated by the same
## condition as the placement controls rather than by whether a placement has
## happened.
func _set_interactive(enabled: bool) -> void:
	rotate_button.disabled = not enabled
	confirm_button.disabled = not enabled
	cancel_button.disabled = not enabled
	end_turn_button.disabled = not enabled


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
