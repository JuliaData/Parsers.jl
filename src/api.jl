# =============================================================================
# The public surface: parse / tryparse with Base.parse's semantics, the
# byte-span forms, and parsenext for tokenizers. Everything here is a thin
# layer over the span-exact kernels — whitespace, prefixes, error messages,
# result types — and nothing else.
# =============================================================================

const _INTS = Union{_SIGNED, _UNSIGNED}
const _FLOATS = Union{Float64, Float32, Float16}

# --- byte views of the input ----------------------------------------------------
# The kernels take Vector{UInt8}. Strings and byte containers become one
# without copying whenever their bytes are contiguous in memory.
_bytes(v::Vector{UInt8}) = v
_bytes(s::String) = unsafe_wrap(Vector{UInt8}, s)
_bytes(s::SubString{String}) = unsafe_wrap(Vector{UInt8}, pointer(s), ncodeunits(s))
_bytes(s::AbstractString) = _bytes(String(s))
_bytes(c::Base.CodeUnits{UInt8, <:Union{String, SubString{String}}}) = _bytes(c.s)
_bytes(v::AbstractVector{UInt8}) = Vector{UInt8}(v)

# ASCII whitespace, Base.parse's tolerance for numbers and Bools
@inline _isws(b::UInt8) = b == UInt8(' ') || (UInt8('\t') <= b <= UInt8('\r'))
@inline function _stripws(buf::Vector{UInt8}, i::Int, j::Int)
    @inbounds while i <= j && _isws(buf[i]); i += 1; end
    @inbounds while j >= i && _isws(buf[j]); j -= 1; end
    return i, j
end
_spanstring(buf::Vector{UInt8}, i::Int, j::Int) = String(buf[max(i, 1):min(j, length(buf))])
# Base's error messages show the input through `repr` (escapes visible)
_q(s::String) = repr(s)

# --- integers ---------------------------------------------------------------------

