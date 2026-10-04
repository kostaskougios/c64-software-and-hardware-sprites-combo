ACME ?= acme
PYTHON ?= python3
VICE ?= x64sc

.PHONY: all sprites backgrounds run clean

all: build/sprite-demo.prg

sprites: src/generated_sprites.asm

backgrounds: src/generated_background.asm

src/generated_sprites.asm: data/characters.txt tools/convert_sprites.py
	$(PYTHON) tools/convert_sprites.py

src/generated_background.asm: tools/convert_background.py
	$(PYTHON) tools/convert_background.py

build/sprite-demo.prg: src/sprite_demo.asm src/generated_sprites.asm src/generated_background.asm
	@mkdir -p build
	$(ACME) -f cbm -o $@ src/sprite_demo.asm

run: build/sprite-demo.prg
	$(VICE) -autostart $<

clean:
	rm -rf build src/generated_sprites.asm src/generated_background.asm
