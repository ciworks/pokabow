# ADR-017 — Sixty-second turns

Status: Decided (user request, 2026-10-05).

Duration amended to 60 seconds per turn by user request on 2026-10-10.
Saved turns retain their existing deadline; every new turn receives 60 seconds.

Each human and AI action phase has 60 seconds. A committed line or swap ends
the turn immediately as before. At zero, discard the uncommitted preview, keep
the player's held tiles and score, and pass through the normal turn boundary.
Timeouts do not add a new match-ending condition. Existing end conditions apply.
This supersedes ADR-003's no-clock rule and ADR-011's restriction to line/swap
turn endings. An AI proposal completed after its deadline must be discarded.

Timer presentation amended by owner request (2026-10-15): the shared tile pot
was shown with a circular countdown ring. Superseded by the concept-matching
presentation amendment below. Avatar panels no longer display a yellow
countdown border. The settings drawer does not pause the turn.

Warning feedback (owner amendment, 2026-10-05): the active player's avatar and
score panel shake together once at each displayed second from 10 through 1.
Duplicate updates within one second do not restart the animation. Zero stops
the warning as the turn expires; the next player's warning follows their own
countdown. Reduced-motion mode suppresses the shakes. This presentation change
does not alter the deadline, turn duration, or timeout behavior.

The deadline continues while the app is backgrounded or closed. On return,
expire only the turn that was left if overdue; the next player receives a fresh
60 seconds. Do not simulate missed turns or AI moves while away. Persist the
absolute deadline with the turn; older saves without timer fields start with
60 seconds. Timer fields are optional additions to the existing save schema.

Implemented in TurnManager, TurnState, and GameSessionController. The current
presentation is recorded in the latest amendment below.

## Amendment - concept-matching timer and pot, 2026-10-18

At the owner's direction, the ring is removed. The score header keeps the
supplied tile-pot artwork with a plain `N left` count beneath it. A single slim
row directly below the score header shows the active-turn text at left, the
compact opponent rack in the center, and a right-aligned `m:ss` countdown. The
turn text uses 16px Fredoka Regular and the 16px timer uses Fredoka Semibold,
both in deep teal `#173D42`. The timer remains 60 seconds and continues through the
settings drawer; timeout behavior is unchanged. Low-time visual feedback is
removed in the amendment below.

## Amendment - remove avatar panels and shake, 2026-10-18

At the owner's direction, remove the surrounding player score cards and the
last-ten-second avatar shake. The avatars and scores remain in the header, and
the timer remains as plain `m:ss` text in the turn-information row. This is a
presentation-only change; turn deadlines, timeout behavior, and settings-drawer
clock behavior are unchanged.

The original ring validation below records the superseded presentation. Current
editor import and text-format checks are recorded with the game-screen update.

Per-second warning validation (2026-10-05): the focused scene suite passed 243
assertions, including all warning seconds for human and AI, duplicate-tick
suppression, turn re-entry, expiry cleanup, and reduced-motion suppression.
The repeated animation was not manually reviewed on a physical device.

Shared-pot timer validation (2026-10-15, Godot 4.6): 387 focused interaction
assertions, six portrait configuration checks, and 137 rendered layout/state
assertions passed. Full, half-full, ten-second, and empty rings were visually
inspected. Coverage includes both players, per-second updates without board
rebuilds, timeout handover, match-end clearing, restart, warning feedback, and
reduced motion. Physical-device testing remains outstanding.