# the base and where the digits start after an optional 0x/0o/0b prefix
# (Base's rule: prefixes are recognized only when no base is given, after the
# sign, lowercase letters only)
@inline function _intprefix(buf::Vector{UInt8}, i::Int, j::Int, base::Union{Nothing, Int})
    base === nothing || return (i, base, false)
    k = i
    @inbounds if k <= j && (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
        k += 1
    end
    @inbounds if k + 1 <= j && buf[k] == UInt8('0')
        c = buf[k + 1]
        b = c == UInt8('x') ? 16 : c == UInt8('o') ? 8 : c == UInt8('b') ? 2 : 0
        b != 0 && return (k + 2, b, true)       # digits start after the prefix; sign handled by caller
    end
    return (i, 10, false)
end

"""
    tryparse(T, buf, i, j; base=nothing, groupmark=nothing) -> Union{T, Nothing}
"""
function _tryparseint(::Type{T}, buf::Vector{UInt8}, i::Int, j::Int, base, groupmark,
                      throwing::Bool) where {T <: _INTS}
    orig_i, orig_j = i, j
    i, j = _stripws(buf, i, j)
    if base !== nothing
        2 <= base <= 62 || throw(ArgumentError("invalid base: base must be 2 ≤ base ≤ 62, got $base"))
    end
    if i > j
        throwing && throw(ArgumentError("input string is empty or only contains whitespace"))
        return nothing
    end
    @inbounds if T <: _UNSIGNED && (buf[i] == UInt8('-') || buf[i] == UInt8('+'))
        # Base: any sign is an invalid digit for an unsigned type
        throwing && throw(ArgumentError("invalid base $(something(base, 10)) digit '$(Char(buf[i]))' in $(_q(_spanstring(buf, orig_i, orig_j)))"))
        return nothing
    end
    dstart, b, prefixed = _intprefix(buf, i, j, base)
    if prefixed
        # sign (if any) sits before the prefix; the digits follow it
        neg = @inbounds buf[i] == UInt8('-')
        if dstart > j
            throwing && throw(ArgumentError("premature end of integer: $(_q(_spanstring(buf, orig_i, orig_j)))"))
            return nothing
        end
        if neg && T <: _UNSIGNED
            throwing && throw(ArgumentError("invalid base 10 digit '-' in $(_q(_spanstring(buf, orig_i, orig_j)))"))
            return nothing
        end
        v, rc, bad = parseint(T, buf, dstart, j, b)
        neg && rc == RC_OK && (v = -v)   # magnitude parsed; typemin cannot be spelled with a prefix... it can: check
        rc == RC_OK && return v
    elseif b == 10 && groupmark !== nothing && T === Int64
        v, rc = _hasbyte(buf, i, j, groupmark % UInt8) ?
                parsegroupedint64(buf, i, j, groupmark % UInt8) : parseint64(buf, i, j)
        rc == RC_OK && return v
        bad = i
    else
        v, rc, bad = parseint(T, buf, i, j, b)
        rc == RC_OK && return v
    end
    throwing || return nothing
    s = _spanstring(buf, orig_i, orig_j)
    rc == RC_OVERFLOW && throw(OverflowError("overflow parsing $(_q(s))"))
    # invalid: Base names the first offending character; a sign with nothing
    # after it counts as empty
    k = max(bad, i)
    @inbounds if k > j || (k == i && (buf[k] == UInt8('-') || buf[k] == UInt8('+')) && k == j)
        throw(ArgumentError("input string is empty or only contains whitespace"))
    end
    @inbounds _isws(buf[k]) &&                     # digits, whitespace, then more: Base's wording
        throw(ArgumentError("extra characters after whitespace in $(_q(s))"))
    ch = first(String(buf[k:min(k + 3, j)]))
    throw(ArgumentError("invalid base $b digit '$ch' in $(_q(s))"))
end

# --- floats -----------------------------------------------------------------------

function _tryparsefloat(::Type{T}, buf::Vector{UInt8}, i::Int, j::Int, decimal::UInt8,
                        groupmark, throwing::Bool) where {T <: _FLOATS}
    orig_i, orig_j = i, j
    i, j = _stripws(buf, i, j)
    P = T === Float16 ? Float32 : T          # Base parses Float16 through Float32
    local v::P
    rc = RC_INVALID
    if i <= j
        # hexadecimal float?
        k = i
        @inbounds if buf[k] == UInt8('-') || buf[k] == UInt8('+')
            k += 1
        end
        @inbounds if k + 1 <= j && buf[k] == UInt8('0') && _lower(buf[k + 1]) == UInt8('x')
            v, rc = _parsehexfloat(P, buf, i, j)
        elseif groupmark !== nothing && _hasbyte(buf, i, j, groupmark % UInt8)
            scratch = Vector{UInt8}(undef, max(j - i + 1, 8))
            n = degroup!(scratch, buf, i, j, groupmark % UInt8, decimal)
            if n >= 0
                v, rc = parsefloat(P, scratch, 1, n, decimal)
            else
                v = zero(P)
            end
        else
            v, rc = parsefloat(P, buf, i, j, decimal)
        end
    else
        v = zero(P)
    end
    if rc == RC_OK
        return T === Float16 ? Float16(v) : v
    end
    # RC_OVERFLOW / RC_UNDERFLOW: Base rejects out-of-range results (strtod's
    # ERANGE) — the kernel still holds the ±Inf / ±0 for callers that want it
    throwing || return nothing
    throw(ArgumentError("cannot parse $(_q(_spanstring(buf, orig_i, orig_j))) as $T"))
end

# --- bools --------------------------------------------------------------------------

function _tryparsebool(buf::Vector{UInt8}, i::Int, j::Int, trues, falses, throwing::Bool)
    orig_i, orig_j = i, j
    i, j = _stripws(buf, i, j)
    if trues === nothing && falses === nothing
        # Base.parse(Bool, s): "true"/"false"/"1"/"0" exactly
        v, rc = parsebool(buf, i, j)
        rc == RC_OK && return v
        if i == j
            @inbounds b = buf[i]
            b == UInt8('1') && return true
            b == UInt8('0') && return false
        end
    else
        trues !== nothing && matchsentinel(buf, i, j, trues) && return true
        falses !== nothing && matchsentinel(buf, i, j, falses) && return false
    end
    throwing || return nothing
    i > j && throw(ArgumentError(orig_i > orig_j ? "input string is empty" :
                                                  "input string only contains whitespace"))
    throw(ArgumentError("invalid Bool representation: $(_q(_spanstring(buf, orig_i, orig_j)))"))
end

# --- arbitrary precision & UUID -----------------------------------------------------------

function _tryparsebig(::Type{BigInt}, buf, i, j, throwing::Bool)
    orig_i, orig_j = i, j
    i, j = _stripws(buf, i, j)
    v, rc = parsebigint(buf, i, j)
    rc == RC_OK && return v
    throwing || return nothing
    throw(ArgumentError("invalid BigInt: $(_q(_spanstring(buf, orig_i, orig_j)))"))
end
function _tryparsebig(::Type{BigFloat}, buf, i, j, decimal::UInt8, throwing::Bool)
    orig_i, orig_j = i, j
    i, j = _stripws(buf, i, j)
    v, rc = parsebigfloat(buf, i, j, decimal)
    rc == RC_OK && return v
    throwing || return nothing
    throw(ArgumentError("cannot parse $(_q(_spanstring(buf, orig_i, orig_j))) as BigFloat"))
end
function _tryparseuuid(buf, i, j, throwing::Bool)
    u, rc = parseuuid(buf, i, j)
    rc == RC_OK && return Base.UUID(u)
    throwing || return nothing
    throw(ArgumentError("Malformed UUID string: $(_q(_spanstring(buf, i, j)))"))
end

# --- dates ----------------------------------------------------------------------------

_datepattern(::Nothing, ::Type{Dates.Date}) = ISO_DATE
_datepattern(::Nothing, ::Type{Dates.DateTime}) = ISO_DATETIME
_datepattern(::Nothing, ::Type{Dates.Time}) = ISO_TIME
_datepattern(fmt::AbstractString, ::Type) = compilepattern(fmt)
_datepattern(fmt::Dates.DateFormat, ::Type) = compilepattern(_patternstring(fmt))
_datepattern(p::DatePattern, ::Type) = p

_todates(::Type{Dates.Date}, c::CivilParts) = todate(c)
_todates(::Type{Dates.DateTime}, c::CivilParts) = todatetime(c)
_todates(::Type{Dates.Time}, c::CivilParts) = totime(c)

function _tryparsedate(::Type{T}, buf::Vector{UInt8}, i::Int, j::Int, dateformat,
                       throwing::Bool) where {T <: Dates.TimeType}
    pat = _datepattern(dateformat, T)
    c, rc = parsecivil(buf, i, j, pat)
    rc == RC_OK && return _todates(T, c)
    throwing || return nothing
    throw(ArgumentError("cannot parse \"$(_spanstring(buf, i, j))\" as $T" *
                        (dateformat === nothing ? "" : " with format $(repr(dateformat))")))
end

# --- dispatch: the public functions -------------------------------------------------------

"""
    Parsers.parse(T, s; kw...) -> T
    Parsers.parse(T, bytes, first, last; kw...) -> T
    Parsers.tryparse(T, s; kw...) -> Union{T, Nothing}
    Parsers.tryparse(T, bytes, first, last; kw...) -> Union{T, Nothing}

Parse the whole of `s` (an `AbstractString` or byte vector) — or the byte span
`bytes[first:last]` — as `T`. `parse` throws `Base.parse`'s errors on failure
(`ArgumentError` for malformed input, `OverflowError` for integers out of
range); `tryparse` returns `nothing`. Numbers and `Bool` tolerate surrounding
ASCII whitespace; dates and UUIDs must fill the span exactly.

Keywords:
  * `base`      integers: 2 ≤ base ≤ 62; when omitted, `0x`/`0o`/`0b`
                prefixes select 16/8/2 (Base's rule)
  * `decimal`   floats: the decimal separator character (default `'.'`)
  * `groupmark` ints/floats: a digit-group separator to ignore (`1,000,000`)
  * `trues`/`falses`  Bool: extra accepted spellings (`["yes"]`, `["no"]`)
  * `dateformat` Date/DateTime/Time: a format string or `Dates.DateFormat`

Supported `T`: `Int8`…`Int128`, `UInt8`…`UInt128`, `Bool`, `Float16`,
`Float32`, `Float64`, `BigInt`, `BigFloat`, `Base.UUID`, `Date`, `DateTime`,
`Time`.
"""
function parse end
function tryparse end

# every entry funnels to one (T, buf, i, j, throwing) dispatcher
_dispatch(::Type{T}, buf, i, j, throwing; base=nothing, groupmark=nothing, kw...) where {T <: _INTS} =
    _tryparseint(T, buf, i, j, base, groupmark, throwing)
_dispatch(::Type{T}, buf, i, j, throwing; decimal::Char='.', groupmark=nothing, kw...) where {T <: _FLOATS} =
    _tryparsefloat(T, buf, i, j, decimal % UInt8, groupmark, throwing)
_dispatch(::Type{Bool}, buf, i, j, throwing; trues=nothing, falses=nothing, kw...) =
    _tryparsebool(buf, i, j, _bytelist(trues), _bytelist(falses), throwing)
_dispatch(::Type{BigInt}, buf, i, j, throwing; kw...) = _tryparsebig(BigInt, buf, i, j, throwing)
_dispatch(::Type{BigFloat}, buf, i, j, throwing; decimal::Char='.', kw...) =
    _tryparsebig(BigFloat, buf, i, j, decimal % UInt8, throwing)
_dispatch(::Type{Base.UUID}, buf, i, j, throwing; kw...) = _tryparseuuid(buf, i, j, throwing)
_dispatch(::Type{T}, buf, i, j, throwing; dateformat=nothing, kw...) where {T <: Dates.TimeType} =
    _tryparsedate(T, buf, i, j, dateformat, throwing)
_dispatch(::Type{T}, buf, i, j, throwing; kw...) where {T} =
    throw(ArgumentError("Parsers does not know how to parse $T (supported: integers of every " *
                        "width, Bool, Float16/32/64, BigInt, BigFloat, UUID, Date, DateTime, Time)"))

_bytelist(::Nothing) = nothing
_bytelist(xs) = Vector{UInt8}[Vector{UInt8}(codeunits(String(x))) for x in xs]

# whole-input forms: hold the source alive across the zero-copy byte view
function parse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}}; kw...) where {T}
    GC.@preserve s begin
        buf = _bytes(s)
        return _dispatch(T, buf, 1, length(buf), true; kw...)
    end
