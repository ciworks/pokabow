# ADR-011: Line Placement and Hand Legality

* **Status:** Decided
* **Date:** 2026-09-22
* **Accepted:** 2026-09-22
* **Owners:** Game design and engineering
* **Decision scope:** Phase 1 core placement and turn rules
* **Source:** Owner instruction, 2026-09-22
* **Related:** ADR-001 (poker scoring), ADR-006 (placement), ADR-007 (atomic scoring), ADR-010 (deck and multi-placement turns)

## Context

Amendment (2026-10-05): [ADR-017](ADR-017-turn-timer.md) adds a 60-second
deadline. A timeout ends the turn without a line or swap; unconfirmed tiles stay
in the player's deck. Other placement, scoring, and match-end rules are unchanged.

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

A move places one or more of the active player's deck tiles as a single line.
The opening move needs at least two newly placed tiles; later a single tile may
complete a hand with committed tiles:

* all tiles lie in one row or one column (one orientation, never mixed);
* the line is contiguous: no gaps between the tiles;
* the line grows from the first tile placed, which fixes the orientation;
* its merged hand, including committed tiles it joins, contains at most five
  tiles (later owner correction).

A single tile alone is not a hand. It is legal only when its merged line with
committed tiles has at least two tiles and a ranked poker category (section 4).

### 2. A move may extend an existing line

The line may include tiles already committed to the board. Placing a third Ace
beside a committed pair of Aces is legal, and the hand is judged over the whole
merged line, not only the tiles placed this move. The placed tiles must still
form one contiguous extension of the merged line.

### 3. Hand legality

The merged line formed by the move must be a valid poker hand. Judged over the
canonical face ranks (Ace, King, Queen, Jack) by rank frequency, valid hands
have two to five tiles and one of these ranked combinations:

| Length | Valid rank-frequency patterns | Examples | Invalid example |
|---|---|---|---|
| 2 | Pair (2) | A A | A K |
| 3 | Pair (2+1), Three-of-a-Kind (3) | A A K; A A A | A K Q |
| 4 | Pair (2+1+1), Two Pair (2+2), Three-of-a-Kind (3+1), Four-of-a-Kind (4) | A A K Q; A A K K; A A A K; A A A A | A K Q J |
| 5 | Pair (2+1+1+1), Two Pair (2+2+1), Three-of-a-Kind (3+1+1), Full House (3+2), Four-of-a-Kind (4+1), Five-of-a-Kind (5) | A A K Q J; A A K K Q; A A A K Q; A A A K K; A A A A K; A A A A A | none with four ranks |

High Card is not valid. Red/black is not a poker suit and does not create a
Flush. With four ranks, a five-tile hand always has a repeated rank. A move
that creates a connected run longer than five tiles in either direction is
invalid. Every horizontal or vertical run of at least two tiles touched by a
new tile must classify as a ranked hand. A valid perpendicular hand scores as
a distinct hand.

### 4. The opening move

The opening move on an empty board is not exempt: it must form a valid 2–5 tile
hand. The shortest opening is a pair. A player who cannot form any valid opening
hand may use the swap action (section 6).

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

The later owner correction adds an end condition: after a turn, the match ends
when neither player's current deck can form any legal placement under the shared
line validator. A player who alone has no legal placement may still swap when
the pot can supply replacements. The earlier full-board and exhausted-supply
conditions remain, though a legal full board is unreachable with runs capped
at five tiles.

When exactly one player's held deck has no legal placement and the pot cannot
supply a complete swap for that deck, that player's turn is skipped and play
passes to the opponent with the notice `No valid move available, now opponents
turn`. If neither deck has a legal placement, the match ends under the condition
above instead of skipping into an unplayable turn.

### 10. Scoring

The 2026-09-22 amendment extends poker scoring to valid two-, three-, and
four-tile hands. Every newly formed distinct valid hand awards its existing
ADR-001 category value once. If a scored hand is extended, its new larger hand
may award its category value once; the earlier award is not removed. Distinct
hands formed by one move, including perpendicular hands, each score once.
Canonical hand IDs must distinguish length so growth does not reuse the prior
hand's ID. Five-of-a-Kind remains valid for five identical ranks and awards 16.

