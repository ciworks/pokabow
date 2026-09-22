# ADR-011: Line Placement and Hand Legality

* **Status:** Decided
* **Date:** 2026-09-22
* **Accepted:** 2026-09-22
* **Owners:** Game design and engineering
* **Decision scope:** Phase 1 core placement and turn rules
* **Source:** Owner instruction, 2026-09-22
* **Related:** ADR-001 (poker scoring), ADR-006 (placement), ADR-007 (atomic scoring), ADR-010 (deck and multi-placement turns)

## Context

The owner specified two placement rules:

1. Tiles formed on the board, whether placed directly or formed by adjacency to
   existing tiles, must form valid poker hands.
2. Within one move, the first tile starts a line and every subsequent tile must
   be placed adjacent in a horizontal or vertical orientation with no gaps.

These change placement legality, which ADR-006 previously limited to "empty cell
plus orthogonal adjacency", and they make poker rank patterns a legality
condition rather than only a scoring bonus (ADR-001). ADR-010's turn model also
assumed a turn was several independently committed single-tile placements.

The owner resolved the ambiguities in a four-round decision conversation. This
ADR records the result. It is the authority for placement and turn shape from
this point; where it conflicts with ADR-006 or ADR-010, this ADR wins.

## Decision

### 1. A move is one line

A move places two or more of the active player's deck tiles as a single line:

* all tiles lie in one row or one column (one orientation, never mixed);
* the line is contiguous: no gaps between the tiles;
* the line grows from the first tile placed, which fixes the orientation.

A single-tile move is not legal, because rule 1 requires a formed hand and a
single tile cannot form one (section 4).

### 2. A move may extend an existing line

The line may include tiles already committed to the board. Placing a third Ace
beside a committed pair of Aces is legal, and the hand is judged over the whole
merged line, not only the tiles placed this move. The placed tiles must still
form one contiguous extension of the merged line.

### 3. Hand legality

The merged line formed by the move must be a valid poker hand. Judged over the
canonical face ranks (Ace, King, Queen, Jack) by rank frequency, a valid hand is
a line whose ranks contain a repeated rank, that is at least a pair:

| Line length | Legal | Illegal |
|---|---|---|
| 2 | A A | A K |
| 3 | A A K, A A A | A K Q |
| 4 | A A K Q, A A A K, A A A A | A K Q J |
| 5 or more | always legal | none |

With only four ranks, five or more cells cannot all hold distinct ranks, so every
line of five or more is legal. The shortest legal line is a pair of equal ranks.

The hand category (pair, two pair, three-of-a-kind, full house, four-of-a-kind,
five-of-a-kind) is classified by the same rank-frequency rules ADR-001 section 2
already defines, using the merged line as the hand.

### 4. The opening move

The opening move on an empty board is not exempt: it must form a valid hand, so
it must place at least two tiles of equal rank as a contiguous line. A player who
holds no such pair cannot open and must use the swap action (section 6).

### 5. Validation and atomicity

Legality is judged when the line is assembled, and the whole line commits once,
as a single atomic move:

* nothing is written to the board, the ledger, the scored-window set, or the
  history until the assembled line is validated;
* a rejected line changes nothing at all, and the player keeps their tiles and
  may reassemble;
* a committed line is immutable, as ADR-006 section 5 already requires.

This replaces ADR-007 section 4's per-tile transaction with a per-move
transaction. The transaction still performs ADR-007's steps in order; only the
unit changes from one tile to one line. Score events are attributed to the player
who committed the line, and the move is one entry in the history with one move
identifier.

### 6. Swap action

When the active player cannot or does not wish to form a legal line, they may
swap: return any number of their deck tiles to the pot and draw the same number
of replacements. A swap uses the player's whole turn and passes play to the
opponent. A swap cannot place a tile and cannot score.

Swapping requires the pot to hold at least as many tiles as are returned. When
the pot cannot supply the whole swap, the swap is refused and the player keeps
their tiles.

### 7. Turn model

A turn is exactly one move: either one committed line (section 1) or one swap
(section 6). Committing the line or resolving the swap ends the turn and passes
play to the opponent. This supersedes ADR-010 section 3's "one or more
placements ended by an explicit End Turn action"; the explicit end-turn action is
removed, and there is one move per turn.

