# ADR-010: Deck of Six and Multi-Placement Turns

- **Status:** Accepted
- **Date:** 2026-09-22
- **Accepted:** 2026-09-22
- **Owners:** Game design (owner-directed)
- **Decision scope:** Phase 1 core turn loop and tile supply
- **Source:** owner instruction of 2026-09-22; `GAME_SPEC.md` sections 13.5, 13.6, 13.9
- **Related:** ADR-003 (turn rules and game end), ADR-004 (tile distribution), ADR-005 (AI evaluation), ADR-006 (placement), ADR-007 (incremental scoring architecture)

## Context

The accepted Phase 1 rules give each player **one** active tile, drawn at that
player's `TURN_START`, and each normal turn commits **exactly one** tile
(ADR-003 sections 3 and 4, ADR-004 section 6).

The gameplay owner has decided to replace that with a **deck of six tiles** for
each player, presented as a horizontal spread under the board, from which the
player may play **one or more tiles in a turn**. This gives the player a choice
of which tile to commit instead of a single forced tile, and it changes the
shape of a turn.

Those two changes together supersede several accepted rules, so this ADR
records the replacement explicitly rather than leaving the older documents to
contradict the implementation (AGENTS.md section 15: there must be one clear
source of truth for an important gameplay rule).

## Constraints inherited from the specification and accepted decisions

1. The board is 12 x 12 and holds 144 cells; the shared pot holds exactly 144
   tiles, one per cell (ADR-004 section 1).
2. A placement is committed atomically, and only a committed placement changes
   score (ADR-006 section 6, ADR-007 section 4).
3. Scoring categories, values, one-time windows, and the no-multiplier rule are
   unchanged (ADR-001, ADR-002, ADR-007 constraint 9).
4. Placement legality is unchanged: empty cell, opening cells for the first
   move, then orthogonal connection (ADR-006 sections 2 and 3).
5. Edge colours never restrict placement (ADR-006 section 4).
6. Undrawn pot contents and draw order stay hidden from both the player-facing
   UI and the AI decision interface (ADR-004 section 7).
7. The base game has no score multipliers, and no match state may live in an
   autoload (ADR-007 constraint 9, ADR-008 section 6).

## Decision

### 1. Deck size

Each player holds a deck of exactly `deck_size` tiles, with a Phase 1 default of
**6**. The value is configuration, not a literal in control flow: it lives in a
versioned rules resource alongside the other approved configurable values
(ADR-008 section 12), so a future mode can change it without touching the turn
loop.

### 2. Match setup

`MATCH_SETUP` deals from the one shared pot, in a fixed order:

1. the human's deck is filled to `deck_size`;
2. the AI's deck is filled to `deck_size`.

With the Phase 1 defaults that is 12 tiles dealt at setup, leaving 132 in the
pot. The deal order is deterministic so a replay reproduces the same decks from
the same seed (ADR-004 section 3).

### 3. A turn is one or more placements

A normal turn consists of **one or more** tile placements by the active player:

1. Identify the active player.
2. Ensure that player's deck is stocked (see section 5).
3. Enter the action phase.
4. The active player selects any tile from their deck and a legal empty cell and
   rotation.
5. For a human, display a non-authoritative preview and require confirmation.
6. For the AI, validate its selected move through the same rules interface.
7. Commit the tile through ADR-006's atomic placement operation, which applies
   the score events of ADR-007 to the active player.
8. Record the move in match history.
9. The player may repeat steps 4 to 8 with any remaining tile in their deck, or
   end the turn (section 4).
10. On turn end, refill the deck (section 5), check end conditions (section 7),
    and if the game continues switch active player and increment the turn
    number.

Each placement is its own atomic move with its own score events. A turn is not
one transaction; it is a sequence of independent committed placements, which is
what keeps ADR-006 section 6 and ADR-007 section 4 unchanged.

### 4. Ending a turn

- The active player ends their turn with an **explicit end-turn action**.
- End-turn is available throughout the active player's action phase, including
  before any tile has been placed.
- Ending a turn with zero placements is therefore permitted. This is a narrow,
  deliberate relaxation of ADR-003 section 5's "voluntary passing is not
  supported", and it is required by this design: once a turn may contain several
  placements, the player must be able to say when the turn is over. It is
  recorded here so the older text is not read as forbidding it.
- The turn also ends automatically when the active player holds no tiles and the
  pot cannot supply one, because that player has no legal placement.

### 5. Refill happens at the turn boundary, not per placement

When a turn ends, the active player's deck is topped back up to `deck_size` from
the pot, taking as many tiles as the pot can supply.

This timing is the core of the decision and is deliberate:

- Refilling **after each individual placement** would let a player place a tile,
  refill, place again, and continue until the pot was empty. With multiple
  placements already allowed in a turn, that makes a single turn effectively
  unbounded - one player could place roughly half the board before the opponent
  moved at all.
