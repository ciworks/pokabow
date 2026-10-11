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

The active avatar score panel shows a yellow perimeter. Remove one sixtieth
of its length after each elapsed second, clockwise from the top-left straight
edge; the underlying panel border remains visible. The inactive player and
finished matches have no yellow timer outline. A new turn restores a full ring.
The settings drawer does not pause the turn.

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

Implemented in TurnManager, TurnState, GameSessionController, and the avatar
outline control. Automated and visual validation results are recorded below.

Per-second warning validation (2026-10-05): the focused scene suite passed 243
assertions, including all warning seconds for human and AI, duplicate-tick
suppression, turn re-entry, expiry cleanup, and reduced-motion suppression.
The repeated animation was not manually reviewed on a physical device.
