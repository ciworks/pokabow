extends TestCase

## Milestone 1 tile generation tests (docs/PHASE-1-IMPLEMENTATION-PLAN.md).
##
## Covers the versioned rules resource, the accepted 144-tile bag, deterministic
## identity, permitted duplicate configurations, zero initial rotation, and the
## large-sample distribution sanity check required by ADR-004 section 9.
##
## Randomness tests never assert exact frequencies for a single bag. Fixed-seed
## tests assert exact deterministic output; the distribution check only detects
## gross weighting errors (ADR-004 section 9).

const RULES_RESOURCE_PATH: String = "res://resources/rules/tile_generation_rules.tres"
const SAMPLE_MATCH_ID: StringName = &"match-generation"
const DISTRIBUTION_SAMPLE_SEEDS: int = 10


func test_default_rules_are_valid() -> void:
	var rules: TileGenerationRules = TileGenerationRules.create_default()

	check(rules.is_valid(), "the Phase 1 defaults must validate: %s" % [rules.validate()])
	check_eq(rules.bag_size, 144, "the bag must hold one tile per board cell")
	check_eq(
		rules.rank_weights.size(),
		TileEnums.TileRank.size(),
		"there must be one rank weight per face rank"
	)
	check_eq(
		rules.face_color_weights.size(),
		TileEnums.FaceColor.size(),
		"there must be one face-colour weight per face colour"
	)
	check_eq(
		rules.edge_color_weights.size(),
		TileEnums.EdgeColor.size(),
		"there must be one edge-colour weight per edge colour"
	)


func test_rules_resource_on_disk_matches_the_approved_defaults() -> void:
	var loaded: Resource = load(RULES_RESOURCE_PATH)
	if not check_not_null(loaded, "the versioned rules resource must load"):
		return
	if not check(loaded is TileGenerationRules, "the resource must be a TileGenerationRules"):
		return

	var rules: TileGenerationRules = loaded as TileGenerationRules
	check(rules.is_valid(), "the on-disk rules must validate: %s" % [rules.validate()])
	check_eq(rules.schema_version, TileGenerationRules.SCHEMA_VERSION, "schema version must match")
	check_eq(rules.bag_size, TileGenerationRules.DEFAULT_BAG_SIZE, "bag size must be the default")
	check_eq(rules.version_key(), "tile-generation:1", "the version key must be stable and versioned")
	check_eq(rules.rank_weights, _uniform(TileEnums.TileRank.size()), "ranks must be uniformly weighted")
	check_eq(
		rules.face_color_weights, _uniform(TileEnums.FaceColor.size()), "face colours must be uniform"
	)
	check_eq(
		rules.edge_color_weights, _uniform(TileEnums.EdgeColor.size()), "edge colours must be uniform"
	)


func test_rules_validation_rejects_unusable_configurations() -> void:
	var zero_ranks: TileGenerationRules = _rules_with_weights(_uniform_zeros(4), _uniform(2), _uniform(4))
	check(not zero_ranks.is_valid(), "a category with no positive weight must be rejected")

	var short_ranks: TileGenerationRules = _rules_with_weights(_uniform(3), _uniform(2), _uniform(4))
	check(not short_ranks.is_valid(), "a weight list of the wrong length must be rejected")

	var negative_ranks: TileGenerationRules = _rules_with_weights(
		_negative_first(4), _uniform(2), _uniform(4)
	)
	check(not negative_ranks.is_valid(), "a negative weight must be rejected")

	var empty_bag: TileGenerationRules = TileGenerationRules.create_default()
	empty_bag.bag_size = 0
	check(not empty_bag.is_valid(), "a non-positive bag size must be rejected")

	var future_schema: TileGenerationRules = TileGenerationRules.create_default()
	future_schema.schema_version = TileGenerationRules.SCHEMA_VERSION + 1
	check(not future_schema.is_valid(), "an unsupported schema version must be rejected")


