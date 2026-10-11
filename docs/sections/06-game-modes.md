# 06 - Game Modes & Engagement

**Status:** Base mode Specified; achievements Decided and implemented; cosmetic economy Proposed; other engagement and advanced features Future.
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

---

## 5. Advanced / Future Features

The [Credits and Cosmetic Economy proposal](10-credits-and-cosmetics.md) and
[ADR-016](../decisions/ADR-016-cosmetic-currencies.md) develop separate earned and
premium currencies for cosmetic-only use, as requested by the owner. Reward
rules, amounts, wallet architecture, and rollout remain Proposed. Paid currency
and shop delivery remain Future; existing achievement triggers are unchanged.

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
| Earned Credits and separate premium cosmetic currency | Owner-selected direction; detailed economy and ADR-016 Proposed |
| Timed challenges, pre-set boards, events, streaks | Future |
| Multipliers, power tiles, PvP, cosmetics, leaderboards | Future |
