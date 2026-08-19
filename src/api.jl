# =============================================================================
# The public surface: parse / tryparse with Base.parse's semantics, the
# byte-span forms, and parsenext for tokenizers. Everything here is a thin
# layer over the span-exact kernels — whitespace, prefixes, error messages,
# result types — and nothing else.
# =============================================================================

const _INTS = Union{_SIGNED, _UNSIGNED}
const _FLOATS = Union{Float64, Float32, Float16}

# --- byte views of the input ----------------------------------------------------
# The kernels take AbstractVector{UInt8}. Strings use their allocation-free
# CodeUnits view; other non-Vector byte containers keep the existing copy-to-
# contiguous behavior because the word-at-a-time kernels require contiguous
# storage.
_bytes(v::Vector{UInt8}) = v
_bytes(s::Union{String, SubString{String}}) = codeunits(s)
_bytes(s::AbstractString) = codeunits(String(s))
_bytes(c::Base.CodeUnits{UInt8, <:Union{String, SubString{String}}}) = c
_bytes(v::AbstractVector{UInt8}) = Vector{UInt8}(v)

# ASCII whitespace, Base.parse's tolerance for numbers and Bools
@inline _isws(b::UInt8) = b == UInt8(' ') || (UInt8('\t') <= b <= UInt8('\r'))
@inline function _stripws(buf::AbstractVector{UInt8}, i::Int, j::Int)
    @inbounds while i <= j && _isws(buf[i]); i += 1; end
    @inbounds while j >= i && _isws(buf[j]); j -= 1; end
    return i, j
end
_spanstring(buf::AbstractVector{UInt8}, i::Int, j::Int) =
    String(buf[max(i, 1):min(j, length(buf))])
# Base's error messages show the input through `repr` (escapes visible)
_q(s::String) = repr(s)

@inline function _bytechar(c::Char, name::Symbol)
    UInt32(c) <= 0xff ||
        throw(ArgumentError("$name must fit in one byte, got $(repr(c))"))
    return UInt8(c)
end

@inline function _decimalbyte(c::Char)
    b = _bytechar(c, :decimal)
    ((b - UInt8('0')) > 0x09 && b != UInt8('+') && b != UInt8('-') &&
     _lower(b) != UInt8('e')) ||
        throw(ArgumentError("decimal must not be a digit, sign, or exponent marker"))
    return b
end

@inline function _floatgroupbyte(groupmark, decimal::UInt8)
    groupmark === nothing && return nothing
    b = _bytechar(groupmark, :groupmark)
    ((b - UInt8('0')) > 0x09 && b != decimal && b != UInt8('+') &&
     b != UInt8('-') && _lower(b) != UInt8('e')) ||
        throw(ArgumentError("groupmark must differ from decimal and must not be a digit, sign, or exponent marker"))
    return b
end

@inline _normalizebase(::Nothing) = nothing
@inline function _normalizebase(base)
    base isa Integer || throw(ArgumentError("base must be an integer, got $(repr(base))"))
    2 <= base <= 62 ||
        throw(ArgumentError("invalid base: base must be 2 ≤ base ≤ 62, got $base"))
    return Int(base)
end

@inline function _intgroupbyte(groupmark, base::Int)
    groupmark === nothing && return nothing
    gm = _bytechar(groupmark, :groupmark)
    (_digitvalue(gm, base) >= base && gm != UInt8('+') && gm != UInt8('-')) ||
        throw(ArgumentError("groupmark must not be a sign or a base-$base digit"))
    return gm
end

# --- integers ---------------------------------------------------------------------

