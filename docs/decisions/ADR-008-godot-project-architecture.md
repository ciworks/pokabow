# ADR-008: Godot Project Architecture

- **Status:** Proposed - requires technical approval
- **Date:** 2026-09-21
- **Owners:** Engineering
- **Decision scope:** Phase 1 Godot 4.6 project
- **Source:** `GAME_SPEC.md` and `iterative_specification.pdf`
- **Related:** ADR-001 through ADR-007

## Context

The game targets Godot 4.6 and must support a mobile-first Human vs AI experience, deterministic rules, incremental scoring, save/resume, and automated tests. The accepted ADRs deliberately define gameplay independently of rendering. The project architecture must preserve that separation while remaining simple enough for iterative AI-assisted development.

Without explicit boundaries, game rules can drift into scene scripts, UI can become authoritative state, autoloads can hide dependencies, and AI/tests can require visual nodes. This ADR defines the initial project layout, dependency direction, scene ownership, and integration contracts.

## Architectural goals

1. Keep gameplay rules testable without loading visual scenes.
2. Maintain one authoritative `GameSession` for an active match.
3. Make UI and effects react to committed results rather than calculate rules.
4. Use typed GDScript compatible with Godot 4.6.
5. Keep dependencies explicit and minimize global state.
6. Support landscape mobile layouts, touch input, interruption, and save/resume.
7. Allow optimized implementations to be checked against pure reference logic.
8. Keep the project runnable after every coherent development increment.

## Proposed decision

### 1. Layered dependency direction

Use four conceptual layers:

```text
Presentation -> Application -> Domain
	   |             |
	   +-------> Infrastructure
```

- **Domain:** deterministic game data and rules; no dependency on scenes, controls, animation, audio, or device APIs.
- **Application:** coordinates use cases such as starting a match, previewing a move, committing a turn, running AI, saving, and resuming.
- **Presentation:** scenes, controls, input mapping, animation, particles, sound, haptics, and view models.
- **Infrastructure:** persistence, platform adapters, logging, clocks, and optional analytics.

Dependencies point inward toward Domain. Domain code must not import Presentation or Infrastructure types.

### 2. Project directory layout

Use a feature-aware structure with clear layer boundaries:

```text
res://
  project.godot
  assets/
	audio/
	fonts/
	textures/
  resources/
	rules/
	themes/
  scenes/
	app/
	splash/
	game/
	components/
	debug/
  scripts/
	domain/
	  tile/
	  board/
	  placement/
	  scoring/
	  turn/
	  ai/
	application/
	infrastructure/
	presentation/
  tests/
	unit/
	integration/
	fixtures/
  docs/
	decisions/
```

Do not organize all scripts into one large generic folder or mirror every scene with a manager singleton.

### 3. Domain object types

Use these Godot base types intentionally:

- `RefCounted` for transient domain commands, results, evaluators, and services.
- `Resource` for versioned rule configuration and serializable immutable definitions.
- Plain typed value fields, enums, arrays, and dictionaries for deterministic state.
- `Node` only when scene-tree lifecycle, signals, processing, or platform integration is actually required.

Core domain types include:

- `TileData` and `TileSnapshot`
- `BoardState`
- `PlacementRequest` and `PlacementResult`
- `GameSessionState` and `TurnState`
- `MoveCommand` and `MoveResult`
- `ScoreEvent` and `ScoreLedger`
- category scoring services
- AI state snapshot and decision result

Domain services receive dependencies through constructors or explicit initialization methods rather than reading the scene tree or autoloads.

### 4. Scene hierarchy

The initial runtime scene hierarchy is:

```text
AppRoot
  SceneHost
	SplashScreen | HubScreen | OpponentSelectionScreen | GameScreen | ProfileScreen
  OverlayLayer
	TransitionOverlay
	ErrorDialog
  AccessibilityLayer
```

