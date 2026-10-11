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
3. cluster points;
4. edge-match points;
5. number of distinct score events; and
6. deterministic seeded tie-break value.

Medium does not model the human response, future draws, blocking, or unawarded potential. It chooses the highest immediate scoring placement it can see.

### 6. Hard difficulty

Hard performs a two-ply, hidden-information-aware search:

* **Ply 1:** enumerate and score the AI's current legal moves.
* **Ply 2:** estimate the strongest human reply after each candidate without inspecting the real future bag.

Because ADR-003 draws the human tile at the human's next `TURN_START`, the actual reply tile is unknown. Hard uses a fixed, versioned representative sample generated from public tile probabilities, not from the remaining bag.

The initial Phase 1 sample contains **16 deterministic representative tiles** covering:

* all four ranks;
* both face colors across the sample; and
* balanced edge-color frequencies and rotations of edge patterns.

The sample is a versioned rules resource. It is identical for equivalent analyses and does not reveal or consume future tiles.

For each AI candidate:

1. Apply the candidate to a detached hypothetical state.
2. Calculate the AI's immediate score.
3. For each representative human tile, find that tile's highest-valued legal immediate response.
4. Average those best-response scores using the configured sample weights.
5. Evaluate board opportunity and denial features.
6. Rank the AI move by total utility.

The Phase 1 Hard utility is:

```text
utility =
    ai_immediate_points * 100
    - expected_human_reply_points * 70
    + ai_open_opportunity * 8
    - human_open_threat * 10
    + matched_edge_count * 2
```

The coefficients are integer configuration values for reproducibility and require balance simulation. They are not gameplay score multipliers; they exist only inside AI move ranking.

### 7. Opportunity and blocking features

Hard may consider only deterministic features derived from public board state:

* number of unscored five-cell windows containing four occupied cells and one legal empty frontier cell;
* best poker category potentially completable in those windows by any rank;
* color components one tile below the next cluster milestone;
* legal frontier cells that can touch multiple matching edges; and
* whether the candidate occupies a high-value completion cell available before the move.

`ai_open_opportunity` measures opportunities retained or created for the AI's later turns. `human_open_threat` measures publicly visible completion cells left available to the next player. Hard may block a threat by occupying its cell even if the move scores fewer immediate points.

These features cannot assume the next tile's exact values and cannot inspect player-private or undrawn data.

### 8. Search budget and pruning

Use deterministic work budgets rather than wall-clock cutoffs for rules-level selection:

* Easy evaluates no score previews.
* Medium evaluates every legal candidate once.
* Hard sorts AI candidates by Medium's ranking, searches the best **24** candidates deeply, and evaluates the remainder only at one ply.
* For each sampled human tile, Hard searches the best **16** responses after an immediate-score pre-sort.
* The maximum Phase 1 deep response evaluations are therefore `24 x 16 x 16 = 6,144`, plus first-ply work.

If fewer candidates exist, evaluate all of them. Configuration may reduce budgets on low-end devices but must record the chosen profile in diagnostics. A reduced budget changes strength, not legality or scoring.

### 9. Time slicing and cancellation

* AI work may be divided across frames or run on detached data in a worker thread.
* The render loop must remain responsive.
* Cancellation is checked between candidate batches.
* Closing or restarting a match, or changing the board revision, cancels the outstanding decision.
* Partial search results are not committed after cancellation.
* A presentation delay may make an immediate decision feel natural, but it is not part of search correctness.

Hard and Medium fall back to the best fully evaluated candidate if an application-level safety limit stops analysis. The deterministic rules test profile does not use wall-clock interruption.
ADR-017 adds a distinct match-rule deadline: after the 60-second turn expires,
discard the proposal and pass instead of committing any fallback move.

### 10. Tie-breaking

After all difficulty-specific ranking fields are equal:

1. Assign each tied candidate a deterministic pseudo-random value from the decision seed and its canonical move key.
2. Select the highest value.
3. Record the tied keys and selected value in diagnostics.

This creates variety across matches while preserving reproducibility. Do not resolve ties using iteration order, object address, frame time, or platform-dependent hashing.

### 11. Commit and recovery

* The AI returns a proposal tagged with the source board revision.
* The application revalidates it using the current active tile and board.
* If stale or invalid, discard it and retry once from a fresh snapshot as specified by ADR-003.
* The proposal then enters ADR-007's normal atomic move transaction.
* If retry fails because of an AI implementation error, enter the recoverable error state; do not substitute an illegal move or secretly change difficulty.

### 12. Diagnostics

Development builds record:

* difficulty and configuration version;
* decision seed;
* candidate count and deduplication count;
* candidates evaluated at each ply;
* score-event breakdowns;
* Hard utility feature values;
* pruning and budget profile;
* tied candidates and tie-break outcome;
* elapsed diagnostic time; and
* final validation result.

Diagnostics must not expose future bag contents because the strategy never receives them.

## Configuration resources

Use a versioned `AiDifficultyConfig` resource containing:

* difficulty enum;
* evaluation version;
* Hard representative-tile sample and version;
* utility coefficients;
* first-ply and reply beam widths;
* deterministic work budget; and
* optional presentation delay range.

