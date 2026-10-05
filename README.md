# C64 software sprite demo

This project builds a Commodore 64 program that moves eight coloured characters
around a hires bitmap screen. Each character is made from two layers:

* a multicolour VIC-II hardware sprite expanded to 2x width and 2x height;
* a one-pixel black hires bitmap contour drawn around the expanded sprite.

The demo uses one hardware sprite per character and reuses four character
designs across the eight sprites. Each frame sorts the characters by vertical
position from back to front. The bitmap renderer composites the character
contours, then clears bitmap ink under every opaque sprite pixel. Hardware
sprite slots use the same depth order, since lower numbered VIC-II sprites
have higher priority when sprites overlap. The characters bounce inside the
visible bitmap area. The demo renders the
next hires frame into a hidden VIC-II bank, then switches banks at the bottom
of the screen. Each frame starts by restoring the static background to that
buffer, draws the character contours, then removes all black ink from opaque
sprite pixels so background details cannot cross the characters. A colored,
pixel-art dystopian neighborhood provides
the background in both buffers, with black outlines and facade details over
the per-cell colors.

## Build and run

Requirements: [ACME](https://github.com/meonwax/acme) and VICE (`x64sc` or
`x64`). From the project directory:

```sh
make
make run
```

This creates `build/sprite-demo.prg` and launches it in VICE with warp enabled
and true-drive emulation temporarily disabled during PRG autostart. Turn warp
off once the game appears. The equivalent command is
`x64sc -warp -autostart-handle-tde -autostart build/sprite-demo.prg`.

To check VICE startup and PRG execution without using the emulated disk drive,
run the standalone hello program:

```sh
make run-hello
```

It should show “HELLO WORLD!” and “C64 PROGRAM IS RUNNING.” This target starts
VICE in warp mode and injects the PRG directly into memory, bypassing the disk
drive and temporary autostart-warp behavior. Turn warp off after the text
appears. It is a useful comparison if `make run` remains at `LOADING`.

## Assembly routines

`SortActors` produces a stable back-to-front order using each actor's Y
coordinate. `DrawActors` draws each 48x42 sprite contour, then clears background
and overlapping contour ink under every opaque sprite silhouette. The converter
pre-shifts silhouette and
contour masks for the two reachable pixel alignments (0 and 4) and stores each
nonempty row as a byte-position bitset followed by its nonzero bytes. Actors
start on four-pixel boundaries and move horizontally in four-pixel steps, so
no other alignments are needed. The renderer visits only occupied bitmap bytes
and computes a row address once per nonempty row. Each hidden bitmap is restored
from the static scene before compositing. Hardware sprite registers are then
mapped from the same depth order before the bitmap banks swap.

The sprite converter packs four 12x21 multicolour pixels per row into the
VIC-II's three-byte row format and derives an expanded hires contour from the
silhouette. Code `1` marks light-grey feature areas; the converter derives
one-pixel black detail contours around them, while the bitmap contour adds the
external silhouette. It also generates alignment-specific sparse contour and
silhouette masks for drawing and depth occlusion. These masks live outside the
bitmap buffers. The background converter generates the colored neighborhood,
black bitmap ink, and one background color per 8x8 cell. Edit `data/characters.txt`
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
