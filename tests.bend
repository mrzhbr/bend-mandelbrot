import Base
import ./mandelbrot.bend as M

def check(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "FAIL: " ++ label)

def is_inside(result: M.Escape) -> Bool:
  match result:
    case M.Inside{}:
      True{}
    case M.Escaped{steps, radius_squared}:
      False{}

def escaped_at(result: M.Escape, expected: U32) -> Bool:
  match result:
    case M.Inside{}:
      False{}
    case M.Escaped{steps, radius_squared}:
      U32.is_eq(steps, expected)

def is_black(rgb: M.RGB) -> Bool:
  match rgb:
    case M.RGB{r, g, b}:
      U32.is_eq(r, 0) && U32.is_eq(g, 0) && U32.is_eq(b, 0)

def main() -> IO(Unit):
  do IO<Unit>:
    check(is_inside(M.escape(100n, 0.0, 0.0)), "c=0 remains bounded")
    check(is_inside(M.escape(100n, F32.neg(1.0), 0.0)), "c=-1 has period two")
    check(is_inside(M.escape(100n, F32.neg(2.0), 0.0)), "c=-2 is on the boundary")
    check(is_inside(M.escape(100n, 0.0, 1.0)), "c=i remains bounded")
    check(escaped_at(M.escape(100n, 1.0, 0.0), 3), "c=1 escapes at step three")
    check(escaped_at(M.escape(1n, 3.0, 0.0), 1), "escape on the last allowed step counts")
    check(is_inside(M.escape(1n, 2.0, 0.0)), "radius exactly two is not escape")
    check(escaped_at(M.escape(2n, 2.0, 0.0), 2), "c=2 escapes at step two")
    check(is_inside(M.escape(0n, 3.0, 0.0)), "zero budget performs no steps")
    check(is_black(M.color(M.Inside{})), "bounded points are black")
    IO.print("10 numerical tests passed")
