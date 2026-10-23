# ADR-019: Live online play

Status: Implemented. The owner selected live turns on 2026-10-13.

Two authenticated accounts pair in the existing lobby and both ready up.
The oldest queued account occupies the first seat and opens the game. Existing
placement, scoring, swap, timer and resignation rules apply unchanged. The API
owns committed state and 60-second deadlines; client clocks are display-only.
Disconnects do not pause time and do not introduce an automatic forfeit rule.

Reuse the Godot domain rules in a bounded headless server worker. Store full
snapshots privately in a dedicated online_matches table, outside the
creator-controlled local-game mirror. Return a public board plus the requesting
player's hand; never return the seed, bag or opponent hand.

Serialize readiness against queue cancellation using the existing database
transaction lock. Serialize online commands using a match-row lock, expected
version and persisted command UUID. Repeated successful commands have no effect.
Reject malformed, stale, out-of-turn and non-owned-tile commands. Resolve elapsed
deadlines before accepting new commands, including after reconnect.

The Godot online controller reuses the board and staging UI while delegating all
commits to the API. It never runs an AI turn, writes the local AI save or submits
the online projection to snapshot synchronization.

Consequences: the API host now needs a compatible Godot executable and the
matching game rules checkout. Polls read cached projections; changes launch
bounded workers. This is the first casual-play deployment, with load testing,
device validation, ranking, rematches and rewards left for later work.
