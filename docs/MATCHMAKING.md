# Online matchmaking and lobby

Implemented: rating-aware pairing, readiness and live PvP. API migration 012
was verified on the configured local database on 2026-10-20.
The same day, isolated PostgreSQL tests passed for rating-aware pairing,
concurrent joins, one-time XP awards and authoritative match completion.
See ONLINE_PLAY.md for authoritative gameplay, setup and validation.
Invitations and bot fallback remain outside this delivery.

## Player flow

The hub's **Online lobby** button opens matchmaking even when **Resume** points
to a saved AI match. **New Game** also offers an **AI rival / Online lobby** mode
picker. AI play keeps its existing difficulty selection and portrait reveal.

In Online lobby, **Find opponent** joins the authenticated API queue. The screen
shows searching, reconnecting, a real opponent's public display name, or a clear
departure/expiry message. **Cancel search**, **Leave lobby** and **Back** all stop
the search. On a configured server, both matched players choose Ready to start
one shared online match. It never starts an AI match or changes the local save.

## Server setup

In the associated `pokabow-api` database, apply
`migrations/007_matchmaking.sql` after the existing migrations, then build and
restart that API. Keep both clients pointed at the same configured API server.
The new migration was validated against a disposable PostgreSQL instance; it
was applied to the configured local `localhost:5432/tilegame` database on 2026-10-12, together with prerequisite migrations 001, 002, 004, 005 and 006. The previously missing database was created; optional demo-account migration 003 was skipped. No production database was changed.

The API's `openapi.json` documents the `/matchmaking` endpoints. Every request
uses bearer-token authentication. Opponent responses include an ID, display
name and Online Tier. When a match is found, the client requests that player's
avatar through the paired-opponent endpoint. A missing avatar or failed request
keeps the packaged rival portrait.

The join request uses `rulesVersion: "pokabow-v3"`. The sibling API's
`MATCHMAKING_RULES_VERSION` must match before the client can enter the queue;
deploy and restart the API when this compatibility marker changes. A mismatch
returns HTTP 400 before a ticket is created.

## Lifecycle and concurrency

- One active ticket per account, enforced by a partial unique database index.
- The closest rated searching ticket within both players' expanding search
  windows is paired with the arriving player. The queue serializes pairing
  under the same database lock. New players begin at 1500 with high
  uncertainty, so their first search has a wider window.
- Queue operations share a short PostgreSQL transaction lock, including across
  API processes. Both tickets enter one lobby atomically.
- Presence renews every two seconds while searching or matched and expires after
  30 seconds without renewal. Backgrounded clients stop sending heartbeats;
  resume asks the server for the actual outcome rather than reviving an expiry.
- Repeated joins recover the same ticket. Cancelling by request ID records a
  tombstone so a delayed join cannot resurrect a cancelled search. A cancellation
  for an old ticket cannot cancel a newer ticket.
- Leaving, expiry or account deletion ends the opponent's lobby. The remaining
  player can explicitly search again. No automatic AI substitution occurs.
- Expired presence and empty lobbies are cleaned during queue requests. Terminal
  ticket records remain for retry protection; long-term retention and abuse
  controls should be set before a public launch.

`MatchmakingApiClient` is app-scoped and separate from `GameSyncApiClient`. It
finishes cancellation after leaving the screen, retries transient errors, and
retains the ticket through token refresh. Account changes clear the old request
and UI state. An abrupt app exit or unavailable network relies on the lease to
release presence.

The queue requires both clients to remain present. The owner selected live
turns for playable PvP on 2026-10-13; ONLINE_PLAY.md describes reconnect behavior.

## Validation

The API tests cover authentication, request validation, ownership, duplicate and
concurrent joins, cancellation races, delayed requests, expiry and account
deletion using an isolated PostgreSQL database. The Godot tests cover recovery,
late replies, cancellation, token refresh, account changes, background/resume
and the lobby's separation from local AI play.

For API integration tests, set `MATCHMAKING_TEST_DATABASE_URL` to an **empty,
disposable** PostgreSQL database, build the API, then run
`node --test tests/matchmaking.test.mjs`. The integration suite refuses a database
that already contains `public.users`. Without that variable, the regular API
tests run route validation and skip the database integration suite.

Godot's ordinary test harness discovers
`tests/integration/test_matchmaking.gd`. Physical-device validation remains open.

Validation on 2026-10-12: API type checking passed; eight database-backed/route
checks passed against disposable PostgreSQL; existing API auth/account-deletion
regressions passed; seven focused Godot tests passed with 37 assertions. Two
Godot clients connected through real HTTP, entered the same lobby, and observed
opponent departure correctly. Rendered screens were inspected at phone sizes,
including 320x568, and landscape capture checks passed. Godot reported an existing
settings-icon UID fallback warning; no matchmaking script errors were reported.

## Two-device LAN check

1. Start the migrated API from `pokabow-api` with `npm run start`. This builds
   the current routes before launching. If port 3000 is occupied by an older
   instance, stop that instance first: `/health` alone does not prove that the
   running server includes matchmaking. An unauthenticated
   `GET /matchmaking/tickets/current` should return 401, not 404.
2. Keep the phone and the API computer on the same LAN. Configure the API
   computer's address in `pokabow/server_ip` before export, and clear any older
   `network/server_ip` value in `user://settings.cfg` on each client if it
   overrides the new default. The development address is currently
   `192.168.0.215` on port 3000. Do not use `localhost` on the phone.
   Android permits cleartext HTTP only to this address and the older
   `192.168.0.189` development address in `android/build/src/main/res/xml/network_security_config.xml`.
   If the API address changes, update that allowlist and rebuild the APK.
3. Use two distinct accounts. A fresh installation creates its own account
   through the first-launch gate. Two ordinary editor runs share the same saved
   account; use phone plus desktop, two devices, or isolated desktop profiles.
4. On each client, choose **Online lobby > Find opponent**. Keep both apps in
   the foreground. The first waits; the second arrival pairs them and both
   display the other account's public name. Names wrap within the rival card.
5. Choose **Leave lobby** on one client. The other receives the opponent-left
   message and can search again. A matched lobby is not yet a playable game.

Full-app verification on 2026-10-12: the process previously occupying port 3000
returned 404 for matchmaking. Restarting it with the current build enabled the
routes. Two independent Godot processes with isolated profiles completed real
registration, saved-account login, hub navigation, queue joining and reciprocal
matching over HTTP to `192.168.0.189:3000`. Both received the same lobby ID;
heartbeats preserved the lobby, leaving returned the first client to the hub,
and the second observed the departure. Their 360x800 captures were inspected.
Both temporary accounts were deleted after each run; seven focused client tests
also passed (37 assertions). Phone-to-PC connectivity and firewall access still
need confirmation on the physical phone.

## Playable PvP delivery (2026-10-13)

The legacy /games API still mirrors local AI snapshots. Live PvP now uses
separate /online-games routes, server-side Godot rules, private player views,
versioned commands and reconnect/resume without move deadlines. Both players ready up before
one shared match is created. Apply migration 008 and configure the server's
Godot executable and rules checkout as described in ONLINE_PLAY.md.

The validation and LAN notes above record the earlier lobby-only delivery.