The `AppRoot` boot sequence is: the engine's own boot splash shows first, set
from `application/boot_splash` to the same background colour as the scene
splash, with the default image disabled. `AppRoot._ready()` then holds the
authored `SplashScreen` for `SPLASH_HOLD_SECONDS` before showing the hub. A new
match moves from the hub through `OpponentSelectionScreen` to `GameScreen`; a
saved match resumes directly into `GameScreen`.

The hold is branding, not a loading wait - nothing is loaded during it. It is a
`Timer` child rather than an awaited coroutine, so a tree torn down mid-hold
drops the timer instead of resuming into a freed node; the test suite instantiates
and frees the app root without flushing deferred callbacks, so an `await` there
would resume against a freed node. `TurnEnums` documents `SPLASH` as a
presentation state owned by the app shell rather than a rules phase, which is why
the hold lives in the composition root and not in the turn manager. Booting
remains callable directly and synchronously, so the integration test can drive it
without waiting a real second.

The `GameScreen` scene contains (layout revised from the owner's reference on
2026-09-29):

```text
GameScreen
  Root / Column
	HeaderTools
	Hud
	  HumanScorePanel
	  PotPanel (TilePileView, AvailableTilesLabel)
	  AiScorePanel
	Body / BoardViewport / BoardView
	  TileLayer
	  PreviewLayer
	  HighlightLayer
	  ClusterDisplayLayer
	  ScoreRevealLayer
	  EffectsLayer
	  DebugOverlay
	DeckBar / DeckPanel / RackColumn / DeckRow / DeckView
  CommandDrawer
	DrawerScrim
	DrawerPanel
	  DrawerColumn
		DrawerHeader (TurnIndicator, CloseMenuButton)
		CommandScroll / Commands
		  ConfirmButton, RotateButton, SwapButton, CancelButton
		  SwapConfirmButton, SwapCancelButton
		  PreviewPanel, StatusLabel
		  MatchToggle, MatchOptions (DifficultyPicker, RestartButton, ResignButton, MenuHubButton)
	MenuTab
  FeedbackLayer
	FloatingScores
	DealLayer
	SummaryOverlay
	RecoveryOverlay
```

Node names communicate presentation responsibilities only. `BoardView` renders `BoardState`; it does not own placement legality or scores.

`GameCommandDrawer` owns animation, dismissal, responsive bounds, and its Match
settings accordion. `GameScreen` wires its commands and renders a read-only
`ScoreTransaction` supplied by `GameSessionController.pending_score_preview()`.
The pot is a single shared count, and the drawer never computes a game rule.

### 5. Application composition root

`AppRoot` creates application-level services and injects them into the active screen controller. It is the composition root for:

- game session controller;
- move/preview application services;
- tile source;
- scoring coordinator;
- AI coordinator;
- save repository;
- platform feedback adapter; and
- structured logger.

Scene scripts receive narrow interfaces or service references. They do not locate arbitrary nodes by absolute paths or pull rule services from globals.

### 6. Autoload policy

Use autoloads only for process-wide platform/app services whose lifecycle genuinely spans scenes. Phase 1 permits at most:

- `AppState` for navigation-level state and application lifecycle; and
- `PlatformServices` for save-path, haptics, and platform integration adapters.

The active `GameSession`, score ledger, board state, AI, and turn manager are not autoloads. They are owned by the application composition root and released when the match ends.

No autoload may become a general service locator or contain mutable gameplay rules.

### 7. Signals and commands

Use explicit commands from presentation to application and signals/results from application to presentation.

Presentation submits intents such as:

- select/drag active tile;
- rotate preview;
- request placement preview;
- confirm move;
- cancel preview; and
- request save or resume.

Application emits or returns events such as:

- session started;
- turn started;
- preview updated;
- move committed;
- score events committed;
- AI thinking state changed;
- game ended; and
- recovery required.

Signals are typed where Godot permits. Avoid a global event bus: direct ownership and explicit signal connections are easier to trace and test.

