class_name AiCancellationToken
extends RefCounted

## Cooperative cancellation for one AI analysis (ADR-005 section 9).
##
## ADR-005 section 9 requires a cancelled analysis to stop, and requires partial
## results never to be committed. This token is the smallest thing that can
## carry that fact: the owner cancels it, and a search loop polls it between
## candidate batches instead of being killed from outside.
##
## It is deliberately cheap: `is_cancelled()` is one boolean read, so a search may
## poll it in its inner loops without measuring the cost (ADR-005 section 8
## forbids wall-clock cutoffs, so polling is the only interruption mechanism).
##
## Closing or restarting a match cancels the outstanding token
## (ADR-005 section 9); a token is never reused for a later decision.

## True once `cancel()` has been called.
var _cancelled: bool = false

## The turn deadline may cancel analysis, independently of its node budget.
## Zero keeps non-timed analysis and deterministic strategy tests unchanged.
var deadline_msec: int = 0


## Cancels the analysis. Calling it twice changes nothing.
func cancel() -> void:
	_cancelled = true


## Returns true when the owner has cancelled this analysis.
func is_cancelled() -> bool:
	return _cancelled or (deadline_msec > 0 and Time.get_ticks_msec() >= deadline_msec)


## Clears the cancellation so one token may serve a later decision.
##
## ADR-005 section 9 treats a decision as the cancellable unit, so a caller that
## reuses a token must reset it explicitly rather than rely on a default.
func reset() -> void:
	_cancelled = false
	deadline_msec = 0
