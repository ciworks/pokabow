# GAME_SPEC.md

# Pokabow Game Specification

## 1. Document Purpose

The game's name is **Pokabow**, as decided by the owner on 2026-10-05.
Use **Pokabow** in prose and **POKABOW** in uppercase logo artwork. The name has
seven letters: P O K A B O W. This supersedes the earlier spelling in brand copy.
Existing repository paths, asset filenames, configuration keys, and saved-data
identifiers retain their actual names until separately migrated; documentation
must quote those identifiers accurately. This documentation update does not
itself rename runtime labels or identifiers.

This document is the source of truth for the approved game design and technical requirements for the project.

The approved visual standard is [Pokabow Design System — Modern Tabletop](DESIGN_SYSTEM.md),
decided on 2026-10-17 in [ADR-020](decisions/ADR-020-modern-tabletop-design-system.md).
It governs all new or redesigned UI elements, pages, graphics and layouts.
Visual approval is separate from runtime implementation status.

The game is a mobile, turn-based 2D tile-placement game inspired by Scrabble and Poker.

The initial launch/demo mode is Human vs AI.

The game is being developed with Godot 4.6.

This document is derived from the project's initial specification document. Where the source specification does not define a detail, that detail is intentionally left unspecified rather than invented.

---

# 2. Core Gameplay

## 2.1 Game Type

- Turn-based 2D tile placement game.
- Inspired by Scrabble and Poker.
- Mobile-first.
- Initial demo: Human vs AI.

## 2.2 Board

- Board size: 12×12.
- The board may be represented using a 2D array or Godot TileMap.
- Tiles may only be placed into empty cells.
- Placement supports snap-to-grid.
- Tile rotation is supported.
- Adjacency must be tracked for edge and cluster bonus calculations.

## 2.3 Objective

The objective is to:

1. Form poker hands using placed tiles.
2. Maximize edge color bonuses.
3. Maximize the resulting score.

## 2.4 Base Scoring

The base game has:

- Poker-hand points based on faces.
- Edge matching bonus: +1 point per matching edge.
- Additional flat points for edge clusters.
- The scoring enhancement in section 5.7 adds hand multipliers.

---

# 3. Tile System

## 3.1 Tile Properties

Each tile has:

| Property | Values / Notes |
|---|---|
| Face | Ace, King, Queen, Jack, Joker |
| Face Color | Red / Black; Joker has neither |
| Suit | Hearts, Diamonds, Clubs, Spades; Joker has no suit |
| Edges | Top, Right, Bottom, Left |
| Edge Colors | Blue, Red, Green, Yellow |
| Rotation | 0°, 90°, 180°, 270° |

## 3.2 Tile Rotation

Tiles support four orientations:

- 0°
- 90°
- 180°
- 270°

The tile's current orientation determines which edge color occupies each board-facing edge.

The tile system must expose functionality equivalent to:

```gdscript
get_rotated_edges()
```

This returns the tile's edges in its current orientation.

## 3.3 Tile Generation

New tiles are generated using:

- Random face.
- Random red/black color and suit for non-Jokers; Joker has neither.
- Random edge colors.
- Initial rotation of 0°.

The source specification does not define probability distributions or weighting for faces or edge colors. Do not introduce such weighting without an explicit design decision.

### 3.4 Joker supply (decided 2026-09-27)

One pot contains at most 4 Joker-ranked tiles (ADR-014). Joker is drawn at the
ordinary rank rate until that allowance is spent, after which the remaining
tiles draw from the other four ranks only. The allowance is the `max_jokers`
value of the versioned tile-generation rules resource, never a literal in code.

Joker supply is capped (decided 2026-09-27, ADR-014): one generated pot holds at
most 4 Joker-ranked tiles, set by `max_jokers` on the versioned tile-generation
rules. While the allowance is unspent Joker is drawn at its configured rank
weight; once it is spent the remaining tiles draw from the ordinary ranks only.
Scoring is unchanged - card values and factors remain as section 5.7 defines
them.

---

# 4. Board System

## 4.1 Grid

The game board is a 12×12 grid.

The board should maintain a representation of:

- Cell occupancy.
- Tile position.
- Tile orientation.
- Adjacency relationships required for scoring.

## 4.2 Placement

A placement must:

- Target an empty cell.
- Snap to the grid.
- Respect the tile's current rotation.
- Update board adjacency information.

Occupied cells cannot receive another tile.

## 4.3 Placement Validation

The board system is responsible for determining whether a proposed placement is valid.

The specification explicitly states that only empty cells are allowed for placement.

Other placement restrictions are not defined in the source specification and must not be invented without a design decision.

