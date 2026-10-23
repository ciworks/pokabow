# Game API integration

## Android development on the local network

The Android export must enable `permissions/internet=true`, including for LAN
requests. Re-export and reinstall the APK after changing this permission.
See [Godot HTTPRequest documentation](https://docs.godotengine.org/en/4.4/classes/class_httprequest.html).

`ApiConfiguration` uses a saved `network/server_ip` in `user://settings.cfg`
first, then `pokabow/server_ip` in the project settings, then its fallback.
Requests currently use HTTP on port 3000. The development project's configured
address is `192.168.0.189`; change it when the API host's LAN address changes.
An installed app's saved address takes precedence over a newly exported default.
The hub Settings screen can update the saved Server IP once accessible.

On 2026-10-05, the local Windows API was listening at `192.168.0.189:3000`;
an HTTP GET to `/` returned 404, demonstrating HTTP connectivity even though
the root route is not defined. Localhost refused connections because this
instance was bound to its LAN address. This was a desktop-side check, not proof
of phone connectivity or successful account registration.

For device diagnosis, open `http://<desktop-LAN-IP>:3000/` in the phone browser.
An HTTP response, including 404, establishes reachability; a timeout does not.
If unreachable, check that the service is bound to the LAN address or all
interfaces, Windows Firewall allows inbound TCP 3000 on the applicable network,
and Wi-Fi guest/client isolation or a VPN is not separating the devices. Do not
disable the firewall. Do not use the router address or phone localhost as the
API address. APK installation and account registration on a phone remain to be
verified after rebuilding with Internet permission enabled.

## Request mapping

### Authentication recovery (implemented)

A protected request returning HTTP 401 invalidates the cached session and
requests one shared login using saved credentials. Concurrent failures share
that request. A token rejected within 60 seconds of a successful login stops
automatic recovery, preventing a repeated 401/login loop.

When `POST /auth/login` rejects saved credentials with HTTP 401, the client
treats that account as unavailable (owner direction, 2026-10-14). It stops the
old account's services, removes credentials, cached profile, queued unlocks,
local match saves, sync queues, online resume state and account settings, then
reloads the game into the Terms of Use/new-account setup flow. Accepting creates
a fresh identity through the existing registration flow. No remote account
deletion is requested. The saved Server IP is retained so registration reaches
the same service. If cleanup fails, Retry retries local cleanup; no new account
starts until cleanup succeeds.

An expired bearer token alone does not reset the account: the saved-credential
login must return 401. Network failures, other HTTP errors and unusable login
responses remain retryable through **Retry** and **Close**, retaining local
account and match data. Matchmaking leaves its waiting state and online play
suspends polling until authentication recovers.

Automated regression coverage uses fake responses for concurrent 401s, login
failure and retry, rejection of a refreshed token, non-JSON 401 bodies, and
preservation of queued online commands during temporary failures, rejected-account
cleanup/restart, cleanup failure/retry and prevention of stale profile writes.
Live API/editor verification remains manual.

Pokabow retains its local, deterministic human-versus-AI rules. The Games API
stores the match and receives authenticated actions. Its current turn score is
still a placeholder; it must not replace the local ledger or determine achievements.

| Game feature | API request | Behavior |
| --- | --- | --- |
| First account / returning account | `POST /auth/register`, `POST /auth/login` | Existing account flow; a 401 from sync, achievements or profile requests a fresh login. |
| Profile / Save changes | `GET /auth/me`, `PATCH /auth/me`, `GET/PUT /auth/me/avatar` | One profile action uploads the normalized PNG avatar and updates `displayName` through the existing authenticated routes. The client caches the avatar after upload confirmation and reports partial success if the username update then fails. |
| Start match | `GET /games`, then `POST /games` if absent | Finds the local match ID before creating a remote record; preserves the initial snapshot while offline. |
| Resume match | `GET /games/{gameId}` | Refreshes API version before draining queued actions. Local validated save remains the playable state. |
| Human line / points scored | `POST /games/{gameId}/turns`, then `PATCH /games/{gameId}` | Stable turn ID supports retries. PATCH stores the actual board, rotations, ledger, decks and lifecycle snapshot. Placeholder API scores are ignored. |
| AI line | `PATCH /games/{gameId}` | Stores AI state without falsely submitting an AI move using the human bearer identity. |
| Swap (human or AI) | `PATCH /games/{gameId}` | Saves the resulting deck/pot and turn. A dedicated `/swaps` contract is now proposed; the server does not implement it yet. |
| Automatic human pass | `POST /games/{gameId}/pass`, then `PATCH /games/{gameId}` | If the current two-account endpoint returns `INVALID_TURN` for the local AI match, preserves the local pass with PATCH. Other errors retain the action for recovery. |
| Automatic AI pass | `PATCH /games/{gameId}` | Persists the turn change under the game owner's identity. |
| Stage / move / rotate / undo a line | `POST /games/{gameId}/turns/preview` when locally legal | Debounced by 300 ms, waits for state sync, includes absolute quarter-turn rotations. Cancelling or changing the line invalidates in-flight results. |
| Match ends, including resignation | `PATCH /games/{gameId}` | Stores completed status, the final local snapshot (`outcome`, `end_reason`, scores and board), and a compact `result` record with `winner`, outcome, end reason and score totals. For resignation, `result.winner` is `ai`, regardless of score. |
| Clear game cache | `DELETE /games/{gameId}` | Deletes the remote record; offline/failed deletes are retained and retried. This is not resignation. |
| View achievements | `GET /achievements` | Existing account catalog and unlock display. |
| Earn achievement | `POST /achievements/unlocks` | Existing committed-event detection; pending IDs retry after transient failure or login. Previews award nothing. |
| Track achievement progress | `POST /achievements/progress` | Sends stable IDs for committed human Two Pair and Perfect Match events. The API deduplicates per account and returns newly unlocked IDs; offline events retry. Requires migration `010_achievement_progress.sql`. |

`pokabow-api` already provides the separate authenticated avatar upload and
download endpoints, backed by migration `009_user_avatars.sql`. The client
contract uses those routes together with the existing username update. They are
two API writes, so they are not atomic; the profile reports when only the avatar
was saved and retains the username draft for retry.

Preview remains a **proposed** server route. A 404/501 disables further preview
requests for that local match during the client session. Failures, malformed
scores, mismatched rules/versions, and stale responses leave the local preview
in use. A successful current response supplies only the displayed preview;
it does not change committed scores, legality or achievement state.

Requests have 15-second timeouts. Mutating game sync retries transient failures
with a 2–60-second backoff, keeping action IDs and ordered snapshots. Version
conflicts trigger a game lookup and one immediate retry; permanent failures do
not spin. Queue state and deletion IDs are persisted in `game_sync_state.json`.

The OpenAPI additions for swaps and resignation, and its proposed AI-pass
extension, are **not API implementations**. The client sends the finished local
resignation result through the existing game PATCH; the API stores the supplied
snapshot and completed status but does not independently validate the winner.
Before treating these actions as server-authoritative,
the backend needs validated match state, a real scoring engine, and internal AI
actor/turn handling. The present client snapshot synchronization is not a
cheat-resistant server authority. No Google sign-in flow is added: there is no
corresponding game UI, and the API callback contract alone does not provide a
native-app token handoff.

Run focused contract checks using `--headless --path . --script
res://tools/validate_api_clients.gd` with the project engine. These tests use a
fake HTTP transport and never modify a live account or game.
