# Fredoka — Pokabow interface font

Added 2026-10-18 from the official Google Fonts repository.

- [Family page](https://fonts.google.com/specimen/Fredoka).
- [Original variable font](https://github.com/google/fonts/blob/main/ofl/fredoka/Fredoka%5Bwdth%2Cwght%5D.ttf).
- [Licence source](https://github.com/google/fonts/blob/main/ofl/fredoka/OFL.txt).
- Local licence: [OFL.txt](OFL.txt), SIL Open Font License 1.1.
- Font SHA-256: 2ba02e68b152868aef9ba28e24b3648c7d457fe6f25c761f2c2c53fb61a73fc8.

The downloaded font bytes are unmodified; the local filename is
Fredoka-Variable.ttf for convenient resource paths. The .tres resources use the
font's real OpenType weight axis at normal width (100), without synthetic bold
or horizontal scaling:

| Resource | Weight | Use |
| --- | --- | --- |
| Fredoka-Regular.tres | 400 | Supporting text and body copy |
| Fredoka-Medium.tres | 500 | Gameplay interface and stronger labels |
| Fredoka-Semibold.tres | 600 | Buttons and section labels |
| Fredoka-Bold.tres | 700 | Wordmark and headline |

The licence permits commercial use and font embedding subject to its terms.
Preserve the copyright notice and OFL.txt when distributing these fonts.
The Android export preset includes OFL.txt explicitly. New export presets must
also include the licence; it is not automatically imported as a Godot resource.
The font may not be sold on its own.

The approved type sizes and usage are in [DESIGN_SYSTEM.md](../../../docs/DESIGN_SYSTEM.md#typography).

Godot 4.6 resources use numeric OpenType tags (2003265652 for weight and 2003072104 for width). Renderer-coordinate verification is required: string-tag settings fell back to the Light master in the installed engine.