func test_bag_contains_exactly_144_tiles() -> void:
	var source: TileSource = _generated_source(SAMPLE_MATCH_ID, 20260921)

	check(source.is_initialized(), "a source with valid inputs must initialize")
	check_eq(source.get_bag_size(), 144, "ADR-004 section 1 requires a 144-tile bag")
	check_eq(source.remaining_count(), 144, "an untouched bag must offer all 144 tiles")
	check(not source.is_exhausted(), "a full bag must not report exhaustion")


func test_same_seed_and_match_id_produce_an_identical_bag() -> void:
	var first: TileSource = _generated_source(SAMPLE_MATCH_ID, 4242)
	var second: TileSource = _generated_source(SAMPLE_MATCH_ID, 4242)

	check_eq(
		_bag_signature(first.debug_bag_snapshot()),
		_bag_signature(second.debug_bag_snapshot()),
		"ADR-004 section 3 requires the same seed to reproduce the same bag exactly"
	)


func test_different_seeds_produce_a_different_bag() -> void:
	var first: TileSource = _generated_source(SAMPLE_MATCH_ID, 1)
	var second: TileSource = _generated_source(SAMPLE_MATCH_ID, 2)

	check(
		_bag_signature(first.debug_bag_snapshot())
		!= _bag_signature(second.debug_bag_snapshot()),
		"two different seeds must not produce the same 144-tile bag"
	)


func test_match_id_participates_in_tile_identity() -> void:
	var first: TileSource = _generated_source(&"match-a", 7)
	var second: TileSource = _generated_source(&"match-b", 7)

	check_eq(
		_values_signature(first.debug_bag_snapshot()),
		_values_signature(second.debug_bag_snapshot()),
		"the same seed must produce the same tile values regardless of match ID"
	)
	check_eq(
		first.debug_bag_snapshot()[0].tile_id,
		&"match-a:tile:000",
		"tile identity must derive from the match ID and bag index"
	)
	check_eq(
		second.debug_bag_snapshot()[0].tile_id,
		&"match-b:tile:000",
		"a different match must produce different tile IDs for the same position"
	)


func test_tile_ids_are_unique_and_follow_the_documented_format() -> void:
	var tiles: Array[TileDefinition] = _generated_source(SAMPLE_MATCH_ID, 99).debug_bag_snapshot()
	var seen_ids: Dictionary = {}

	for index: int in range(tiles.size()):
		var expected_id: StringName = StringName("%s:tile:%03d" % [SAMPLE_MATCH_ID, index])
		check_eq(tiles[index].tile_id, expected_id, "bag position %d must use its deterministic ID" % index)
		check(not seen_ids.has(tiles[index].tile_id), "every tile ID must be unique")
		seen_ids[tiles[index].tile_id] = true

	check_eq(seen_ids.size(), 144, "all 144 tile IDs must be distinct")


func test_every_generated_tile_has_valid_domain_values() -> void:
	var tiles: Array[TileDefinition] = _generated_source(SAMPLE_MATCH_ID, 1234).debug_bag_snapshot()
	var invalid_count: int = 0

	for tile in tiles:
		if not tile.is_valid():
			invalid_count += 1

	check_eq(invalid_count, 0, "every generated tile must carry valid ranks, colours, and four edges")


func test_generated_tiles_start_at_zero_rotation() -> void:
	var tiles: Array[TileDefinition] = _generated_source(SAMPLE_MATCH_ID, 55).debug_bag_snapshot()
	var snapshot: TileSnapshot = TileSnapshot.create(tiles[0], Vector2i(5, 5))

	check_eq(snapshot.get_rotation(), 0, "ADR-004 section 2 requires a zero initial rotation")
	check_eq(
		snapshot.get_rotated_edges(),
		tiles[0].get_base_edges(),
		"an undrawn tile must present its canonical edges"
	)