**Later decided rule:** ADR-011 defines a move as one contiguous line. An
opening move stages at least two tiles; later moves may stage one tile when it
completes a valid hand with committed board tiles. A formed hand has two to five
tiles and must classify as a
ranked poker combination; High Card is not valid. The entire move is validated
and committed atomically. ADR-011 supersedes the earlier single-tile placement
interpretation where they conflict.

## 4.4 Adjacency

The board must track adjacent tiles so that the scoring system can determine:

- Matching edges.
- Edge clusters.
- Affected areas after a tile placement.

## 4.5 Incremental Scoring Support

The board should support identifying the tiles and relationships affected by a placement.

Scoring should recalculate only affected tiles/areas rather than unnecessarily recalculating the complete board after every move.

A full-board scoring path should remain possible for validation/testing.

---

# 5. Scoring System

## 5.1 Overview

Scoring consists of:

1. Poker-hand scoring.
2. Edge-match scoring.
3. Edge-cluster scoring.

Hand scoring also uses the card values and multipliers in section 5.7.

## 5.2 Poker Hands

The game evaluates poker-style hands based on tile faces.

The source specification explicitly mentions:

- Pair
- Three-of-a-Kind
- Full House
- Other poker hands

The exact complete poker-hand hierarchy and point values are not defined in the source specification.

Until those values are explicitly approved, do not invent them.

## 5.3 Poker Hand Evaluation

The scoring system must be capable of:

- Identifying applicable poker hands.
- Calculating the associated score once hand values have been defined.
- Supporting the game's tile face values.

The exact definition of which tiles constitute a hand is not specified in the source document and requires an explicit design decision if implementation requires it.

**Later decided rule (ADR-012, 2026-09-23; supersedes ADR-001 section 2 and the
ADR-011 section 3 hand table):** A valid hand is a contiguous straight line of
two, three, four, or five tiles that classifies as one of a closed list of seven
hands. Anything else is refused by the placement validator and can never be
scored. The closed list, with the lengths at which each is legal, is:

| Hand | Length | Shape |
|---|---|---|
| Pair | 2, 3, 4, 5 | one rank repeated; the remaining tiles are single ranks |
| Two Pair | 4 | two ranks repeated twice each |
| Three-of-a-Kind | 3, 4 | one rank repeated three times; remaining tiles single |
| 4-of-a-Kind | 4 | one rank repeated four times |
| 3-straight | 3 | three different ranks in sequence order |
| 4-straight | 4 | four different ranks in sequence order |
| Full House | 5 | one rank three times plus another rank twice |

The length column is exhaustive, so a Five-of-a-Kind is no longer a hand and no
longer has a point value, and a five-tile line is legal only as a Full House. A
five-tile line of 3+1+1, 2+2+1, 4+1, or 5 is refused. No unmatched High Card
line is valid.

The four face ranks form one sequence ladder, lowest to highest: Jack, Queen,
King, Ace. A sequence hand must read in sequence order along the line, ascending
or descending: 3-straight is `J Q K`, `K Q J`, `Q K A`, or `A K Q`, and 4-straight
is `J Q K A` or `A K Q J`. A line holding the right faces in the wrong order
(`J K Q`) is refused, and no five-tile straight exists because the ladder has
only four ranks.

Approved point values, stored as data in `PokerScoreRules`: Pair 2, Two Pair 4,
3-straight 5, Three-of-a-Kind 6, 4-straight 9, Full House 10, 4-of-a-Kind 12. No
points are awarded for a hand outside the list. Section 5.7 adds multipliers to
the category points and card values of valid hands.

A move is rejected if its merged line or a perpendicular connected run through a
newly placed tile would exceed five tiles. Every touched run of at least two
tiles must be a hand from the closed list, including modified perpendicular runs.
Runs of two to five score
as one maximal hand. Each newly formed
distinct hand scores its category's point value once, including a
larger hand formed by extending a previously scored hand. Distinct perpendicular
hands completed by the same move also score. Red/black remains outside poker
classification. Section 5.7 adds color, suit, exact-card, and new-edge multipliers.

**Later decided ending rule (2026-09-22):** The match ends when neither player's
current deck can make a legal placement. This check uses the same placement
validator as human and AI moves. A full board remains an end condition, though
the five-tile connected-run cap makes it unreachable in ordinary play.

