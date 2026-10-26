extends TestCase


func _rack_tiles() -> Array[TileDefinition]:
	var tiles: Array[TileDefinition] = []
	for index: int in range(6):
		tiles.append(TileDefinition.create(StringName("rack-%d" % index), TileEnums.TileRank.ACE,
			TileEnums.FaceColor.RED, [TileEnums.EdgeColor.BLUE, TileEnums.EdgeColor.RED,
			TileEnums.EdgeColor.GREEN, TileEnums.EdgeColor.YELLOW]))
	return tiles


func test_staged_slots_remain_vacant_and_cannot_select_neighbors() -> void:
	var row := DeckView.new()
	row.size = Vector2(480, 96)
	row.set_locked(false)
	var tiles: Array[TileDefinition] = _rack_tiles()
	row.set_deck(tiles)
	var rectangles: Array[Rect2] = []
	for index: int in range(6):
		rectangles.append(row.tile_rect_at(index))
	var visible: Array[TileDefinition] = [tiles[0], tiles[2], tiles[5]]
	row.set_deck(visible, &"", 0, tiles)
	for index: int in range(visible.size()):
		check_eq(row.tile_rect_at(index), rectangles[tiles.find(visible[index])], "staging several tiles keeps every survivor in place")
	var selected: Array[StringName] = []
	row.tile_selected.connect(func(id: StringName) -> void: selected.append(id))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = rectangles[1].get_center()
	row._gui_input(press)
	check(selected.is_empty(), "pressing a vacant slot does not select a neighbor")
	row.set_deck(tiles)
	for index: int in range(6):
		check_eq(row.tile_rect_at(index), rectangles[index], "cancel restores original slots")
	visible = [tiles[0], tiles[2], tiles[3], tiles[4], tiles[5]]
	row.set_deck(visible)
	check_eq(row.tile_rect_at(1), rectangles[2], "committed removal also leaves a gap")
	var replacement: TileDefinition = TileDefinition.create(&"replacement", tiles[1].rank, tiles[1].face_color, tiles[1].get_base_edges())
	visible.append(replacement)
	row.set_deck(visible)
	check_eq(row.tile_rect_at(5), rectangles[1], "refill takes vacant slot")
	row.free()


func test_every_rack_insertion_preserves_order_and_survives_refresh() -> void:
	var tiles: Array[TileDefinition] = _rack_tiles()
	for origin: int in range(6):
		for boundary: int in range(7):
			var row := DeckView.new()
			row.size = Vector2(480, 96)
			row.set_locked(false)
			row.set_deck(tiles)
			var x: float = 1.0
			if boundary == 6:
				x = row.size.x - 1.0
			elif boundary > 0:
				x = (row.tile_rect_at(boundary - 1).get_center().x + row.tile_rect_at(boundary).get_center().x) * 0.5
			check(row.insert_tile_at(tiles[origin].tile_id, Vector2(x, 48)), "every insertion boundary is accepted")
			row.set_deck(tiles, tiles[origin].tile_id, 2)
			for frame: int in range(60):
				row._process(1.0 / 60.0)
			var expected: Array[TileDefinition] = tiles.duplicate()
			expected.remove_at(origin)
			expected.insert(boundary - 1 if boundary > origin else boundary, tiles[origin])
			for index: int in range(6):
				var expected_rect: Rect2 = DeckView.tile_rect(index, 6, row.size)
				if expected[index].tile_id == tiles[origin].tile_id:
					expected_rect.position.y -= DeckView.SELECTED_LIFT
				check_eq(row.tile_rect_at(tiles.find(expected[index])), expected_rect, "refresh retains requested order and selected lift")
			check_eq(row.selected_tile_id(), tiles[origin].tile_id, "reordering keeps selection identity")
			check_eq(row.selected_rotation(), 2, "reordering keeps pending rotation")
			row.free()


