> Superseded by ADR-022 (2026-10-23). This decision is retained as history.

# ADR-021: Joker rank substitution in poker hands

* **Status:** Accepted
* **Date:** 2026-10-23
* **Source:** Owner approval of the automatic, rank-only, per-hand recommendation
* **Supersedes:** ADR-013's Joker-as-own-rank poker classification rule

## Decision

A Joker substitutes for one of Jack, Queen, King, or Ace when classifying each
completed two- to five-tile poker hand. The evaluator tries every assignment
for the Jokers in that hand, applies the existing ordered-straight and grouped-rank
rules, and selects the legal category with the greatest category point value.
Equal-scoring assignments use the first assignment in Jack, Queen, King, Ace
order, walking the hand from its first cell to its last. If no assignment produces
one of the seven approved hands, the hand is invalid.

Each hand is resolved independently. A Joker at the crossing of two scored hands
may stand for different ranks in those hands. Its physical tile remains a Joker
on the board; no rank is locked to the tile or chosen by a player. The chosen
rank for each hand is recorded with its score event so preview, score feedback,
replay, and audit can explain the award.

Substitution changes poker classification only. A Joker retains card value 5,
has no suit or red/black face color, and forces the hand's card factor to 1.
Its printed and rotated edge colors remain ordinary physical edges. The hand
catalogue, category points, new-edge factor, separate matching-edge points,
cluster bonuses, and four-Joker pot cap are unchanged.

## Compatibility

The scoring rules version advances. Older saved matches and score ledgers are
rejected under the new rules rather than silently reinterpreted. Online clients
and the server must run the same scoring rules version before accepting moves.