When exactly one player's current deck has no legal placement and cannot be
swapped from the remaining tile supply, skip that player's turn, show `No valid
move available, now opponents turn`, and hand play to the opponent. When neither
player has a legal placement, the match ends under the rule above.

## 5.4 Edge Matching

When adjacent tile edges have the same ordinary color:

- Award +1 point per matching edge.

The edge colors are:

- Blue
- Red
- Green
- Yellow

Matching must use the tiles' current rotated edge positions.

## 5.5 Edge Clusters

Connected groups of relevant matching edges can produce an additional flat bonus.

Cluster detection should use an adjacency search such as:

- Flood-fill
- Equivalent adjacency traversal

The exact cluster bonus value and the precise definition of a cluster are not specified in the source document and must be explicitly defined before final implementation.

## 5.6 Incremental Scoring

Incremental scoring is required and is intended to be suitable for mobile.

After a placement, the scoring system should recalculate only affected scoring regions.

The system should support comparison between:

- Incremental score calculation.
- Full-board score calculation.

These should produce equivalent results for the same board state.

## 5.7 Tile scoring enhancement (decided 2026-09-27)

`Enhancements to scoring.txt` authorizes card values, matching-card multipliers,
and matching-edge multipliers. The owner clarified the interactions with existing
rules on 2026-09-27.

For each newly scored valid hand, add its existing category points (section 5.3)
to its card values: Jack 1, Queen 2, King 3, Ace 4, Joker 5. Multiply this sum by
one card-match factor and then by its edge factor. The card factor is 4 when every
tile has the same rank and suit, otherwise 3 when every tile has the same suit,
otherwise 2 when every tile has the same red/black color, otherwise 1. These
factors never stack. A hand containing a Joker always has card factor 1.

Joker is its own rank. Repeated Jokers can form frequency hands under the existing
hand list. Joker is outside the Jack–Queen–King–Ace straight ladder, has no suit
or red/black color, and does not substitute for another rank.

The hand edge factor starts at 1. For each boundary between consecutive tiles in
that hand that the current move creates, add 1 when the touching edges have the
same color. Edge colors are limited to Blue, Red, Green, and Yellow. Existing
boundaries do not contribute again when a later move extends a hand. Only
boundaries inside the scored hand count, even when the move creates other
adjacent matches.

The existing +1 per same-color edge and flat color-specific cluster bonuses
remain separate. The source document's `10 * 30 = 30` suit example is a typo:
suit factor 3 yields 30.

---

# 6. AI System

## 6.1 AI Players

The initial game includes AI opponents.

Three difficulty levels are specified:

- Easy
- Medium
- Hard

The source specification does not state which level a new game starts on. That
default is a project decision (ADR-005 amendment of 2026-09-27): a fresh match
begins on **Easy**, and the player may select any of the three from the HUD
difficulty picker.

## 6.2 Easy

Easy AI behavior:

- Select a random valid placement.
- Select a random valid rotation.

The source specification does not define additional Easy AI behavior.

## 6.3 Medium

Medium AI behavior:

- Prioritize poker-hand opportunities.
- Consider edge matches.

The exact evaluation weights and search depth are not specified.

## 6.4 Hard

Hard AI behavior:

- Plan approximately 1–2 turns ahead.
- Attempt to block the player.
- Attempt to maximize its own score.

The exact search algorithm, evaluation function, tie-breaking behavior, and computational budget are not specified.

## 6.5 AI Integration

AI should operate against game-state and game-rule systems rather than directly depending on visual presentation.

AI decisions should produce valid game actions such as:

- Placement.
- Rotation.

The board/game systems remain responsible for validating and applying those actions.

---

# 7. Mobile UX & Feedback

Screen orientation (decided 2026-10-05): the game is portrait-only, including
splash, hub, and matches. Use a 540x960 reference canvas with aspect-preserving
scaling. Taller phones expand the logical canvas vertically to fill the available
height (responsive portrait update, 2026-10-12); the 540x960 canvas is a reference,
not a fixed aspect ratio. Wide windows retain a portrait play area with unused
space at the sides; device rotation must not enable landscape gameplay.

## 7.1 Input

The mobile interaction model includes:

- Tap to select.
- Drag to move.
- Rotation button and/or gesture.

Board navigation (decided 2026-10-06): drag the board to pan and use a two-finger
pinch for continuous zoom between the full-board 1x view and close 2x view.
The close-view target adapts to viewport width, showing the maximum number of
columns that preserves 64 logical pixels per cell, capped at 12 columns and 2x.
Pinching remains available up to 2x. Zooming changes only the view and cancels
any pending tile-drag gesture without changing staged tiles.
The configured `mouse_wheel_zoom_in` and `mouse_wheel_zoom_out` actions follow
the adaptive close-view and full-board 1x steps and stop at their respective zoom
limits.

## 7.2 Placement Feedback

The UI should:

- Highlight valid placements.
- Provide clear feedback for tile positioning.
- Support snap-to-grid behavior.

**Implemented presentation of ADR-011 staging:** A selected deck tile appears at
its staged board cell even while the line is incomplete or invalid, with separate
validity feedback. The visible deck row leaves staged tiles' slots vacant and shows them
again if they are un-staged or the pending line is cancelled. As requested on
2026-10-17, dropping a tile back between rack tiles (or at either end) inserts it
there and shifts the intervening slots into the new order. The authoritative
match deck retains those tiles until the valid line commits. This display flow
does not add a gameplay rule.

Decided and implemented (2026-10-17): successfully dropping a tile onto the
board from the full-board 1x view switches to 2x and centers the destination
cell as far as the board boundaries allow. This also applies when repositioning
a staged tile. Drag previews, refused drops, rotation, and rack returns do not
trigger this camera change; existing close or intermediate pinch zoom is retained.
After a committed hand's score feedback and replacement-tile animations finish,
the view returns to the centered full-board 1x overview. This applies to both
players' committed hands. A new placement takes priority over a camera reset
still waiting for the preceding hand's effects.

## 7.3 Edge and Cluster Feedback

The game should visually communicate:

- Edge matches.
- Edge clusters.

The source specification suggests:

- Animation.
- Particle effects.

Visual treatment follows [the Modern Tabletop design system](DESIGN_SYSTEM.md)
(ADR-020): restrained effects, readable tile faces and the established four edge
colours. Preserve scoring feedback and reduced-motion behaviour. Exact effect
timing and device tuning remain implementation details to validate.

## 7.4 Score Feedback

The UI should provide floating score popups for:

- Poker-hand points.
- Edge bonuses.

After a committed hand awards points, the game screen's top label should state
which player scored and the combined point total for that move.

## 7.5 Haptics

Optional haptic feedback is supported.

Haptics should not be required for the core game to be playable.

## 7.6 Visual design standard (Decided, 2026-10-17)

[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) defines the approved palette, typography,
spacing, tiles, avatars, buttons, page structure, component states and UI review
requirements. Its written requirements take precedence over the illustrative
reference and earlier styling notes. Read it for every new or redesigned screen,
including screens absent from the reference image. Current gameplay and feature
contracts remain unchanged; existing screens migrate incrementally. No runtime
visual migration is implied by this documentation decision.

---

# 8. Game Modes & Engagement

## 8.1 Base Mode

The base game mode is:

**Human vs AI**

This is the initial/demo mode.

## 8.2 Optional Engagement Features

The source specification identifies the following as optional/future engagement features:

- Timed challenges.
- Pre-set boards.
- Daily/weekly events.
- Streak rewards.

## 8.3 Achievements (Decided, 2026-09-29)

Achievements are account-wide milestones awarded from committed Human-vs-AI
match outcomes and scoring events. They do not alter legality, scores, tile
generation, or match outcomes. The first achievement set is:

| ID | Name | Unlock condition |
|---|---|---|
| `first_hand` | First Deal | The human scores any valid poker hand. |
| `straight` | Straight Shooter | The human scores a 3-straight or 4-straight. |
| `full_house` | Full House | The human scores a Full House. |
| `edge_cluster` | Colour Connection | The human earns an edge-cluster score event. |
| `ai_victory` | Table Champion | The human wins a completed match against the AI. |

Each achievement unlocks once per account and remains unlocked across matches
and devices. The client derives scoring achievements only from committed
human-attributed score events, and the win achievement only from a completed
`HUMAN_WIN` result. The API owns the catalog and durable unlock state; its
achievement submission endpoint authenticates the account and is idempotent,
but current clients report the trigger and the API does not independently replay
or validate game rules. A modified client can therefore forge an unlock; future
server-authoritative turn evaluation is required before achievements can be
considered cheat-resistant. Achievement failures while offline must not block
gameplay; unlock IDs are queued in local account state and retried when an
authenticated session becomes available.

The expanded account catalogue includes `two_pair_10` (ten distinct committed
human Two Pair hand events across matches) and `perfect_match` (one committed
human five-tile Full House with all four suits represented and all four internal
hand boundaries matching by rotated edge colour). Progress events have stable
per-account IDs, are queued offline, and are deduplicated by the API. These
milestones do not change poker scoring or placement legality. Additional
catalogue entries may use registered progress metrics and thresholds; new
trigger types require a specification update and tested detection code.

The first three engagement achievements were approved on 2026-10-20:

| ID | Name | Unlock condition |
|---|---|---|
| `first_login` | First Login | First authenticated app visit recorded after the engagement feature is deployed. |
| `streak_starter` | Streak Starter | Authenticated app visits on seven consecutive UTC calendar days. |
| `loyal_user` | Loyal User | Authenticated app visits on 100 distinct UTC calendar days in total. |

An app visit occurs when an authenticated game session starts or the app resumes.
The API records at most one visit per account per UTC day, determines the day
using its database clock, and awards these milestones once per account. Repeated
logins, token refreshes and multiple devices cannot add extra days. Existing
account creation dates are not evidence of earlier visits; days before the
engagement tracking migration are not backfilled. Night Owl and Power User
remain proposed and are not tracked by this feature.

These are not required for the base game unless separately approved.

## 8.4 Future Features

Future features identified by the specification include:

- Additional multiplier systems beyond section 5.7.
- Special/power tiles.
- PvP multiplayer.
- Cosmetic unlocks.
- Leaderboards.

These should not be treated as part of the base game.

## 8.5 Gems and Match Pot (partly Decided, 2026-10-22)

The owner chose **Gems** as the earned in-game currency, replacing the earlier
proposed earned Credits. In the first release, only online matches generate a
shared, system-funded Gem pot: qualifying hands played by either player add to
the pot without debiting either player's balance. Every distinct committed
poker-hand event contributes, even when the same category is scored again.
The winner receives the pot; a draw splits it evenly. A player who completes a
normal match receives a fixed completion grant outside the pot. A resigning
player receives no completion grant and the opponent receives the pot only,
with no completion grant. The same reward outcome is intended
for a future match-ending timeout/forfeit; existing turn timeouts only pass a
turn and are unchanged. AI matches do not generate pot or completion Gems in
the first release. Achievement and optional rewarded-ad grants are desired
sources; the existing result interstitial is not a rewarded ad. Tournament entry
will spend Gems when tournaments launch; prices and tournament rules are open.

For the first balancing pass, each distinct committed hand contributes an even
Gem amount to the pot: Pair 2, Two Pair 4, 3-straight 6, Three-of-a-Kind 8,
4-straight 10, Full House 12 and 4-of-a-Kind 14. A normal completed match
awards 10 additional Gems to each player. The amounts are provisional and
separate from poker points; all draw pots therefore divide evenly.

[Gems and Online Match Pot](sections/11-gems-and-match-pot.md) records the
settled direction, proposed accounting model and open decisions. The online
gameplay screen now shows a live pot projection and gain animation from
committed score events. Final balancing, edge cases, tournament pricing and
rules, achievement/ad grant policy and rollout remain Proposed. No Gem wallet
or payout settlement is implemented. The earlier [Credits and Cosmetic
Economy proposal](sections/10-credits-and-cosmetics.md) and
[ADR-016](decisions/ADR-016-cosmetic-currencies.md) are superseded where they
conflict with the Gem direction. A future separate premium currency remains a
proposal; no purchase or conversion rule is approved.

---

# 9. Godot Scene & Node Structure

The project targets Godot 4.6.

The source specification requires the eventual technical specification to define:

- Scene hierarchy.
- Node structure.
- Incremental scoring integration.
- Tile placement notes.

The initial source document does not prescribe a final scene/node hierarchy.

Therefore, the implementation should establish a clear Godot architecture while documenting significant architectural decisions.

Gameplay state and scoring logic should be kept sufficiently separate from visual presentation to allow independent testing where practical.

---

# 10. Feature Roadmap

## Phase 1 — Core Base Game

Required priorities:

- Tiles.
- Board.
- Placement.
- Rotation.
- Poker scoring.
- Edge bonuses.
- Cluster scoring.
- AI.
- Mobile UX.
- Incremental scoring.

## Phase 2 — Engagement

Planned/optional features:

- Tile preview.
- Rotation hints.
- Cluster visualization.
- Challenges.
- Streaks.

## Phase 3 — Advanced

Planned/optional features:

- Additional multiplier systems beyond section 5.7.
- Power tiles.
- Timed mode.
- Campaign.
- PvP.
- Cosmetic unlocks.

## Phase 4 — Polish & Optimization

Planned focus:

- Animations.
- Performance.
- Haptics.
- General polish.

---

# 11. Future Expansion

The specification identifies the following possible expansion areas.

## 11.1 Scoring

- Additional optional multipliers beyond section 5.7.
- Power tiles.
- Board multipliers.
- Combo bonuses.

These are future features and are not part of the base scoring system.

## 11.2 AI

- Adaptive difficulty.
- More advanced turn planning.

## 11.3 Content

- Campaign/puzzle boards.
- New tile faces.
- New edge patterns.

## 11.4 Multiplayer

- PvP multiplayer mode.

## 11.5 Meta / Cosmetics

- Cosmetic unlocks.
- Additional visual effects.
- Separate earned and premium cosmetic currencies: owner-selected direction;
  detailed economy and architecture Proposed in section 8.5 and ADR-016.

---

# 12. Technical Design Principles

The following principles are derived from the requirements in the source specification.

## 12.1 Separation of Concerns

Keep the following concerns logically separated where practical:

- Tile data.
- Tile presentation.
- Board state.
- Board presentation.
- Placement validation.
- Adjacency.
- Poker-hand evaluation.
- Edge scoring.
- Cluster detection.
- AI decision-making.
- UI.
- Visual effects.
- Haptics.

## 12.2 Data-Driven Game State

Game rules should operate on game-state data rather than relying unnecessarily on scene-tree presentation nodes.

This supports:

- Testing.
- AI decision-making.
- Incremental scoring.
- Future feature expansion.

## 12.3 Mobile Performance

The specification explicitly calls for incremental scoring suitable for mobile.

Avoid unnecessary full-board recalculation after every move.

Prefer localized updates based on affected tiles and adjacency relationships.

## 12.4 Extensibility

The architecture should not unnecessarily prevent future additions such as:

- Multipliers.
- Power tiles.
- Advanced AI.
- Campaign boards.
- PvP.
- Cosmetic systems.
- Additional tile faces.
- Additional edge patterns.

Future extensibility should not introduce unnecessary complexity into the base game.

---

# 13. Specification Gaps Requiring Explicit Decisions

The source specification intentionally leaves several implementation/game-design details open.

These should be resolved through explicit design decisions rather than silently invented by an AI coding agent.

Each gap is owned by an Architecture Decision Record (ADR). The gap-to-ADR mapping, the review requirements an ADR must satisfy before it is part of this specification, and the current status of every gap are recorded in section 19.

## 13.1 Poker Scoring Values

Need to define:

- Complete list of poker hands.
- Point value for each hand.
- Whether multiple hands can score from one placement.
- How hands are selected when multiple interpretations are possible.

## 13.2 Hand Formation

Need to define:

- What constitutes a poker hand on the 12×12 board.
- Whether hands are rows, columns, connected groups, fixed lengths, or another structure.
- Whether hands may overlap.
- Whether existing hands can score again after subsequent placements.

## 13.3 Edge Cluster Definition

Need to define:

- What constitutes a cluster.
- Minimum cluster size.
- Whether a cluster consists of matching edges, tiles, or colors.
- Whether clusters are color-specific.
- How cluster boundaries are determined.

## 13.4 Cluster Bonus

Need to define:

- Flat bonus value.
- Whether bonus varies by cluster size.
- Whether a cluster can score repeatedly.
- Whether one placement can create multiple cluster bonuses.

## 13.5 Turn Rules

Decided and implemented (2026-10-05, [ADR-017](decisions/ADR-017-turn-timer.md)):
both players have 60 seconds per action phase. A line or swap still ends the
turn immediately. At zero, return unconfirmed tiles to the rack and pass without
placing or scoring. The remaining time is shown as a compact `m:ss` text timer
in the gameplay information row, as amended in [ADR-017](decisions/ADR-017-turn-timer.md).
Existing match-end conditions still apply. The deadline continues while away;
on return, expire only the abandoned turn, then start the next player's full
60 seconds. The settings drawer does not pause the timer.

Need to define:

- Tile source/deck behavior.
- Number of tiles available to a player.
- Whether a player draws a new tile after placement.
- Pass behavior.
- Game-end conditions.
- Starting player rules.

Decided (2026-10-10, [ADR-018](decisions/ADR-018-resignation.md)): a human may
resign an active match from the settings drawer or gameplay action bar. Both
entries open the same confirmation. Resignation ends the match
immediately and awards the rival the win regardless of the score; committed
scores remain unchanged. The final local snapshot records outcome `AI_WIN` and
end reason `RESIGNATION`, and the game API receives it with completed status.
Resignation after the match has ended is unavailable.

## 13.6 Tile Distribution

Decided (ADR-004, ADR-010, ADR-014):

- Generation uses one finite shared pot, not unbounded randomness.
- Face and edge probabilities are uniform unless a design decision changes them.
- Duplicate tile configurations are permitted; identity is by tile ID.
- The pot holds at most 4 Joker-ranked tiles.
- The live pot drawer shows the faces, suits and edges of all remaining tiles, without tile IDs or future draw order. Both online seats see the same unordered inventory.

Resolved by ADR-004 (finite seeded bag, uniform rank/colour/edge selection,
duplicates permitted) and ADR-014 (at most 4 Jokers in one pot).

## 13.7 AI Evaluation

Need to define:

- Medium AI evaluation method.
- Hard AI search method.
- Search depth interpretation.
- AI score evaluation.
- Blocking behavior.
- Time/performance budget.

## 13.8 Board Placement Rules

Need to define any restrictions beyond:

- Cell must be empty.
- Tile must occupy a valid grid cell.

For example, the source document does not specify whether tiles must connect to existing tiles.

## 13.9 Game End

Decided (2026-10-10, [ADR-018](decisions/ADR-018-resignation.md)): the normal
score-based winner rule has one exception. When the human resigns, the rival is
the winner regardless of score, with no change to committed scores.

Need to define:

- Maximum turn count, if any.
- What happens when no valid placements remain.

## 13.10 Cosmetic Economy (Proposed)

ADR-016 owns the proposed wallet and reward-accounting design. The detailed
[proposal review list](sections/10-credits-and-cosmetics.md#9-review-decisions-still-needed)
tracks unresolved reward values, catalog relationship, premium grants and
conversion, match eligibility, daily reset, hand-bonus settlement, existing
achievement backfill, offline behavior, trust model, and rollout. These are not
Phase 1 blockers or approved implementation requirements.

---

# 14. External Service Integration

Pokabow uses the Tiletopia API for account registration and authentication.
On first launch, after Terms of Use acceptance, the client registers an account
with `POST /auth/register`, stores the account record locally, then logs in via
`POST /auth/login` and stores the returned bearer token and user state. On later
launches, it restores local user state and attempts login with saved credentials.
The API's `openapi.json` is the endpoint and payload contract; see
`sections/07-godot-structure.md` for the current integration status.

Decided and implemented (2026-10-14): if login using saved credentials returns
HTTP 401, treat the old account as unavailable. Clear its local credentials,
profile, account settings, match saves, achievement queues and synchronization
state, then restart at new-account setup. Retain the configured Server IP.
A protected request's expired token first triggers login; network failures and
other inconclusive login failures retain the account and offer retry. Account
reset does not send a remote deletion request or change gameplay rules.

Local match persistence remains authoritative. The client creates a matching
server game, submits every committed move using the API's `turnId` and
`expectedVersion` contract, and calls `PATCH /games/{gameId}` with the latest
full match snapshot after each accepted line or swap. When the local match ends,
the update marks the API record `completed`. Pending turns and updates are
stored locally for retry. This mirrors match activity; it does not implement
server-authoritative game rules, score calculation, multiplayer, or restoring
gameplay from cloud state. `ApiConfiguration` reads the saved Server IP first,
then the `pokabow/server_ip` project setting, and uses HTTP port 3000. The current
development address is `192.168.0.189`. Android exports enable Internet
permission; see `API_INTEGRATION.md` for local-network setup and diagnosis.

The hub labels its primary action **New Game** when no local saved session is
present and **Resume** when one is present. New Game shows a pre-match reveal
with a difficulty picker. It cycles through images in the selected difficulty's
rival folder, randomly settles on one, and starts the local match with that AI
difficulty and portrait. Online matchmaking pairs authenticated accounts into a lobby; both players can ready up for server-authoritative live PvP (see `ONLINE_PLAY.md` and `MATCHMAKING.md`). Empty folders
temporarily use the legacy shared portraits. Resume skips the reveal and
restores the saved match. Starting a new match creates or reconnects its
matching Tiletopia game record; resuming reuses the local match identity and
associated API record.

Decided (2026-10-20): Table Level is a separate account progression marker.
Only a completed, server-verified online match awards XP, equally for wins,
draws and losses. Online pairing uses a separate skill rating. See
`sections/06-game-modes.md` for the initial thresholds and `MATCHMAKING.md`
for search behavior. Migration 012 was verified on the configured local database
on 2026-10-20; tournament
access and mystery-tile unlock rules remain Future.

The Settings panel provides **Clear game cache**, which deletes the local saved
match and its client-side API sync record. If the sync record contains a server
game ID and the client has an authenticated token, it also requests
`DELETE /games/{gameId}`. Remote deletion is best-effort; clearing local state
does not depend on API availability.

This section records application integration and does not change gameplay rules.

The authenticated Tiletopia API also provides the account-wide achievement
catalog and unlock records. Pokabow submits unlock IDs after qualifying
committed score events or a human match win, and displays the catalog and
unlock state in the profile. Install API migration `006_achievements.sql`
after the existing migrations. Achievement writes are retry-safe on the server;
the client queues offline submissions locally and retries after authentication.

---

# 15. Implementation Status Vocabulary

Use the following terminology when updating project documentation:

- **Specified** — explicitly defined in this specification.
- **Decided** — explicitly agreed as a project decision.
- **Implemented** — present in the codebase.
- **Tested** — verified through automated or documented manual testing.
- **Proposed** — suggested but not yet approved.
- **Future** — intentionally deferred.

Do not treat unspecified behavior as approved design.

---

# 16. Change Control

When an approved gameplay rule changes:

1. Update this specification.
2. Identify affected systems.
3. Update the implementation.
4. Update relevant tests.
5. Update affected technical documentation.
6. Record significant architectural decisions separately.

The game specification should remain the authoritative description of approved gameplay behavior.

---

# 17. Development Sequence

The original specification organizes detailed development/specification work in this order:

1. Tile System
2. Board System
3. Scoring System
4. AI System
5. Mobile UX & Feedback
6. Game Modes & Engagement
7. Godot Scene & Node Structure
8. Feature Roadmap
9. Future Expansion

Each area should be sufficiently defined before dependent implementation is treated as final.

---

# 18. Core Requirement Summary

At minimum, the initial playable game must provide:

- A 12×12 board.
- Randomly generated tiles.
- Ace/King/Queen/Jack faces.
- Red/Black face property.
- Four colored edges.
- Four tile rotations.
- Valid empty-cell placement.
- Grid snapping.
- Adjacency tracking.
- Poker-hand scoring.
- +1 edge-match scoring.
- Edge-cluster bonus.
- Hand multipliers as decided in section 5.7.
- Incremental scoring.
- Human vs AI gameplay.
- Easy, Medium, and Hard AI behavior.
- Mobile-oriented interaction.
- Valid-placement highlighting.
- Edge/cluster visual feedback.
- Floating score feedback.
- Optional haptics.

Anything beyond these requirements should be treated according to its status as specified, decided, proposed, or future.

---

# 19. Specification Integrity Rule

When an AI agent is implementing the game, it must not silently fill specification gaps with invented gameplay rules.

If implementation requires an undefined rule, the agent should:

1. Identify the missing rule.
2. Explain why it is required.
3. Propose one or more possible interpretations if useful.
4. Obtain an explicit decision.
5. Record the decision.
6. Update this specification where appropriate.
7. Implement against the approved decision.

The goal is to keep the implemented game aligned with an explicit, reviewable specification.

---

# 20. Architecture Decision Records (ADRs) and Review

Significant gameplay and technical decisions are recorded as Architecture
Decision Records in `docs/decisions/`. The index, template and review workflow
live in `docs/decisions/README.md`; individual review findings live in
`docs/decisions/reviews/`.

ADR-015 records the account achievement catalog, triggers, persistence, and
client-trust limitation defined in sections 8.3 and 14.

ADR-016 is a Proposed record for the cosmetic economy in sections 8.5 and
13.10. Its recommendations do not supersede approved gameplay or achievement
rules before review and acceptance.

## 20.1 Review requirement

An ADR is part of the design specification only once it has been reviewed
against this document. Review is required before any dependent implementation is
treated as final, and must confirm:

1. The decision does not contradict a rule in this specification.
2. The decision covers the gap it claims to resolve, or states explicitly what it
   leaves open.
3. Constraints inherited from the specification are listed and honoured.
4. Open approval questions are listed explicitly.
5. Required tests and affected systems are identified.
6. Cross-references to other ADRs and to sections of this document are valid and
   not dangling.

A review may recommend amendments; it must not silently alter a decision.

## 20.2 Status discipline

- An ADR marked **Proposed** is not approved gameplay. It must not be described
  as specified, and rules it introduces must not be implemented as final
  (sections 14 and 18).
- An ADR moves to **Accepted** (or **Decided** in ADR-011) only after its approval
  questions are answered and any amendment is recorded.
- When an ADR is accepted, this specification is updated first; implementation,
  tests and technical documentation follow (section 15).

## 20.3 Gap ownership

| Gap | Topic | ADR | Status |
|---|---|---|---|
| 13.1 | Poker scoring values | ADR-001; hand list and values superseded by ADR-012 | Accepted; ADR-012 Accepted |
| 13.2 | Hand formation | ADR-001; later placement legality in ADR-011; hand list in ADR-012 | Accepted; ADR-011 Decided; ADR-012 Accepted |
| 13.3 | Edge cluster definition | ADR-002 | Accepted |
| 13.4 | Cluster bonus | ADR-002 | Accepted |
| 13.5 | Turn rules | ADR-003, ADR-010, ADR-011 | Accepted; ADR-011 Decided and supersedes parts of earlier decisions |
| 13.6 | Tile distribution | ADR-004; deck size and refill in ADR-010 | Accepted |
| 13.7 | AI evaluation | ADR-005; line candidates in ADR-011 | Accepted; ADR-011 Decided |
| 13.8 | Board placement rules | ADR-006, ADR-011 | Accepted; ADR-011 Decided and supersedes parts of ADR-006 |
| 13.9 | Game end | ADR-003, ADR-010, ADR-011 | Accepted; ADR-011 Decided |
| 13.10 | Cosmetic economy and account wallet | ADR-016 | Proposed; separate currencies and cosmetic-only direction confirmed |
| - | Incremental scoring architecture | ADR-007; whole-line transactions in ADR-011 | Accepted; ADR-011 Decided |
| - | Godot project architecture | ADR-008 | Proposed; technical approval remains open in the ADR |
| - | Tile scoring multipliers and expanded tile values | ADR-013 | Accepted |
| - | Visual identity and reusable UI design standard | ADR-020 | Decided; runtime adoption pending |

ADR-009 was reserved for clusters but not used; ADR-002 records that decision.
The status above reports the ADR files' current status. Implementation and tests
do not by themselves change a Proposed ADR into an accepted decision.