### 8. Input architecture

- Centralize pointer-to-board coordinate conversion in `BoardInputController`.
- Treat tap and drag as presentation gestures that produce the same placement-preview intent.
- Keep rotation as an explicit command independent of visual animation.
- Support mouse input in development through the same intent path as touch.
- Disable or gate human input outside the human `AWAIT_ACTION` phase.
- Never commit a move directly from `_input`; submit a command to the application layer.

### 9. Rendering and view synchronization

- Render committed tiles from immutable `MoveResult` and session snapshots.
- Render previews in a separate layer with no mutation of `BoardState`.
- Use object pooling only after profiling shows allocation or frame-time pressure.
- Animate from committed score events in deterministic event order.
- If animation is skipped or interrupted, synchronize immediately to the authoritative snapshot.
- Visual effects never delay or determine rules completion; the application may expose an animation barrier for presentation pacing only.

### 10. AI execution

- AI consumes an immutable domain snapshot and returns a move proposal.
- AI never reads or manipulates `BoardView` nodes.
- Medium and Hard AI may run through a worker thread or deferred task after their algorithms are stable.
- Any threaded work operates only on detached data and cannot access the live scene tree.
- The returned move is revalidated on the main rules path before commit.
- Cancellation tokens or generation IDs discard stale decisions when a session closes or restarts.

### 11. Save and lifecycle integration

`SaveRepository` serializes a versioned DTO produced by the application layer. Scene nodes are never serialized as game state.

Save at stable transaction boundaries:

- after match setup;
- after each committed move; and
- when the application receives a background/suspend notification, if state is stable.

If suspension occurs during a preview or AI calculation, preserve the last committed snapshot plus the active tile and resume in the appropriate `AWAIT_ACTION` phase as defined by ADR-003.

### 12. Rules resources

Versioned `.tres` resources provide approved configurable values, including:

- poker-hand point values;
- cluster milestone size and points;
- tile-generation weights and bag size;
- board dimensions; and
- AI difficulty parameters after ADR-005 is accepted.

Load and validate these resources during match setup, then store a stable rules version/hash in match state. Do not allow a live match to change when an editor resource is reloaded.

### 13. Testing architecture

Use three test levels:

1. **Domain unit tests:** instantiate `RefCounted`/`Resource` rules directly with no scene tree.
2. **Application integration tests:** construct a complete session with deterministic fakes for tile source, save repository, and AI.
3. **Scene smoke tests:** load key scenes to verify signal wiring, responsive layout, and command routing.

Domain and application tests must run headlessly. Scene smoke tests should be few and focused; rule correctness must not depend on pixel interaction tests.

### 14. Logging and debug tools

Use structured diagnostic records keyed by match ID, move ID, turn, board revision, and rules version. Development builds may expose overlays for:

- cell coordinates;
- tile IDs and rotations;
- valid frontier;
- rotated edges and matches;
- poker windows;
- color clusters and entitlement;
- score-event ledger;
- AI candidate values; and
- incremental versus replay verification.

Debug overlays observe snapshots and diagnostic results. They do not gain mutation privileges unavailable to production UI.

### 15. Performance policy

- Correct pure reference logic comes before optimized caches.
- Measure on representative mobile hardware before introducing pooling, multithreading, or custom rendering.
- Avoid per-frame rules recalculation; update views in response to state changes.
- Keep AI and full replay off the render-critical path when they become expensive.
- The 12 x 12 board is small enough that clarity is preferred over premature low-level optimization.

## Dependency rules

The following dependencies are allowed:

| From | May depend on |
|---|---|
| Domain | Domain and approved rules resources |
| Application | Domain and narrow infrastructure interfaces |
| Infrastructure | Domain DTOs and platform APIs |
| Presentation | Application interfaces/results and presentation assets |

The following are prohibited:

- Domain importing scene scripts or `Control`/`Node2D` implementations.
- UI calculating placement legality or points.
- AI querying visual nodes.
- Infrastructure advancing turns or altering rules.
- Autoloads exposing arbitrary mutable match objects.
- Scene paths serving as identifiers for tiles, moves, players, or score events.

## Alternatives considered

### Put all behavior in the main game scene

This is quick for a prototype but couples rules to lifecycle and visual nodes, preventing reliable headless tests and AI simulation.

### Make every manager an autoload

Global managers simplify access but hide ownership, leak state between matches, and make tests order-dependent. Explicit composition is preferred.

### Use Nodes for every domain class

Nodes add scene-tree lifecycle and coupling where plain data/services are sufficient. `RefCounted` and `Resource` types are more appropriate for deterministic rules.

### Adopt a large dependency-injection framework

The project does not need that complexity. A manual composition root and explicit references are sufficient for Phase 1.

### Build a custom ECS architecture

The small turn-based board does not justify an entity-component-system framework. Focused domain types and services are simpler.

## Consequences

### Benefits

- Rules, AI, replay, and saves can operate without visual scenes.
- Scene responsibilities are narrow and understandable.
- Match state has clear ownership and lifecycle.
- Mobile interruption and preview behavior align with accepted ADRs.
- Tests can validate most functionality headlessly and quickly.
- Later optimization can replace internals behind stable application contracts.

### Costs and risks

- Explicit DTOs and application services require more initial files than scene-centric scripting.
- Developers must maintain discipline around dependency direction.
- Manual composition needs a clear bootstrap path.
- Presentation snapshots and signals require careful disconnect/cleanup when scenes change.
- Godot editor conveniences may tempt rules back into exported scene fields.

## Required tests and checks

- Domain tests run without loading `GameScreen`.
- A session can be constructed with fake infrastructure dependencies.
- Human and AI commands route through the same application commit service.
- Scene teardown releases the match and disconnects signals.
- A second match starts with no state leaked from the first.
- Preview rendering never mutates `BoardState`.
- Interrupted animation resynchronizes to authoritative state.
- Save/resume uses DTOs rather than scene serialization.
- Backgrounding during preview and AI thinking preserves the last valid state.
- Rules resources validate and remain fixed during a match.
- Headless replay produces the same result as an interactive session.
- Landscape layouts remain usable at supported aspect ratios and safe areas.
- Debug overlays cannot mutate production state.

## Approval questions

This ADR should not move to **Accepted** until the following are confirmed:

1. Should the project use Domain, Application, Presentation, and Infrastructure boundaries?
2. Should gameplay rules primarily use `RefCounted`/`Resource` types and remain independent of scenes?
3. Should `AppRoot` act as the manual composition root for per-match services?
4. Should autoloads be restricted to process-wide app/platform services, excluding active match state?
5. Should UI and AI interact with gameplay only through commands, snapshots, and committed results?
6. Should saves serialize versioned DTOs rather than scene nodes?
7. Should domain and application tests run headlessly, with only focused scene smoke tests?

## Acceptance and implementation

Once the approval questions are resolved:

1. Change the status to **Accepted** and record any amendments.
2. Create the directory structure and minimal Godot 4.6 project.
3. Add rules resources and foundational domain DTOs.
4. Implement the composition root and an empty `GameScreen` integration shell.
5. Add the headless test harness before implementing feature logic.
6. Build the first vertical slice in dependency order: tiles, board, placement, scoring, turns, UI, then AI.

## Amendments

- 2026-09-23: Owner replaced the side-panel active-tile preview with the shared
  tile count, moving that count out of the HUD. The `ActiveTileView` node and the
  `RemainingTilesLabel` node are gone; `AvailableTilesLabel` now sits in
  `ActiveTilePanel`, and both the tree above and `game_screen.gd` report it.
  Staging feedback is unchanged: the pending line and its validity verdict are
  still drawn on the board by `PreviewLayer`. Presentation only; no gameplay rule,
  scoring, or placement behaviour was altered.
