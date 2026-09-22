# 06 - Game Modes & Engagement

**Status:** Base mode Specified; engagement and advanced features Future.
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

---

## 4. Advanced / Future Features

Explicitly out of scope for the base game:

- Multipliers.
- Special / power tiles.
- PvP multiplayer.
- Cosmetic unlocks.
- Leaderboards.

---

## 5. Status Summary

| Area | Status |
|---|---|
| Human vs AI base mode | Specified |
| Easy / Medium / Hard AI levels | Specified |
| Turn / supply / end rules | Open - ADR-003 |
| Timed challenges, pre-set boards, events, streaks | Future |
| Multipliers, power tiles, PvP, cosmetics, leaderboards | Future |
