# Headless test harness

Milestone 0 scaffold for the testing architecture in ADR-008 section 13:
domain unit tests, application integration tests, and a few focused scene smoke
tests. Rule correctness must never depend on pixel interaction.

## Running the tests

Use the one repeatable command from the repository root:

```text
tools/validate.sh      # bash / Git Bash / macOS / Linux
tools/validate.cmd     # Windows cmd.exe
```

Both wrappers run project validation and then the headless smoke tests. They
resolve the engine from `GODOT_BIN` first, then `godot`/`godot4` on `PATH`, then
the engine bundled with the Summer app. Set `GODOT_BIN` to a Godot 4.6 binary if
none of those apply:

```text
GODOT_BIN=/path/to/godot tools/validate.sh
```

To run only the tests:

```text
godot --headless --path . --script res://tests/harness/test_runner.gd
```

The runner exits with `0` only when every assertion passed, and prints
`[harness] PASS` or `[harness] FAIL` as the last line.

## Layout

| Path | Purpose |
|---|---|
| `tests/harness/test_case.gd` | Base class for a test suite. Plain `RefCounted`, never a `Node`. |
| `tests/harness/test_runner.gd` | `SceneTree` entry point. Discovers and runs suites. |
| `tests/unit/` | Domain unit tests. No scene tree. |
| `tests/integration/` | Application tests with fakes. |
| `tests/fixtures/` | Deterministic seeds and fixture data. |

## Writing a test

Create `tests/unit/test_<subject>.gd`:

```gdscript
extends TestCase


func test_something_important() -> void:
	check_eq(2 + 2, 4, "arithmetic must still work")
```

- File names must start with `test_` and end with `.gd`.
- Every public method whose name starts with `test_` is run with no arguments.
- Assertions come from `TestCase`: `check`, `check_eq`, `check_not_null`.
- A failing assertion records a message and continues, so one broken expectation
  does not hide the rest of the method.
- Keep logic deterministic: pass explicit seeds rather than relying on ambient
  randomness (ADR-004 section 9).

## Discipline

- Tests must run headlessly, with no window and no human input.
- Domain and application tests must not load `GameScreen` (ADR-008 section 13).
- Only a small number of scene smoke tests are expected, and only for signal
  wiring, responsive layout, and command routing.
- Add a regression test whenever a core-logic bug is fixed (AGENTS.md section 16).
