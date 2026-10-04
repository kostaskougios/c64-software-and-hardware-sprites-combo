# C64 software sprite demo

This project builds a Commodore 64 program that moves four coloured characters
around a hires bitmap screen. Each character is made from two layers:

* a multicolour VIC-II hardware sprite expanded to 2x width and 2x height;
* a one-pixel black hires bitmap contour drawn around the expanded sprite.

The demo uses one hardware sprite per character and one shared bitmap outline
shape. The characters bounce inside the visible bitmap area. It renders the
next hires frame into a hidden VIC-II bank, then switches banks at the bottom
of the screen. The previous frame stays visible while the next outline is drawn,
so the contours do not disappear during rendering. A generated star field and
colored, pixel-art hills provide a static background in both buffers.

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

`DrawOutline` takes `BaseX` and `BaseY`, the top-left bitmap coordinate of the
48x42 expanded character. It plots a black contour into the back-buffer hires
bitmap. `PlotPixel` accounts for the VIC-II's 8x8 character-cell bitmap layout.
`PlotPixel` takes `PixelX` as a low byte plus `PixelXHi` (0 or 1), and
`PixelY` (0..199), then sets one black pixel. The routines use the shared
workspace in the assembly and clobber A, X, Y, and `Ptr`. The caller clears or
restores the back buffer before drawing; the demo copies the static background
to that buffer before adding the four outlines.

The sprite converter packs four 12x21 multicolour pixels per row into the
VIC-II's three-byte row format and derives an expanded hires contour from the
silhouette. The background converter generates the stars, hills, and bitmap
cell colors. Edit `data/characters.txt` (21 rows of up to 12 characters;
`.` transparent, `1`/`2`/`3` colour codes) and run `make` to regenerate the
assembly data.

## Artwork

The character proportions are redrawn and simplified from the CC0 16x16 base
character artwork published on [OpenGameArt](https://opengameart.org/content/16x16-base-sprites).
The text designs in `data/characters.txt` are this project's C64-specific
re-draw; the conversion does not require a network connection or redistribute
the source PNG. The source listing identifies the artwork as CC0 and says no
attribution is required.