- Refilling **at the turn boundary** bounds a turn at `deck_size` placements and
  keeps the opponent's turn meaningful, while still delivering the requested
  behaviour: the player continues with a full deck of six.

A deck therefore only ever holds fewer than `deck_size` tiles when the pot can no
longer supply the difference. Undrawn pot contents and draw order remain hidden
(ADR-004 section 7).

### 6. Tiles that may be played in one turn

A player may place at most `deck_size` tiles in one turn, because the deck holds
at most that many and it does not refill mid-turn.

### 7. End conditions

The match ends after resolving the current committed placement when either:

1. **Board full:** all 144 cells hold a committed tile; or
2. **Nothing left to play:** neither player holds a tile and the pot cannot
   supply one.

This replaces ADR-003 section 7's "two consecutive automatic `NO_TILE_AVAILABLE`
skips". That counter assumed a player could be idle with tiles still in the pot
for the opponent; with per-player decks a player can legitimately hold no tiles
while the pot is empty and the board is not yet full, and the old rule would end
the match early. A player who cannot be supplied simply ends their turn, and the
match continues until both players are out of tiles.

Because the pot holds exactly one tile per cell and every tile must eventually be
placed, condition 1 is the normal terminal state, and total tiles placed always
matches total cells occupied.

There is still no early end for score difference, a target score, a fixed turn
limit, or an AI prediction.

### 8. Winner and final score

Unchanged from ADR-003 section 8: each player's final score is the sum of the
committed events attributed to them, the higher total wins, equal totals are a
draw, and there is no endgame bonus, remaining-tile penalty, multiplier, or
tie-breaker. A deck holding unplayed tiles at the end of the match carries no
penalty.

### 9. Move identifiers

ADR-007 section 5 defines a move identifier as `move:<match-id>:<turn-number>`.
With more than one placement in a turn that format is no longer unique, and
uniqueness is what makes duplicate-commit refusal idempotent (ADR-007 section 5).

The identifier becomes:

```text
move:<match-id>:<turn-number>:<placement-index>
```

where `placement-index` is 1-based within the turn. The second placement of turn
3 in match `m1` is `move:m1:3:2`. Score event identifiers keep their existing
shape and inherit the new move identifier unchanged.

### 10. Active tiles, save, and resume

- A player's "active tile" is replaced by that player's deck, holding zero to
  `deck_size` tiles.
- The save record stores each player's deck as an ordered list of tile
  identifiers, together with the pot's next draw index, so a resumed match
  continues with the same decks and the same remaining pot order (ADR-004 save
  requirements, ADR-003 section 9).
- The tile-conservation check of ADR-004's save requirements extends to the new
  locations: every tile identifier must appear exactly once across the remaining
  pot, the human's deck, the AI's deck, and the committed board, and the total
  must still be 144.
- A preview is still never persisted as authoritative state.

### 11. AI behaviour

The AI's candidate source changes from one tile to every tile in its deck
(amending ADR-005 sections 2, 4, 5, and 6, which all assume a single active
tile):

- Legal move generation pairs each deck tile with each legal frontier cell and
  each valid rotation, deduplicating rotationally equivalent candidates as
  ADR-005 section 2 already requires.
- The AI's turn policy is to keep placing with its difficulty strategy until its
  deck is exhausted, then end the turn.
- Easy still selects uniformly at random among legal candidates and never
  evaluates score. Medium and Hard rank candidates with the same sections 5 and
  6 tuples and utilities they already define; only the candidate source grows.
- The AI must never read undrawn pot contents, and its decision randomness
  remains separate from the pot's stream (ADR-004 section 7, ADR-005 section 3).

Performance note: per-decision work grows roughly in proportion to deck size,
because each deck tile can be placed at each frontier cell in each rotation.
ADR-005 section 8's deterministic budgets still bound a decision, but Hard does
more of them per turn. If this proves slow on target hardware, the response is
to tune the section 8 budgets or move analysis off the main thread, which
ADR-008 section 10 already permits - not to change the rules.

### 12. Presentation

The deck is drawn as a horizontal spread of tiles under the board. Selecting a
deck tile is what arms a placement, and the action phase also exposes the
end-turn action. The deck view renders tile data; it does not evaluate legality
or score (ADR-008 section 4, AGENTS.md section 19).

## Alternatives considered

### Refill after every placement

Rejected. Combined with multi-placement turns it removes the turn boundary,
letting one player empty the pot before the opponent moves. See section 5.

### Keep one tile and one placement per turn

Rejected by the owner. It is the existing ADR-003 behaviour and offers no tile
choice.

### A shared hand used by both players

Rejected: it removes the per-player ownership that makes the deck a decision,
and it would let a player see tiles the opponent has effectively reserved.

### Refill at `TURN_START` instead of at turn end

