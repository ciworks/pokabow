# ADR-005: AI Evaluation and Search

* **Status:** Accepted
* **Date:** 2026-09-21
* **Accepted:** 2026-09-21
* **Owners:** Game design and engineering
* **Decision scope:** Phase 1 Human vs AI mode
* **Source:** `GAME_SPEC.md` and `iterative_specification.pdf`
* **Related:** ADR-001, ADR-002, ADR-003, ADR-004, ADR-006, ADR-007, ADR-008

## Context

The source specification defines three AI difficulties:

* Easy selects a random valid placement and rotation.
* Medium prioritizes poker hands and edge matches.
* Hard plans approximately one to two turns, blocks the human, and maximizes score.

The accepted ADRs now define legal moves, deterministic scoring, hidden future tiles, turn timing, and architectural boundaries. This ADR converts the difficulty descriptions into deterministic, testable behavior that does not inspect the hidden tile bag or manipulate scene nodes.

## Constraints inherited from accepted decisions

1. AI and human moves use the same placement validator and atomic commit path.
2. The AI knows its active tile, committed board state, public score history, and rules configuration.
3. Future bag contents and draw order are hidden from the AI.
4. Every legal frontier cell accepts the active tile in any valid rotation.
5. Preview scoring uses the same pure calculators as committed scoring.
6. Committed tiles cannot be moved or rotated.
7. The AI may propose a move but cannot mutate authoritative state.
8. The returned move is revalidated immediately before commit.

## Decision

### 1. Shared AI contract

All difficulty strategies implement the same interface:

```gdscript
class_name AiStrategy
extends RefCounted

func choose_move(
	snapshot: AiGameSnapshot,
	active_tile: TileData,
	config: AiDifficultyConfig,
	decision_seed: int,
	cancellation: AiCancellationToken
) -> AiDecision:
	return AiDecision.new()
```

`AiGameSnapshot` is immutable and includes only public or legitimately owned information. `AiDecision` contains a proposed coordinate, rotation, diagnostics, and the board revision on which it was calculated.

### 2. Legal move generation

Generate candidates through the accepted rules interfaces:

1. Read the legal-placement frontier from the snapshot.
2. Pair each frontier cell with rotations `0`, `1`, `2`, and `3`.
3. Remove rotationally equivalent candidates when the tile's visible edges are identical under those rotations.
4. Validate remaining candidates using `PlacementValidator`.
5. Sort candidates by coordinate and rotation before applying a difficulty strategy.

The AI must never create its own looser placement rules. If no legal candidate exists, return `NO_LEGAL_MOVE`; ADR-003 determines the turn outcome.

### 3. Determinism and decision randomness

* Each AI turn receives a dedicated deterministic decision seed derived from match seed, turn number, player ID, and difficulty.
* AI randomization uses a separate RNG from the tile bag.
* Given the same snapshot, tile, configuration, and decision seed, the AI returns the same decision and diagnostics.
* AI analysis cannot consume tile-source randomness or change future draws.
* Difficulty configuration and evaluation versions are stored with replays when exact AI reproduction is required.

### 4. Easy difficulty

Easy behavior is intentionally non-strategic:

1. Generate every legal coordinate/rotation candidate.
2. Select one candidate uniformly using the AI decision RNG.
3. Return it without evaluating score or future board potential.

Rotationally equivalent candidates are deduplicated before selection so symmetric tiles do not bias particular cells. Easy may accidentally make an excellent move; it simply does not prefer one.

### 5. Medium difficulty

Medium performs exhaustive one-ply evaluation of every legal candidate using ADR-007's preview calculators.

Primary value is the move's immediate committed score:

```text
immediate_score = poker_points + edge_match_points + cluster_points
```

Candidates are ranked by this deterministic tuple, highest first:

1. total immediate score;
2. poker points;
3. c
