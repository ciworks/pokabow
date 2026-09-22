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
    SplashScreen | GameScreen
  OverlayLayer
    TransitionOverlay
    ErrorDialog
  AccessibilityLayer
```

The `GameScreen` scene contains:

```text
GameScreen
  BoardViewport
    BoardView
      TileLayer
      PreviewLayer
      HighlightLayer
      EffectsLayer
  Hud
    HumanScorePanel
    AiScorePanel
    TurnIndicator
    RemainingTilesLabel
  ActiveTilePanel
    ActiveTileView
    RotateButton
    ConfirmButton
    CancelButton
  FeedbackLayer
    FloatingScores
    MatchSummary
```

Node names communicate presentation responsibilities only. `BoardView` renders `BoardState`; it does not own placement legality or scores.

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

None. This is the initial proposal.
