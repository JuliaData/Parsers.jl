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
    an explicit byte span. `String`, `SubString`, `CodeUnits`, and
    `Vector{UInt8}` inputs use allocation-free byte views; other containers
    can be normalized to contiguous storage.
  * **`Parsers.parsenext(T, bytes, pos, last; kw...)`** — the prefix primitive
    for tokenizers (JSON, SQL wire formats): parse the longest well-formed
    value of `T` starting at `pos`, return `(value, nextpos, code)`.

Everything below those is a family of *span-exact* kernels — `parseint`,
`parsefloat`, `parsebool`, `parsebigint`, `parsebigfloat`, `parseuuid`,
`parsecivil` — that consume exactly `buf[i:j]` and return a value plus one of
`RC_OK`, `RC_INVALID`, `RC_OVERFLOW`, or `RC_UNDERFLOW`. The explicit-base
integer overloads also return the invalid byte position.
Malformed data is reported by return code. Configuration errors, such as an
invalid base, can throw. Common fixed-width paths are allocation-free.
`BigInt` and `BigFloat` use GMP/MPFR arithmetic, but they do not call the
libraries' string parsers or round-trip through `Base.parse`.

Supported `T`: every `Int8…Int128`/`UInt8…UInt128`, `Bool`, `Float16/32/64`,
`BigInt`, `BigFloat`, `Base.UUID`, and — through the `Dates` adapters —
`Date`, `DateTime`, `Time` (custom formats via `dateformat=`, including
`I`/`p`/`e`/`E` tokens).

Keywords: `decimal` (float decimal byte), `groupmark` (numeric digit-group
separator), `base` (fixed integers and `BigInt`, 2…62; `0x`/`0o`/`0b`
prefixes when omitted), `rounding` (`BigFloat`), `trues`/`falses` (replacement
Bool spelling lists), and `dateformat`.
"""
module Parsers

using Dates            # ONLY the adapters in dates.jl touch it; the kernels are Dates-free

# result codes shared by every kernel
"Successful parse."
const RC_OK = 0x00
"The span does not match the requested grammar."
const RC_INVALID = 0x01
"The value is above the target range; fixed floats hold signed infinity."
const RC_OVERFLOW = 0x02
"A nonzero value rounded to signed zero in the target float format."
const RC_UNDERFLOW = 0x03

include("ints.jl")     # SWAR digit gathering, Int/UInt of every width, bases, digit groups
include("floats.jl")   # Float64/Float32 (Eisel–Lemire + exact fallback), Float16, hex floats
include("bigs.jl")     # BigInt / BigFloat / UUID
include("bools.jl")    # Bool + custom spelling lists
include("civil.jl")    # CivilParts + format programs (Dates-independent)
include("dates.jl")    # Date/DateTime/Time adapters
include("api.jl")      # parse / tryparse / parsenext — the Base-parity surface
include("precompile.jl")

end # module Parsers
