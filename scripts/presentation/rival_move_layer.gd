class_name RivalMoveLayer
extends Control
## Animates only public committed tiles. Replacement tiles never expose faces.
## The board and hand have already changed; this layer delays their drawing only.

signal placements_finished
signal finished
signal refill_flight_started

const STAGGER: float = 0.12
const FLIGHT: float = 0.42
const REFILL_PAUSE: float = 0.08
const REFILL_FLIGHT: float = 0.35
const ARC_LIFT: float = 28.0

var board: BoardView
var rack: OpponentRackView
var pile: TilePileView
var _snapshots: Array[TileSnapshot] = []
var _before: int = 0
var _after: int = 0
var _remaining: int = 0
var _refill_count: int = 0
var _refill_started_count: int = 0
var _elapsed: float = 0.0
var _playing: bool = false
var _placements_done: bool = false
var _camera_focused: bool = false
var _focus_camera: bool = true


func _ready() -> void:
	# The pot has raised artwork; flights must remain visible as they leave its mouth.
	z_index = 2
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(_playing)


func is_playing() -> bool:
	return _playing


func play(tiles: Array[TileSnapshot], hand_before: int, hand_after: int, focus_camera: bool = true) -> bool:
	cancel()
	if board == null or rack == null or pile == null or tiles.is_empty():
		return false
	if hand_before < tiles.size() or hand_after < hand_before - tiles.size():
		return false
	if AccessibilitySettings.reduced_motion():
		rack.set_tile_count(hand_after)
		return false
	_snapshots = tiles.duplicate()
	_before = hand_before
	_after = hand_after
	_remaining = _before - _snapshots.size()
	_refill_count = _after - _remaining
	_refill_started_count = 0
	_elapsed = 0.0
	_placements_done = false
	_focus_camera = focus_camera
	_playing = true
	var cells: Array[Vector2i] = []
	for snapshot: TileSnapshot in _snapshots:
		cells.append(snapshot.get_cell())
	if _focus_camera:
		board.reveal_cells(cells)
		_camera_focused = board.tile_global_rect(cells[0]).has_area()
	else:
		_camera_focused = true
	_sync_visuals()
	set_process(true)
	queue_redraw()
	return true


## Interruption reveals the already-authoritative state, never leaves hidden tiles.
func cancel() -> void:
	if _playing:
		board.set_concealed_cells([] as Array[Vector2i])
		rack.set_tile_count(_after)
		rack.set_concealed([] as Array[int])
	_playing = false
	_snapshots.clear()
	set_process(false)
	queue_redraw()


func placement_duration() -> float:
	return float(maxi(0, _snapshots.size() - 1)) * STAGGER + FLIGHT


func total_duration() -> float:
	if _refill_count == 0:
		return placement_duration()
	return placement_duration() + REFILL_PAUSE + float(_refill_count - 1) * STAGGER + REFILL_FLIGHT


func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	if AccessibilitySettings.reduced_motion():
		_elapsed = total_duration()
		_sync_visuals()
		if not _placements_done:
			_placements_done = true
			placements_finished.emit()
		cancel()
		finished.emit()
		return
	while _refill_started_count < _refill_count:
		var start: float = placement_duration() + REFILL_PAUSE + float(_refill_started_count) * STAGGER
		if _elapsed < start:
			break
		_refill_started_count += 1
		refill_flight_started.emit()
	_sync_visuals()
	if not _placements_done and _elapsed >= placement_duration():
		_placements_done = true
		placements_finished.emit()
	if _elapsed >= total_duration():
		cancel()
		finished.emit()
	queue_redraw()


func _sync_visuals() -> void:
	var hidden_cells: Array[Vector2i] = []
	var hidden_slots: Array[int] = []
	for index: int in range(_snapshots.size()):
		if _elapsed < float(index) * STAGGER + FLIGHT:
			hidden_cells.append(_snapshots[index].get_cell())
		if _elapsed >= float(index) * STAGGER:
			hidden_slots.append(index)
	board.set_concealed_cells(hidden_cells)
	if _elapsed < placement_duration():
		rack.set_tile_count(_before)
		rack.set_concealed(hidden_slots)
		return
	hidden_slots.clear()
	for index: int in range(_refill_count):
		if _elapsed < placement_duration() + REFILL_PAUSE + float(index) * STAGGER + REFILL_FLIGHT:
			hidden_slots.append(_remaining + index)
	rack.set_tile_count(_after)
	rack.set_concealed(hidden_slots)


func _draw() -> void:
	if not _playing:
		return
	if _focus_camera and not _camera_focused and board.tile_global_rect(_snapshots[0].get_cell()).has_area():
		var cells: Array[Vector2i] = []
		for snapshot: TileSnapshot in _snapshots:
			cells.append(snapshot.get_cell())
		board.reveal_cells(cells)
		_camera_focused = true
	var to_local: Transform2D = get_global_transform().affine_inverse()
	for index: int in range(_snapshots.size()):
		var progress: float = (_elapsed - float(index) * STAGGER) / FLIGHT
		if progress < 0.0 or progress >= 1.0:
			continue
		var source: Rect2 = to_local * rack.tile_global_rect(index, _before)
		var target: Rect2 = to_local * board.tile_global_rect(_snapshots[index].get_cell())
		if not source.has_area() or not target.has_area():
			continue
		var rect: Rect2 = _flight_rect(source, target, progress)
		var flip_bounds: Rect2 = rect
		# Turn over in flight; paint the committed rotation when the face appears.
		var flip: float = clampf((progress - 0.2) / 0.6, 0.0, 1.0)
		var width: float = maxf(0.02, absf(1.0 - 2.0 * flip))
		var flipped_size: Vector2 = Vector2(rect.size.x * width, rect.size.y)
		rect = Rect2(rect.get_center() - flipped_size * 0.5, flipped_size)
		if flip < 0.5:
			TilePainter.paint_tile_back(self, rect)
		else:
			TilePainter.paint_tile(self, rect, _snapshots[index])
		TilePainter.paint_flip_depth(self, flip_bounds, flip)
	for index: int in range(_refill_count):
		var start: float = placement_duration() + REFILL_PAUSE + float(index) * STAGGER
		var progress: float = (_elapsed - start) / REFILL_FLIGHT
		if progress < 0.0 or progress >= 1.0:
			continue
		var target: Rect2 = to_local * rack.tile_global_rect(_remaining + index, _after)
		var source_size: Vector2 = target.size * DealLayer.START_SCALE
		var origin: Vector2 = to_local * pile.stack_origin_global()
		var source := Rect2(origin - source_size * 0.5, source_size)
		TilePainter.paint_tile_back(self, _flight_rect(source, target, progress))


func _flight_rect(source: Rect2, target: Rect2, progress: float) -> Rect2:
	var eased: float = smoothstep(0.0, 1.0, progress)
	var center: Vector2 = source.get_center().lerp(target.get_center(), eased)
	center.y -= ARC_LIFT * sin(PI * progress)
	var tile_size: Vector2 = source.size.lerp(target.size, eased)
	return Rect2(center - tile_size * 0.5, tile_size)