### 8. Decks, dealing, and refill

ADR-010 sections 2, 5, and 6 still govern the deck: each player holds six tiles
dealt from the shared pot at setup, and a player's deck is topped back up to six
at their turn boundary, taking only what the pot can supply. A line consumes
several deck tiles at once, so a deck is refilled by as many tiles as the line
used, capped by the pot.

### 9. End conditions

ADR-010 section 7 still governs: the match ends when every cell holds a committed
tile, or when neither player holds a deck tile and the pot cannot supply one.
Because a player may always swap while the pot has tiles, an unplayable hand is
handled by swapping rather than by ending the match.

### 10. Scoring is unchanged

ADR-001 and ADR-002 scoring is untouched. Committed five-cell windows still score
once each through canonical window identifiers, matching boundaries still award
+1, and cluster milestones still award flat entitlement deltas. Rule 3 restricts
where tiles may be placed; it does not change what a placement scores. A line may
score several windows, exactly as before.

### 11. Presentation consequences

The player assembles the line before committing, so the interface needs a
staging state: tiles chosen from the deck are shown on the board as a pending
line, with validity feedback, and a single confirm commits the whole line.
Rotating a tile updates the pending line without writing to the board. Cancel
returns every staged tile to the deck.

### 12. AI consequences

The AI's move generation changes from "one tile per candidate" to "one line per
candidate": it must enumerate legal lines from its deck rather than single
placements. ADR-005's budgets and beams still bound the search; the candidate
generator must apply rule 3 so it never proposes an illegal line.

## Superseded sections

* ADR-006 section 3 (later placements) - connectivity is now line-shaped per
  sections 1 and 2.
* ADR-006 section 5 (preview and confirmation) - confirmation now commits a whole
  line, per section 5.
* ADR-006 section 8 (board-full and no-move state) - an unplayable hand swaps
  rather than ending the match, per sections 6 and 9.
* ADR-007 section 4 (atomic score transaction) - the transaction unit is a whole
  move, per section 5.
* ADR-010 section 3 (deck of six and multi-placement turns) - a turn is one move,
  per section 7. Its sections 2, 5, 6, and 7 still apply as section 8 records.

## Consequences

### Benefits

* Placement is legible: a turn is one visible line.
* Poker rank patterns now drive play, not only scoring, so hand building is the
  game rather than a bonus.
* Whole-line commits make the board transition unambiguous and keep rejected
  moves free of side effects.
* The swap action removes dead hands without inventing a pass.

### Costs and risks

* The per-move transaction replaces per-tile atomicity, so ADR-007's tests,
  ADR-010's turn tests, and the AI's candidate generation all need revision.
* A one-move turn means far fewer turns per match, so turn-count expectations in
  existing tests are invalidated.
* The opening move requires a pair, which makes the first turn depend on the
  dealt hand; the swap action is the escape hatch and must be reachable from the
  first turn.
* Save data changes: a move record now carries several placed tiles rather than
  one.

## Required tests

Automated tests must cover:

* a legal line in each orientation, and rejection of a mixed-orientation move;
* rejection of a move with a gap, and of a diagonal-only continuation;
* every legal and illegal line in the section 3 table, including the shortest
  legal (a pair) and the all-distinct short lines;
* extending an existing board line, judged over the merged line;
* the opening move requiring a pair, and being refused when the held tiles
  cannot form one;
* whole-line atomicity: a rejected line leaves board, ledger, windows, history,
  deck, and turn state unchanged;
* one move identifier and one history entry per committed line;
* deck refill by the number of tiles the line consumed, capped by the pot;
* the swap action: any number, replacements equal to the number returned, turn
  consumed, play passed, and refusal when the pot cannot supply it;
* a turn consisting of exactly one move, with no end-turn action;
* scoring unchanged for a line that completes several windows;
* both end conditions unchanged;
* AI move generation proposing only legal lines, and never an illegal one; and
* a full match played to a verified result under the new rules.

## Amendments

* 2026-09-22: Accepted as recorded, following the owner's four-round decision
  conversation. No superseded interpretation was left open.
