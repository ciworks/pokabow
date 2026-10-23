# Account deletion

The hub settings panel stays within the viewport with 16px margins and scrollable content. Close remains outside the scroll area.

Delete Account opens a warning and a separate permanent-delete confirmation. Cancel sends no request. Confirm sends authenticated DELETE /auth/me with {"confirm": true}; an expired token is refreshed once using the saved credentials. Only HTTP 204 or HTTP 200 with success=true starts local cleanup. Connection, authentication and server failures keep local data and offer retry.

After server success the shell stops sync and achievement clients, cancels account requests, releases match/profile state, and removes users_state.json (credentials, token, user details, terms and pending achievements), match_save.json, match_fixture.json, game_sync_state.json and settings.cfg from user://. Cleanup failures offer a local-only retry. Success remains visible until Continue restarts the shell at account setup. This clears this installation's state; other devices are not remotely wiped.

The companion pokabow-api must be deployed with DELETE /auth/me. Its transaction removes games involving the account and their turns/memberships, then the user; OAuth links and achievements cascade. Existing bearer tokens are rejected by other protected routes once the account is gone. A valid signed deletion token can retry deletion idempotently if the response was lost. The current game mode is human versus AI.
