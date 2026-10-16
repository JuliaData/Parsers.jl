"""
    Parsers

Fast, exact parsers for Julia's scalar types.

  * `Parsers.parse(T, s; kw...)` and `Parsers.tryparse(T, s; kw...)` parse a
    whole string, byte vector, or byte span like `Base.parse` and
    `Base.tryparse`.
  * `Parsers.parsenext(T, bytes, pos, last; kw...)` parses the longest value of
    `T` that starts at `pos` and returns `(value, nextpos, code)`, for
    tokenizers.
  * The span-exact kernels `parseint`, `parsefloat`, `parsebool`,
    `parsebigint`, `parsebigfloat`, `parseuuid`, and `parsecivil` consume
    exactly `buf[i:j]` and return a value plus one of `RC_OK`, `RC_INVALID`,
    `RC_OVERFLOW`, or `RC_UNDERFLOW`. They report malformed data by return code
    and throw only for invalid configuration, such as a bad base.

Supported `T`: `Int8`…`Int128`, `UInt8`…`UInt128`, `Bool`, `Float16`,
`Float32`, `Float64`, `BigInt`, `BigFloat`, `Base.UUID`, and the `Dates` types
`Date`, `DateTime`, and `Time`. See `Parsers.parse` for the keywords.
"""
module Parsers

using Dates            # civil.jl stays Dates-free; dates.jl owns translation and adaptation

# Julia 1.14's Dates reads `n` in a format string as a fractional-second code; earlier
# versions read it as a literal letter. Format strings follow the running Dates.
const _DATES_N_CODE = haskey(Dates.CONVERSION_SPECIFIERS, 'n')

# result codes shared by every kernel
"Successful parse."
const RC_OK = 0x00
"The span does not match the requested grammar."
const RC_INVALID = 0x01
"""
The value is outside the target range. `parsefloat` returns a signed infinity;
other kernels return zero.
"""
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
