# ADR-001: Poker Hand Formation and Scoring

- **Status:** Accepted
- **Date:** 2026-09-21
- **Accepted:** 2026-09-21
- **Owners:** Game design and engineering
- **Decision scope:** Phase 1 core game
- **Source:** `GAME_SPEC.md` and `iterative_specification.pdf`
- **Related:** ADR-002 (edge clusters), ADR-007 (incremental scoring)

## Context

The source specification requires poker-style scoring based on tile faces and names Pair, Three-of-a-Kind, and Full House as examples. Tiles have one of four ranks (Ace, King, Queen, Jack) and a red/black property. The source does **not** define:

- which board tiles form a hand;
- the number of tiles in a hand;
- whether diagonals count;
- whether hands overlap;
- whether an existing hand can score again;
- the complete hand catalogue or point values;
- whether red/black affects poker hands; or
- how a hand is attributed to a player.

These rules affect placement feedback, incremental scoring, AI evaluation, tests, and save-game data. They must be explicit before the scoring engine is implemented.

## Constraints inherited from the specification

The decision must preserve these confirmed requirements:

1. Poker points are based on tile faces.
2. The face set is Ace, King, Queen, and Jack; each face also has a red/black property.
3. Pair, Three-of-a-Kind, and Full House must be supported.
4. Poker scoring is separate from edge-match and edge-cluster scoring.
5. The base game has no score multipliers.
6. Scoring must support incremental recalculation after a placement.
7. The initial mode is Human vs AI on a 12 x 12 board.

## Decision

### 1. Hand geometry

A poker hand is a **contiguous, straight, orthogonal sequence of five occupied cells**.

- Horizontal and vertical sequences count.
- Diagonal sequences do not count.
- A gap or empty cell breaks a sequence.
- A sequence longer than five is evaluated as every distinct five-cell window.
- Only windows containing the tile placed on the current turn are candidates for new scoring.
- A window is identified canonically by its orientation and ordered cell coordinates.

This rule makes a hand visually understandable, keeps evaluation bounded, and permits local recalculation around the newly placed tile.

### 2. Rank evaluation

Each five-tile window is classified using the frequency of its face ranks. In Phase 1, use only categories that are meaningful with the four-rank tile set:

| Category | Rank-frequency pattern | Example |
|---|---:|---|
| Five-of-a-Kind | 5 | A A A A A |
| Four-of-a-Kind | 4 + 1 | K K K K A |
| Full House | 3 + 2 | Q Q Q J J |
| Three-of-a-Kind | 3 + 1 + 1 | A A A K Q |
| Two Pair | 2 + 2 + 1 | K K Q Q J |
| Pair | 2 + 1 + 1 + 1 | A A K Q J |

The evaluator returns exactly one category: the highest category whose pattern matches. A Full House therefore does not also score as a Pair and Three-of-a-Kind. With five tiles and only four ranks, every complete window contains at least a Pair, so Phase 1 has no High Card category.

### 3. Red/black property

Red/black is **not used for poker-hand classification in Phase 1**. It remains tile metadata for presentation or a future explicitly approved rule. This avoids silently treating a two-color property as conventional poker suits.

### 4. Score values

Point values are data, not hard-coded control flow. Store them in a Godot `Resource` (for example, `PokerScoreRules`) so balancing does not require changes to the evaluator.

Use the following values for the first playable balance pass:

| Category | Points |
|---|---:|
| Pair | 2 |
| Two Pair | 4 |
| Three-of-a-Kind | 6 |
| Full House | 10 |
| Four-of-a-Kind | 12 |
| Five-of-a-Kind | 16 |

No points are awarded for an unclassified window. No multiplier is applied.

### 5. When a hand scores

- After a valid tile placement, evaluate all candidate five-cell windows containing the newly placed tile.
- Score each candidate window only if its canonical identifier has not previously been scored.
- If one placement creates multiple distinct windows, each qualifying window scores once.
- Previously scored windows never score again merely because another tile was placed nearby.
- Attribute all points created by a placement to the player who made that placement, regardless of who placed the older tiles in the window.
- Persist scored window identifiers in game state and in save data.

