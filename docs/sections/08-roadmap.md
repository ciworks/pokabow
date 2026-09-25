# 08 - Feature Roadmap

**Status:** Specified.
**Source of truth:** `docs/GAME_SPEC.md` section 10, `AGENTS.md` section 10.

The roadmap below is the approved phase ordering. A feature is only "complete"
when it is implemented, integrated, tested, documented, and free of known
regressions (`AGENTS.md` section 21).

---

## Phase 1 - Core Base Game

Required priorities:

- Tiles
- Board
- Placement
- Rotation
- Poker scoring
- Edge bonuses
- Cluster scoring
- Incremental scoring
- AI
- Mobile UX

**Status:** Specified. Not yet implemented. Phase 1 depends on the resolution of
the open rule decisions (see `../decisions/README.md`).

---

## Phase 2 - Engagement

Planned / optional:

- Tile preview
- Rotation hints
- Cluster visualization
- Challenges
- Streaks

**Status:** Started. Cluster visualization (persistent) and rotation hints have
landed as presentation over existing state, documented in `05-mobile-ux.md`
section 4; tile preview is the existing staged-line ghost. Challenges and streaks
are not started.

---

## Phase 3 - Advanced

Planned / optional:

- Multipliers
- Power tiles
- Timed mode
- Campaign
- PvP
- Cosmetic unlocks

**Status:** Future.

---

## Phase 4 - Polish & Optimization

Planned focus:

- Animations
- Performance
- Haptics
- General polish

**Status:** Future.

---

## Suggested Phase 1 Build Order

The specification's development sequence (`GAME_SPEC.md` section 16) implies this
dependency order:

1. Tile System (`01`)
2. Board System (`02`)
3. Scoring System (`03`)
4. AI System (`04`)
5. Mobile UX & Feedback (`05`)

Each area should be sufficiently defined before dependent implementation is
treated as final. Sections 03 and 04 are currently blocked on open decisions.

---

## Status Summary

| Phase | Status |
|---|---|
| Phase 1 - Core Base Game | Specified, blocked on open rule decisions |
| Phase 2 - Engagement | Future |
| Phase 3 - Advanced | Future |
| Phase 4 - Polish & Optimization | Future |
