# Pokabow header logo v2

Created 2026-10-05 with the built-in image_gen tool, editing v1.

Asset: [Transparent PNG](pokabow-header-logo-v2.png).

Straightened the seven-letter POKABOW wordmark and removed the tile. Preserved gold/ivory lettering and the royal-blue outline. Visually checked spelling, upright alignment and tile removal. The PNG retains alpha transparency. Earlier variants are preserved.

Integrated into `scenes/game/game_screen.tscn` on 2026-10-05 through
[the AtlasTexture resource](pokabow-header-logo-v2.tres), which excludes the
transparent margins. The centered 48px header preserves image proportions and
settings clearance in both orientations. Rendered at five phone/desktop sizes;
layout bounds and interaction checks passed. Physical-device QA remains open.

Integrated into `scenes/splash/splash_screen.tscn` on 2026-10-06, replacing
the text title with the same AtlasTexture at 440x84 reference-canvas pixels.
The logo keeps its proportions above the existing accent and tagline.
Rendered at 320x568, 540x960 and 1280x720 window sizes using Godot 4.7.2;
logo bounds passed and phone/wide-window previews were visually inspected.
Godot 4.6 and physical-device verification remain open.

## Exact generation prompt

Use case: precise-object-edit / logo-brand.
Edit the supplied POKABOW header logo.
Make exactly these changes:
1. Remove the entire square spade tile emblem at the left. Remove every part of the tile, its colored edges, shadow and outline. Leave only the wordmark.
2. Straighten the wordmark: all seven letters P O K A B O W should be upright, without individual rotation or italic slant, set on one perfectly straight horizontal baseline with consistent cap height. No arch, wave, perspective skew or tilting. Use balanced even spacing.
Preserve the existing exact spelling POKABOW and its bold block-serif identity, warm ivory/gold face, subtle polished gold bevel and dark royal-blue outline/extrusion. Preserve the attractive high-contrast mobile-game finish. Do not redesign the typeface, add ornaments, add a crown, replace the tile with anything, or add any other words.
Output one centered standalone horizontal POKABOW wordmark. Genuinely transparent alpha background, with modest padding closely surrounding the wordmark. No scene, background rectangle, mockup or baked-in checkerboard. Keep all lettering fully visible. The only visible content is the straightened seven-letter POKABOW wordmark.
