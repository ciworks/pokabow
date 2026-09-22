class_name ClusterScoreRules
extends Resource

## Versioned cluster milestone configuration (ADR-002 section 4).
##
## ADR-002 section 4 defines a flat award for every completed group of
## `milestone_size` tiles in a single-colour cluster:
##
##     cluster_entitlement(n) = flat_award * floor(n / milestone_size)
##
## With the Phase 1 defaults of four tiles and three points that gives
##
##     size 1-3   -> 0
##     size 4-7   -> 3
##     size 8-11  -> 6
##     size 12-15 -> 9
##
## This is a series of fixed milestone awards, not a multiplier: ADR-002
## section 4 and ADR-007 section 11 both forbid multipliers in Phase 1, so the
## formula is integer arithmetic on counted tiles.
##
## ADR-008 section 3 places versioned rule configuration in `Resource`, which is
## why this type extends `Resource` rather than `RefCounted`.

## Rules/schema version, persisted with saves so a rebalance can be detected.
const SCHEMA_VERSION: int = 1

## Phase 1 milestone size in unique tiles (ADR-002 section 4).
const DEFAULT_MILESTONE_SIZE: int = 4

## Phase 1 flat award per completed milestone (ADR-002 section 4).
const DEFAULT_FLAT_AWARD: int = 3

## Rules/schema version recorded alongside saved matches.
@export var schema_version: int = SCHEMA_VERSION

## Number of unique tiles that completes one milestone.
@export var milestone_size: int = DEFAULT_MILESTONE_SIZE

## Points awarded for each completed milestone.
@export var flat_award: int = DEFAULT_FLAT_AWARD


## Returns a stable identifier for this rules version, persisted with saves.
func version_key() -> String:
	return "cluster-score:%d" % schema_version


## Returns the total entitlement of a cluster containing `size` unique tiles.
##
## Entitlement is the total a cluster has earned, not an increment: callers award
## the positive difference between the post-move and pre-move entitlements
## (ADR-002 section 5).
##
## Returns 0 for a non-positive size or an unusable configuration.
func entitlement_for_size(size: int) -> int:
	if size <= 0 or milestone_size <= 0 or flat_award <= 0:
		return 0
	return flat_award * int(size / milestone_size)


## Returns every validation problem found, so callers can report all of them.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if schema_version != SCHEMA_VERSION:
		problems.append(
			"unsupported schema_version %d (expected %d)" % [schema_version, SCHEMA_VERSION]
		)
	if milestone_size <= 0:
		problems.append("milestone_size must be positive, got %d" % milestone_size)
	if flat_award < 0:
		problems.append("flat_award must not be negative, got %d" % flat_award)
	return problems


## Returns true when no validation problem was found.
func is_valid() -> bool:
	return validate().is_empty()


## Returns a rules instance carrying the approved Phase 1 values.
static func create_default() -> ClusterScoreRules:
	return ClusterScoreRules.new()