- 2026-09-23: Added the turn highlight. `HumanScorePanel` and `AiScorePanel` are
  now uniquely named, and `game_screen.gd` outlines the panel of the player whose
  turn it is in `TURN_HIGHLIGHT_COLOR`, restores the authored style for the other,
  and highlights neither once the match is over. The outlined style is derived from
  the panel's own style at runtime, so the node tree above and section 4's names are
  unchanged. Presentation only: the highlight reports the turn the controller
  already owns and decides nothing.
- 2026-09-24: Added edge and cluster visualization (AGENTS.md section 8,
  GAME_SPEC section 7.3, Milestone 8's first deliverable). A new
  `ScoreRevealLayer` under `BoardView` draws what a committed move actually
  scored: a bar across each matching boundary and a tinted, outlined region over
  each paying colour cluster. It is driven from the same committed `ScoreEvent`
  list the floating popups read, taking the cells and the edge colour each event
  already carries, so it re-derives nothing and can only ever show awards that
  were really made. The reveal holds, fades, and drops its marks, and is cleared
  when the board is torn down, so no mark outlives its match or an interrupted
  animation (section 9). Presentation only: no rule, score value, or placement
  behaviour changed.
- 2026-09-24: Wired the match persistence that Milestone 7 requires (section 11
  already required saving at stable boundaries; nothing reached the save before
  this). `GameSessionController._after_state_change()` now calls `autosave()`, so
  the one choke point every committed change passes through - setup, a human
  line, a swap, and the opponent's move - persists the result, and it does so
  before the rival's turn is scheduled. The same autosave runs on
  `NOTIFICATION_APPLICATION_PAUSED`, `NOTIFICATION_WM_WINDOW_FOCUS_OUT`, and
  `NOTIFICATION_WM_CLOSE_REQUEST` as a second safety net for a termination
  between moves. `AppRoot.boot_game_screen` calls `resume_match()` before
  `start_new_match()`, so an interrupted match is picked up; a resume is now
  reported through the existing `notice` channel. The single save path became a
  `save_path` property defaulting to `SAVE_PATH`, so a test points it at its own
  file instead of overwriting the player's match. The recovery screen itself
  (a scene rendering `MatchPhase.RECOVERY_ERROR`) is still not built: a refused
  restore reports through `notice` and starts a fresh match, which is the
  behaviour a boot-time failure needs.
- 2026-09-24: Development overlays and replay/export fixture support, the other
  two Milestone 7 deliverables, are not implemented. They are diagnostics with no
  effect on play, and they remain open.
- 2026-09-24: Reworked the score reveal after the owner reported it did not say
  clearly which tiles scored. The per-join boundary bar is gone: the owner found
  it unreadable, so every scoring group - edge match, cluster, and now poker hand
  - is instead outlined around its tiles' outer perimeter in one high-contrast
  `HIGHLIGHT_COLOR`, with the outer edge of the group only rather than every
  tile, so an adjacent pair reads as one joined shape. Poker hands are revealed
  here for the first time; the layer previously skipped them. The owner also
  asked for the hand's tiles to bounce in sequence, so the layer raises a
  staggered lift signal that the shared `BoardRenderState` carries as a per-cell
  offset and `BoardTileLayer` applies when it draws the committed tile. The reveal
  drives that animation itself, so it can pause on the last frame instead of
  being cut off by the fade, and it still reads only the committed `ScoreEvent`
  cells, so it can never show an award that was not made.
- 2026-09-29: The owner requested that played poker hands leave no board
  highlights. The regular last-move outline was removed, and `ScoreRevealLayer`
  now skips poker-hand outlines while retaining the requested tile bounce;
  floating score feedback remains. The owner then requested that edge matches
  not be marked on the board. `ScoreRevealLayer` skips edge-match outlines and
  `BoardPreviewLayer` no longer draws match ticks on staged tiles. Edge-match
  scoring remains unchanged, as does cluster feedback. These changes supersede
  the corresponding visual details described in the 2026-09-24 note above.
- 2026-09-25: Added the rival difficulty picker, closing the gap that made
  Milestone 6's exit criterion unreachable (all three AI difficulties existed and
  were tested, but nothing let the player select one). `GameScreen` gained a
  `DifficultyPicker` `OptionButton` in a `DifficultyBox` in the HUD, built from
  `AiEnums.Difficulty` and wired to the already-documented
  `GameSessionController.set_ai_difficulty()`, plus `_refresh_difficulty()` so the
  control displays the policy actually in force. "New match" carries the chosen
  difficulty into the fresh match rather than reverting to the default. The screen
  still decides nothing: it shows the value the controller reports and forwards
  the player's choice, so the picker and the opponent cannot disagree
  (AGENTS.md section 19). Presentation only; no AI rule changed.
