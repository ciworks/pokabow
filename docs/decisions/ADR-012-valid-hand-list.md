# ADR-012: Valid Hand List

* **Status:** Accepted
* **Date:** 2026-09-23
* **Accepted:** 2026-09-23
* **Owners:** Game design and engineering
* **Decision scope:** Phase 1 core scoring and hand legality
* **Source:** Owner instruction, 2026-09-23
* **Related:** ADR-001 (hand formation), ADR-005 (AI evaluation), ADR-006 (placement), ADR-007 (incremental scoring), ADR-011 (line placement and hand legality)

## Context

ADR-011 section 3 made any ranked rank-frequency hand of two to five tiles legal,
which admitted several shapes the owner no longer wants: a five-tile line of four
Aces and a kicker, a five-tile line of five identical ranks (Five-of-a-Kind), and
every five-tile line that is not a Full House.

The owner replaced the catalogue with an explicit closed list and added two
sequence hands. Four ambiguities were resolved in the same conversation:

1. Five identical ranks stop being a valid hand (previously Five-of-a-Kind, 16).
2. A sequence hand must read in sequence order along the line, not merely contain
   consecutive faces.
3. At five tiles only a Full House (three of one rank plus a pair of another) is
   legal; every other five-tile line is refused.
4. The two sequence hands are worth 5 and 9 points.

This ADR is the authority for which hands exist and what they are worth. Where it
conflicts with ADR-001 section 2 or ADR-011 section 3, this ADR wins.

## Decision

### 1. The closed list of valid hands

Exactly these hands are valid. Any other shape is refused by the placement
validator and can never be scored.

| Hand | Length | Shape |
|---|---|---|
| Pair | 2 | exactly one rank repeated twice |
| Two Pair | 4 | exactly two ranks repeated twice each |
| Three-of-a-Kind | 3 | exactly one rank repeated three times |
| 4-of-a-Kind | 4 | exactly one rank repeated four times |
| 3-straight | 3 | exactly three different ranks in sequence order |
| 4-straight | 4 | exactly four different ranks in sequence order |
| Full House | 5 | exactly one rank three times plus another rank twice |

The list is exact. A hand must be precisely one of the shapes above, at precisely
the length shown, so a shape carrying an unmatched tile is refused even though it
contains a valid smaller hand: `A A K`, `A A A K` and `A A K Q` are all invalid.
At five tiles the *only* legal shape is a Full House (3 + 2), so a five-tile line
of 2 + 1 + 1 + 1, 2 + 2 + 1, 3 + 1 + 1, 4 + 1, or 5 is refused.

Equal ranks must also sit together along the line. A hand whose ranks interleave
is refused however many of each rank it holds, so a five-tile line reading
`Q J Q Q J` is three Queens and two Jacks by count but is not a Full House, and a
four-tile `A K A K` is not a Two Pair. Either group order is legal - `J J J Q Q`
and `Q Q J J J` both count, as do `A A K K` and `K K A A` - but the groups may
not be interleaved. A straight is unaffected, because its ranks are all distinct.
The grouping is judged over the merged line, so a tile that completes a hand must
sit in its own rank's block and not between two of another rank.

Removed from the catalogue: Five-of-a-Kind. Five identical ranks are no longer a
hand and no longer have a point value.

### 2. Sequence hands

The four face ranks form one sequence ladder, lowest to highest:

    Jack, Queen, King, Ace

A sequence hand is three or four tiles whose ranks lie on that ladder and step by
exactly one rank per tile along the line. The line direction may be ascending or
descending, so a sequence hand is legal when it reads forwards or backwards:

* 3-straight: `J Q K`, `K Q J`, `Q K A`, `A K Q`;
* 4-straight: `J Q K A`, `A K Q J`.

A line that holds the same ranks in a non-sequence order is not a sequence hand.
`J K Q` is therefore refused: it is neither in sequence order nor a ranked
frequency hand.

A sequence hand of five tiles cannot exist, because the ladder has only four
ranks. Every five-tile line repeats a rank, so it is judged by rank frequency
only (section 1).

### 3. One category per hand

A hand classifies as exactly one category, the highest one its shape satisfies.

Sequence hands and rank-frequency hands are disjoint: a sequence hand has all
distinct ranks, and every valid rank-frequency hand repeats a rank. No hand can
therefore satisfy both, and no precedence between them is needed.

### 4. Point values

Point values stay data, in `PokerScoreRules`, not in the evaluator (ADR-001
section 4). The approved values are:

| Category | Points |
|---|---:|
| Pair | 2 |
| Two Pair | 4 |
| 3-straight | 5 |
| Three-of-a-Kind | 6 |
| 4-straight | 9 |
| Full House | 10 |
| 4-of-a-Kind | 12 |

