# External API and account lifecycle

Pokabow uses the Tiletopia API for account authentication. The API project and
its `openapi.json` are the contract for network requests; the game should not
duplicate or redefine those endpoint schemas here. The API uses port `3000`
and defaults to the configured server IP `192.168.0.1`. The hub Settings panel
does not expose the API address.

On a new installation, the player accepts the Terms of Use. Pokabow then
generates an account identity and sends `POST /auth/register`; after a
successful registration it saves the account record on the device and sends
`POST /auth/login` to obtain a bearer token. The account record and authenticated
user state are stored separately from match state. On a later launch, the app
restores the cached user state and attempts login with the saved credentials;
the hub remains available if that login request cannot reach the API.

The profile's single **Save changes** action uploads its normalized 195×195 PNG
to authenticated `PUT /auth/me/avatar`, then updates `displayName` through
`PATCH /auth/me`. `GET /auth/me/avatar` restores the portrait on another device;
the API returns PNG bytes and persists them in PostgreSQL through its existing
`user_avatars` table and migration `009_user_avatars.sql`. The client updates
its local avatar cache only after upload success. The username and avatar
requests are separate writes, so a username failure after avatar success is
reported as partial success and keeps the draft available for retry. Email
remains read-only.

The current local account record contains the generated username, email, and
password. Treat this as device-local prototype behavior: credentials should be
protected appropriately before production release, and account recovery or
credential migration is not specified here.

Owner-directed unavailable-account recovery (implemented, 2026-10-14): a 401
from saved-credential login clears local account/profile/settings and associated
match, achievement and sync state, then reloads the shell at first-time account
setup. The Server IP is retained. Existing services are stopped before cleanup
to prevent late responses from restoring old state. Cleanup failure offers a
local retry before registration can proceed. Expired bearer tokens first retry
login; transport failures and other inconclusive responses do not erase accounts.

The API provides authenticated game CRUD, turn submission, and pass endpoints.
`GameSyncApiClient` creates one server game for each local match, stores the
server game ID and version alongside a durable queue of pending operations.
Each committed line is submitted to `POST /games/{gameId}/turns` with a UUID
`turnId`, current `expectedVersion`, and placed tile IDs and coordinates. After
that turn is accepted, the client calls `PATCH /games/{gameId}` with the current
version, the latest complete local match snapshot, and its active/completed
status. Swaps also update the snapshot through PATCH. A revision marker lets
the client recover if a PATCH succeeded but its response was lost. Successful
responses advance the stored API version; pending operations retry across
launches, and repeated turn IDs are idempotent. The client keeps local match
state authoritative; it does not restore gameplay from the server record.

The hub's primary action starts a new game. The Active Games panel below the
Online lobby lists saved local AI matches and the current resumable online match.
Each card shows the rival and both current scores, and its Resume button opens
that exact match. Local AI snapshots use a match-specific save file; the legacy
`match_save.json` remains discoverable and resumable. The online API currently
exposes one resumable match per account, so at most one online card is shown.

The hub Settings panel offers **Clear game cache**. It removes all local match
saves and the matching `GameSyncApiClient` record. When that record contains a
server game ID and an authenticated token is available, the client sends
`DELETE /games/{gameId}`. Deletion is best-effort; local saves are cleared even
if the server cannot be reached or refuses the request.

`ApiConfiguration` still reads a saved API server IP from `user://settings.cfg`
before the Project Settings default. The player-facing Settings panel does not
expose that address. Auth, game sync, and achievement requests continue to build
their endpoint URLs from the shared configuration.

The current Tiletopia API treats submitted scores as temporary placeholder
scores and does not provide server-side game-rule validation. Local play and
scoring therefore remain authoritative. The API currently leaves the creator
as current player after each turn, so both local human and AI committed moves
are mirrored through that account's authenticated turn endpoint.

## Status

| Integration | Status |
|---|---|
| First-launch registration and login | Implemented |
| Returning-account login | Implemented |
| Multiple local AI match save/resume | Implemented; match-specific files with legacy save discovery |
| Hub Active Games cards | Implemented; local AI matches and current online match |
| Server game creation, committed-turn submission, and match snapshot updates | Implemented; local match remains authoritative |
| Clear local match cache and best-effort server game deletion | Implemented; creator-authenticated `DELETE /games/{gameId}` |
| Server pass synchronization and server-authoritative restore | Not implemented |
| Achievement unlock reporting and profile catalog | Implemented; API trusts the authenticated client trigger |
| Production API base URL configuration | Required before deployment |
