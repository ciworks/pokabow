class_name PokerScoreRules
extends Resource

## Versioned poker point values (ADR-001 sections 4 and 6).
##
## ADR-001 section 4 requires point values to be data rather than hard-coded
## control flow so balancing never changes the evaluator. ADR-008 section 3
## places versioned rule configuration in `Resource`, which is why this type
## extends `Resource` rather than `RefCounted`.
##
## Values are stored in one array indexed by `ScoringEnums.PokerHandCategory`
## instead of one field per category, so adding a category is a single-entry
## change and `points_for()` cannot drift out of step with the enum.
##
## Phase 1 defaults (ADR-012 section 4):
##
##     NONE              0
##     PAIR              2
##     TWO_PAIR          4
##     STRAIGHT_3        5
##     THREE_OF_A_KIND   6
##     STRAIGHT_4        9
##     FULL_HOUSE       10
##     FOUR_OF_A_KIND   12
##
## Five-of-a-Kind has no entry: ADR-012 section 1 removed it from the valid hand
## list, so five identical ranks are refused rather than scored.
##
## Phase 1 has no multipliers (ADR-007 section 11), so a category's value is the
## whole award for that category.

## Rules/schema version, persisted with saves so a rebalance can be detected
## (ADR-004 section 3 pattern, ADR-007 section 11).
##
## Version 2 records ADR-012 section 4: the point table lost Five-of-a-Kind and
## gained the two sequence hands, so a match saved under version 1 is refused
## rather than silently re-scored (ADR-012 section 6).
const SCHEMA_VERSION: int = 2

## Rules/schema version recorded alongside saved matches.
@export var schema_version: int = SCHEMA_VERSION

## Points per `ScoringEnums.PokerHandCategory`, indexed by enum value.
@export var points_by_category: Array[int] = [0, 2, 4, 5, 6, 9, 10, 12]


## Returns a stable identifier for this rules version, persisted with saves.
func version_key() -> String:
	return "poker-score:%d" % schema_version


## Returns the points awarded for one poker category.
##
## Returns 0 for an unknown category, which can only happen if a save is
## corrupted; `validate()` reports that case explicitly.
func points_for(category: int) -> int:
	if not ScoringEnums.is_valid_poker_hand(category):
		return 0
	if category < 0 or category >= points_by_category.size():
		return 0
	return points_by_category[category]


## Returns every validation problem found, so callers can report all of them.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if schema_version != SCHEMA_VERSION:
		problems.append(
			"unsupported schema_version %d (expected %d)" % [schema_version, SCHEMA_VERSION]
		)
	var expected_size: int = ScoringEnums.PokerHandCategory.size()
	if points_by_category.size() != expected_size:
		problems.append(
			"points_by_category must hold one value per category (%d), got %d"
			% [expected_size, points_by_category.size()]
		)
	else:
		for category: int in range(points_by_category.size()):
			var points: int = points_by_category[category]
			if points < 0:
				problems.append(
					"%s must not award negative points (got %d)"
					% [ScoringEnums.poker_hand_name(category), points]
				)
		if points_by_category[ScoringEnums.PokerHandCategory.NONE] != 0:
			problems.append(
				"an unclassified window must award 0 points, got %d"
				% points_by_category[ScoringEnums.PokerHandCategory.NONE]
			)
		# Categories are declared in precedence order, so values must not fall as
		# precedence rises. Comparing the weakest against the strongest would
		# reject the approved table, because those two differ by design.
		var previous_points: int = -1
		for category: int in range(points_by_category.size()):
			if category == ScoringEnums.PokerHandCategory.NONE:
				continue
			var points: int = points_by_category[category]
			if previous_points >= 0 and points < previous_points:
				problems.append(
					"%s must not award fewer points than a weaker category (%d < %d)"
					% [ScoringEnums.poker_hand_name(category), points, previous_points]
				)
			previous_points = points
	return problems


## Returns true when no validation problem was found.
func is_valid() -> bool:
	return validate().is_empty()


## Returns a rules instance carrying the approved Phase 1 values.
static func create_default() -> PokerScoreRules:
	return PokerScoreRules.new()
