# Clearer edge bands — concept, 2026-10-19

Status: **Proposed**, not adopted by the game renderer.

The captures use the actual game scene at a 360×800 window, with the existing
logical canvas and unchanged overview/close camera geometry. All variants share
the same 28-tile position from 16 legal moves generated with seed 4242, committed
through MoveCommitter and TurnManager. Scores, remaining tiles and racks come
from that session.

| Treatment | Band thickness | Colour rendering |
| --- | --- | --- |
| Current | 14 / 200 source pixels (7%) | Existing coloured PNG multiplied by palette tint |
| Clear bands | 18 / 200 (9%; about 29% thicker) | Neutral mask, tinted once with the approved palette |
| Stronger bands | 22 / 200 (11%; about 57% thicker) | Neutral mask, tinted once with the approved palette |

The proposed masks retain ivory corner breaks, leave the face readable and keep
the base's lower lip. No palette categories, scoring rules or camera sizes change.
The colour difference is the removal of the artwork's additional colour multiply;
it is not a newly chosen palette. The concepts are not a complete colour-vision
accessibility treatment.

Reproduce with Godot and `--script res://tools/preview_edge_bands.gd`. This tool
overrides only the running process's TilePainter texture cache and restores it
before exiting. It does not modify the production tile artwork or painter.

Rendered with Godot 4.7.2 Compatibility. Legal commits were asserted; screenshot
geometry is identical across variants for each zoom. Visual review covers both
zooms. Physical-device readability, colour-vision user testing and Godot 4.6
verification remain outstanding.
