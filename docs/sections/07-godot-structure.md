# External API and account lifecycle

Pokabow uses the Tiletopia API for account authentication. The API project and
its `openapi.json` are the contract for network requests; the game should not
duplicate or redefine those endpoint schemas here. The API uses port `3000`
and defaults to the configured server IP `192.168.0.1`; players can change and
persist that IP in the hub Settings panel.

On a new installation, the player accepts the Terms of Use. Pokabow then
generates an account identity and sends `POST /auth/register`; after a
successful registration it saves the account record on the device and sends
`POST /auth/login` to obtain a bearer token. The account record and authenticated
user state are stored separately from match state. On a later launch, the app
restores the cached user state and attempts login with the saved credentials;
the hub remains available if that login request cannot reach the API.

The current local account record contains the generated username, email, and
password. Treat this as device-local prototype behavior: credentials should be
protected appropriately before production release, and account recovery or
credential migration is not specified here.

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

The hub's primary action reflects local persistence: it reads **New Game** when
there is no saved session and **Resume** when a saved session exists. Both
actions enter the same composition-root boot path; that path resumes the save
when available, otherwise it starts a new session and creates the corresponding
API game record.

The hub Settings panel offers **Clear game cache**. It removes the local match
save and the matching `GameSyncApiClient` record, so the next Play starts a new
game. When that record contains a server game ID and an authenticated token is
available, the client sends `DELETE /games/{gameId}`. Deletion is best-effort;
the local save is cleared even if the server cannot be reached or refuses the
request.

The Settings panel also stores the API server IP in `user://settings.cfg`. Auth,
game sync, and achievement requests build their endpoint URLs from this shared
setting, so changing the address takes effect for subsequent requests and
persists across launches.

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
| Local match save/resume | Implemented; separate from API account state |
| Server game creation, committed-turn submission, and match snapshot updates | Implemented; local match remains authoritative |
| Clear local match cache and best-effort server game deletion | Implemented; creator-authenticated `DELETE /games/{gameId}` |
| Server pass synchronization and server-authoritative restore | Not implemented |
| Achievement unlock reporting and profile catalog | Implemented; API trusts the authenticated client trigger |
| Production API base URL configuration | Required before deployment |
