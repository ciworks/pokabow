# 06 - Game Modes & Engagement

**Status:** Base mode Specified; achievements Decided and implemented; online progression Decided and implemented, with migration 012 verified on the configured local database; Gem economy direction Decided with reward policy Proposed; other engagement and advanced features Future.
**Source of truth:** `docs/GAME_SPEC.md` section 8.
**Related decisions:** ADR-003 (Turn Rules and Game End), ADR-005 (AI
Evaluation and Search).

---

## 1. Base Mode (Specified)

- **Human vs AI.**
- This is the initial / demo mode and is the only required mode for Phase 1.

The base mode requires run rules that are currently **undecided**: turn order,
tile supply, passing, and end conditions. Those are owned by ADR-003.

---

## 2. AI Difficulty (Specified)

The base mode offers three AI difficulty levels:

- Easy
- Medium
- Hard

Their behaviours are defined in `04-ai-system.md`; the evaluation and search
details are owned by ADR-005.

---

## 3. Optional Engagement Features (Future)

Identified by the specification as optional / future. Not required for the base
game unless separately approved:

- Timed challenges.
- Pre-set boards.
- Daily / weekly events.
- Streak rewards.

## 4. Achievements (Decided)

The initial account-wide achievements use committed scoring and match outcomes:

| ID | Name | Trigger |
|---|---|---|
| `first_hand` | First Deal | Human receives a poker-hand score event. |
| `straight` | Straight Shooter | Human receives a 3-straight or 4-straight score event. |
| `full_house` | Full House | Human receives a Full House score event. |
| `edge_cluster` | Colour Connection | Human receives an edge-cluster score event. |
| `ai_victory` | Table Champion | Human wins a completed Human-vs-AI match. |

The client submits these unlocks to the authenticated Tiletopia API and shows
earned milestones as notices. The profile lists all five and marks unlocked
ones. The API persists each unlock once per user. Because the API does not
replay or validate Pokabow moves, unlock claims currently trust the client.
Unlock IDs are queued locally while offline and retried after authentication.
See `GAME_SPEC.md` section 8.3 and section 14.

The approved engagement set adds First Login, Streak Starter and Loyal User.
The authenticated app checks in at session start and resume; the API records a
unique UTC visit day per account and unlocks the three milestones at one visit,
seven consecutive days and 100 total distinct days. These visits are
server-dated, retry-safe and independent of match scoring. Earlier visits are
not backfilled from account age. Night Owl and Power User are not implemented.

---

## 5. Advanced / Future Features

### Online progression (Decided; implemented locally)

Table Level starts at 1. Each completed, server-verified online match awards
100 XP to both players, whether they win, draw or lose. AI games and
client-reported achievements award no Table Level XP. Level `L` begins at
`100 × L × (L - 1) / 2` cumulative XP. A per-player, per-match award record
prevents duplicate XP on retries and reconnects.

Online matchmaking uses a separate Glicko-2 skill rating, starting at 1500
with deviation 350 and volatility 0.06. It updates on the same completed
matches, using win/draw/loss outcomes. Players have a Provisional tier for
their first ten rated matches; thereafter Novice is below 1350, Contender
below 1650, Expert below 1900, and Master at 1900 or above. Matchmaking pairs
the closest available rating inside a search window starting at the greater of
200 points or the player's uncertainty, then widening by 50 points every
15 seconds to a 500-point cap. Both players' windows must admit the pairing.
The profile displays level, XP progress and Online Tier; the matched lobby
displays the opponent's tier. Tournament entry and mystery-tile rewards remain
Future until their own eligibility and reward rules are approved.

The owner chose earned [Gems and an online match pot](11-gems-and-match-pot.md)
in place of proposed earned Credits. Every distinct committed poker hand adds
to the pot; winner and draw settlement, normal completion grants, resignation
treatment, and future Gem-spending tournament entry are decided. The seven
hand contribution amounts and 10-Gem normal completion grant are provisional
balancing values. Wallet architecture, tournament rules and rollout remain
Proposed. A separate
premium currency and shop remain Future. Existing achievement triggers are
unchanged.

Explicitly out of scope for the base game:

- Multipliers.
- Special / power tiles.
- PvP multiplayer.
- Cosmetic unlocks.
- Leaderboards.

---

## 6. Status Summary

| Area | Status |
|---|---|
| Human vs AI base mode | Specified |
| Easy / Medium / Hard AI levels | Specified |
| Turn / supply / end rules | Open - ADR-003 |
| Five account-wide achievements | Decided; client/API integration implemented |
| Two Pair Collector and Perfect Match | Decided; progress event path and client detection implemented, pending deployment of API migration 010 |
| First Login, Streak Starter and Loyal User | Decided; client/API check-in path implemented, pending deployment of API migration 011 |
| Table Level and Online Tier | Decided; client/API implemented; local migration, endpoint and disposable database lifecycle tests verified 2026-10-20; device verification pending |
| Earned Gems and online match pot | Core direction Decided; online gameplay projection and animation Implemented and headless-tested; wallet, settlement and redemption Proposed |
| Separate premium currency | Future proposal; no purchase implementation |
| Timed challenges, pre-set boards and daily/weekly events | Future |
| Multipliers, power tiles, PvP, cosmetics, leaderboards | Future |
