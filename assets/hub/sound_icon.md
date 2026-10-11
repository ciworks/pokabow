# Hub sound sprite

Created 2026-10-06 with the built-in image_gen tool, using
`settings_icon.png` as the edit reference. Replaces `sound_icon.png`, already
referenced by the hub SoundButton. Transparent background; dark circular steel
rim and ivory speaker match the settings sprite. Existing sound toggle and
muted tint are retained.

The Godot import limits the runtime texture to 128 pixels for the small hub
button while preserving the full-resolution source PNG.

Verified in Godot 4.7.2: imported at 128x128, rendered at 320x568 and 540x960,
and sound-button signals toggled/restored the Master audio bus. Visually checked
beside the settings sprite. Physical-device and Godot 4.6 checks remain open.

## Generation prompt

Use case: precise-object-edit. Asset type: transparent mobile-game sound button sprite. Edit target: the supplied settings icon from the game's hub. Replace ONLY the central ivory gear with a clear ivory speaker pointing right and two simple curved sound-wave strokes to its right. Preserve the reference's round dark charcoal/navy recessed button face, layered dark steel beveled circular rim, subtle cool gray top-left highlights, dark lower-right shading, restrained dimensional game UI finish, front-on view and near-square silhouette. The speaker and waves should be flat warm ivory like the original gear, thick enough to read at a 48px icon size, centered as a single balanced glyph with generous room inside the rim. Keep the circular button artwork filling almost the whole square with narrow transparent padding. Output one standalone sound-on button sprite, genuinely transparent alpha outside the circle. No checkerboard, no text, no neon colors, no extra frame, no gear, no surrounding scene.
