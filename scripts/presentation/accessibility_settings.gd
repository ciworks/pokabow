class_name AccessibilitySettings
extends RefCounted

## The player's accessibility preferences (Milestone 8, docs/sections/05-mobile-ux.md
## section 4, AGENTS.md section 8).
##
## This exists so that one place decides what a preference is CALLED and what it
## defaults to. Three separate systems honour reduced motion - the score reveal,
## the floating points, and the deal - and if each spelled the setting path
## itself, a single typo would leave one of them animating while the player
## believed they had switched animation off. A static read is the smallest thing
## that keeps them agreeing: `TilePainter`, `BoardMetrics` and `EdgeClusterScorer`
## are the same shape, a class of pure helpers rather than an instance.
##
## Reduced motion defaults to FALSE. Motion is the normal experience and this is
## a comfort opt-in, so a build that never mentions the setting behaves exactly
## as it did before this existed. That is the same shape as `feedback/audio` and
## `feedback/haptics`, which also default to on and are read by no rule path.
##
## Reading the setting on every call rather than caching it is deliberate: a
## settings screen can write the preference with `ProjectSettings.set_setting`
## and the very next cue, deal or reveal honours it, with no rebuild and no
## notification plumbing. The reads happen when a moment is cued or a deal
## starts, never per frame, so the dictionary lookup costs nothing noticeable.
##
## Nothing here reads game state, and no rule, score, or turn path may read it:
## switching animation off changes what the player SEES, never what they scored
## (docs/sections/05-mobile-ux.md section 6, the same obligation haptics carry).

## Project setting that switches the animated presentation off for a whole build.
const REDUCED_MOTION_PATH: String = "accessibility/reduced_motion"


## Returns whether the player has asked for reduced motion.
##
## False when the project never sets it, so the setting is opt-in and the normal
## build is unchanged by its existence.
static func reduced_motion() -> bool:
	return bool(ProjectSettings.get_setting(REDUCED_MOTION_PATH, false))
