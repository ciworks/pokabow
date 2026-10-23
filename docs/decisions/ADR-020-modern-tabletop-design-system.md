# ADR-020 — Modern Tabletop Design System

- **Status:** Decided.
- **Date:** 2026-10-17.
- **Owner:** Game owner.
- **Source:** Owner approval of the Modern Tabletop concept and request to formalise it as guidance for new elements, pages and layouts.
- **Resolves:** GAME_SPEC sections 7.3 and 7.6; previously open visual identity and cross-screen consistency.
- **Canonical specification:** [DESIGN_SYSTEM.md](../DESIGN_SYSTEM.md).
- **Implementation status:** Documentation and hub/settings adopted; other screen migrations pending. See the dated implementation note below.

## Context

The project contains several historical visual references and independently
styled screens. The mobile UX notes still described visual style as unspecified.
The owner approved the Modern Tabletop concept and asked for a formal standard
to guide future development.

## Decision

Adopt Modern Tabletop as the common visual language across all new or redesigned
UI, including screens not depicted in the reference. The canonical design system
defines the palette, typography, spacing, tiles, avatars, buttons, page structure,
component states and review checklist. Store the reference image and original
generation prompt in the repository so the guidance has no dependency on a
machine-local chat artifact.

For visual decisions, the written design system outranks the reference image,
earlier styling notes and incidental styles in existing source. Older documents
remain useful records of implemented behaviour and testing. This scope does not
override gameplay, feature availability, input, persistence, networking or
architecture decisions.

Adoption is incremental. New work follows the standard; existing screens are
restyled when that implementation work is undertaken. Shared Godot resources
should carry reusable styling as adoption is implemented. This decision does not
claim those resources or restyled scenes already exist.

## Constraints and consequences

- Preserve the 12×12 board, six-tile rack, current zoom/input behaviour, legal
  ranks and suits, four semantic edge colours, scoring and multiplayer contracts.
- Preserve existing photo preview/save behaviour and reduced-motion settings.
- Treat the generated board and scores as illustrative, not validated gameplay.
- Apply the standard to all UI, without adding unimplemented game features.
- Existing avatars, logos, backgrounds and scenes remain runtime assets until
  deliberately migrated; the concept image is not an importable UI sprite sheet.
- Routine component/layout choices within the system need no further design
  decision. Changes to the shared identity require owner agreement and a recorded
  amendment to the standard and decision history.

## Verification

Review confirmed that this decision defines presentation without changing game
rules. It resolves the open visual direction; detailed gesture thresholds,
effect tuning and physical-device QA remain outside that resolution.

For documentation adoption, verify local links, reference-image integrity,
contributor instructions and removal of conflicting unspecified-style wording
in the game specification and mobile UX summary. No runtime tests establish
visual implementation for a documentation-only change.

For later UI implementation, use the design system's review checklist, render
actual legal game states at the documented phone sizes, test applicable
interaction and asynchronous states, and report device checks still outstanding.

## Implementation note — hub, 2026-10-17

The hub and its settings now consume a shared Modern Tabletop theme and new hero
artwork. This implements the existing decision without changing its scope or
gameplay rules. The design system's [runtime adoption record](../DESIGN_SYSTEM.md#runtime-adoption)
contains the affected flows, render checks and remaining physical-device QA.
Other screens retain their previous visuals pending separate migration.

## Amendment — fixed cartoon character style, 2026-10-17

The owner preferred the original concept's cartoony people and rejected the
first hub illustration's semi-photorealistic characters. The original concept's
2D cartoon character style is therefore a fixed visual requirement for all
authored character assets and future pages.

Use simplified expressive faces, clean contours, grouped hair shapes and flat
colours with restrained cel shading. Photorealistic, semi-photorealistic,
lifelike painterly and realistic 3D people are excluded. This applies to game
artwork, not user-uploaded profile photos; existing photo upload behaviour is
unchanged. Tile and button depth may remain tactile.

[Design system version 1.1](../DESIGN_SYSTEM.md#avatars-and-graphics) defines the
acceptance criteria. The hub now references the replacement cartoon hero v2;
the previous hero remains preserved but superseded. Layout, controls, routes and
gameplay are unchanged by this asset replacement.


## Amendment — Fredoka typography, 2026-10-18

The owner selected Fredoka in place of Dosis and requested sizes matching the
original concept. Fredoka is now the standard interface family: Bold 700 for
wordmark/headline, Semibold 600 for actions, Medium 500 for stronger labels and
gameplay, and Regular 400 for supporting text. Use normal width and actual
OpenType weights, not synthetic styling. The original AI-generated lettering
remains an optical reference rather than an identifiable source font.

The [design system](../DESIGN_SYSTEM.md#typography) records reference sizes and
validation. The font and [SIL Open Font License](../../assets/fonts/fredoka/OFL.txt)
are bundled, with the licence included explicitly by the Android export preset.
The fixed 2D cartoon character direction is unchanged.
