# ADR-003: Turn Rules and Game End

- **Status:** Accepted
- **Date:** 2026-09-21
- **Accepted:** 2026-09-21
- **Owners:** Game design and engineering
- **Decision scope:** Phase 1 Human vs AI mode
- **Source:** `GAME_SPEC.md` and `iterative_specification.pdf`
- **Related:** ADR-001 (poker scoring), ADR-004 (tile distribution), ADR-006 (placement), ADR-007 (incremental scoring)

## Context

The source specification establishes a turn-based Human vs AI game but does not define who moves first, how a turn begins and ends, how tiles enter play, whether passing is allowed, when the match ends, how ties are handled, or when control transfers between the human and AI.

ADR-001 defines how a committed placement scores. ADR-006 defines a legal placement and requires one tile to be previewed, confirmed, and committed atomically. This ADR connects those decisions into a complete match lifecycle without deciding the contents or randomization of the tile supply, which remains the responsibility of ADR-004.

## Constraints inherited from the specification

1. The base mode is one human player versus one AI player.
2. Play is turn-based.
3. The board is 12 x 12.
4. A turn may place a tile using one of four rotations.
5. Scoring includes poker hands, edge matches, and edge clusters.
6. Scoring is incremental and occurs in response to committed placement.
7. The base mode is untimed.
8. A landscape-oriented splash screen appears before gameplay begins.

## Decision

### 1. Match lifecycle

The Phase 1 match progresses through these states:

```text
SPLASH -> MATCH_SETUP -> TURN_START -> AWAIT_ACTION -> RESOLVE_MOVE
                                      ^                    |
                                      |                    v
                                      +----- TURN_END <----+

TURN_END -> GAME_OVER when an end condition is met
```

- `SPLASH` displays the required landscape splash screen and loads core resources.
- `MATCH_SETUP` initializes players, board state, scores, tile source, and deterministic random seed.
- `TURN_START` assigns or retrieves the active player's tile.
- `AWAIT_ACTION` accepts a human preview/confirmation or asks the AI for a move.
- `RESOLVE_MOVE` commits placement and scoring atomically.
- `TURN_END` records the completed turn, checks end conditions, and selects the next player.
- `GAME_OVER` freezes gameplay input and presents the final result.

The rules state machine, not UI animation, owns match progression.

### 2. First player

The human player takes the first turn in the Phase 1 demo. This gives a new player immediate agency, simplifies onboarding, and produces deterministic tutorial behavior.

Random or alternating first-player selection may be introduced later as a mode setting.

### 3. Turn structure

Each normal turn consists of exactly one committed tile placement:

1. Identify the active player.
2. Obtain one active tile from the tile source if the player does not already have one.
3. Enter the action phase.
4. The active player selects a legal empty cell and rotation.
5. For a human, display a non-authoritative preview and require confirmation.
6. For the AI, validate its selected move through the same rules interface.
7. Commit the tile through ADR-006's atomic placement operation.
8. Apply poker, edge-match, and edge-cluster score events to the active player.
9. Record the move in match history.
10. Check game-end conditions.
11. If the game continues, switch active player and increment the turn number.

A player cannot place more than one tile, bank unused actions, or continue placing after a high-scoring move.

### 4. Active tile ownership

- Each player may have at most one active, uncommitted tile.
- The active tile remains assigned to that player while it is being previewed or rotated.
- Canceling a preview does not discard or replace the active tile.
- A committed tile is removed from the player's active slot and becomes board-owned state.
- The next tile is requested at that player's next `TURN_START`, not immediately after placement.
- Tile identity and random generation are controlled by ADR-004.

This boundary prevents UI actions from consuming random values or changing the tile supply.

### 5. Passing and invalid actions

Voluntary passing is not supported in Phase 1.

- Invalid previews or placement requests do not consume the turn.
- A human may retry until committing a legal move.
- If a rules or UI error interrupts a move, restore the last committed state and retain the active tile.
- Under ADR-006, any available tile can be placed while the legal frontier is non-empty because edge mismatches do not block placement.
- If no tile can be supplied, the turn is automatically skipped and recorded with the reason `NO_TILE_AVAILABLE`.

Two consecutive automatic skips caused by an exhausted tile source end the game. This accommodates tile-source designs finalized by ADR-004 without introducing strategic passing.

### 6. AI turns

- Human input is disabled while the AI turn is active.
- The AI receives an immutable game-state snapshot and the same legal-move interface used by the human rules path.
- The AI may think asynchronously, but the authoritative match state remains in `AWAIT_ACTION` until a validated decision is returned.
- The AI decision is revalidated immediately before commit.
- If the decision is stale or invalid, request one retry from the current state.
- If the retry fails because of an implementation error, do not silently skip; stop the match in a recoverable error state and preserve diagnostic information.
- Visual placement and score effects play from the committed result and cannot alter turn state.

Phase 1 has no chess clock or AI time forfeit. A development watchdog may report a stuck AI without changing game rules.

### 7. End conditions

The game ends after resolving the current committed move when any of these conditions is true:

1. **Board full:** all 144 cells are occupied.
2. **Tile source exhausted:** neither player has an active tile, the source cannot provide another tile, and both players have recorded consecutive automatic `NO_TILE_AVAILABLE` skips.
3. **Unrecoverable rules failure:** development and recovery condition only; the match is marked incomplete and no winner is awarded.

Phase 1 does not end early because of score difference, a player reaching a target score, a fixed turn limit, or an AI evaluation that predicts the winner.

### 8. Winner and final score