Equivalent in effect and simpler in one respect, but it delays the refill until
the next turn begins, so a player who ends their turn with an empty deck cannot
see what they will hold. Refilling at turn end makes the next turn immediately
readable, which is what the owner asked for.

### Allow unlimited placements with no end-turn action

Rejected: without an explicit end-turn a turn would never end while the player
held tiles, and the opponent would have to be handed control by some other rule.

## Consequences

### Benefits

- The player chooses which tile to commit instead of being forced into one.
- A turn is bounded at `deck_size` placements, so it stays short and legible.
- Each placement keeps the existing atomic commit, scoring, and replay path, so
  ADR-001, ADR-002, ADR-006, and ADR-007 need no rule changes.
- The pot remains the single finite supply of 144 tiles.

### Costs and risks

- Three accepted ADRs are superseded in part, so the documentation must carry
  unambiguous pointers to this decision.
- The AI's per-decision work grows with deck size (section 11).
- Multi-placement turns make a turn longer than the previous one-tile turn, so
  the presentation must make "your turn is still in progress" visible.
- The move identifier format changes, which invalidates any previously saved
  match and any test asserting the old format.

## Required tests

Automated tests must cover:

- setup deals exactly `deck_size` tiles to each player and leaves the pot
  consistent (144 total across pot, both decks, and the board);
- a turn may commit more than one placement before ending;
- each placement in a turn gets a distinct move identifier containing its
  placement index;
- a placement is still validated, committed, and scored exactly as before;
- the deck refills to `deck_size` at turn end, and the number taken equals the
  number played while the pot can supply it;
- a deck smaller than `deck_size` when the pot runs out, and never larger;
- end-turn before any placement is accepted and consumes the turn;
- the turn ends automatically when the player holds no tiles and the pot cannot
  supply one;
- the match ends when the board is full, and when neither player holds a tile
  and the pot is empty;
- 144 placements end the match with every tile placed exactly once;
- save/resume restores both decks and the remaining pot exactly;
- tile conservation across pot, both decks, and the board;
- AI moves are drawn only from its own deck, are always legal, and never read
  undrawn pot contents;
- a full AI turn plays its deck and then ends its turn;
- deterministic replay from the same seed reproduces decks, placements, and
  scores.

## Decision confirmation

The gameplay owner directed this change on 2026-09-22. It confirms that:

1. Each player holds a deck of six tiles, drawn from the shared pot.
2. A player may place one or more tiles from their deck in a turn.
3. A turn ends on an explicit end-turn action, or automatically when the player
   has no tiles and the pot cannot supply one.
4. Both players play from a deck of six.
5. A deck refills to six at the turn boundary.
6. The match ends when the board is full, or when neither player holds a tile and
   the pot is empty.
7. Each placement remains an independent atomic move with its own score events.

Point 5 is the interpretation the implementing engineer applied to the owner's
instruction. The owner's words ("once one or more tiles from that deck are
played, the equivalent number are extracted from the pot") are also compatible
with a per-placement refill, which is rejected in section 5 as degenerate when
combined with multi-placement turns. If the owner intended the per-placement
refill, only the refill trigger changes; the rest of this decision stands.

## Superseded rules

This decision replaces the following specifically, and those sections must not be
read as current:

- **ADR-003 section 3** (a turn commits exactly one tile) and the closing
  sentence that a player cannot place more than one tile per turn.
- **ADR-003 section 4** (at most one active, uncommitted tile per player).
- **ADR-003 section 5** (voluntary passing is not supported) as it applies to
  ending a turn; see section 4 above.
- **ADR-003 section 7** (end conditions, including the two-consecutive-skip rule).
- **ADR-003 section 9** (save fields naming a single active tile per player).
- **ADR-004 section 6** (draw one tile at `TURN_START` only if the player has
  none) - replaced by dealing a deck and refilling it at the turn boundary.
- **ADR-007 section 5** (the `move:<match-id>:<turn-number>` identifier format).

Everything else in those ADRs, including all scoring, placement-legality, and
commit rules, remains in force.

## Implementation follow-up

1. Add the `deck_size` rules resource and deal decks during `MATCH_SETUP`.
2. Extend the session state, turn manager, and commit path as described.
3. Update the move identifier format and its tests.
4. Build the deck presentation and the end-turn action.
5. Extend the AI candidate source and turn policy.
6. Update `GAME_SPEC.md` where it states the one-tile turn.

## Amendments

- 2026-09-22: Accepted on owner direction. Numbered ADR-010 because the decisions
  index reserves ADR-009 for the edge-cluster decision (GAME_SPEC 13.3, 13.4),
  which was delivered as ADR-002.
- 2026-09-22: ADR-011's later owner correction adds a five-tile connected-run
  cap and ends a match when neither current deck has a legal placement. Its
  section 9 supersedes the end-condition wording above where they differ.
