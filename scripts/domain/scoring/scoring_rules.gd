class_name ScoringRules
extends Resource

## The scoring rule set in force for a match (ADR-007 sections 1 and 11).
##
## ADR-007 section 1 requires every score event to record the rules version in
## force when it was awarded, and section 11 requires unknown rules versions to be
## rejected. A match therefore needs one object that names the whole scoring
## configuration and can be validated as a unit.
##
## The individual values live in their own versioned resources, because ADR-001
## section 4 makes poker values tunable and ADR-002 section 4 makes the cluster
## milestone tunable, independently of each other. This type only composes them
## so callers pass one argument instead of three.
##
## ADR-013 adds integer hand multipliers while retaining non-negative points.

## Rules/schema version, persisted with saves.
##
## Version 7 removes Joker hands; older matches cannot be re-scored under these rules.
const SCHEMA_VERSION: int = 7

## Rules/schema version recorded alongside saved matches.
@export var schema_version: int = SCHEMA_VERSION

## Poker point values (ADR-001 section 4).
@export var poker: PokerScoreRules = null

## Cluster milestone configuration (ADR-002 section 4).
@export var cluster: ClusterScoreRules = null


## Returns a stable identifier for this rules version, persisted with saves.
func version_key() -> String:
	return "scoring:%d" % schema_version


## Returns every validation problem found, so callers can report all of them.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if schema_version != SCHEMA_VERSION:
		problems.append(
			"unsupported schema_version %d (expected %d)" % [schema_version, SCHEMA_VERSION]
		)
	if poker == null:
		problems.append("poker rules are required")
	else:
		for problem: String in poker.validate():
			problems.append("poker: %s" % problem)
	if cluster == null:
		problems.append("cluster rules are required")
	else:
		for problem: String in cluster.validate():
			problems.append("cluster: %s" % problem)
	return problems


## Returns true when no validation problem was found.
func is_valid() -> bool:
	return validate().is_empty()


## Returns a rules instance carrying the approved Phase 1 values.
static func create_default() -> ScoringRules:
	var rules: ScoringRules = ScoringRules.new()
	rules.poker = PokerScoreRules.create_default()
	rules.cluster = ClusterScoreRules.create_default()
	return rules


## Returns the points one poker category is worth under these rules.
func points_for_hand(category: int) -> int:
	if poker == null:
		return 0
	return poker.points_for(category)


## Returns the entitlement of a cluster holding `size` unique tiles.
func entitlement_for_cluster_size(size: int) -> int:
	if cluster == null:
		return 0
	return cluster.entitlement_for_size(size)