- Each player's final score is the sum of committed score events attributed to that player.
- The player with the greater final score wins.
- Equal scores produce a draw.
- There is no endgame bonus, remaining-tile penalty, multiplier, or tie-breaker in Phase 1.
- The results screen displays total score and a breakdown by poker, edge-match, and edge-cluster points.
- Final scores are recalculated from committed match history in debug/test builds and checked against incremental totals.

### 9. Save, resume, and determinism

A restorable match snapshot must include at least:

- rules/schema version;
- deterministic random seed and tile-source state;
- board state and committed tile rotations;
- active player and turn number;
- each player's active tile, if any;
- each player's score totals;
- committed score events or sufficient data to reconstruct them;
- ADR-001 scored hand identifiers;
- edge-cluster scoring state required by ADR-002;
- consecutive automatic-skip count;
- match state; and
- move history or an integrity hash of it.

Do not persist a transient visual preview as authoritative board state. If the app closes during a preview, resume at `AWAIT_ACTION` with the player's active tile uncommitted.

## Turn-state interface

A rules-focused turn manager may expose state similar to:

```gdscript
enum MatchPhase {
    MATCH_SETUP,
    TURN_START,
    AWAIT_ACTION,
    RESOLVE_MOVE,
    TURN_END,
    GAME_OVER,
    RECOVERY_ERROR,
}

class_name TurnState
extends RefCounted

var phase: MatchPhase
var active_player_id: StringName
var turn_number: int
var consecutive_no_tile_skips: int
```

The turn manager may emit events such as:

- `turn_started(player_id, turn_number)`
- `active_tile_assigned(player_id, tile_snapshot)`
- `move_committed(move_result)`
- `turn_ended(player_id, turn_number)`
- `game_ended(game_result)`
- `recovery_required(error_data)`

Signals notify presentation systems; they do not replace authoritative state transitions.

## Data ownership

- `GameSession` owns the match lifecycle and immutable configuration.
- `TurnManager` owns active player, turn number, phase transitions, and skip counting.
- `BoardState` and `MoveCommitter` own committed placement state.
- `TileSource` owns supply and randomization behavior defined by ADR-004.
- `ScoreLedger` owns committed score events and player totals.
- `AIController` proposes a move but never changes authoritative state directly.
- UI observes state, submits intents, and plays effects from committed results.

## Alternatives considered

### Random first player

This adds variety but makes onboarding and deterministic demonstrations less predictable. It can be added after the core loop is validated.

### Allow voluntary passing

Passing adds strategy only if holding a tile has value or placement can be disadvantageous. Neither rule is currently established, so passing would mostly enable stalling.

### Draw the next tile immediately after placement

This exposes future information before the opponent's turn and complicates save boundaries. Drawing at the owner's next turn keeps the sequence clearer.

### End after a fixed number of turns

This guarantees match length but leaves usable board and tile supply unexplored. It should be considered later for timed or challenge modes.

### Break ties using the last scorer or hand count

These rules are arbitrary without a design requirement. A draw is transparent and testable.

## Consequences

### Benefits

- The complete Human vs AI loop has explicit, deterministic state transitions.
- Only committed moves consume turns or alter scores.
- Human and AI placements use the same validation and commit path.
- Save/resume boundaries are clear, including interrupted previews.
- Game-end and draw behavior require no hidden rules.

### Costs and risks

- Human-first play may create a measurable first-player advantage.
- No voluntary pass means every supplied tile must eventually be placed.
- An exhausted finite tile source requires two automatic skip transitions before ending.
- Results depend on ADR-002 and ADR-004 for complete scoring and supply behavior.
- Persisting sufficient deterministic state requires explicit save schema versioning.

## Required tests

Automated tests must cover:

- human player starts a new Phase 1 match;
- exactly one committed placement per normal turn;
- turn does not advance after invalid input or canceled preview;
- turn advances only after successful placement and scoring commit;
- active-tile ownership across preview, cancel, commit, and resume;
- human and AI moves use the same validation path;
- stale AI moves are rejected and retried once;
- board-full end condition, including the 144th placement;
- tile-source exhaustion with two consecutive automatic skips;
- skip counter reset when a tile is successfully supplied;
- winner, loser, and draw results;
- absence of endgame bonuses and tie-breakers;
- incremental score ledger versus full-history recalculation;
- save/resume from each stable match phase;
- interrupted preview resuming without a committed tile; and
- deterministic replay from the same seed and action history.

## Decision confirmation

The gameplay owner accepted the complete proposal on 2026-09-21. This confirms that:

1. The human always takes the first turn in the Phase 1 demo.
2. Each normal turn commits exactly one tile.
3. Voluntary passing is unavailable.
4. A tile is drawn at its owner's `TURN_START`, not immediately after the previous placement.
5. The game ends when the board is full or after two consecutive no-tile automatic skips.
6. Equal final scores produce a draw with no tie-breaker.
7. Phase 1 has no endgame bonuses or remaining-tile penalties.

These rules are authoritative for Phase 1 unless this ADR is superseded or explicitly amended.

## Implementation follow-up

1. Update `GAME_SPEC.md` with the approved turn and game-end rules.
2. Implement the pure match-phase state machine and tests.
3. Resolve ADR-004 before implementing the production tile source.
4. Resolve ADR-002 before finalizing the score breakdown and end-of-game verification.
5. Connect UI and AI only through turn intents and committed results.

## Amendments

- 2026-09-21: The initial proposal was accepted without changes.
- 2026-09-22: Superseded in part by ADR-010 (Deck of Six and Multi-Placement Turns). Sections 3 (turn structure), 4 (active tile ownership), 5 (passing and invalid actions), 7 (end conditions) and the active-tile fields of 9 (save) are replaced there: a player now holds a deck of six tiles and may place one or more of them in a single turn, ending the turn explicitly. Implement ADR-010 for those areas; the rest of this ADR stands.
