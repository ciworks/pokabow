class_name TestCase
extends RefCounted

## Minimal headless test base class (ADR-008 section 13).
##
## A test case is a plain RefCounted object: it never extends Node and never
## touches the scene tree, so domain and application behaviour stays testable
## without loading presentation scenes.
##
## The runner (res://tests/harness/test_runner.gd) discovers every public method
## whose name starts with `test_` and calls it with no arguments.
##
## Assertions record failures instead of aborting, so one broken expectation
## still reports every remaining expectation in the same test method.

## Human-readable failure messages recorded during this run, newest last.
var failures: PackedStringArray = PackedStringArray()

## Number of assertions evaluated during this run.
var assertions: int = 0


## Records one expectation. Returns the condition so callers can chain early exits.
func check(condition: bool, message: String) -> bool:
	assertions += 1
	if not condition:
		failures.append(message)
	return condition


## Records one equality expectation, reporting expected and actual values on failure.
func check_eq(actual: Variant, expected: Variant, message: String) -> bool:
	return check(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


## Records one non-null expectation.
func check_not_null(value: Variant, message: String) -> bool:
	return check(value != null, message)
