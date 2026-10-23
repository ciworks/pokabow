#!/usr/bin/env sh
# Milestone 0 repeatable command: project validation + headless smoke tests.
#
# Usage:  tools/validate.sh
#
# Engine resolution order:
#   1. $GODOT_BIN
#   2. godot / godot4 / Godot on PATH
#
# Exit codes: 0 = all checks passed, 1 = a check failed, 2 = no engine found.

set -u

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

find_engine() {
	if [ -n "${GODOT_BIN:-}" ]; then
		if command -v "$GODOT_BIN" >/dev/null 2>&1 || [ -x "$GODOT_BIN" ]; then
			printf '%s\n' "$GODOT_BIN"
			return 0
		fi
		printf 'GODOT_BIN is set to "%s" but is not executable.\n' "$GODOT_BIN" >&2
		return 1
	fi

	for candidate in godot godot4 Godot; do
		if command -v "$candidate" >/dev/null 2>&1; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	return 1
}

ENGINE=$(find_engine) || {
	echo "No Godot engine binary found."
	echo "Install Godot 4.6, or point GODOT_BIN at one, then re-run:"
	echo "  GODOT_BIN=/path/to/godot tools/validate.sh"
	exit 2
}

echo "engine:  $ENGINE"
echo "project: $PROJECT_DIR"
echo

echo "== project validation (import) =="
"$ENGINE" --headless --path "$PROJECT_DIR" --import
import_status=$?

echo
echo "== headless smoke tests =="
"$ENGINE" --headless --path "$PROJECT_DIR" --script res://tests/harness/test_runner.gd
test_status=$?

echo
if [ "$import_status" -ne 0 ]; then
	echo "RESULT: FAIL (project validation exited $import_status)"
	exit 1
fi
if [ "$test_status" -ne 0 ]; then
	echo "RESULT: FAIL (headless tests exited $test_status)"
	exit 1
fi

echo "RESULT: PASS"
exit 0
