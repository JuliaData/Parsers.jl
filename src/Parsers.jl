"""
    Parsers

Fast, exact parsers for Julia's scalar types, with a checked public layer that
closely follows `Base.parse`/`Base.tryparse` semantics with documented,
platform-independent range handling.

Two API levels:

  * **`Parsers.parse(T, s; kw...)` / `Parsers.tryparse(T, s; kw...)`** — the
    Base-like surface: `s` is an `AbstractString` or a byte vector;
    numbers and Bools tolerate surrounding whitespace, `parse` reports invalid
    or out-of-range values with `ArgumentError` or `OverflowError`, and
    `tryparse` returns `nothing`. It also supports
    `Parsers.parse(T, bytes, first, last; kw...)` on an explicit byte span.
    `String`, `SubString`, `CodeUnits`, and one-based
    `AbstractVector{UInt8}` inputs use their byte storage directly. Byte vectors
    with offset axes are rejected.
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
`BigInt` and the low-level `BigFloat` kernel build results with GMP/MPFR
arithmetic without calling the libraries' string parsers. Public `BigFloat`
parsing uses that package-owned conversion for short default decimals and
in-range configured decimal/group syntax under its supported rounding modes.
Longer default values use MPFR's native string parser, which also handles
validated configured values outside the limb kernel's range, MPFR-only syntax,
and the full exponent range.

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

using Dates            # civil.jl stays Dates-free; dates.jl owns translation and adaptation

# result codes shared by every kernel
"Successful parse."
const RC_OK = 0x00
"The span does not match the requested grammar."
const RC_INVALID = 0x01
"The value is above the target range; fixed floats hold signed infinity."
const RC_OVERFLOW = 0x02
"A nonzero value rounded to signed zero in the target float format."
const RC_UNDERFLOW = 0x03

# Shared option-byte validation. Grammar-specific constraints stay with the
# integer and float modules that consume the byte.
@inline function _bytechar(c::Char, name::Symbol)
    UInt32(c) <= 0xff ||
        throw(ArgumentError("$name must fit in one byte, got $(repr(c))"))
    return UInt8(c)
end

# Kernels use an Int cursor and bounded fixed lookahead. Rebase spans in the
# upper half of the public index space to one checked internal window with
# guard space at both ends. Exact kernels discard the local cursor, except for
# explicit-base integer errors whose byte position is restored once.
# `parsenext` translates its cursor once at the public boundary.
const _INDEX_WINDOW_FIRST = typemin(Int) + 64

struct _IndexWindow{B <: AbstractVector{UInt8}} <: AbstractVector{UInt8}
    source::B
    origin::Int
    len::Int
end

Base.size(window::_IndexWindow) = (window.len,)
Base.axes(window::_IndexWindow) =
    (_INDEX_WINDOW_FIRST:(_INDEX_WINDOW_FIRST + window.len - 1),)
Base.IndexStyle(::Type{<:_IndexWindow}) = IndexCartesian()
@inline function Base.getindex(window::_IndexWindow, i::Int)
    offset = i - _INDEX_WINDOW_FIRST
    0 <= offset < window.len || throw(BoundsError(window, i))
    return window.source[window.origin + offset]
end

@inline _needsindexwindow(j::Int) = j > typemax(Int) ÷ 2

@inline function _indexwindow(b::AbstractVector{UInt8}, i::Int, j::Int)
    len = j - i + 1
    window = _IndexWindow(b, i, len)
    first = _INDEX_WINDOW_FIRST
    final = first + len - 1
    return window, first, final
end

@noinline _exactpositionoverflow() =
    throw(OverflowError("exact parse position is not representable"))

@inline function _restoreexactposition(window::_IndexWindow, result)
    value, code, badpos = result
    code == RC_INVALID || return result
    offset = badpos - _INDEX_WINDOW_FIRST
    0 <= offset <= window.len || _exactpositionoverflow()
    offset <= typemax(Int) - window.origin || _exactpositionoverflow()
    return (value, code, window.origin + offset)
end

include("ints.jl")     # SWAR digit gathering, Int/UInt of every width, bases, digit groups
include("floats.jl")   # Float64/Float32 (Eisel–Lemire + exact fallback), Float16, hex floats
include("bigs.jl")     # BigInt / BigFloat / UUID
include("bools.jl")    # Bool + custom spelling lists
include("civil.jl")    # CivilParts + format programs (Dates-independent)
include("dates.jl")    # Date/DateTime/Time adapters
include("api.jl")      # parse / tryparse / parsenext — the documented Base-like surface

# Julia 1.10 cannot parse `public` syntax. On newer Julia releases, mark only
# the documented namespaced API as public without exporting any names.
@static if VERSION >= v"1.11"
    Core.eval(@__MODULE__, Expr(:public,
        :parse, :tryparse, :parsenext,
        :RC_OK, :RC_INVALID, :RC_OVERFLOW, :RC_UNDERFLOW,
        :parseint, :parsefloat, :parsebool, :parsebigint, :parsebigfloat,
        :parseuuid, :parsecivil,
        :compilepattern, :DatePattern, :CivilParts, :BigWork))
end

include("precompile.jl")

end # module Parsers
