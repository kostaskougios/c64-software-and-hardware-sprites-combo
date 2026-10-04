# C64 software sprite demo

This project builds a Commodore 64 program that moves eight coloured characters
around a hires bitmap screen. Each character is made from two layers:

* a multicolour VIC-II hardware sprite expanded to 2x width and 2x height;
* a one-pixel black hires bitmap contour drawn around the expanded sprite.

The demo uses one hardware sprite per character and reuses four character
designs across the eight sprites. Each frame sorts the characters by vertical
position from back to front. The bitmap renderer removes a farther character's
contour wherever a nearer character's opaque silhouette covers it, then draws
the nearer contour. Hardware sprite slots use the same depth order, since lower
numbered VIC-II sprites have higher priority when sprites overlap. The
characters bounce inside the visible bitmap area. It renders the
next hires frame into a hidden VIC-II bank, then switches banks at the bottom
of the screen. The previous frame stays visible while the next outline is drawn,
so the contours do not disappear during rendering. Colored, pixel-art hills
and a river provide a static background in both buffers.

## Build and run

Requirements: [ACME](https://github.com/meonwax/acme) and VICE (`x64sc` or
`x64`). From the project directory:

```sh
make
make run
```

This creates `build/sprite-demo.prg` and launches it in VICE. You can also run
it directly with `x64sc -autostart build/sprite-demo.prg`.

## Assembly routines

`SortActors` produces a stable back-to-front order using each actor's Y
coordinate. `DrawActors` uses that order to erase previous contour pixels under
an opaque silhouette only when its 48x42 bounds overlap an earlier actor. The
precombined 42-row masks are shifted to the actor's pixel alignment and merged
or cleared a byte at a time; bitmap row addresses stay fixed while the seven
bytes are accessed by offset. Hardware sprite registers are then mapped from
the same depth order before the bitmap banks swap.

The sprite converter packs four 12x21 multicolour pixels per row into the
VIC-II's three-byte row format and derives an expanded hires contour from the
silhouette. Code `1` marks light-grey feature areas; the converter derives
one-pixel black detail contours around them, while the bitmap contour adds the
external silhouette. The converter also generates opaque silhouette masks for
depth occlusion. These masks live outside the bitmap buffers. The background converter generates the colored hills
and bitmap cell colors. Edit `data/characters.txt`
(21 rows of up to 12 characters; `.` transparent, `1` feature area,
`2` shared color, `3` per-sprite color) and run `make` to regenerate the
assembly data.

## Artwork

The character proportions are redrawn and simplified from the CC0 16x16 base
character artwork published on [OpenGameArt](https://opengameart.org/content/16x16-base-sprites).
The text designs in `data/characters.txt` are this project's C64-specific
re-draw; the conversion does not require a network connection or redistribute
the source PNG. The source listing identifies the artwork as CC0 and says no
attribution is required.