# the base and where the digits start after an optional 0x/0o/0b prefix
# (Base's rule: prefixes are recognized only when no base is given, after the
# sign, lowercase letters only)
@inline function _intprefix(buf::AbstractVector{UInt8}, i::Int, j::Int,
                            base::Union{Nothing, Int})
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
@inline function _tryparseint(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                              base, groupmark,
                              ::Val{Throw}) where {T <: _INTS, Throw}
    orig_i, orig_j = i, j
    i, j = _stripws(buf, i, j)
    base = _normalizebase(base)
    if i > j
        Throw && throw(ArgumentError("input string is empty or only contains whitespace"))
        return nothing
    end
    @inbounds if T <: _UNSIGNED && (buf[i] == UInt8('-') || buf[i] == UInt8('+'))
        # Base: any sign is an invalid digit for an unsigned type
        Throw && throw(ArgumentError("invalid base $(something(base, 10)) digit '$(Char(buf[i]))' in $(_q(_spanstring(buf, orig_i, orig_j)))"))
        return nothing
    end
    dstart, b, prefixed = _intprefix(buf, i, j, base)
    gm = _intgroupbyte(groupmark, b)
    if prefixed
        # sign (if any) sits before the prefix; the digits follow it
        neg = @inbounds buf[i] == UInt8('-')
        if dstart > j
            Throw && throw(ArgumentError("premature end of integer: $(_q(_spanstring(buf, orig_i, orig_j)))"))
            return nothing
        end
        pbuf, pi, pj = buf, dstart, j
        if gm !== nothing && _hasbyte(buf, dstart, j, gm)
            scratch = Vector{UInt8}(undef, max(j - dstart + 1, 8))
            n = degroupint!(scratch, buf, dstart, j, gm, b)
            if n < 0
                v, rc, bad = zero(T), RC_INVALID, dstart
            else
                pbuf, pi, pj = scratch, 1, n
                if T <: _SIGNED
                    v, rc, bad = parseprefixedint(T, pbuf, pi, pj, b, neg)
                else
                    v, rc, bad = parseint(T, pbuf, pi, pj, b)
                end
            end
        elseif T <: _SIGNED
            v, rc, bad = parseprefixedint(T, pbuf, pi, pj, b, neg)
        else
            v, rc, bad = parseint(T, pbuf, pi, pj, b)
        end
        rc == RC_OK && return v
    elseif gm !== nothing && _hasbyte(buf, i, j, gm)
        if T === Int64 && b == 10
            v, rc = parsegroupedint64(buf, i, j, gm)
            bad = i
        else
            scratch = Vector{UInt8}(undef, max(j - i + 1, 8))
            n = degroupint!(scratch, buf, i, j, gm, b)
            if n < 0
                v, rc, bad = zero(T), RC_INVALID, i
            else
                v, rc, bad = parseint(T, scratch, 1, n, b)
            end
        end
        rc == RC_OK && return v
    else
        if b == 10
            # Keep the common public path on the small decimal kernel. The
            # arbitrary-base wrapper only adds the invalid-byte position, so
            # compute that detail on the cold throwing failure path.
            v, rc = parseint(T, buf, i, j)
            bad = rc == RC_INVALID && Throw ? _firstbad10(buf, i, j) : 0
        else
            v, rc, bad = parseint(T, buf, i, j, b)
        end
        rc == RC_OK && return v
    end
    Throw || return nothing
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

function _parsefloatspan(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                         decimal::UInt8, groupmark) where {T <: _FLOATS}
    P = T === Float16 ? Float32 : T          # Base parses Float16 through Float32
    v = zero(P)
    rc = RC_INVALID
    gm = _floatgroupbyte(groupmark, decimal)
    if i <= j
        k = i
        @inbounds if buf[k] == UInt8('-') || buf[k] == UInt8('+')
            k += 1
        end
        @inbounds if k + 1 <= j && buf[k] == UInt8('0') && _lower(buf[k + 1]) == UInt8('x')
            v, rc = _parsehexfloat(P, buf, i, j)
        elseif gm !== nothing && _hasbyte(buf, i, j, gm)
            scratch = Vector{UInt8}(undef, max(j - i + 1, 8))
            n = degroup!(scratch, buf, i, j, gm, decimal)
            n >= 0 && ((v, rc) = parsefloat(P, scratch, 1, n, decimal))
        else
            v, rc = parsefloat(P, buf, i, j, decimal)
        end
    end
    return (T === Float16 ? Float16(v) : v, rc)