Changing these values is a balance change. A live match retains the configuration snapshot with which it began.

## Data ownership

* `AiCoordinator` requests or cancels decisions and owns no game rules.
* `AiStrategy` implementations rank candidates on detached snapshots.
* `PlacementValidator` owns legality.
* ADR-007 calculators own scoring previews.
* `TurnManager` owns whether an AI action is currently allowed.
* `MoveCommitter` owns authoritative mutation.
* Presentation observes thinking state and animations but cannot choose or alter the move.

## Alternatives considered

### Let Hard inspect the remaining bag

This would violate hidden information and create difficulty through cheating. Representative public probability samples provide planning without privileged data.

### Use wall-clock time as the only search limit

Different devices would produce different moves and flaky tests. Deterministic node and beam budgets are reproducible; time slicing handles responsiveness.

### Give Medium handcrafted poker and edge weights

The real scoring rules already express their relative value. Medium should maximize immediate actual points rather than duplicate balance values.

### Use random mistakes for Medium and Hard

Artificial mistakes make difficulty unpredictable. Search depth and information considered provide clearer differentiation. Seeded tie-breaking still gives variety among equivalent moves.

### Implement full minimax over future tiles

The hidden random draw and high branching factor make exhaustive minimax inappropriate for mobile Phase 1. A deterministic representative sample is bounded and testable.

### Couple AI to visual placement nodes

This would prevent headless simulation and introduce timing-dependent behavior. AI consumes domain snapshots only.

## Consequences

### Benefits

* Difficulties are observably distinct and match the source specification.
* Every AI move is legal and scored through the same path as human play.
* Hidden future tiles remain hidden at every difficulty.
* Fixed seeds and work budgets make decisions reproducible.
* Hard can block visible opportunities without knowing the next human tile.
* Search can be simulated headlessly for balance and regression testing.

### Costs and risks

* The 16-tile representative sample approximates rather than exactly integrates all 2,048 tile configurations.
* Hard utility coefficients and beam widths require simulation and playtesting.
* A two-ply search may still be expensive on low-end mobile hardware.
* Opportunity heuristics can influence behavior in ways not visible from immediate score.
* Any change to evaluation versions can change replayed AI decisions unless decisions themselves are stored.

## Required tests

Automated tests must cover:

* candidate generation matching the legal frontier and validator;
* rotationally equivalent candidates being deduplicated correctly;
* every returned move revalidating as legal;
* Easy selection being approximately uniform across large seeded samples;
* Easy performing no scoring-based preference;
* Medium selecting the greatest immediate actual score;
* Medium tie-break tuple ordering;
* Hard selecting a lower immediate score when needed to block a larger expected response;
* Hard representative samples never using real future bag entries;
* identical inputs and seeds producing identical decisions and diagnostics;
* AI RNG never changing tile draw order;
* deterministic budget enforcement;
* cancellation and stale-revision rejection;
* single-retry behavior;
* no scene-tree access from strategies;
* score preview equality with committed score for the selected move;
* headless seeded tournaments for win rate, first-player advantage, score distribution, and decision cost; and
* every difficulty completing full matches without illegal moves or deadlocks.

## Decision confirmation

The gameplay owner accepted the complete proposal on 2026-09-21. This confirms that:

1. Easy uniformly selects among deduplicated legal coordinate and rotation candidates.
2. Medium exhaustively maximizes immediate actual score with deterministic tie-breaking.
3. Hard uses two-ply search with a fixed 16-tile representative sample rather than hidden bag access.
4. Hard includes both expected opponent response and public blocking or opportunity features.
5. Deterministic beam and work budgets replace wall-clock cutoffs for move selection.
6. All AI randomness uses a dedicated decision seed independent of tile generation.
7. All difficulties return proposals that are revalidated and committed through the human rules path.

These rules are authoritative for Phase 1 unless this ADR is superseded or explicitly amended.

## Implementation follow-up

1. Update `GAME_SPEC.md` with the approved difficulty behaviors.
2. Implement shared move generation and Easy first.
3. Implement Medium using ADR-007 previews.
4. Build deterministic simulations before implementing Hard.
5. Implement Hard's representative sample, features, and bounded search.
6. Profile representative mobile devices and tune budgets without changing legality.

## Amendments

* 2026-09-21: The initial proposal was accepted without changes.
* 2026-09-22: Amended by ADR-010. The AI now chooses among every tile in its deck rather than a single active tile, and it plays out its deck before ending its turn. Sections 1 to 6 stand, applied per tile considered; the section 8 budgets apply per placement.
* 2026-09-27: Owner set the starting difficulty for a new game to Easy. This
  ADR defines what each difficulty does but deliberately did not fix which one a
  fresh match begins with, so this is a selection default, not a change to any
  difficulty's behaviour: sections 4, 5, and 6 stand unchanged. The default lives
  in one place, `AiEnums.DEFAULT_DIFFICULTY`, and `GameSessionController`,
  `AiCoordinator`, and `AiDifficultyConfig` all read it from there, so a match
  still starts on the policy the HUD picker shows and the player can still switch
  to Medium or Hard at any time.