func test_selected_tile_lifts_and_uses_an_outer_honey_frame() -> void:
	var row := DeckView.new()
	row.size = Vector2(480, 96)
	(Engine.get_main_loop() as SceneTree).root.add_child(row)
	var tiles: Array[TileDefinition] = _rack_tiles()
	row.set_deck(tiles)
	var resting: Rect2 = row.tile_rect_at(2)
	row.set_deck(tiles, tiles[2].tile_id)
	var selected: Rect2 = row.tile_rect_at(2)
	check_eq(selected.position, resting.position - Vector2(0, DeckView.SELECTED_LIFT),
		"selection lifts the tile without shifting its rack slot")
	check_eq(selected.size, resting.size, "selection preserves tile and edge-band dimensions")
	check_eq(row.tile_rect_at(1), DeckView.tile_rect(1, 6, row.size),
		"neighboring tiles remain in their slots")
	check_eq(row._selected_frame.border_color, Color("#F4C86A"), "outer frame uses the honey selection token")
	check_eq(row._selected_keyline.border_color, Color("#173D42"), "keyline separates honey from the ivory rack")
	check_eq(row._selected_frame.border_width_left, DeckView.SELECTED_FRAME_WIDTH,
		"selection frame keeps the specified two-pixel width")
	check(not row._selected_frame.draw_center, "selection frame leaves the face and edge bands clear")
	row.set_mark_mode(true)
	check_eq(row.tile_rect_at(2), resting, "swap mode removes the selection lift")
	row.set_marked(tiles[2].tile_id, true)
	check_eq(row.marked_count(), 1, "swap marking keeps an explicit tile set")
	check_eq(row._marked_frame.border_color, Color("#173D42"), "swap frame uses ink instead of honey")
	check(not row._marked_frame.draw_center, "swap frame leaves the tile face and edge bands clear")
	check_eq(row._marked_marker.bg_color, Color("#173D42"), "check marker matches the swap frame")
	row.set_marked(tiles[2].tile_id, false)
	check_eq(row.marked_count(), 0, "a second swap tap removes the mark")
	row.free()


func test_surrounding_space_selects_nearest_tile_for_every_hand_size() -> void:
	for available: Vector2 in [Vector2(280, 72), Vector2(480, 96), Vector2(720, 140)]:
		for count: int in range(1, 7):
			for index: int in range(count):
				var rect: Rect2 = DeckView.tile_rect(index, count, available)
				var left: float = 0.0
				var right: float = available.x
				if index > 0:
					left = (DeckView.tile_rect(index - 1, count, available).get_center().x + rect.get_center().x) * 0.5
				if index < count - 1:
					right = (rect.get_center().x + DeckView.tile_rect(index + 1, count, available).get_center().x) * 0.5
				for x: float in [left + 0.01, rect.get_center().x, right - 0.01]:
					for y: float in [0.01, available.y * 0.5, available.y - 0.01]:
						check_eq(DeckView._index_at(Vector2(x, y), count, available), index, "artwork and surrounding space select the same tile")
				if index < count - 1:
					var hit: int = DeckView._index_at(Vector2(right, 1), count, available)
					check(hit == index or hit == index + 1, "rounded midpoint selects an adjacent tile with no dead zone")


func test_drag_from_padding_reports_tile_and_respects_interaction_gates() -> void:
	var row := DeckView.new()
	row.size = Vector2(480, 96)
	var tile: TileDefinition = TileDefinition.create(&"touch-target", TileEnums.TileRank.ACE,
		TileEnums.FaceColor.RED, [TileEnums.EdgeColor.BLUE, TileEnums.EdgeColor.RED,
		TileEnums.EdgeColor.GREEN, TileEnums.EdgeColor.YELLOW])
	row.set_deck([tile])
	var started: Array[StringName] = []
	var dropped: Array[StringName] = []
	row.tile_drag_started.connect(func(id: StringName, _point: Vector2) -> void: started.append(id))
	row.tile_drop_requested.connect(func(id: StringName, _point: Vector2) -> void: dropped.append(id))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(1, 1)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = Vector2(1, -20)
	for gate: int in range(3):
		row.set_locked(gate == 0)
		row.set_mark_mode(gate == 1)
		row._gui_input(press)
		row._gui_input(motion)
		check_eq(row.is_dragging(), gate == 2, "padding respects locked and swap modes")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	row._gui_input(release)
	check_eq(started, [tile.tile_id], "padding starts exactly one drag for the nearest tile")
	check_eq(dropped, [tile.tile_id], "release reports the same tile")
	check(not row.is_dragging(), "release ends the gesture")
	row.free()