ADR-002 edge and cluster awards remain unchanged: +1 per new matching boundary
and flat cluster entitlement deltas. There are no multipliers.

### 11. Presentation consequences

The player assembles the line before committing, so the interface needs a
staging state: tiles chosen from the deck are shown on the board as a pending
line, with validity feedback, and a single confirm commits the whole line.
Rotating a tile updates the pending line without writing to the board. Cancel
returns every staged tile to the deck.

For the current interface, a staged tile remains visible at its board cell even
when the line is incomplete or invalid, with a separate validity treatment. It
disappears from the visible deck row while staged and reappears when that tile is
dragged off the board or when the line is cancelled. An unconfirmed tile may also be
dragged to another free cell, which moves it in the line and carries its rotation
with it; the three outcomes are resolved on release, because a press on a staged tile
could still become a turn, a move, or a removal. The application keeps staged
tile identities in the match deck until a valid whole-line commit, preserving
section 5's atomicity and tile conservation. This is a presentation/state-flow
design; it adds no placement or scoring rule.

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
* 2026-09-22: Documented the owner-directed staged-tile board/deck presentation.
  Headless UI integration tests passed; device visual QA remains open. No gameplay
  rule was changed.
* 2026-09-22: Owner replaced the pair-only phrasing with ranked poker hands of
  two to five tiles, allowed longer connected runs, approved scoring shorter hands
  with existing category values and scoring each larger or distinct perpendicular
  hand once, and retained Five-of-a-Kind. This amendment supersedes the earlier
  section 3 and section 10 wording and the fixed-five scoring scope in ADR-001.
  Runs of two to five score as one maximal hand; longer runs score distinct
  five-tile windows containing newly placed tiles. Scoring schema version 2
  distinguishes these awards from saves made under the previous scoring rule.
* 2026-09-22: Owner corrected the run-length interpretation after observing an
  AI move extend a scored five-tile hand to seven tiles. Such extensions are
  illegal for both players. The shared validator now caps every connected run
  through a newly placed tile at five, including perpendicular runs. This
  supersedes the earlier allowance for longer runs. The owner specified that a
  match ends when neither player's current deck has a legal placement. A full
  board remains an end condition but is unreachable under the five-tile cap.
  Restoring a saved match revalidates each recorded move against the current
  placement rule, so an older save containing an overlong run is rejected.
* 2026-09-22: Owner allowed a one-tile move after the opening when the tile and
  committed board tiles form a valid hand of at least two tiles. The opening
  still needs two or more newly staged tiles.
* 2026-09-22: Owner confirmed that rank frequency, rather than rank adjacency
  within a line, determines poker classification. A horizontal A A K K hand may
  grow to a Full House with one K at either end; a K placed perpendicular to a
  board K forms a separate Pair.
* 2026-09-22: Placement validation checks every connected run touched by a new
  tile, including modified perpendicular runs. An unranked run rejects the
  whole move before board or score changes.
* 2026-09-23: Owner clarified that section 1's no-gap rule is judged over the
  MERGED line, not over the staged tiles alone. A move may place tiles on both
  sides of a committed tile, so the staged set may hold a hole that a committed
  tile fills; the merged line must still be gapless, and a span containing a
  genuinely empty cell is refused as before. This supersedes the earlier
  reading that the staged tiles themselves had to be contiguous. Hand
  classification is unchanged: it remains the ADR-012 section 1 exact list,
  judged over the merged line in the order its tiles sit along it, so an
  arrangement whose equal ranks interleave is still refused.
* 2026-09-23: ADR-012 supersedes section 3's hand table and section 10's scoring
  scope. Valid hands are now the closed seven-item list of ADR-012 section 1,
  which adds 3-straight and 4-straight, requires a sequence hand to read in
  sequence order along the line, removes Five-of-a-Kind, and leaves the Full
  House as the only legal five-tile hand. Section 1's line geometry, section 2's
  merged-line rule, sections 4 to 9, and ADR-002's edge and cluster awards are
  unchanged.
