BEND := .tools/bend/bin/bend
PYTHON ?= python3
THREADS ?= 8

.PHONY: setup check build image hq test bench bench-hq clean

setup:
	bash scripts/setup.sh

$(BEND):
	bash scripts/setup.sh

check: $(BEND)
	$(BEND) main.bend --check-only
	$(BEND) tests.bend --check-only

build: build/mandelbrot

build/mandelbrot: main.bend mandelbrot.bend $(BEND)
	mkdir -p build
	$(BEND) main.bend -o "$@"

build/numerical-tests: tests.bend mandelbrot.bend $(BEND)
	mkdir -p build
	$(BEND) tests.bend -o "$@"

image: build
	mkdir -p output
	./build/mandelbrot --threads $(THREADS) 960 640 300 output/mandelbrot.ppm parallel
	@sh -c 'if command -v sips >/dev/null; then sips -s format png output/mandelbrot.ppm --out output/mandelbrot.png; fi'

# 9.8 megapixels, 16 subpixel orbits per pixel, and a larger iteration budget.
hq: build
	mkdir -p output
	./build/mandelbrot --threads $(THREADS) 3840 2560 3000 output/zoom-hq.ppm parallel -0.7435 0.1314 0.012 4
	@sh -c 'if command -v sips >/dev/null; then sips -s format png output/zoom-hq.ppm --out output/zoom-hq.png; fi'

test: check build build/numerical-tests
	./build/numerical-tests --threads 1
	$(PYTHON) scripts/test_render.py

bench: build
	$(PYTHON) scripts/benchmark.py --threads $(THREADS)

bench-hq: build
	$(PYTHON) scripts/benchmark.py --threads $(THREADS) --width 960 --height 640 --iterations 3000 --samples 4 --center-x -0.7435 --center-y 0.1314 --span 0.012 --repeat 3

clean:
	rm -rf build output
