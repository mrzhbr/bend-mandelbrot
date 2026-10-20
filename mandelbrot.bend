import Base

# A finite iteration budget cannot prove membership: Inside means "not yet escaped".
type Escape is Data:
  Inside{}
  Escaped{steps: U32, radius_squared: F32}

type RGB is Data:
  RGB{r: U32, g: U32, b: U32}

# Match on a Boolean parameter, rather than on a computed expression (Bend 2).
# The decreasing Nat fuel makes termination explicit; the tail call becomes a loop.
def orbit(fuel: Nat, escaped: Bool, +cx: F32, +cy: F32,
  +zx: F32, +zy: F32, +steps: U32) -> Escape:
  match fuel escaped:
    case _ True{}:
      Escaped{steps, (zx * zx + zy * zy : F32)}
    case 0n False{}:
      Inside{}
    case 1n+left False{}:
      +nx = (zx * zx - zy * zy + cx : F32)
      +ny = (2.0 * zx * zy + cy : F32)
      orbit(left, (nx * nx + ny * ny > 4.0 : F32), cx, cy,
        nx, ny, (steps + 1 : U32))

def escape(limit: Nat, cx: F32, cy: F32) -> Escape:
  orbit(limit, False{}, cx, cy, 0.0, 0.0, 0)

# Continuous escape-time colouring removes the old integer-iteration bands.
# radius_squared > 4, so both logarithms have valid, positive inputs.
def color(result: Escape) -> RGB:
  match result:
    case Inside{}:
      RGB{0, 0, 0}
    case Escaped{steps, radius_squared}:
      smooth = (U32.to_f32(steps) + 1.0 - F32.log2((0.5 * F32.log(radius_squared) : F32)) : F32)
      +phase = (smooth * 0.025 : F32)
      RGB{F32.to_u32((127.5 * (1.0 + F32.cos((phase + 0.8 : F32))) : F32)),
        F32.to_u32((127.5 * (1.0 + F32.cos((phase + 1.8 : F32))) : F32)),
        F32.to_u32((127.5 * (1.0 + F32.cos((phase + 3.3 : F32))) : F32))}

# Sample within a pixel. Positive imaginary coordinates are at the top.
def sample(+index: U32, +width: U32, height: U32, limit: Nat,
  center_x: F32, center_y: F32, +span: F32, offset_x: F32, offset_y: F32) -> RGB:
  +scale = (span / U32.to_f32(width) : F32)
  x = (U32.to_f32((index % width : U32)) + offset_x : F32)
  y = (U32.to_f32((index / width : U32)) + offset_y : F32)
  cx = (center_x - span * 0.5 + x * scale : F32)
  cy = (center_y + U32.to_f32(height) * scale * 0.5 - y * scale : F32)
  color(escape(limit, cx, cy))

def add_rgb(a: RGB, b: RGB) -> RGB:
  match a b:
    case RGB{ar, ag, ab} RGB{br, bg, bb}:
      RGB{(ar + br : U32), (ag + bg : U32), (ab + bb : U32)}

def average_rgb(rgb: RGB, +count: U32) -> RGB:
  match rgb:
    case RGB{r, g, b}:
      RGB{(r / count : U32), (g / count : U32), (b / count : U32)}

# A stratified grid: n=1 is the pixel centre; n=4 traces 16 orbits per pixel.
# The accumulator never exceeds 16*255 per channel.
def supersample(left: Nat, +i: U32, +grid: U32, +index: U32,
  +width: U32, +height: U32, +limit: Nat, +center_x: F32, +center_y: F32,
  +span: F32, sum: RGB) -> RGB:
  match left:
    case 0n:
      average_rgb(sum, (grid * grid : U32))
    case 1n+rest:
      ox = ((U32.to_f32((i % grid : U32)) + 0.5) / U32.to_f32(grid) : F32)
      oy = ((U32.to_f32((i / grid : U32)) + 0.5) / U32.to_f32(grid) : F32)
      rgb = sample(index, width, height, limit, center_x, center_y, span, ox, oy)
      supersample(rest, (i + 1 : U32), grid, index, width, height, limit,
        center_x, center_y, span, add_rgb(sum, rgb))

def pixel(index: U32, width: U32, height: U32, limit: Nat,
  center_x: F32, center_y: F32, span: F32, +grid: U32) -> RGB:
  supersample(U32.to_nat((grid * grid : U32)), 0, grid, index, width, height,
    limit, center_x, center_y, span, RGB{0, 0, 0})

def prepend_rgb(rgb: RGB, bytes: List<&2, U32>) -> List<&2, U32>:
  match rgb:
    case RGB{r, g, b}:
      b <> g <> r <> bytes

# Accumulate bytes backwards, then reverse once per leaf. No shared mutable array.
def tile(left: Nat, +index: U32, +width: U32, +height: U32, +limit: Nat,
  +center_x: F32, +center_y: F32, +span: F32, +grid: U32, bytes: List<&2, U32>) -> List<&2, U32>:
  match left:
    case 0n:
      List.reverse(&2, U32, bytes)
    case 1n+rest:
      bytes = prepend_rgb(pixel(index, width, height, limit, center_x, center_y, span, grid), bytes)
      tile(rest, (index + 1 : U32), width, height, limit, center_x, center_y, span, grid, bytes)

# Preserve row-major order without repeatedly concatenating large lists.
type Pixels is Type:
  Leaf{bytes: List<&2, U32>}
  Branch{left: Pixels, right: Pixels}

# Fork a bounded number of tiles, NOT one task per pixel. Adjacent halves may
# take different times near the boundary; this is deliberately a simple baseline.
def render(+depth: Nat, +start: U32, +count: U32, +width: U32, +height: U32,
  +limit: Nat, +center_x: F32, +center_y: F32, +span: F32, +grid: U32) -> Pixels:
  match depth:
    case 0n:
      Leaf{tile(U32.to_nat(count), start, width, height, limit,
        center_x, center_y, span, grid, [])}
    case 1n+rest:
      +half = (count / 2 : U32)
      a b = render(rest, start, half, width, height, limit, center_x, center_y, span, grid)
        render(rest, (start + half : U32), (count - half : U32), width, height,
          limit, center_x, center_y, span, grid)
      Branch{a, b}

def finish_write(pair: File & Result<&1, &1, U32 & String, Unit>) -> IO(File):
  (file, result) = pair
  do IO<File>:
    IO.pass(Unit, result)
    return file

# Render first, then stream leaf buffers in order. Timing is done before this IO.
def write_pixels(pixels: Pixels, file: File) -> IO(File):
  match pixels:
    case Leaf{bytes}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, File,
        File.write_bytes(file, bytes), finish_write)
    case Branch{a, b}:
      do IO<File>:
        file : File <- write_pixels(a, file)
        write_pixels(b, file)
