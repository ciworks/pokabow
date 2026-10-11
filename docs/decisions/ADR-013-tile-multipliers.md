# ADR-013: Tile scoring multipliers

* **Status:** Accepted
* **Date:** 2026-09-27
* **Source:** `Enhancements to scoring.txt` and owner clarifications on 2026-09-27
* **Supersedes:** Earlier no-multiplier and four-face/four-edge assumptions where they conflict

## Decision

The valid-hand catalogue and its category points remain. A scored hand awards
`(category points + sum of card values) × card factor × new-edge factor`.
Card values are J=1, Q=2, K=3, A=4, Joker=5. Exactly one card factor applies:
exact same rank and suit ×4, otherwise same suit ×3, otherwise same red/black
color ×2, otherwise ×1. A hand containing Joker uses ×1. Joker is its own rank,
may repeat in frequency hands, has no suit/color, and cannot form a straight.

New-edge factor begins at 1 and adds 1 for each same-color boundary between
consecutive tiles in the scored hand created by the current move. Edge colors
are Blue, Red, Green, and Yellow. Previously committed boundaries do not count.
Same-color edge points and color-specific clusters remain separate.

Suits are tile data: Hearts and Diamonds are red, Clubs and Spades are black.
Generated non-Joker tiles draw a suit within their color. Joker has no suit.
The source document's suit example uses ×3; its `10 * 30 = 30` expression is a
typographical error.

## Implementation and compatibility

Tile DTO, tile-generation rules, and scoring rules versions advance. Older saves
are rejected by version checks because they lack suits and multiplier evidence.
Score events record the factors and newly counted hand boundaries so audits can
verify final-board values; replay verifies the historical timing of those edges.
The AI's representative hidden-tile sample advances to 20 equal-weight tiles:
five ranks in four rotations, using the four allowed edge colors. Each
ordinary rank appears once in each suit; Joker remains suitless.

Affected systems: tile generation and presentation, tile saves, hand scoring,
edge scoring, score audit, AI preview, and score UI. Relevant tests cover factor
priority, Joker, matching-color new boundaries, and preview/commit/audit agreement.

## Amendment — four edge colors (2026-09-28)

The owner constrained tile edges to Blue, Red, Green, and Yellow. Golden is not
an edge color or wildcard. Hand edge factors therefore increase only when the
two touching edge values are equal; no special wildcard case applies. Tile DTO,
tile-generation, and scoring schema versions advance so older saved tile and
score data is not silently interpreted under the changed edge vocabulary and
scoring rule.