- 2026-09-25: Completed Milestone 7's three outstanding deliverables, all of them
  diagnostics that leave match state untouched.
  1. *Recovery screen.* `GameSessionController` gained a `recovery_failed(reason)`
     signal, emitted by `_recovery_failed()` alongside the existing notice, so a
     refused restore is a state the player resolves rather than one line of
     status. `game_screen.tscn` gained a `RecoveryOverlay` under `FeedbackLayer`
     (dim, centred panel, reason, and a "Start a fresh match" button), and
     `GameScreen._on_recovery_failed()` renders it while creating no session. The
     unreadable save is deliberately left on disk, so the refusal preserves the
     last valid transaction instead of destroying it. The overlay is visible only
     after a failure, so it cannot block input in a normal session.
  2. *Development overlays.* A new `DebugOverlay` control, last child of
     `BoardView` so it draws above every board layer, rendering cell coordinates,
	 the legal frontier from `BoardState`, the last move's committed cells, and a
	 panel of board revision, pot, move count, difficulty, and the latest award's
     score events. It is off unless the `debug/overlays` project setting is on,
     toggled with F3, and it never calls `set_input_as_handled`, so it cannot
     swallow a board gesture (AGENTS.md section 17 keeps debug tooling out of the
     player experience). It reads only what the controller and the committed
     `ScoreEvent` list already report, so it cannot invent a diagnostic.
  3. *Replay/export.* `GameSessionController.export_fixture()`, bound to F4 in the
     overlay, writes the same versioned snapshot the autosave writes - complete
     bag, both decks, board, ledger, and the ordered move history the replay
     verifier consumes - to `user://match_fixture.json`, wrapped with the export
     time, engine version, and difficulty. It is the snapshot rather than a second
     summary of the match, so a fixture cannot describe a position the rules could
     not produce, and loading it back exercises the same restore path a saved
     match uses. The location is a `fixture_path` property defaulting to that
	 constant, so a test does not overwrite a developer's export.
- 2026-09-25: Implemented the platform feedback adapter's second and third
  channels, closing Milestone 8's audio-and-haptics deliverable. `AppRoot` now
  creates a `FeedbackAdapter` and injects it into the screen with
  `attach_feedback_adapter`, exactly as section 5 requires and as the difficulty
  picker did for the AI: composition stays in the root and the screen only reports
  and displays. The service grew haptic cues and a short one-shot sound per cue,
  both optional and separately switchable, both silent no-ops when off. It owns its
  own `AudioStreamPlayer` pool as children rather than an autoload, because section
  6 forbids a service in a global. The screen calls the cues when a human gesture
  resolves, never by subscribing to controller signals: `line_committed` and
  `score_awarded` fire for the rival's move as well, so a subscriber would buzz the
  player's phone for an action they did not take. No rule, score, or turn path
  reads either channel, so the match plays identically with sound and haptics off -
  that is what keeps them optional rather than required. Presentation only; no
  gameplay rule changed.
