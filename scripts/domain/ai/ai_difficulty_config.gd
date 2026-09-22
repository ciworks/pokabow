class_name AiDifficultyConfig
extends Resource

## Versioned AI tuning for one difficulty (ADR-005 sections 6, 8, 10, and 12).
##
## ADR-005 "Configuration resources" requires the Phase 1 tuning values to be
## data with a version, not literals in the search. This type carries:
##
## - the difficulty the configuration is for;
## - the evaluation version recorded in every decision's diagnostics
##   (ADR-005 section 12);
## - the Hard utility coefficients of ADR-005 section 6, whose approved Phase 1
##   values are 100 for the AI's immediate points, 70 for the expected human
##   reply, 8 for a retained AI opportunity, 10 for a publicly available human
##   threat, and 2 for the connectivity (matched-edge) term;
## - the ADR-005 section 8 work budgets: candidate beam 24, reply beam 16, and a
##   maximum of 6144 deep response evaluations;
## - the presentation-delay range the application layer uses to show a thinking
##   state. The delay is presentation timing, never a search budget: ADR-005
##   section 8 forbids wall-clock cutoffs in move selection, so nothing here can
##   affect which move is chosen;
## - the versioned representative sample of ADR-005 section 6.
##
## ADR-008 section 3 places versioned rule configuration in `Resource`, which is
## why this type extends `Resource` rather than `RefCounted`.

## Config/schema version, persisted with saves so a retune can be detected.
const SCHEMA_VERSION: int = 1

## Algorithm/evaluation version reported in decision diagnostics (ADR-005
## section 12: "the evaluation version" is recorded for every decision).
const EVALUATION_VERSION: int = 1

## Approved Phase 1 coefficients (ADR-005 section 6).
const DEFAULT_AI_IMMEDIATE_COEFFICIENT: int = 100
const DEFAULT_EXPECTED_HUMAN_REPLY_COEFFICIENT: int = 70
const DEFAULT_AI_OPEN_OPPORTUNITY_COEFFICIENT: int = 8
const DEFAULT_HUMAN_OPEN_THREAT_COEFFICIENT: int = 10
const DEFAULT_MATCHED_EDGE_COUNT_COEFFICIENT: int = 2

## Approved Phase 1 work budgets (ADR-005 section 8).
const DEFAULT_HARD_CANDIDATE_BEAM: int = 24
const DEFAULT_HARD_REPLY_BEAM: int = 16
const DEFAULT_DEEP_EVALUATION_BUDGET: int = 6144

## Presentation-delay range used while the rival is thinking.
##
## The application layer needs a human-readable pause; the domain needs no
## timing at all. The range keeps the pause short on a phone without ever
## influencing move selection.
const DEFAULT_PRESENTATION_DELAY_MIN_SECONDS: float = 0.45
const DEFAULT_PRESENTATION_DELAY_MAX_SECONDS: float = 0.9

## Config/schema version recorded alongside saved matches.
@export var schema_version: int = SCHEMA_VERSION

## Evaluation version recorded in every decision's diagnostics.
@export var evaluation_version: int = EVALUATION_VERSION

## `AiEnums.Difficulty` value this configuration tunes.
@export var difficulty: int = AiEnums.Difficulty.MEDIUM

## Coefficient on the AI's immediate points (ADR-005 section 6).
@export var ai_immediate_coefficient: int = DEFAULT_AI_IMMEDIATE_COEFFICIENT

## Coefficient on the expected best human reply (ADR-005 section 6).
@export var expected_human_reply_coefficient: int = DEFAULT_EXPECTED_HUMAN_REPLY_COEFFICIENT

## Coefficient on retained or created AI opportunities (ADR-005 section 6).
@export var ai_open_opportunity_coefficient: int = DEFAULT_AI_OPEN_OPPORTUNITY_COEFFICIENT

## Coefficient on completion cells left to the next player (ADR-005 section 6).
@export var human_open_threat_coefficient: int = DEFAULT_HUMAN_OPEN_THREAT_COEFFICIENT

## Coefficient on the candidate's connectivity term (ADR-005 section 6).
@export var matched_edge_count_coefficient: int = DEFAULT_MATCHED_EDGE_COUNT_COEFFICIENT

## Number of candidates Hard may score deeply per decision (ADR-005 section 8).
@export var hard_candidate_beam: int = DEFAULT_HARD_CANDIDATE_BEAM

## Number of replies kept per sample tile (ADR-005 section 8).
@export var hard_reply_beam: int = DEFAULT_HARD_REPLY_BEAM

## Maximum deep response evaluations per decision (ADR-005 section 8).
@export var deep_evaluation_budget: int = DEFAULT_DEEP_EVALUATION_BUDGET