func test_duplicate_configurations_are_permitted_but_ids_stay_unique() -> void:
	var edges: Array[TileEnums.EdgeColor] = [
		TileEnums.EdgeColor.BLUE,
		TileEnums.EdgeColor.BLUE,
		TileEnums.EdgeColor.RED,
		TileEnums.EdgeColor.RED,
	]
	var first: TileDefinition = TileDefinition.create(&"a:tile:000", TileEnums.TileRank.KING, TileEnums.FaceColor.RED, edges)
	var second: TileDefinition = TileDefinition.create(&"a:tile:001", TileEnums.TileRank.KING, TileEnums.FaceColor.RED, edges)

	check_eq(first.rank, second.rank, "two tiles may share a face rank")
	check_eq(first.face_color, second.face_color, "two tiles may share a face colour")
	check_eq(first.get_base_edges(), second.get_base_edges(), "two tiles may share all four edge colours")
	check(first.tile_id != second.tile_id, "ADR-004 section 5 requires identity by ID, not by values")


func test_large_sample_covers_every_rank_and_edge_colour() -> void:
	var seen_ranks: Dictionary = {}
	var seen_edge_colours: Dictionary = {}

	for offset: int in range(DISTRIBUTION_SAMPLE_SEEDS):
		var tiles: Array[TileDefinition] = _generated_source(SAMPLE_MATCH_ID, 1000 + offset).debug_bag_snapshot()
		for tile in tiles:
			seen_ranks[tile.rank] = true
			for edge in tile.get_base_edges():
				seen_edge_colours[int(edge)] = true

	check_eq(
		seen_ranks.size(),
		TileEnums.TileRank.size(),
		"all four face ranks must appear across a large sample (ADR-004 section 9)"
	)
	check_eq(
		seen_edge_colours.size(),
		TileEnums.EdgeColor.size(),
		"all four edge colours must appear across a large sample (ADR-004 section 9)"
	)


# --- Helpers ---


func _generated_source(match_id: StringName, seed: int) -> TileSource:
	var source: TileSource = TileSource.new()
	source.initialize(match_id, seed, TileGenerationRules.create_default())
	return source


func _rules_with_weights(
	rank_weights: Array[float], face_color_weights: Array[float], edge_color_weights: Array[float]
) -> TileGenerationRules:
	var rules: TileGenerationRules = TileGenerationRules.create_default()
	rules.rank_weights = rank_weights
	rules.face_color_weights = face_color_weights
	rules.edge_color_weights = edge_color_weights
	return rules


func _uniform(size: int) -> Array[float]:
	var weights: Array[float] = []
	for _index: int in range(size):
		weights.append(1.0)
	return weights


func _uniform_zeros(size: int) -> Array[float]:
	var weights: Array[float] = []
	for _index: int in range(size):
		weights.append(0.0)
	return weights


func _negative_first(size: int) -> Array[float]:
	var weights: Array[float] = _uniform(size)
	weights[0] = -1.0
	return weights


## Returns a comparable signature of a bag: identity plus visible values, in order.
func _bag_signature(tiles: Array[TileDefinition]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for tile in tiles:
		parts.append(
			"%s|%d|%d|%s"
			% [
				tile.tile_id,
				tile.rank,
				tile.face_color,
				",".join(_edge_strings(tile.get_base_edges())),
			]
		)
	return "~".join(parts)


## Returns a comparable signature of a bag's visible values, ignoring tile identity.
## ADR-004 section 5 derives identity from the match ID, so identity must be left
## out when comparing the values produced by two different matches.
func _values_signature(tiles: Array[TileDefinition]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for tile in tiles:
		parts.append(
			"%d|%d|%s"
			% [
				tile.rank,
				tile.face_color,
				",".join(_edge_strings(tile.get_base_edges())),
			]
		)
	return "~".join(parts)


func _edge_strings(edges: Array[TileEnums.EdgeColor]) -> PackedStringArray:
	var parts: PackedStringArray = PackedStringArray()
	for edge in edges:
		parts.append(str(int(edge)))
	return parts
