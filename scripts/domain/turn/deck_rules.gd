class_name DeckRules
extends Resource

## Versioned deck configuration (ADR-010 sections 1 and 6).
##
## ADR-010 section 1 replaces the single active tile of ADR-003 section 4 with a
## deck of exactly `deck_size` tiles per player, with a Phase 1 default of six.
## The ADR is explicit that the value is configuration rather than a literal in
## control flow, so it lives here as data alongside the other approved
## configurable values (ADR-008 section 12): a future mode can change the deck
## size without touching the turn loop.
##
## Two rules read this value and nothing else reads it:
##
## - the deal at `MATCH_SETUP` and the top-up at every turn end fill a deck to
##   `deck_size` from the shared pot (ADR-010 sections 2 and 5);
## - the most tiles a player may place in one turn is `deck_size`, because the
##   deck holds at most that many and it does not refill mid-turn
##   (ADR-010 section 6).
##
## ADR-008 section 3 places versioned rule configuration in `Resource`, which is
## why this type extends `Resource` rather than `RefCounted`.

## Rules/schema version, persisted with saves so a rebalance can be detected.
const SCHEMA_VERSION: int = 1

## Phase 1 deck size: six tiles per player (ADR-010 sections 1 and 2).
const DEFAULT_DECK_SIZE: int = 6

## Rules/schema version recorded alongside saved matches.
@export var schema_version: int = SCHEMA_VERSION

## Tiles each player holds between turn boundaries (ADR-010 section 1).
@export var deck_size: int = DEFAULT_DECK_SIZE


## Returns a stable identifier for this rules version, persisted with saves.
func version_key() -> String:
	return "deck:%d" % schema_version


## Returns the number of tiles a deck is filled to.
##
## A deck is only ever smaller than this when the shared pot cannot supply the
## difference (ADR-010 section 5), so this is a target rather than a guarantee.
func tiles_per_deck() -> int:
	return deck_size


## Returns the most tiles one player may place in a single turn
## (ADR-010 section 6).
func max_placements_per_turn() -> int:
	return deck_size


## Returns every validation problem found, so callers can report all of them.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if schema_version != SCHEMA_VERSION:
		problems.append(
			"unsupported schema_version %d (expected %d)" % [schema_version, SCHEMA_VERSION]
		)
	if deck_size <= 0:
		problems.append("deck_size must be positive, got %d" % deck_size)
	return problems


## Returns true when no validation problem was found.
func is_valid() -> bool:
	return validate().is_empty()


## Returns a rules instance carrying the approved Phase 1 value.
static func create_default() -> DeckRules:
	return DeckRules.new()
