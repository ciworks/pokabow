# Artwork

Drop real assets here and point the page at them.

## Game screenshots

The page currently renders device frames containing a labelled placeholder
block, so it never looks broken while the artwork is missing. To use a real
screenshot, find the matching comment in `index.html` and replace the
placeholder div with an image:

```html
<!-- SCREENSHOT SLOT: hero phone -->
<img src="assets/game-board.png" alt="A Pokabow board mid-match, with tiles placed and the score panel visible" loading="lazy" width="720" height="1560">
```

Suggested files:

- `game-board.png` - a board mid-match. Used in the hero phone.
- `screenshot-hand.png` - the deck row and a staged line.
- `screenshot-scoring.png` - a move being scored.
- `screenshot-versus.png` - the two-player score panel.

Export at roughly 2x the display size and keep each under ~300 KB. The hero
image is above the fold and should load eagerly; everything else should keep
`loading="lazy"`.

## Logo

Replace the `[LOGO]` span in the header and footer with an SVG. A dark wordmark
on the light backgrounds and a light one on the navy section are both needed;
`currentColor` in the SVG will let one file serve both.
