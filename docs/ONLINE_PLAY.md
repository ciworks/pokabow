# Live online play

Implemented on 2026-10-13. The owner selected live turns with both players
present. Casual two-player play uses the existing tile, placement, scoring,
swap and resignation rules. Turns have no move deadline under ADR-023.

## Player flow

Open **Online lobby**, find an opponent, then both choose **Ready**. The oldest
queued player takes the first turn. Readiness creates one shared match, even if
both clients retry. Each player sees the same board and their own six-tile hand.
The opponent's account avatar appears in the lobby and match HUD when available;
otherwise the packaged rival portrait remains. The avatar is fetched separately
from the polled match state.
The existing drag, rotate, Play and Swap controls submit commands to the server.
Input locks while a command is pending or the connection is unavailable.

Disconnecting, backgrounding the app or returning to the hub preserves the
pending turn. No disconnect-forfeit rule exists. A player can resign explicitly.
Open **Online lobby** again to resume; the server supplies the current board,
hand and score. An account-specific local file stores only
the last online match ID. A saved AI game remains separate.

## Turn notifications

The hub Settings panel has an opt-in **Push notifications** switch on Android
and iOS. It saves its choice on the device and requests notification permission
when enabled. The installed Notification Scheduler plugin posts a local alert
when the client observes an online match changing from the opponent's turn to
the player's turn. Repeated polls, completed matches and the first snapshot of
a match do not create alerts. Turning the switch off cancels a pending alert.
The bundled plugin is v5.2, the release tested by its publisher against this
project's Godot 4.6 target; the current v6.0 release targets Godot 4.7.

This is local scheduling, not remote push delivery. Online polling pauses while
the app is suspended, so an opponent move made then is only detected after the
app resumes. Delivery while the app is closed or suspended needs a server event
for the accepted move, per-device push tokens, and FCM/APNs delivery. The client
and API do not yet provide that path. Notification permission and display still
need verification on physical Android and iOS devices.

## Server setup

In the sibling pokabow-api project:

1. Apply migrations/008_online_play.sql after migrations 001, 002, 004, 005,
   006 and 007, using the normal database migration process.
2. Install Godot 4.6 or a compatible engine on the API host.
3. Set GODOT_BIN to the **main Godot executable** and ONLINE_RULES_PROJECT
   to the absolute path of this game checkout. Both are server configuration,
   never client-provided paths. Keep this checkout's rules fixed for active games.
4. Import the project once with Godot's --headless --path <game-directory> --import.
5. Build and restart the API (npm run start). Keep both clients on this server.

The server must be able to run Godot and write temporary job files. Without
the two environment settings, the lobby explains that online play is not enabled
and does not offer Ready. No production database is modified by the test tools.

## Authority and privacy

OnlineRules and tools/online_rules_worker.gd run the existing Godot domain
rules headlessly on the API host. This avoids a second implementation of poker
scoring. The API invokes one bounded worker for initialization or a state change;
ordinary polls read stored projections without launching Godot.

The API stores the complete snapshot and both private projections in
online_matches, separate from the client-owned games table. Existing snapshot
PATCH/DELETE routes cannot address online records. Only participants can read or
act, and each receives their own projection. Neither the opponent's hand, the
seed, bag IDs nor future draw order is sent to clients. The owner-approved
tile-pot drawer makes the remaining faces, suits and four edges public to both
seats through an appearance-sorted `potTiles` array. The client projection
deliberately cannot be saved as a complete local match.

The API passes through the Godot worker's view fields, so this addition needs
the updated game checkout on the API host; it does not require a database
migration. Existing stored match projections gain `potTiles` on their next
accepted command. Until then, the client shows the count with a
tile-details-unavailable message instead of inventing tiles.

Mutations lock the match row. Commands carry a UUID and expected version.
Successful retries have no additional effect; reusing an ID with a different
payload is rejected. Stale versions and invalid moves return fresh private
state with an error, allowing the player to correct their move.

There are no move deadlines. An active turn remains with its player through a
long absence and reconnect. Presence is
displayed as disconnected after 15 seconds without a poll. This is informational
and does not invent a loss condition. Account deletion ends the affected match
as a resignation when the survivor next polls.

## API

All routes require bearer authentication and return Cache-Control: no-store.
See the API's openapi.json and docs/ONLINE_PLAY.md.

| Method | Route | Purpose |
| --- | --- | --- |
| POST | /matchmaking/tickets/{ticketId}/ready | Ready up, idempotently |
| GET | /online-games/current | Recover the active match |
| GET | /online-games/{matchId} | Private state and presence |
| POST | /online-games/{matchId}/commands | Place, swap or resign |

## Validation and remaining limits

Verified on 2026-10-13 with Godot 4.6: 221 focused assertions, 10 online API
tests and 8 existing matchmaking API tests passed. Two real Godot clients also
completed readiness, an accepted opening, identical-board checks, reconnect and
resignation over HTTP. The 360×800 desktop rendering was visually inspected.

Focused Godot tests cover private hands, seat mapping, placement/scoring parity,
swap restoration, resignation, retries, input locking and the online
game screen. The API integration suite uses real PostgreSQL and the real Godot
worker to check readiness races, ownership, malformed commands, privacy,
idempotency, stale versions, absence without turn expiry, cancellation and account deletion.

Run Godot --headless --path . --script res://tools/validate_online_play.gd.
The dedicated runner waits for the scene tree to be ready before UI tests.
The full suite reported 8,236 assertions and one failure: its AppRoot boot test
expects an empty board despite a saved match from another fixture. It also calls
the nonexistent LineResult.is_legal() in an existing game-screen test. Inspect
raw output for script errors as well as the reported assertion count.

Physical phone-to-PC play, sustained public-server load and native mobile
background/resume still need device validation. Updates use one-second polling;
the server starts a bounded Godot process for each change. This first delivery
does not add ranking, invitations, bot fallback, rematches or PvP rewards.

An existing tile-source defect was fixed: swapping now moves the original
drawn tile to the pot's tail instead of duplicating its ID. Draw order and swap
rules are unchanged; subsequent snapshots now restore correctly.