end
function tryparse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}}; kw...) where {T}
    GC.@preserve s begin
        buf = _bytes(s)
        return _dispatch(T, buf, 1, length(buf), false; kw...)
    end
end
# byte-span forms
function parse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer; kw...) where {T}
    checkbounds(buf, first:last)
    return _dispatch(T, _bytes(buf), Int(first), Int(last), true; kw...)
end
function tryparse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer; kw...) where {T}
    checkbounds(buf, first:last)
    return _dispatch(T, _bytes(buf), Int(first), Int(last), false; kw...)
end

# --- parsenext: the tokenizer primitive ------------------------------------------------

"""
    Parsers.parsenext(T, bytes, pos, last; kw...) -> (value, nextpos, code)

Parse the longest well-formed value of `T` that starts at `bytes[pos]` and
report where it ended: `nextpos` is the first byte NOT consumed. `code` is
`RC_OK`, or `RC_INVALID` (no value starts at `pos`; `nextpos == pos`), or a
range code for numbers. This is the primitive JSON/SQL-style tokenizers need:
the numeric token is delimited by its own syntax, not by the caller.

Numbers: `[+-]` digits, and for floats `.`digits / `e±digits` /
`inf`/`infinity`/`nan` (case-insensitive) — the same grammar the whole-input
parsers accept. Bools: `true`/`false`. No whitespace is skipped.
"""
function parsenext(::Type{T}, buf::AbstractVector{UInt8}, pos::Integer, last::Integer; kw...) where {T}
    b = _bytes(buf)
    i, j = Int(pos), Int(last)
    stop = _tokenend(T, b, i, j)
    stop < i && return (_zero(T), i, RC_INVALID)
    return _nextvalue(T, b, i, stop; kw...)
