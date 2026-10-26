# ADR-022: Remove Jokers and wildcard hands

**Status:** Decided, implemented 2026-10-23

The game uses four tile ranks: Ace, King, Queen, and Jack. Every tile has a red
or black face and one of the four suits. Generation, AI samples, poker hand
classification, card values, the board, and score feedback use those printed
ranks directly. There is no Joker tile, wildcard rank assignment, or player
choice of rank.

This supersedes ADR-014 and ADR-021 and the Joker-specific parts of ADR-013.
The shared pot remains 52 tiles and the other scoring rules remain unchanged.
Tile generation, scoring, AI sample, and tile-save versions advance. Existing
saved matches from the five-rank rules are rejected rather than silently
reinterpreted; online matchmaking uses a new rules version.
