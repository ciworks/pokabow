class_name TileGenerationRules
extends Resource

## Versioned tile generation configuration (ADR-004 sections 2, 3, and 8).
##
## Weights are data rather than control flow, so rebalancing never requires
## changes to the generator. Phase 1 defaults are uniform: every rank, face
## colour, and edge colour has weight 1.0 (ADR-004 section 8).
##
## The bag holds one tile per board cell (ADR-004 section 1). `bag_size` is
## configurable so a future mode could change supply without touching code.
##
## ADR-004 section 8 requires the resource to validate that every category has
## at least one positive weight.

## Generator and schema version, persisted with saves so a future generator
## change can be detected (ADR-004 section 3).
const SCHEMA_VERSION: int = 1

## Default bag size: one tile for every 12 x 12 board cell.
const DEFAULT_BAG_SIZE: int = 144

## Generator/schema version recorded alongside saved matches.
@export var schema_version: int = SCHEMA_VERSION

## Number of tiles generated during MATCH_SETUP.
@export var bag_size: int = DEFAULT_BAG_SIZE

## Relative weights, indexed by `TileEnums.TileRank`.
@export var rank_weights: Array[float] = [1.0, 1.0, 1.0, 1.0]

## Relative weights, indexed by `TileEnums.FaceColor`.
@export var face_color_weights: Array[float] = [1.0, 1.0]

## Relative weights, indexed by `TileEnums.EdgeColor`.
@export var edge_color_weights: Array[float] = [1.0, 1.0, 1.0, 1.0]


## Returns a stable identifier for this rules version, persisted with saves.
func version_key() -> String:
	return "tile-generation:%d" % schema_version


## Returns every validation problem found, so callers can report all of them.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if schema_version != SCHEMA_VERSION:
		problems.append(
			"unsupported schema_version %d (expected %d)" % [schema_version, SCHEMA_VERSION]
		)
	if bag_size <= 0:
		problems.append("bag_size must be positive, got %d" % bag_size)
	_collect_weight_problems(problems, "rank_weights", rank_weights, TileEnums.TileRank.size())
	_collect_weight_problems(
		problems, "face_color_weights", face_color_weights, TileEnums.FaceColor.size()
	)
	_collect_weight_problems(
		problems, "edge_color_weights", edge_color_weights, TileEnums.EdgeColor.size()
	)
	return problems


## Returns true when no validation problem was found.
func is_valid() -> bool:
	return validate().is_empty()


## Returns a rules instance carrying the Phase 1 uniform default weights.
static func create_default() -> TileGenerationRules:
	return TileGenerationRules.new()


## Appends at most one message per problem class for a single weight category.
func _collect_weight_problems(
	problems: PackedStringArray,
	label: String,
	weights: Array[float],
	expected_size: int
) -> void:
	if weights.size() != expected_size:
		problems.append(
			"%s must hold one weight per value (%d), got %d"
			% [label, expected_size, weights.size()]
		)
		return
	var positive_count: int = 0
	var negative_count: int = 0
	for weight in weights:
		if weight < 0.0:
			negative_count += 1
		elif weight > 0.0:
			positive_count += 1
	if negative_count > 0:
		problems.append("%s must not contain negative weights (found %d)" % [label, negative_count])
	if positive_count == 0:
		problems.append("%s must contain at least one positive weight" % label)