end
# floats: surface the kernel's range code with the ±Inf/±0 it rounded to
function _nextvalue(::Type{T}, b::Vector{UInt8}, i::Int, stop::Int; decimal::Char='.', kw...) where {T <: Union{Float64, Float32}}
    v, rc = parsefloat(T, b, i, stop, decimal % UInt8)
    rc == RC_INVALID && return (zero(T), i, RC_INVALID)
    return (v, stop + 1, rc)
end
function _nextvalue(::Type{T}, b::Vector{UInt8}, i::Int, stop::Int; kw...) where {T}
    v = _dispatch(T, b, i, stop, false; kw...)
    v === nothing && return (_zero(T), i, RC_INVALID)
    return (v, stop + 1, RC_OK)
end
_zero(::Type{T}) where {T <: Number} = zero(T)
_zero(::Type{Bool}) = false
_zero(::Type{T}) where {T} = nothing

# last index of the numeric token starting at i (i-1 when there is none)
function _tokenend(::Type{T}, buf::Vector{UInt8}, i::Int, j::Int) where {T <: _INTS}
    k = i
    @inbounds if k <= j && (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
        k += 1
    end
    start = k
    @inbounds while k <= j && buf[k] - UInt8('0') <= 0x09
        k += 1
    end
    return k == start ? i - 1 : k - 1
end
function _tokenend(::Type{T}, buf::Vector{UInt8}, i::Int, j::Int) where {T <: Union{_FLOATS, BigFloat}}
    k = i
    @inbounds if k <= j && (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
        k += 1
    end
    # word specials
    @inbounds if k <= j && (_lower(buf[k]) == UInt8('i') || _lower(buf[k]) == UInt8('n'))
        for n in (8, 3)   # infinity, inf / nan
            k + n - 1 <= j || continue
            _, ok = _matchspecial(buf, i, k + n - 1)
            ok && return k + n - 1
        end
        return i - 1
    end
    start = k
    @inbounds while k <= j && buf[k] - UInt8('0') <= 0x09; k += 1; end
    @inbounds if k <= j && buf[k] == UInt8('.')
        k += 1
        while k <= j && buf[k] - UInt8('0') <= 0x09; k += 1; end
    end
    k == start && return i - 1
    @inbounds if k <= j && (buf[k] == UInt8('e') || buf[k] == UInt8('E'))
        e = k + 1
        e <= j && (buf[e] == UInt8('-') || buf[e] == UInt8('+')) && (e += 1)
        if e <= j && buf[e] - UInt8('0') <= 0x09
            while e <= j && buf[e] - UInt8('0') <= 0x09; e += 1; end
            k = e
        end
    end
    return k - 1
end
_tokenend(::Type{BigInt}, buf::Vector{UInt8}, i::Int, j::Int) = _tokenend(Int64, buf, i, j)
function _tokenend(::Type{Bool}, buf::Vector{UInt8}, i::Int, j::Int)
    for n in (4, 5)
        i + n - 1 <= j || continue
        parsebool(buf, i, i + n - 1)[2] == RC_OK && return i + n - 1
    end
    return i - 1
end
