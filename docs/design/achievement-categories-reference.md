# Achievement category browser reference

Approved by the owner for implementation, 2026-10-18.

The reference shows a collection overview and a six-badge category page. Its 60-achievement catalogue, extra categories, and unlock counts are illustrative. Runtime uses only the authenticated API catalogue.

Implemented by `scripts/presentation/achievement_browser.gd`, hosted inside the existing profile screen. Native Fredoka labels and theme colours remain separate from artwork.

The reference was created with the built-in image generation tool. Runtime badges are original editable SVG illustrations in `assets/achievements/`, following the same flat cartoon direction.

## Generation prompt

Design a high-fidelity TWO-SCREEN mobile UI concept board for POKABOW's scalable achievements experience. Two complete portrait screens side by side, equal size, with generous narrow neutral gutter, subtle rounded screen boundaries, no device hardware. Landscape overall canvas approximately 3:2, high resolution, readable text. Small editorial captions outside the screens above them: "01  Collection overview" and "02  Browse a category". This is a future expanded-catalog mockup with illustrative sample counts, not real player data.

STYLE REFERENCE: supplied image is the previous achievements page. Preserve its warm ivory #F6F2E9, deep teal #173D42, sage #DFEAE4, honey #F4C86A, peach accents, rounded Fredoka-style typography, clean 2D cartoon badge illustration. Change its long list into a compact well-organised browsable collection. Use smaller headings and compact components to avoid wasting vertical space. Crisp flat UI, ample alignment and margins, no photorealistic material, no glossy 3D.

LEFT SCREEN — COLLECTION OVERVIEW:
Top safe area, header with back chevron and "Achievements".
A compact sage rounded summary card: left text "Your collection", bold "24 of 60 unlocked", a slim teal progress bar filled 40 percent; small charming honey cartoon trophy at right. No giant promotional headline.
Next label "Recently unlocked". One row of THREE small circular colourful badges with short labels beneath: "First Hand" (A spade tile), "Full House" (little house made of five tiles), "AI Victory" (honey medal with teal star). Small check marks. This row is secondary, no descriptions.
Next label "Explore categories".
A balanced TWO-COLUMN grid of FOUR generous tappable rounded category cards, TWO rows, with one distinct cartoon illustration, bold title, unlocked count and subtle chevron in each:
"Hands", "6 of 18 unlocked" — fan of square ivory A K Q J tiles.
"Edge Matching", "5 of 12 unlocked" — four linked square edge-coloured tiles.
"Victories", "8 of 18 unlocked" — friendly honey trophy with teal ribbon.
"Milestones", "5 of 12 unlocked" — a honey star badge with three little stepping stones.
Use alternating soft sage and pale peach/ivory panels within the controlled palette; keep illustrations secondary to titles. No long lists. All four category cards visible above navigation, no clipped content.
Bottom navigation anchored: Home outline house, Achievements teal trophy selected with sage pill, Profile person outline. Comfortable bottom safe area.

RIGHT SCREEN — HANDS CATEGORY:
Top safe area, back chevron, centered header "Hands", small outline search icon on right.
Below a compact line "6 of 18 unlocked" and short supporting text "Build your poker collection."
A single row of THREE pill filters "All", "Unlocked", "Locked". All selected in deep teal with ivory text, others outlined/muted.
Main content: TWO-COLUMN grid, THREE rows, SIX equal comfortable rounded badge cards. Each card contains a large centered circular cartoon badge, concise title below, and small explicit status with check or lock. NO full descriptions here, detail is revealed by tapping a card.
Row1: "First Hand" Unlocked (A-spade tile) and "Pair" Unlocked (two K-heart tiles).
Row2: "Full House" Unlocked (three Q tiles below two K tiles) and "Straight" Locked (four square tiles J Q K A ascending).
Row3: "Three of a Kind" Locked (three Q tiles) and "Four of a Kind" Locked (four K tiles).
Unlocked cards show peach/honey/sage colours and teal checks. Locked cards remain readable with subdued sage illustration and clearly labelled lock icons. Do not represent disabled buttons; these cards can still be opened to read requirements.
Below grid, small centered helper "Tap a badge to see how to unlock it."
Compact pagination: left chevron, "1 of 3", right chevron. This allows a large category to be browsed six badges at a time without a huge vertical scroll.
Same bottom navigation as left with Achievements selected.

Ensure clean aligned layout with generous but efficient spacing, no overlapping elements, no tiny unreadable labels. Both complete screens fit within canvas. Game tiles are SQUARE with ivory faces, small rounded corners, and distinct solid blue/vermilion/green/yellow edge bands. Use only A K Q J rank lettering, no 9/10, no elongated playing cards. No currency, XP, rewards, claim buttons, gameplay changes, date stamps, phone status bars or extra screens. Add one very small editorial footnote OUTSIDE both screens at bottom: "Expanded catalogue concept · Illustrative achievements and counts".

