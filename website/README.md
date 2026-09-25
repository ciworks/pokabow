# Polkabow marketing site

A static landing page for the game, kept in the repo beside it but completely
outside the Godot project. `res://website/.gdignore` makes the engine skip this
folder, so nothing here is scanned, imported, or added to an export.

## Files

- `index.html` - the page. All nine sections, semantic, no build step.
- `styles.css` - the design system and every section's layout.
- `main.js` - nav toggle, section reveals, the tile-wave animation, count-ups,
  and hero parallax. No dependencies.
- `assets/` - drop real artwork here (see `assets/README.md`).

## Previewing it

Open `index.html` directly in a browser, or serve the folder:

```
python -m http.server 8000 --directory website
```

then visit http://localhost:8000

Fonts load from Google Fonts over the network. Offline, the page falls back to
the system rounded stack and still looks correct.

## Before this goes live

The page ships with clearly marked placeholders. Search `index.html` for the
square-bracket tokens and replace each one:

| Token | Where |
|---|---|
| `[APP STORE URL]` | every store button |
| `[GOOGLE PLAY URL]` | every store button |
| `[LOGO]` | header brand mark and footer |
| `[SUPPORT EMAIL]` | footer |
| `[SOCIAL LINKS]` | footer |
| `[GAMEPLAY SCREENSHOT n]` | hero phone, feature rows |

Nothing on the page claims a download count, a rating, an award, a player
number, or a testimonial. The sample scores and player names in the community
and stats sections are labelled as illustrative. Do not replace them with real
numbers unless the numbers are real.
