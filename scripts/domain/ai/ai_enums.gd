class_name AiEnums
extends RefCounted

## Shared AI vocabulary (ADR-005 sections 1, 2, 4, 5, 6, and 11).
##
## This script holds the difficulty set, the proposal status set, and small pure
## helpers only. It has no state, no scene dependency, and no Godot node usage,
## so the strategies, the coordinator, the application layer, and the tests all
## share one vocabulary instead of re-declaring strings.
##
## Authority notes:
## - ADR-005 section 1 defines the three Phase 1 difficulties: Easy selects a
##   random legal candidate, Medium evaluates every legal candidate, and Hard
##   plans one to two turns.
## - ADR-005 sections 2 and 11 define what a decision can report: a proposal, no
##   legal candidate at all, a cancelled analysis, and a proposal that could not
##   be validated against the current board revision.
## - Nothing here decides a rule. Legality stays with `PlacementValidator`,
##   scoring stays with ADR-007, and no difficulty changes scoring.

## The three Phase 1 AI difficulties (ADR-005 sections 4, 5, and 6).
enum Difficulty {
	## Selects a uniformly random legal candidate and never evaluates score.
	EASY = 0,
	## Evaluates every legal candidate and ranks by ADR-005 section 5.
	MEDIUM = 1,
	## Performs the ADR-005 section 6 two-ply search with a representative sample.
	HARD = 2,
}

## What an AI decision reports (ADR-005 sections 2, 9, and 11; ADR-011 section 6).
enum AiDecisionStatus {
	## A move is available: a legal line (ADR-011 section 1) or the swap the rival
	## takes when no line is legal (ADR-011 section 6).
	OK = 0,
	## No legal candidate exists for the rival's deck (ADR-005 section 2). The
	## live strategies report the ADR-011 section 6 swap instead, so this remains
	## the structured refusal for callers that ask for it.
	NO_LEGAL_MOVE = 1,
	## The analysis was cancelled before it finished, so nothing may be committed
	## (ADR-005 section 9).
	CANCELLED = 2,
	## No proposal survived revalidation against the current board revision, so
	## the caller must stop instead of substituting a move (ADR-005 section 11).
	INVALID = 3,
}

## The difficulty a new game starts on, and the one used when a caller does not
## choose (ADR-005 section 5).
##
## This is the only place the starting difficulty is stated. `AiCoordinator`,
## `AiDifficultyConfig.create_default`, and `GameSessionController` all read this
## constant rather than naming a difficulty themselves, so changing it here
## changes the default for a fresh match and nothing else - the picker still
## shows whatever the controller reports, and a mid-match selection is untouched.
const DEFAULT_DIFFICULTY: int = Difficulty.EASY


## Returns true when `value` is one of the three Phase 1 difficulties.
static func is_valid_difficulty(value: int) -> bool:
	return Difficulty.values().has(value)


## Returns the difficulty's constant name, for diagnostics only.
static func difficulty_name(value: int) -> String:
	if not is_valid_difficulty(value):
		return "UNKNOWN_DIFFICULTY"
	return String(Difficulty.find_key(value))


## Returns a lowercase difficulty slug for identifier and diagnostic use.
##
## Returns an empty string for an unknown difficulty, so a malformed request
## cannot silently become a valid one.
static func difficulty_slug(value: int) -> String:
	match value:
		Difficulty.EASY:
			return "easy"
		Difficulty.MEDIUM:
			return "medium"
		Difficulty.HARD:
			return "hard"
	return ""


## Returns true when `value` is one of the defined decision statuses.
static func is_valid_status(value: int) -> bool:
	return AiDecisionStatus.values().has(value)


## Returns the status's constant name, for diagnostics only.
static func status_name(value: int) -> String:
	if not is_valid_status(value):
		return "UNKNOWN_STATUS"
	return String(AiDecisionStatus.find_key(value))
