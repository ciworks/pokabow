extends TestCase

## Milestone 1 tile source tests (docs/PHASE-1-IMPLEMENTATION-PLAN.md).
##
## Covers draw order, remaining count, exhaustion, and the guarantee that a draw
## never consumes randomness, regenerates, or reorders the bag (ADR-004
## sections 3 and 6, plus the tile-source interface note).

const MATCH_ID: StringName = &"match-source"
const SEED: int = 8675309

func test_returned_tiles_preserve_unique_save_and_draw_order() -> void:
	var source: TileSource = _source()
	var first: TileDefinition = source.draw()
	var second: TileDefinition = source.draw()
	var next_id: StringName = source.debug_bag_snapshot()[2].tile_id
	check(source.return_to_pot(first), "drawn tile can return to the pot")
	check(not source.return_to_pot(first), "same tile cannot be returned twice")
	check_eq(source.get_bag_size(), 52, "return moves identity rather than duplicating it")
	check_eq(source.remaining_count(), 51, "return restores exactly one available tile")
	check(source.to_dto().is_valid(), "swapped bag can be serialized")
	var restored: TileSource = TileSource.from_dto(source.to_dto())
	check_not_null(restored, "swapped bag can be restored")
	check_eq(restored.draw().tile_id, next_id, "return preserves upcoming draw order")
	while restored.remaining_count() > 1:
		restored.draw()
	check_eq(restored.draw().tile_id, first.tile_id, "returned tile is drawn last")
	check(source.return_to_pot(second), "another drawn tile can also return")


func test_source_is_uninitialized_until_initialize_succeeds() -> void:
	var source: TileSource = TileSource.new()

	check(not source.is_initialized(), "a fresh source must not report itself initialized")
	check_eq(source.remaining_count(), 0, "an uninitialized source must offer no tiles")
	check(source.is_exhausted(), "an uninitialized source must report exhaustion")
	check(source.draw() == null, "drawing before initialize must return null, not a tile")
	check_eq(source.get_bag_size(), 0, "an uninitialized source must report no bag")
	check(source.get_rules_version().is_empty(), "an uninitialized source must report no rules version")


func test_initialize_rejects_unusable_inputs() -> void:
	var source: TileSource = TileSource.new()

	check(not source.initialize(MATCH_ID, SEED, null), "a null rules resource must be rejected")
	check(not source.is_initialized(), "a rejected initialize must leave the source uninitialized")

	var invalid_rules: TileGenerationRules = TileGenerationRules.create_default()
	invalid_rules.bag_size = 0
	check(
		not source.initialize(MATCH_ID, SEED, invalid_rules),
		"an invalid rules resource must be rejected"
	)
	check(not source.is_initialized(), "a rejected initialize must leave the source uninitialized")

	check(
		not source.initialize(&"", SEED, TileGenerationRules.create_default()),
		"an empty match ID must be rejected"
	)
	check_eq(source.get_bag_size(), 0, "a rejected initialize must not generate a bag")


func test_initialize_records_its_generation_identity() -> void:
	var source: TileSource = _source()

	check(source.is_initialized(), "a source with valid inputs must initialize")
	check_eq(source.get_match_id(), MATCH_ID, "the source must report its match ID")
	check_eq(source.get_seed(), SEED, "the source must report its seed for replay")
	check_eq(
		source.get_rules_version(),
		TileGenerationRules.create_default().version_key(),
		"the source must record the rules version that produced the bag"
	)


func test_draw_returns_tiles_in_generated_bag_order() -> void:
	var source: TileSource = _source()
	var bag: Array[TileDefinition] = source.debug_bag_snapshot()

	for index: int in range(20):
		var drawn: TileDefinition = source.draw()
		if not check_not_null(drawn, "draw %d must return a tile" % index):
			return
		check_eq(drawn.tile_id, bag[index].tile_id, "draw %d must follow generated bag order" % index)


