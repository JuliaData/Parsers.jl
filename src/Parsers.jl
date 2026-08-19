"""
    Parsers

Fast, exact, self-contained parsers for Julia's scalar types, and a thin layer
that reproduces `Base.parse`/`Base.tryparse` semantics on top of them.

Two API levels:

  * **`Parsers.parse(T, s; kw...)` / `Parsers.tryparse(T, s; kw...)`** — the
    Base-compatible surface: `s` is an `AbstractString` or a byte vector;
    numbers and Bools tolerate surrounding whitespace, `parse` throws the same
    errors `Base.parse` throws (`ArgumentError`, `OverflowError`), `tryparse`
    returns `nothing`. Also `Parsers.parse(T, bytes, first, last; kw...)` on
    an explicit byte span (no substring, no copy).
  * **`Parsers.parsenext(T, bytes, pos, last; kw...)`** — the prefix primitive
    for tokenizers (JSON, SQL wire formats): parse the longest well-formed
    value of `T` starting at `pos`, return `(value, nextpos, code)`.

Everything below those is a family of *span-exact* kernels — `parseint`,
`parsefloat`, `parsebool`, `parsebigint`, `parsebigfloat`, `parseuuid`,
`parsecivil` — that consume exactly `buf[i:j]` and return `(value, code)`
with `code` one of `RC_OK`, `RC_INVALID`, `RC_OVERFLOW`, `RC_UNDERFLOW`.
They never throw, never allocate on the fixed-width paths, and never fall
back to C, `Base.parse`, or GMP/MPFR string routines: 768-digit halfway
floats, subnormals, `Int128`, arbitrary bases, and hexadecimal floats are all
handled by self-contained code. That is what makes them candidates for Base
itself, and what CSV.jl builds its columnar loops on.

Supported `T`: every `Int8…Int128`/`UInt8…UInt128`, `Bool`, `Float16/32/64`,
`BigInt`, `BigFloat`, `Base.UUID`, and — through the `Dates` adapters —
`Date`, `DateTime`, `Time` (custom formats via `dateformat=`, including
`I`/`p`/`e`/`E` tokens).

Keywords: `decimal` (float decimal byte), `groupmark` (digit-group separator
for ints/floats), `base` (ints, 2…62; `0x`/`0o`/`0b` prefixes when omitted),
`trues`/`falses` (extra Bool spellings), `dateformat`.
"""
module Parsers

using Dates            # ONLY the adapters in dates.jl touch it; the kernels are Dates-free

# result codes shared by every kernel
const RC_OK        = 0x00
const RC_INVALID   = 0x01
const RC_OVERFLOW  = 0x02   # ints: outside T's range; floats: rounded to ±Inf
const RC_UNDERFLOW = 0x03   # floats: a nonzero spelling rounded to ±0

include("ints.jl")     # SWAR digit gathering, Int/UInt of every width, bases, digit groups
include("floats.jl")   # Float64/Float32 (Eisel–Lemire + exact fallback), Float16, hex floats
include("bigs.jl")     # BigInt / BigFloat / UUID
include("bools.jl")    # Bool + custom spelling lists
include("civil.jl")    # CivilParts + format programs (Dates-independent)
include("dates.jl")    # Date/DateTime/Time adapters
include("api.jl")      # parse / tryparse / parsenext — the Base-parity surface
include("precompile.jl")

end # module Parsers