end

function _tryparsefloat(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int, decimal::UInt8,
                        groupmark, ::Val{Throw}) where {T <: _FLOATS, Throw}
    orig_i, orig_j = i, j
    i, j = _stripws(buf, i, j)
    v, rc = _parsefloatspan(T, buf, i, j, decimal, groupmark)
    if rc == RC_OK
        return v
    end
    # RC_OVERFLOW / RC_UNDERFLOW: Base rejects out-of-range results (strtod's
    # ERANGE) — the kernel still holds the ±Inf / ±0 for callers that want it
    Throw || return nothing
    throw(ArgumentError("cannot parse $(_q(_spanstring(buf, orig_i, orig_j))) as $T"))
end

# --- bools --------------------------------------------------------------------------

function _tryparsebool(buf::AbstractVector{UInt8}, i::Int, j::Int, trues, falses,
                       ::Val{Throw}) where {Throw}
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
    Throw || return nothing
    i > j && throw(ArgumentError(orig_i > orig_j ? "input string is empty" :
                                                  "input string only contains whitespace"))
    throw(ArgumentError("invalid Bool representation: $(_q(_spanstring(buf, orig_i, orig_j)))"))
end

# --- arbitrary precision & UUID -----------------------------------------------------------

function _tryparsebig(::Type{BigInt}, buf, i, j, base, groupmark,
                      ::Val{Throw}) where {Throw}
    orig_i, orig_j = i, j
    i, j = _stripws(buf, i, j)
    base = _normalizebase(base)
    if i > j
        Throw && throw(ArgumentError("input string is empty or only contains whitespace"))
        return nothing
    end
    dstart, b, prefixed = _intprefix(buf, i, j, base)
    gm = _intgroupbyte(groupmark, b)
    if prefixed && dstart > j
        Throw && throw(ArgumentError("premature end of integer: $(_q(_spanstring(buf, orig_i, orig_j)))"))
        return nothing
    end
    pbuf, pi, pj = buf, prefixed ? dstart : i, j
    if gm !== nothing && _hasbyte(pbuf, pi, pj, gm)
        scratch = Vector{UInt8}(undef, max(pj - pi + 1, 8))
        n = degroupint!(scratch, pbuf, pi, pj, gm, b)
        if n < 0
            v, rc = BigInt(0), RC_INVALID
        else
            pbuf, pi, pj = scratch, 1, n
            if b == 10
                v, rc = parsebigint(pbuf, pi, pj)
            else
                v, rc, _ = parsebigint(pbuf, pi, pj, b)
            end
        end
    elseif b == 10
        v, rc = parsebigint(pbuf, pi, pj)
    else
        v, rc, _ = parsebigint(pbuf, pi, pj, b)
    end
    prefixed && @inbounds(buf[i] == UInt8('-')) && rc == RC_OK &&
        Base.GMP.MPZ.neg!(v)
    rc == RC_OK && return v
    Throw || return nothing
    throw(ArgumentError("invalid BigInt: $(_q(_spanstring(buf, orig_i, orig_j)))"))
end
function _parsebigfloatspan(buf, i, j, decimal::UInt8, groupmark,
                            rounding::RoundingMode)
    gm = _floatgroupbyte(groupmark, decimal)
    if gm !== nothing && _hasbyte(buf, i, j, gm)
        scratch = Vector{UInt8}(undef, max(j - i + 1, 8))
        n = degroup!(scratch, buf, i, j, gm, decimal)
        if n >= 0
            return parsebigfloat(scratch, 1, n, decimal; rounding)
        end
        return (BigFloat(0), RC_INVALID)
    end
    return parsebigfloat(buf, i, j, decimal; rounding)
end

