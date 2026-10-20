import Base
import ./mandelbrot.bend as M

type Mode is Data:
  Sequential{}
  Parallel{}

type View is Data:
  View{x: F32, y: F32, span: F32, samples: U32}

def usage() -> String:
  "Mandelbrot in Bend 2\n\nUsage:\n  mandelbrot [width height iterations output.ppm sequential|parallel [center_x center_y span [samples]]]\n\nDefaults: 960 640 300 mandelbrot.ppm parallel -0.5 0.0 3.2 1\nNative runtime options: --threads N (place before application arguments).\nSpan is the horizontal view width. Samples: grid size 1-4 (4 means 16 orbits/pixel)."

def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 2, message)

def number_result(value: Maybe<&2, U32>, label: String, +max: U32) -> IO(U32):
  match value:
    case None{}:
      IO.die(U32, 2, "Invalid integer: " ++ label)
    case Some{+n}:
      do IO<U32>:
        require((n > 0 : U32) && (n <= max : U32),
          label ++ " must be between 1 and " ++ U32.show(max))
        return n

def number(text: String, label: String, max: U32) -> IO(U32):
  number_result(U32.read(text), label, max)

def real_result(value: Maybe<&2, F32>, label: String) -> IO(F32):
  match value:
    case None{}:
      IO.die(F32, 2, "Invalid number: " ++ label)
    case Some{+n}:
      do IO<F32>:
        require((F32.abs(n) <= 1000000.0 : F32),
          label ++ " must be finite with absolute value <= 1000000")
        return n

def real(text: String, label: String) -> IO(F32):
  real_result(F32.read(text), label)

def samples(args: List<String>) -> IO(U32):
  match args:
    case Nil{}:
      IO.pure(U32, 1)
    case Con{n, Nil{}}:
      number(n, "samples", 4)
    case _:
      IO.die(U32, 2, usage())

def view(args: List<String>) -> IO(View):
  match args:
    case Nil{}:
      IO.pure(View, View{F32.neg(0.5), 0.0, 3.2, 1})
    case Con{x, Con{y, Con{span, rest}}}:
      do IO<View>:
        x : F32 <- real(x, "center_x")
        y : F32 <- real(y, "center_y")
        +span : F32 <- real(span, "span")
        require((span > 0.0 : F32), "span must be positive")
        grid : U32 <- samples(rest)
        return View{x, y, span, grid}
    case _:
      IO.die(View, 2, usage())

def mode_result(sequential: Bool, parallel: Bool) -> IO(Mode):
  match sequential parallel:
    case True{} _:
      IO.pure(Mode, Sequential{})
    case False{} True{}:
      IO.pure(Mode, Parallel{})
    case _ _:
      IO.die(Mode, 2, "mode must be sequential or parallel")

def mode(+text: String) -> IO(Mode):
  mode_result(String.eq(text, "sequential"), String.eq(text, "parallel"))

# Both modes run exactly the same numerical code. Depth 8 creates 256 tiles;
# depth 0 creates one tile with no forks. Use --threads to control CPU workers.
def compute(mode: Mode, view: View, +width: U32, +height: U32, limit: Nat) -> M.Pixels:
  match mode view:
    case Sequential{} View{x, y, span, grid}:
      M.render(0n, 0, (width * height : U32), width, height, limit, x, y, span, grid)
    case Parallel{} View{x, y, span, grid}:
      M.render(8n, 0, (width * height : U32), width, height, limit, x, y, span, grid)

def save(pixels: M.Pixels, +path: String, +width: U32, +height: U32) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open(path, "w"))
    file : File <- IO.bind(File & Result<&1, &1, U32 & String, Unit>, File,
      File.write(file, "P6\n" ++ U32.show(width) ++ " " ++ U32.show(height) ++ "\n255\n"), M.finish_write)
    file : File <- M.write_pixels(pixels, file)
    File.close(file)
    IO.print("Saved " ++ path ++ " (" ++ U32.show(width) ++ " x " ++ U32.show(height) ++ ")")

def run(+width: U32, +height: U32, +iterations: U32, output: String,
  mode: Mode, view: View) -> IO(Unit):
  do IO<Unit>:
    require((width * height <= 16777216 : U32), "Image must have at most 16777216 pixels")
    threads : U32 <- IO.thread_count()
    IO.print("CPU workers: " ++ U32.show(threads) ++ "; iteration limit: " ++ U32.show(iterations))
    start : Nat <- IO.now()
    pixels : M.Pixels = compute(mode, view, width, height, U32.to_nat(iterations))
    end : Nat <- IO.now()
    IO.print("Render time: " ++ Nat.show(Nat.sub(end, start)) ++ " ms (includes pixel buffers; excludes file IO)")
    save(pixels, output, width, height)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}:
      run(960, 640, 300, "mandelbrot.ppm", Parallel{}, View{F32.neg(0.5), 0.0, 3.2, 1})
    case Con{+help, Nil{}}:
      do IO<Unit>:
        require(String.eq(help, "--help") || String.eq(help, "-h"), usage())
        IO.print(usage())
    case Con{w, Con{h, Con{n, Con{path, Con{m, rest}}}}}:
      do IO<Unit>:
        width : U32 <- number(w, "width", 8192)
        height : U32 <- number(h, "height", 8192)
        iterations : U32 <- number(n, "iterations", 10000)
        mode : Mode <- mode(m)
        view : View <- view(rest)
        run(width, height, iterations, path, mode, view)
    case _:
      IO.die(Unit, 2, usage())

def command_line(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}:
      arguments([])
    case Con{program, rest}:
      arguments(rest)

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), command_line)
