class_name GemPotRules
extends RefCounted

## Provisional online Gem pot values from GAME_SPEC section 8.5.
## This projection reads committed server score events; it never grants wallet Gems.
const POLICY_VERSION: String = "gem-pot-v1"
const COMPLETION_GEMS: int = 10


static func contribution(event: ScoreEvent) -> int:
	if event == null or event.category != ScoringEnums.ScoreCategory.POKER_HAND:
		return 0
	match String(event.evidence.get("category", "")):
		"PAIR":
			return 2
		"TWO_PAIR":
			return 4
		"STRAIGHT_3":
			return 6
		"THREE_OF_A_KIND":
			return 8
		"STRAIGHT_4":
			return 10
		"FULL_HOUSE":
			return 12
		"FOUR_OF_A_KIND":
			return 14
	return 0


static func total(events: Array[ScoreEvent]) -> int:
	var seen: Dictionary = {}
	var amount: int = 0
	for event: ScoreEvent in events:
		if event == null or seen.has(event.event_id):
			continue
		seen[event.event_id] = true
		amount += contribution(event)
	return amount


## A display-only projection from a completed, server-verified online match.
## The backend has not yet credited an account wallet; callers must label this
## pending and must never use these numbers as an account balance.
static func projected_payout(result: MatchResult, pot: int) -> Dictionary:
	if result == null or result.is_incomplete() or result.outcome == TurnEnums.MatchOutcome.IN_PROGRESS:
		return {}
	pot = maxi(0, pot)
	var winner: StringName = result.winner_id()
	var resignation: bool = result.end_reason == TurnEnums.EndReason.RESIGNATION
	var human_pot: int = 0
	var rival_pot: int = 0
	if result.is_draw():
		human_pot = int(pot / 2)
		rival_pot = pot - human_pot
	elif winner == TurnEnums.HUMAN_PLAYER_ID:
		human_pot = pot
	elif winner == TurnEnums.AI_PLAYER_ID:
		rival_pot = pot
	var completion: int = 0 if resignation else COMPLETION_GEMS
	return {
		"human_pot": human_pot,
		"rival_pot": rival_pot,
		"human_completion": completion,
		"rival_completion": completion,
		"human_total": human_pot + completion,
		"rival_total": rival_pot + completion,
	}
