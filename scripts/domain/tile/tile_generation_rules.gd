class_name TileGenerationRules
extends Resource

## Versioned tile generation configuration (ADR-004 sections 2, 3, and 8).
##
## Weights are data rather than control flow. Defaults are uniform for all five
## ranks, both ordinary face colours, four suits, and four edge colours.
##
## The bag is the shared supply one match draws from, and `bag_size` is how many
## tiles it holds (ADR-004 sections 1 and 2).
##
## The Figure Actually In Force: `bag_size` is an exported value, so the number a
## real match uses is the one stored in
## `res://resources/rules/tile_generation_rules.tres`, NOT the constant below.
## A stored value always wins over a script default, so the `@export` line is the
## authority in play and this constant is only the fallback for a rules instance
## built in code. Changing one without the other silently does nothing, which is
## the single easiest way to misconfigure supply here.
##
## `max_jokers` is the most Joker-ranked tiles the pot may hold, whatever the bag
## size (ADR-014). It is a figure of the whole bag, not of one player's deck: the
## generator treats the Joker rank weight as zero once that allowance is spent, so
## the rest of the bag draws the ordinary ranks in proportion to `rank_weights`.
##
## ADR-004 section 8 requires the resource to validate that every category has
## at least one positive weight.

## Generator and schema version, persisted with saves so a future generator
## change can be detected (ADR-004 section 3). Version 4 removes Golden from the
## edge-color vocabulary; old bags and tile records must not be replayed under
## the four-color rules.
const SCHEMA_VERSION: int = 4

## Fallback bag size, used only when a rules instance is built in code. Keep it in
## step with the value stored in `res://resources/rules/tile_generation_rules.tres`,
## which is what a real match loads.
const DEFAULT_BAG_SIZE: int = 52

## Fallback Joker allowance, used only when a rules instance is built in code.
## Keep it in step with the value stored in
## `res://resources/rules/tile_generation_rules.tres`, which is what a real match
## loads.
const DEFAULT_MAX_JOKERS: int = 4

## Generator/schema version recorded alongside saved matches.
@export var schema_version: int = SCHEMA_VERSION

## Number of tiles generated during MATCH_SETUP.
@export var bag_size: int = DEFAULT_BAG_SIZE

## Most Joker-ranked tiles the generated pot may contain (ADR-014).
##
## A cap at or above `bag_size` never binds, because the bag cannot hold more
## tiles than that in total. Zero removes Jokers from the pot entirely. This is the
## single source of truth for the allowance; generator code must not carry its own
## copy of the number.
@export var max_jokers: int = DEFAULT_MAX_JOKERS

## Relative weights, indexed by `TileEnums.TileRank`.
@export var rank_weights: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0]

## Relative weights, indexed by `TileEnums.FaceColor`.
@export var face_color_weights: Array[float] = [1.0, 1.0]

@export var suit_weights: Array[float] = [1.0, 1.0, 1.0, 1.0]

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
	if max_jokers < 0:
		problems.append("max_jokers must not be negative, got %d" % max_jokers)
	_collect_weight_problems(problems, "rank_weights", rank_weights, TileEnums.TileRank.size())
	_collect_weight_problems(
		problems, "face_color_weights", face_color_weights, TileEnums.FaceColor.size() - 1
	)
	_collect_weight_problems(problems, "suit_weights", suit_weights, TileEnums.Suit.size() - 1)
	if suit_weights.size() == TileEnums.Suit.size() - 1:
		if suit_weights[0] + suit_weights[1] <= 0.0:
			problems.append("red suits must have positive total weight")
		if suit_weights[2] + suit_weights[3] <= 0.0:
			problems.append("black suits must have positive total weight")
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