function _tryparsebig(::Type{BigFloat}, buf, i, j, decimal::UInt8, groupmark,
                      rounding::RoundingMode, ::Val{Throw}) where {Throw}
    orig_i, orig_j = i, j
    i, j = _stripws(buf, i, j)
    v, rc = _parsebigfloatspan(buf, i, j, decimal, groupmark, rounding)
    rc == RC_OK && return v
    Throw || return nothing
    throw(ArgumentError("cannot parse $(_q(_spanstring(buf, orig_i, orig_j))) as BigFloat"))
end
function _tryparseuuid(buf, i, j, ::Val{Throw}) where {Throw}
    u, rc = parseuuid(buf, i, j)
    rc == RC_OK && return Base.UUID(u)
    Throw || return nothing
    throw(ArgumentError("Malformed UUID string: $(_q(_spanstring(buf, i, j)))"))
end

# --- dates ----------------------------------------------------------------------------

_datepattern(::Nothing, ::Type{Dates.Date}) = ISO_DATE
_datepattern(::Nothing, ::Type{Dates.DateTime}) = ISO_DATETIME
_datepattern(::Nothing, ::Type{Dates.Time}) = ISO_TIME
_datepattern(fmt::AbstractString, ::Type) = compilepattern(fmt)
_datepattern(fmt::Dates.DateFormat, ::Type) = compilepattern(fmt)
_datepattern(p::DatePattern, ::Type) = p

_todates(::Type{Dates.Date}, c::CivilParts) = todate(c)
_todates(::Type{Dates.DateTime}, c::CivilParts) = todatetime(c)
_todates(::Type{Dates.Time}, c::CivilParts) = totime(c)

