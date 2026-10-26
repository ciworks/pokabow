# Hub hero animation layers

`ace.png`, `queen.png`, and `king.png` contain unchanged pixels extracted from
`../modern-tabletop-hero-cartoon-v2.png` by `tools/build_hub_hero_layers.gd`.
`static_plate.png` keeps every original pixel outside the tile outlines and
fills the space behind the tiles from
`../modern-tabletop-hero-tileless-backing.png`.

The backing was made with the built-in ImageGen edit tool from the approved
cartoon hero. Prompt: remove only the three foreground Ace, King, and Queen
tiles, continue the soft green tabletop and hidden torso areas, and keep both
players, their frames, the surrounding glow, and all other details in the same
composition and 2D cartoon style. At rest, the game draws the untouched
original image. When a tile bounces, the game draws these layers.
