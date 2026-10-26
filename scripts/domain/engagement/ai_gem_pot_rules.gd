class_name AiGemPotRules
extends RefCounted

## Provisional, display-only AI Gem policy. Wallet settlement requires a
## server-verified match and is deliberately outside this local projection.
const POLICY_VERSION: String = "ai-gem-pot-v1"
const EASY_CAP: int = 20
const MEDIUM_CAP: int = 40
const HARD_CAP: int = 80


static func cap_for(difficulty: int) -> int:
	match difficulty:
		AiEnums.Difficulty.EASY:
			return EASY_CAP
		AiEnums.Difficulty.MEDIUM:
			return MEDIUM_CAP
		AiEnums.Difficulty.HARD:
			return HARD_CAP
	return EASY_CAP


## Reuses the online hand table, but bounds the entire AI match pot.
static func contribution(event: ScoreEvent, current_total: int, difficulty: int) -> int:
	return mini(GemPotRules.contribution(event), maxi(0, cap_for(difficulty) - current_total))


static func total(events: Array[ScoreEvent], difficulty: int) -> int:
	var seen: Dictionary = {}
	var amount: int = 0
	for event: ScoreEvent in events:
		if event == null or seen.has(event.event_id):
			continue
		seen[event.event_id] = true
		amount += contribution(event, amount, difficulty)
	return amount


## Only the human can receive an AI pot. A draw pays half; all unclaimed Gems
## disappear. This is a projection, not a wallet transaction.
static func projected_payout(result: MatchResult, pot: int, difficulty: int) -> Dictionary:
	if result == null or result.is_incomplete() or result.outcome == TurnEnums.MatchOutcome.IN_PROGRESS:
		return {}
	pot = clampi(pot, 0, cap_for(difficulty))
	var human_pot: int = 0
	if result.end_reason != TurnEnums.EndReason.RESIGNATION:
		if result.winner_id() == TurnEnums.HUMAN_PLAYER_ID:
			human_pot = pot
		elif result.is_draw():
			human_pot = int(pot / 2)
	return {
		"mode": "ai",
		"human_pot": human_pot,
		"human_completion": 0,
		"human_total": human_pot,
		"rival_pot": 0,
		"rival_completion": 0,
		"rival_total": 0,
	}