function _tryparsedate(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int, dateformat,
                       ::Val{Throw}) where {T <: Dates.TimeType, Throw}
    pat = _datepattern(dateformat, T)
    c, rc = parsecivil(buf, i, j, pat)
    rc == RC_OK && return _todates(T, c)
    Throw || return nothing
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
  * `base`      fixed integers and `BigInt`: 2 ≤ base ≤ 62; when omitted,
                `0x`/`0o`/`0b` prefixes select 16/8/2 (Base's rule)
  * `decimal`   floats: the decimal separator character (default `'.'`)
  * `groupmark` numbers: a digit-group separator to ignore (`1,000,000`)
  * `rounding`  `BigFloat`: a supported `RoundingMode` (current MPFR mode by default)
  * `trues`/`falses`  Bool: replacement spelling lists (`["yes"]`, `["no"]`)
  * `dateformat` Date/DateTime/Time: a format string or `Dates.DateFormat`

Supported `T`: `Int8`…`Int128`, `UInt8`…`UInt128`, `Bool`, `Float16`,
`Float32`, `Float64`, `BigInt`, `BigFloat`, `Base.UUID`, `Date`, `DateTime`,
`Time`.
"""
function parse end
function tryparse end

@doc (@doc parse) tryparse

# every entry funnels to one (T, buf, i, j, Val(throwing)) dispatcher
_dispatch(::Type{T}, buf, i, j, throwing; base=nothing, groupmark=nothing) where {T <: _INTS} =
    _tryparseint(T, buf, i, j, base, groupmark, throwing)
_dispatch(::Type{T}, buf, i, j, throwing; decimal::Char='.', groupmark=nothing) where {T <: _FLOATS} =
    _tryparsefloat(T, buf, i, j, _decimalbyte(decimal), groupmark, throwing)
_dispatch(::Type{Bool}, buf, i, j, throwing; trues=nothing, falses=nothing) =
    _tryparsebool(buf, i, j, _bytelist(trues), _bytelist(falses), throwing)
_dispatch(::Type{BigInt}, buf, i, j, throwing; base=nothing, groupmark=nothing) =
    _tryparsebig(BigInt, buf, i, j, base, groupmark, throwing)
_dispatch(::Type{BigFloat}, buf, i, j, throwing; decimal::Char='.', groupmark=nothing,
          rounding::RoundingMode=Base.Rounding.rounding(BigFloat)) =
    _tryparsebig(BigFloat, buf, i, j, _decimalbyte(decimal), groupmark, rounding, throwing)
_dispatch(::Type{Base.UUID}, buf, i, j, throwing) = _tryparseuuid(buf, i, j, throwing)
_dispatch(::Type{T}, buf, i, j, throwing; dateformat=nothing) where {T <: Dates.TimeType} =
    _tryparsedate(T, buf, i, j, dateformat, throwing)
_dispatch(::Type{T}, buf, i, j, throwing) where {T} =
    throw(ArgumentError("Parsers does not know how to parse $T (supported: integers of every " *
                        "width, Bool, Float16/32/64, BigInt, BigFloat, UUID, Date, DateTime, Time)"))

_bytelist(::Nothing) = nothing
_bytelist(xs) = Vector{UInt8}[Vector{UInt8}(codeunits(String(x))) for x in xs]

# whole-input forms: hold the source alive across the zero-copy byte view
function parse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}}; kw...) where {T}
    GC.@preserve s begin
        buf = _bytes(s)
        return _dispatch(T, buf, 1, length(buf), Val(true); kw...)::T
    end
end
function tryparse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}}; kw...) where {T}
    GC.@preserve s begin
        buf = _bytes(s)
        return _dispatch(T, buf, 1, length(buf), Val(false); kw...)
    end
end
# byte-span forms
function parse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer; kw...) where {T}
    checkbounds(buf, first:last)
    return _dispatch(T, _bytes(buf), Int(first), Int(last), Val(true); kw...)::T
end
function tryparse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer; kw...) where {T}
    checkbounds(buf, first:last)
    return _dispatch(T, _bytes(buf), Int(first), Int(last), Val(false); kw...)
end

# --- parsenext: the tokenizer primitive ---------------------------------------

"""
    Parsers.parsenext(T, bytes, pos, last; kw...) -> (value, nextpos, code)

Parse the longest well-formed value of `T` that starts at `bytes[pos]`.
`nextpos` is the first byte not consumed. `code` is `RC_OK`, `RC_INVALID`,
`RC_OVERFLOW`, or `RC_UNDERFLOW`; range tokens are consumed and retain the
kernel's range value. No whitespace is skipped.

The supported targets are the integer types, `Float16`/`Float32`/`Float64`,
`BigInt`, `BigFloat`, and `Bool`. Their `base`, radix-prefix, `decimal`,
`groupmark`, `rounding`, and `trues`/`falses` rules match the whole-input
parsers. Custom Bool lists replace the default spellings.
"""
function parsenext(::Type{T}, buf::AbstractVector{UInt8}, pos::Integer,
                   last::Integer; kw...) where {T}
    b = _bytes(buf)
    i, j = Int(pos), Int(last)
    n = length(b)
    ((i <= j && 1 <= i && j <= n) || (i == n + 1 && j == n)) ||
        throw(BoundsError(b, i:j))
    i > j && return (_zero(T), i, RC_INVALID)
    stop = _tokenend(T, b, i, j; kw...)
    stop < i && return (_zero(T), i, RC_INVALID)
    return _nextvalue(T, b, i, stop; kw...)
end

_zero(::Type{T}) where {T <: Number} = zero(T)
_zero(::Type{Bool}) = false
_zero(::Type{T}) where {T} = nothing

@inline _validdigit(b::UInt8, base::Int) = begin
    d = _digitvalue(b, base)
    d != 0xff && d < base
end

# Return the first byte after a digit run and whether at least one digit was
# consumed. A group mark is consumed only when it is between two valid digits.
@inline function _scandigits(buf, k::Int, j::Int, base::Int, gm)
    saw = false
    @inbounds while k <= j
        if _validdigit(buf[k], base)
            saw = true
            k += 1
        elseif gm !== nothing && saw && buf[k] == gm && k < j &&
               _validdigit(buf[k + 1], base)
            k += 1
        else
            break
        end
    end
    return k, saw
end

# Integer scanner, including the sign-before-prefix shape that the exact-span
# kernel receives through `parseprefixedint`.
function _tokenend(::Type{T}, buf, i::Int, j::Int; base=nothing,
                   groupmark=nothing) where {T <: Union{_INTS, BigInt}}
    base = _normalizebase(base)
    @inbounds if T <: _UNSIGNED &&
                 (buf[i] == UInt8('-') || buf[i] == UInt8('+'))
        return i - 1
    end
    dstart, b, prefixed = _intprefix(buf, i, j, base)
    gm = _intgroupbyte(groupmark, b)
    k = prefixed ? dstart : i
    @inbounds if !prefixed && k <= j &&
                 (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
        k += 1
    end
    k, saw = _scandigits(buf, k, j, b, gm)
    return saw ? k - 1 : i - 1
end

@inline function _scanhexdigits(buf, k::Int, j::Int)
    saw = false
    @inbounds while k <= j
        b = buf[k]
        d = b - UInt8('0')
        ishex = d <= 0x09 || (_lower(b) - UInt8('a')) <= 0x05
        ishex || break
        saw = true
        k += 1
    end
    return k, saw
end

function _tokenendhex(buf, i::Int, k::Int, j::Int)
    @inbounds (k + 1 <= j && buf[k] == UInt8('0') &&
               _lower(buf[k + 1]) == UInt8('x')) || return i - 1
    k += 2
    k, sawint = _scanhexdigits(buf, k, j)
    sawfrac = false
    @inbounds if k <= j && buf[k] == UInt8('.')
        k += 1
        k, sawfrac = _scanhexdigits(buf, k, j)
    end
    (sawint || sawfrac) || return i - 1
    @inbounds if k <= j && _lower(buf[k]) == UInt8('p')
        e = k + 1
        e <= j && (buf[e] == UInt8('-') || buf[e] == UInt8('+')) && (e += 1)
        estart = e
        while e <= j && (buf[e] - UInt8('0')) <= 0x09
            e += 1
        end
        e > estart && (k = e)  # incomplete p/sign stays outside the token
    end
    return k - 1
end

function _tokenend(::Type{T}, buf, i::Int, j::Int; decimal::Char='.',
                   groupmark=nothing) where {T <: _FLOATS}
    return _tokenendfloat(T, buf, i, j, decimal, groupmark)
end
function _tokenend(::Type{BigFloat}, buf, i::Int, j::Int; decimal::Char='.',
                   groupmark=nothing,
                   rounding::RoundingMode=Base.Rounding.rounding(BigFloat))
    # Validate even when the token is exact; this keeps scanner and parser
    # keyword behavior identical.
    _roundup(rounding, false, false, false, false)
    return _tokenendfloat(BigFloat, buf, i, j, decimal, groupmark)
end

function _tokenendfloat(::Type{T}, buf, i::Int, j::Int, decimal::Char,
                        groupmark) where {T}
    dec = _decimalbyte(decimal)
    gm = _floatgroupbyte(groupmark, dec)
    k = i
    @inbounds if buf[k] == UInt8('-') || buf[k] == UInt8('+')
        k += 1
    end
    k > j && return i - 1
    @inbounds if _lower(buf[k]) == UInt8('i') || _lower(buf[k]) == UInt8('n')
        for len in (8, 3)
            k + len - 1 <= j || continue
            _, ok = _matchspecial(buf, i, k + len - 1)
            ok && return k + len - 1
        end
        return i - 1
    end
    @inbounds if k + 1 <= j && buf[k] == UInt8('0') &&
                 _lower(buf[k + 1]) == UInt8('x')
        return _tokenendhex(buf, i, k, j)
    end
    k, sawint = _scandigits(buf, k, j, 10, gm)
    sawfrac = false
    @inbounds if k <= j && buf[k] == dec
        k += 1
        k, sawfrac = _scandigits(buf, k, j, 10, nothing)
    end
    (sawint || sawfrac) || return i - 1
    @inbounds if k <= j && _lower(buf[k]) == UInt8('e')
        e = k + 1
        e <= j && (buf[e] == UInt8('-') || buf[e] == UInt8('+')) && (e += 1)
        estart = e
        while e <= j && (buf[e] - UInt8('0')) <= 0x09
            e += 1
        end
        e > estart && (k = e)
    end
    return k - 1
end

@inline function _sentinelprefix(buf, i::Int, j::Int, s::Vector{UInt8})
    n = length(s)
    (n > 0 && i + n - 1 <= j) || return false
    @inbounds for k in 1:n
        buf[i + k - 1] == s[k] || return false
    end
    return true
end

function _tokenend(::Type{Bool}, buf, i::Int, j::Int; trues=nothing,
                   falses=nothing)
    ts = _bytelist(trues)
    fs = _bytelist(falses)
    if ts === nothing && fs === nothing
        @inbounds (buf[i] == UInt8('1') || buf[i] == UInt8('0')) && return i
        for len in (4, 5)
            i + len - 1 <= j || continue
            parsebool(buf, i, i + len - 1)[2] == RC_OK && return i + len - 1
        end
        return i - 1
    end
    stop = i - 1
    ts !== nothing && for s in ts
        _sentinelprefix(buf, i, j, s) && (stop = max(stop, i + length(s) - 1))
    end
    fs !== nothing && for s in fs
        _sentinelprefix(buf, i, j, s) && (stop = max(stop, i + length(s) - 1))
    end
    return stop
end

_tokenend(::Type{T}, buf, i::Int, j::Int; kw...) where {T} =
    throw(ArgumentError("parsenext does not support $T"))

function _nextvalue(::Type{T}, b, i::Int, stop::Int; base=nothing,
                    groupmark=nothing) where {T <: _INTS}
    v = _tryparseint(T, b, i, stop, base, groupmark, Val(false))
    v === nothing && return (zero(T), stop + 1, RC_OVERFLOW)
    return (v, stop + 1, RC_OK)
end
function _nextvalue(::Type{BigInt}, b, i::Int, stop::Int; base=nothing,
                    groupmark=nothing)
    v = _tryparsebig(BigInt, b, i, stop, base, groupmark, Val(false))
    v === nothing && return (BigInt(0), i, RC_INVALID)
    return (v, stop + 1, RC_OK)
end
function _nextvalue(::Type{T}, b, i::Int, stop::Int; decimal::Char='.',
                    groupmark=nothing) where {T <: _FLOATS}
    v, rc = _parsefloatspan(T, b, i, stop, _decimalbyte(decimal), groupmark)
    rc == RC_INVALID && return (zero(T), i, RC_INVALID)
    return (v, stop + 1, rc)
end
function _nextvalue(::Type{Float16}, b, i::Int, stop::Int; decimal::Char='.',
                    groupmark=nothing)
    p, rc = _parsefloatspan(Float32, b, i, stop, _decimalbyte(decimal), groupmark)
    v = Float16(p)
    if rc == RC_OK
        isfinite(p) && isinf(v) && (rc = RC_OVERFLOW)
        p != 0 && iszero(v) && (rc = RC_UNDERFLOW)
    end
    rc == RC_INVALID && return (Float16(0), i, RC_INVALID)
    return (v, stop + 1, rc)
end
function _nextvalue(::Type{BigFloat}, b, i::Int, stop::Int; decimal::Char='.',
                    groupmark=nothing,
                    rounding::RoundingMode=Base.Rounding.rounding(BigFloat))
    v, rc = _parsebigfloatspan(b, i, stop, _decimalbyte(decimal), groupmark, rounding)
    rc == RC_INVALID && return (BigFloat(0), i, RC_INVALID)
    return (v, stop + 1, rc)
end
function _nextvalue(::Type{Bool}, b, i::Int, stop::Int; trues=nothing,
                    falses=nothing)
    v = _tryparsebool(b, i, stop, _bytelist(trues), _bytelist(falses), Val(false))
    v === nothing && return (false, i, RC_INVALID)
    return (v, stop + 1, RC_OK)
end
