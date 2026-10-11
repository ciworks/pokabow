extends TestCase


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


func test_outside_empty_and_zero_size_rows_cannot_select_tiles() -> void:
	var available := Vector2(480, 96)
	for point: Vector2 in [Vector2(-1, 48), Vector2(480, 48), Vector2(240, -1), Vector2(240, 96)]:
		check_eq(DeckView._index_at(point, 6, available), -1, "targets do not extend outside the deck")
	check_eq(DeckView._index_at(Vector2(240, 48), 0, available), -1, "empty deck cannot select a tile")
	check_eq(DeckView._index_at(Vector2.ZERO, 6, Vector2.ZERO), -1, "zero size deck cannot select a tile")
	check_eq(DeckView._index_at(Vector2(10, 1), 6, Vector2(480, 8)), -1, "undrawable tiles cannot be selected")