No points are awarded for a hand outside the section 1 list. There are no
multipliers.

The values are stored in one array indexed by `ScoringEnums.PokerHandCategory`,
which is declared in ascending point order so the existing validation rule
(stronger categories never award fewer points) still holds.

### 5. Everything else is unchanged

This ADR changes only which hands exist and what they are worth. All of the
following remain in force:

* ADR-011 sections 1, 2, 4 to 9: a move is one contiguous line of two to five
  tiles, may extend committed tiles, caps every connected run at five, and uses
  the swap action;
* ADR-011 section 5: the whole line validates before anything is written;
* ADR-001 section 5 and ADR-007: each distinct canonical hand scores once, the
  player who commits the line receives the points, and scoring stays incremental;
* ADR-001 section 3: the red/black face property plays no part in classification;
* ADR-002: edge-match and edge-cluster awards are untouched.

### 6. Save and rules-version consequences

Score events persist a category *name*, not an enum index (ADR-007 section 5), so
renumbering `PokerHandCategory` does not invalidate a save by itself. The rule
change is versioned instead:

* `PokerScoreRules.SCHEMA_VERSION` becomes 2, because the point table changed;
* `ScoringRules.SCHEMA_VERSION` becomes 3, because the hand catalogue changed.

A match saved under the older rule set carries the older version keys, so
restoring it is refused rather than silently re-scored, and a recorded
`FIVE_OF_A_KIND` award revalidates as an invalid hand on audit, exactly as
ADR-011's amendments already require for an overlong run.

## Alternatives considered

### Treat five identical ranks as Four-of-a-Kind

Keeps the hand legal and avoids a save/data migration, but keeps a hand the owner
explicitly removed from the list, and invents a rule ("five counts as four") that
players cannot see on the board.

### Keep Five-of-a-Kind as a rare legal hand

Retains a one-in-many hand that rewards luck over assembly, and contradicts the
owner's closed list.

### Accept any arrangement of consecutive faces as a straight

Simpler to hold in mind, but the owner requires the line to read in sequence
order, which also keeps a straight visually legible on the board.

### Score a straight inside a longer line

Impossible in practice with four ranks: any five-tile line repeats a rank, so it
is judged by frequency (section 1).

## Consequences

### Benefits

* The valid hands are a short, closed list a player can learn and see.
* The four-rank tile set no longer produces exotic hands such as Five-of-a-Kind.
* Sequence hands give the ladder between Jack and Ace a real role, using the same
  four faces rather than a new suit concept.

### Costs and risks

* A five-tile hand now requires a Full House, so most long lines are refused; a
  4-straight or 4-of-a-Kind line can never grow to five legal tiles.
* Shorter hands dominate, so more scoring events happen on a busy board.
* Old saves made under the previous rule set are refused on restore.
* Any test or AI heuristic that assumed five-tile hands always rank must change.

## Required tests

Automated tests must cover:

* every category in section 1 at every length it may occupy;
* refusal of every shape outside the list, including `A K Q` at three tiles,
  `A A A A K` at five tiles, and `A A A A A` at five tiles;
* sequence order: `J Q K` and `K Q J` legal, `J K Q` refused, for both the
  three-tile and four-tile ladders;
* the point values of section 4, read from the rules resource;
* hand legality through `LineValidator`, not only through the evaluator;
* incremental scoring still agreeing with a full-board scan; and
* `PokerScoreRules` and `ScoringRules` validating at their new schema versions.

## Amendments

* 2026-09-23: Accepted as recorded, following the owner's four-question decision
  conversation. No superseded interpretation was left open.
* 2026-09-23: Owner observed the rival completing a hand laid as `J Q Q J` beside
  a committed Queen, which counts as three Queens plus two Jacks but does not
  read as a Full House. Section 1 now requires each rank's tiles to be adjacent
  along the line: a hand whose ranks interleave is refused. The owner confirmed
  the requirement applies to every hand made of more than one rank, so a four-tile
  `A K A K` is refused as well as a five-tile `Q J Q Q J`. Either group order
  remains legal and a straight is unaffected, because its ranks are all distinct.
* 2026-09-23: Owner tightened section 1 from a minimum-length list to an exact
  list, after observing the AI rival form `K + J + Q + Q`. A hand must now be
  precisely one listed shape at precisely the length shown, so a shape carrying
  an unmatched tile is refused even though it contains a valid smaller hand.
  This removes the pair-plus-kicker shapes `A A K` and `A A K Q` and the
  three-of-a-kind-plus-kicker shape `A A A K`, which the earlier wording had
  admitted. The point values and every other section are unchanged.