func test_remaining_count_tracks_each_draw() -> void:
	var source: TileSource = _source()

	check_eq(source.remaining_count(), 52, "a fresh bag must offer 52 tiles")

	for expected_remaining: int in range(51, 47, -1):
		source.draw()
		check_eq(
			source.remaining_count(),
			expected_remaining,
			"each draw must remove exactly one tile"
		)

	check_eq(source.get_draw_index(), 4, "the draw index must count every draw")


func test_public_remaining_faces_track_draws_without_exposing_order() -> void:
	var source: TileSource = _source()
	var first: Array[Dictionary] = source.remaining_tile_faces()
	check_eq(first.size(), source.remaining_count(), "every undrawn tile has one public face")
	for face: Dictionary in first:
		check(not face.has("tile_id"), "public faces omit generated tile IDs")
		check_eq(face["edges"].size(), TileEnums.EDGE_COUNT, "public faces include all four edges")
	for index: int in range(1, first.size()):
		check(TileSource._face_key(first[index - 1]) <= TileSource._face_key(first[index]), "public inventory is sorted by appearance")
	var before: String = JSON.stringify(first)
	check_eq(before, JSON.stringify(source.remaining_tile_faces()), "inventory ordering is stable")
	var drawn: TileDefinition = source.draw()
	check_eq(source.remaining_tile_faces().size(), first.size() - 1, "a draw removes one visible face")
	check(source.return_to_pot(drawn), "a swapped tile can return to the pot")
	check_eq(JSON.stringify(source.remaining_tile_faces()), before, "return restores the same unordered inventory")


func test_bag_exhausts_after_exactly_52_draws() -> void:
	var source: TileSource = _source()
	var drawn_ids: Dictionary = {}

	for index: int in range(52):
		var tile: TileDefinition = source.draw()
		if not check_not_null(tile, "draw %d of a full bag must return a tile" % index):
			return
		drawn_ids[tile.tile_id] = true

	check_eq(drawn_ids.size(), 52, "the full bag must yield 52 distinct tiles")
	check_eq(source.remaining_count(), 0, "the bag must be empty after 52 draws")
	check(source.is_exhausted(), "the source must report exhaustion once the bag is empty")


func test_exhausted_source_never_generates_an_extra_tile() -> void:
	var source: TileSource = _source()
	for _index: int in range(52):
		source.draw()

	check(source.draw() == null, "an exhausted source must return null")
	check(source.draw() == null, "repeated draws must stay null")
	check_eq(source.remaining_count(), 0, "an exhausted source must stay empty")
	check_eq(source.get_draw_index(), 52, "an exhausted source must not advance past the bag")
	check_eq(source.get_bag_size(), 52, "exhaustion must not change the configured bag size")


func test_drawing_never_mutates_or_reorders_the_bag() -> void:
	var source: TileSource = _source()
	var before: String = _bag_signature(source.debug_bag_snapshot())

	for _index: int in range(52):
		source.draw()

	check_eq(
		_bag_signature(source.debug_bag_snapshot()),
		before,
		"drawing must not regenerate, reorder, or mutate bag contents (ADR-004 section 3)"
	)


func test_two_sources_draw_the_same_sequence_independently() -> void:
	var first: TileSource = _source()
	var second: TileSource = _source()
	var mismatches: int = 0

	for _index: int in range(52):
		var first_tile: TileDefinition = first.draw()
		var second_tile: TileDefinition = second.draw()
		if first_tile.tile_id != second_tile.tile_id:
			mismatches += 1

	check_eq(mismatches, 0, "two sources with the same seed must draw an identical sequence")


# --- Helpers ---


func _source() -> TileSource:
	var source: TileSource = TileSource.new()
	source.initialize(MATCH_ID, SEED, TileGenerationRules.create_default())
	return source


func _bag_signature(tiles: Array[TileDefinition]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for tile in tiles:
		var edges: PackedStringArray = PackedStringArray()
		for edge in tile.get_base_edges():
			edges.append(str(int(edge)))
		parts.append("%s|%d|%d|%s" % [tile.tile_id, tile.rank, tile.face_color, ",".join(edges)])
	return "~".join(parts)
