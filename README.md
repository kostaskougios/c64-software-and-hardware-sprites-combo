# C64 software sprite demo

This project builds a Commodore 64 program that moves eight coloured characters
around a hires bitmap screen. Each character is made from two layers:

* a multicolour VIC-II hardware sprite expanded to 2x width and 2x height;
* a one-pixel black hires bitmap contour drawn around the expanded sprite.

The demo uses one hardware sprite per character and reuses four character
designs across the eight sprites. Each frame sorts the characters by vertical
position from back to front. The bitmap renderer composites the character
contours in depth order: it clears background and farther contour ink under
each opaque shape, then draws that character's outer and inner contours.
Hardware sprite slots use the same depth order, since lower numbered VIC-II
sprites have higher priority when sprites overlap. The characters bounce inside the
visible bitmap area. At startup, the static 8 KB bitmap background is copied
into both VIC-II banks. The demo renders each new frame into a hidden bank, then
switches banks at the bottom of the screen. When a bank is reused, it restores
only the previous sprite regions from the static background. It then draws the
new contours in depth order, clearing farther ink under each opaque shape before
adding that character's own contour. Each bank keeps its own previous sprite
positions, so old outlines are cleared from the right locations without copying
the full background every frame. A colored,
pixel-art dystopian neighborhood provides the background in both buffers,
with black outlines and facade details over the per-cell colors.

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

To run the character-mode version, use:

```sh
make run-chars
```

This builds `build/sprite-demo-chars.prg`. It reuses the same eight sprites,
designs, depth sorting, and movement. The character background uses 20 base
glyphs; uncommon cell patterns are approximated. The moving contour atlas
contains 434 distinct mask glyphs, so per-cell mask maps use 16-bit IDs.
Dynamic composites use character codes 20-255; the silhouette masks touch up
to 230 cells, leaving six spare glyphs. Separate character sets are used for the
two screen buffers. The contour masks follow the expanded 48-by-42 pixel sprite
shape, its reachable pixel alignments, and interior seams around the light-grey
features. Character-mode sprites use 2x width and height expansion and keep
three opaque colors. The bitmap build keeps its original renderer and remains
available with `make run`.

City linework and moving outline masks both use multicolor code 10, which reads
the shared black VIC-II color. Building interiors use code 11 and their
per-cell colors for cyan, purple, and green facade variety. The compositor
clears character pixels under each opaque sprite silhouette before adding its
outline and interior seams. Background fill uses code 00 and remains behind
the hardware sprites.

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
coordinate. `RestorePreviousActorAreas` restores up to seven 8-pixel bitmap
columns by 42 rows for each previous sprite position (at most 2,352 bytes per
buffer update), using separate position histories for the two banks.
`DrawActors` clears background and farther contour ink under each opaque
48x42 silhouette, then draws that actor's outer and inner contour. The converter
pre-shifts silhouette and contour masks for the two reachable pixel alignments
(0 and 4), storing only occupied byte-position/value pairs in each row. Actors
start on four-pixel boundaries and move horizontally in four-pixel steps, so
no other alignments are needed. The renderer visits only occupied bitmap bytes
and computes a row address once per nonempty row. Hardware sprite registers are
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