Because placed tiles are assumed immutable after commitment, a scored window does not later change category. If a future feature permits moving, replacing, or changing tiles, this ADR must be revisited.

### 6. Evaluation result

The rules layer should return data rather than trigger visual effects directly. A result should contain at least:

```gdscript
class_name PokerHandResult
extends RefCounted

var category: PokerHandCategory
var points: int
var cells: Array[Vector2i]
var hand_id: StringName
```

The UI may consume this result for highlights, animation, sound, haptics, and floating-score text. The evaluator must not depend on scene nodes.

## Incremental evaluation

For a newly placed tile at `(x, y)`, inspect only horizontal and vertical five-cell windows that include `(x, y)`. There are at most five candidate windows per orientation and therefore at most ten candidates before bounds and occupancy checks.

The incremental algorithm is:

1. Generate in-bounds five-cell windows containing the placed coordinate.
2. Reject any window containing an empty cell.
3. Build its canonical identifier.
4. Reject it if the identifier is already in the scored-hand set.
5. Count face ranks and classify the pattern.
6. Look up the category's point value.
7. Return qualifying results and record their identifiers when the move commits.

A debug-only full-board scan must produce the same set of canonical windows and total poker score as incremental evaluation.

## Alternatives considered

### Maximal row/column runs of variable length

This resembles word formation in Scrabble, but poker categories normally assume a fixed hand size. It also requires new definitions for how Pair or Full House behaves in runs longer than five.

### Connected clusters of any shape

This overlaps conceptually with edge-cluster scoring and makes hands harder for players to read and for the AI to evaluate. It is not recommended for Phase 1.

### Diagonal hands

Diagonals increase scoring opportunities but weaken the visual connection to the grid and expand the affected search area. They can be reconsidered after playtesting.

### Score every matching subset

Counting all pairs, triples, and other subsets inside one window would stack several awards from the same tiles and behave like a combo/multiplier system. The proposal instead assigns one best category per window.

## Consequences

### Benefits

- Players can see and anticipate a hand as a five-cell line.
- Incremental evaluation has a small, fixed search area.
- Canonical IDs make one-time scoring deterministic and saveable.
- AI difficulty levels can use the same pure evaluator as the human player.
- Balance values remain configurable without duplicating classification logic.

### Costs and risks

- Fixed five-cell hands take time to form and may be rare without suitable tile supply and placement rules.
- A long occupied line can create several overlapping scoring windows from one placement.
- Five-of-a-Kind is possible even though it is not a conventional poker hand.
- With only four ranks, a five-tile all-unique High Card, Straight, and conventional Straight Flush are impossible.
- The red/black property has no scoring role under this proposal.

## Required tests

At minimum, automated tests must cover:

- every supported rank-frequency pattern;
- category precedence, especially Full House versus Pair/Three-of-a-Kind;
- horizontal and vertical windows;
- rejection of diagonal, incomplete, gapped, and out-of-bounds windows;
- all windows in a line longer than five;
- multiple hands created by one placement;
- one-time scoring through canonical identifiers;
- correct player attribution;
- configurable score values;
- equality of incremental and full-board results; and
- deterministic evaluation independent of scene nodes.

## Decision confirmation

The gameplay owner accepted the complete proposal on 2026-09-21. This confirms that:

1. Hands contain exactly five tiles in straight horizontal or vertical lines.
2. One move may score multiple distinct, overlapping five-cell windows.
3. Each canonical window scores only once during the game.
4. The point values in this ADR are the initial balance values.
5. Five-of-a-Kind is a supported category.
6. Red/black remains outside poker-hand scoring in Phase 1.
7. The player who completes a hand receives all points for it.

These rules are authoritative for Phase 1 unless this ADR is superseded or amended through an explicit gameplay decision.

## Implementation follow-up

1. Update `GAME_SPEC.md` with the approved gameplay rules.
2. Implement a pure `PokerHandEvaluator` and configurable `PokerScoreRules` resource.
3. Add the required automated tests before integrating scoring feedback or AI heuristics.
4. Ensure ADR-007 uses the canonical hand identifier and the same full-scan equivalence rule.

## Amendments

- 2026-09-21: The initial proposal was accepted without changes.