## Shortest presentation delay for a thinking state, in seconds.
@export var presentation_delay_min_seconds: float = DEFAULT_PRESENTATION_DELAY_MIN_SECONDS

## Longest presentation delay for a thinking state, in seconds.
@export var presentation_delay_max_seconds: float = DEFAULT_PRESENTATION_DELAY_MAX_SECONDS

## The versioned representative sample of ADR-005 section 6.
@export var sample: AiRepresentativeSample = null


## Returns a configuration carrying the approved Phase 1 values.
##
## An unknown difficulty is normalised to Medium rather than accepted, so a
## malformed request cannot produce a config that fails validation later.
static func create_default(difficulty_value: int) -> AiDifficultyConfig:
	var config: AiDifficultyConfig = AiDifficultyConfig.new()
	config.difficulty = difficulty_value
	if not AiEnums.is_valid_difficulty(config.difficulty):
		config.difficulty = AiEnums.DEFAULT_DIFFICULTY
	config.sample = AiRepresentativeSample.create_default()
	return config


## Returns a stable identifier for this configuration, used in diagnostics.
##
## The difficulty is part of the key because the same budgets apply to different
## policies (ADR-005 section 12).
func version_key() -> String:
	return "ai-difficulty:%d:%d:%s" % [
		schema_version, evaluation_version, AiEnums.difficulty_slug(difficulty),
	]


## Returns the representative sample's version key, or an empty string.
func sample_version() -> String:
	if sample == null:
		return ""
	return sample.version_key()


## Returns how many representative tiles the configured sample holds.
func sample_size() -> int:
	if sample == null:
		return 0
	return sample.sample_size()


## Returns the presentation delay for a thinking state, in seconds.
##
## A single deterministic value is used so repeated presentations of the same
## state do not vary; the range exists so a retune stays a data change.
func presentation_delay_seconds() -> float:
	var low: float = maxf(presentation_delay_min_seconds, 0.0)
	var high: float = maxf(presentation_delay_max_seconds, low)
	return (low + high) * 0.5


## Returns every validation problem found, so callers can report all of them.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if schema_version != SCHEMA_VERSION:
		problems.append(
			"unsupported schema_version %d (expected %d)" % [schema_version, SCHEMA_VERSION]
		)
	if evaluation_version != EVALUATION_VERSION:
		problems.append(
			"unsupported evaluation_version %d (expected %d)"
			% [evaluation_version, EVALUATION_VERSION]
		)
	if not AiEnums.is_valid_difficulty(difficulty):
		problems.append("unknown difficulty %d" % difficulty)
	if ai_immediate_coefficient <= 0:
		problems.append(
			"ai_immediate_coefficient must be positive, got %d" % ai_immediate_coefficient
		)
	for problem: String in _collect_coefficient_problems():
		problems.append(problem)
	if hard_candidate_beam <= 0:
		problems.append("hard_candidate_beam must be positive, got %d" % hard_candidate_beam)
	if hard_reply_beam <= 0:
		problems.append("hard_reply_beam must be positive, got %d" % hard_reply_beam)
	if deep_evaluation_budget < 0:
		problems.append(
			"deep_evaluation_budget must not be negative, got %d" % deep_evaluation_budget
		)
	if presentation_delay_min_seconds < 0.0:
		problems.append(
			"presentation_delay_min_seconds must not be negative, got %f"
			% presentation_delay_min_seconds
		)
	if presentation_delay_max_seconds < presentation_delay_min_seconds:
		problems.append(
			"presentation_delay_max_seconds (%f) must not be below the minimum (%f)"
			% [presentation_delay_max_seconds, presentation_delay_min_seconds]
		)
	if sample == null:
		problems.append("a representative sample is required (ADR-005 section 6)")
	else:
		for problem: String in sample.validate():
			problems.append("sample: %s" % problem)
	return problems


## Returns true when no validation problem was found.
func is_valid() -> bool:
	return validate().is_empty()


## Returns every negative-coefficient problem among the secondary coefficients.
func _collect_coefficient_problems() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var coefficients: Dictionary = {
		"expected_human_reply_coefficient": expected_human_reply_coefficient,
		"ai_open_opportunity_coefficient": ai_open_opportunity_coefficient,
		"human_open_threat_coefficient": human_open_threat_coefficient,
		"matched_edge_count_coefficient": matched_edge_count_coefficient,
	}
	for name: String in coefficients.keys():
		var value: int = int(coefficients[name])
		if value < 0:
			problems.append("%s must not be negative, got %d" % [name, value])
	return problems