func test_same_hand_refresh_keeps_a_press_and_drag_until_release() -> void:
	var row := DeckView.new()
	row.size = Vector2(480, 96)
	row.set_locked(false)
	row.set_deck(_rack_tiles())
	var selected: Array[StringName] = []
	var dropped: Array[StringName] = []
	var cancelled: Array[StringName] = []
	row.tile_selected.connect(func(id: StringName) -> void: selected.append(id))
	row.tile_drop_requested.connect(func(id: StringName, _point: Vector2) -> void: dropped.append(id))
	row.tile_drag_cancelled.connect(func(id: StringName) -> void: cancelled.append(id))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = row.tile_rect_at(0).get_center()
	row._gui_input(press)
	row.set_deck(_rack_tiles(), &"rack-0")
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = press.position + Vector2(DeckView.DRAG_THRESHOLD + 4, 0)
	row._gui_input(motion)
	check(row.is_dragging(), "selection redraw preserves the held press")
	row.set_deck(_rack_tiles(), &"rack-0")
	check(row.is_dragging(), "same-hand polling redraw preserves the drag")
	check_eq(row.dragging_index(), 0, "polling keeps the dragged tile identity")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	row._gui_input(release)
	check_eq(selected, [&"rack-0"], "press selects exactly once")
	check_eq(dropped, [&"rack-0"], "release still reports a drop")
	check(cancelled.is_empty(), "unchanged redraw never cancels the drag")
	row.free()


func test_changed_hand_or_turn_cancels_a_held_drag() -> void:
	var row := DeckView.new()
	row.size = Vector2(480, 96)
	row.set_locked(false)
	var tiles: Array[TileDefinition] = _rack_tiles()
	row.set_deck(tiles)
	var cancelled: Array[StringName] = []
	row.tile_drag_cancelled.connect(func(id: StringName) -> void: cancelled.append(id))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = row.tile_rect_at(0).get_center()
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = press.position + Vector2(DeckView.DRAG_THRESHOLD + 4, 0)
	row._gui_input(press)
	row._gui_input(motion)
	row.set_deck([tiles[1], tiles[2], tiles[3], tiles[4], tiles[5]])
	check(not row.is_dragging(), "a changed hand cancels the drag")
	check_eq(cancelled, [&"rack-0"], "changed hand reports cancellation once")
	row.set_deck(tiles)
	row._gui_input(press)
	row._gui_input(motion)
	row.set_locked(true)
	check(not row.is_dragging(), "turn lock cancels the drag")
	check_eq(cancelled.size(), 2, "turn lock reports one additional cancellation")
	row.free()


func test_outside_empty_and_zero_size_rows_cannot_select_tiles() -> void:
	var available := Vector2(480, 96)
	for point: Vector2 in [Vector2(-1, 48), Vector2(480, 48), Vector2(240, -1), Vector2(240, 96)]:
		check_eq(DeckView._index_at(point, 6, available), -1, "targets do not extend outside the deck")
	check_eq(DeckView._index_at(Vector2(240, 48), 0, available), -1, "empty deck cannot select a tile")
	check_eq(DeckView._index_at(Vector2.ZERO, 6, Vector2.ZERO), -1, "zero size deck cannot select a tile")
	check_eq(DeckView._index_at(Vector2(10, 1), 6, Vector2(480, 8)), -1, "undrawable tiles cannot be selected")
