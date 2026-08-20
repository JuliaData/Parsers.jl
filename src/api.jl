# =============================================================================
# The public surface: parse / tryparse with Base.parse's semantics, the
# byte-span forms, and parsenext for tokenizers. Fixed-width values use the
# span-exact kernels. Rare unresolved fixed-float conversions use Julia's
# bounded C parser, and public BigFloat conversion uses MPFR for Base parity.
# =============================================================================

const _INTS = Union{_SIGNED, _UNSIGNED}
const _FLOATS = Union{Float64, Float32, Float16}

# --- byte views of the input ----------------------------------------------------
# The kernels take AbstractVector{UInt8}. Strings use their allocation-free
# CodeUnits view. Arbitrary byte vectors stay as views: `_load8` has pointer
# fast paths for contiguous storage and a safe scalar gather for other layouts.
_bytes(v::Vector{UInt8}) = v
_bytes(s::Union{String, SubString{String}}) = codeunits(s)
_bytes(s::AbstractString) = codeunits(String(s))
_bytes(c::Base.CodeUnits{UInt8, <:Union{String, SubString{String}}}) = c
@inline function _bytes(v::AbstractVector{UInt8})
    Base.require_one_based_indexing(v)
    return v
end

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
                              ::Nothing, ::Nothing,
                              ::Val{Throw}) where {T <: _INTS, Throw}
    orig_i, orig_j = i, j
    i, j = _stripws(buf, i, j)
    if i > j
        Throw && throw(ArgumentError("input string is empty or only contains whitespace"))
        return nothing
    end
    @inbounds if T <: _UNSIGNED && (buf[i] == UInt8('-') || buf[i] == UInt8('+'))
        Throw && throw(ArgumentError("invalid base 10 digit '$(Char(buf[i]))' in $(_q(_spanstring(buf, orig_i, orig_j)))"))
        return nothing
    end
    k = i
    @inbounds (buf[k] == UInt8('-') || buf[k] == UInt8('+')) && (k += 1)
    @inbounds if k + 1 <= j && buf[k] == UInt8('0')
        c = buf[k + 1]
        if c == UInt8('x') || c == UInt8('o') || c == UInt8('b')
            return _tryparseintradix(T, buf, orig_i, orig_j, i, j, nothing, nothing,
                                     Val(Throw))
        end
    end
    v, rc = parseint(T, buf, i, j)
    rc == RC_OK && return v
    Throw || return nothing
    bad = rc == RC_INVALID ? _firstbad10(buf, i, j) : 0
    _throwintfailure(buf, orig_i, orig_j, i, j, 10, rc, bad)
end

@inline function _tryparseint(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                              base, groupmark,
                              ::Val{Throw}) where {T <: _INTS, Throw}
    orig_i, orig_j = i, j
    i, j = _stripws(buf, i, j)
    if i > j
        Throw && throw(ArgumentError("input string is empty or only contains whitespace"))
        return nothing
    end
    # Decimal input is the dominant public call. Avoid setting up the
    # arbitrary-radix route unless the first bytes can actually be a radix
    # prefix. This matters on Julia 1.10, where the otherwise-dead keyword and
    # tuple setup remains visible for short and invalid-first-byte inputs.
    if base === nothing
        @inbounds if T <: _UNSIGNED && (buf[i] == UInt8('-') || buf[i] == UInt8('+'))
            Throw && throw(ArgumentError("invalid base 10 digit '$(Char(buf[i]))' in $(_q(_spanstring(buf, orig_i, orig_j)))"))
            return nothing
        end
        k = i
        @inbounds (buf[k] == UInt8('-') || buf[k] == UInt8('+')) && (k += 1)
        prefixed = false
        @inbounds if k + 1 <= j && buf[k] == UInt8('0')
            c = buf[k + 1]
            prefixed = c == UInt8('x') || c == UInt8('o') || c == UInt8('b')
        end
        if !prefixed
            if groupmark === nothing
                v, rc = parseint(T, buf, i, j)
                bad = rc == RC_INVALID && Throw ? _firstbad10(buf, i, j) : 0
            else
                gm = _intgroupbyte(groupmark, 10)
                v, rc, bad = _parsegroupeddecimal(T, buf, i, j, gm, false, true)
            end
            rc == RC_OK && return v
            Throw || return nothing
            _throwintfailure(buf, orig_i, orig_j, i, j, 10, rc, bad)
        end
    end

    return _tryparseintradix(T, buf, orig_i, orig_j, i, j, base, groupmark,
                             Val(Throw))
end

# Prefixes and explicit bases need the full arbitrary-radix setup. Keep that
# uncommon branch out of the inlined decimal parser so its code size does not
# tax short scalar calls.
@noinline function _tryparseintradix(::Type{T}, buf::AbstractVector{UInt8},
                                     orig_i::Int, orig_j::Int, i::Int, j::Int,
                                     base, groupmark,
                                     ::Val{Throw}) where {T <: _INTS, Throw}
    base = _normalizebase(base)
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
        if gm !== nothing
            if T <: _SIGNED
                v, rc, bad = parsegroupedprefixedint(T, buf, dstart, j, gm, b, neg)
            else
                v, rc, bad = parsegroupedint(T, buf, dstart, j, gm, b)
            end
        elseif T <: _SIGNED
            v, rc, bad = parseprefixedint(T, pbuf, pi, pj, b, neg)
        else
            v, rc, bad = parseint(T, pbuf, pi, pj, b)
        end
        rc == RC_OK && return v
    elseif gm !== nothing
        v, rc, bad = parsegroupedint(T, buf, i, j, gm, b)
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
    _throwintfailure(buf, orig_i, orig_j, i, j, b, rc, bad)
end

@noinline function _throwintfailure(buf, orig_i, orig_j, i, j, b, rc, bad)
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

@inline function _parsefloatspan(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
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
        special, isspecial = gm === nothing ? (0.0, false) : _matchspecial(buf, i, j)
        if isspecial
            v, rc = P(special), RC_OK
        elseif @inbounds(k + 1 <= j && buf[k] == UInt8('0') &&
                         _lower(buf[k + 1]) == UInt8('x'))
            v, rc = _parsehexfloat(P, buf, i, j)
        elseif gm !== nothing && _hasbyte(buf, i, j, gm)
            v, rc = parsegroupedfloatpublic(P, buf, i, j, decimal, gm)
        else
            v, rc = parsefloatpublic(P, buf, i, j, decimal)
        end
    end
    return (T === Float16 ? Float16(v) : v, rc)
end

# Julia's Windows float parser accepts some ERANGE results as the rounded
# infinity or signed zero. Ask Base only on that cold path and only for Base's
# grammar. The explicit Boolean keeps both policy branches directly testable.
@inline _checkbasefloatrange(rc, decimal, groupmark,
                             iswindows::Bool=Sys.iswindows()) =
    iswindows && decimal == UInt8('.') && groupmark === nothing &&
    (rc == RC_OVERFLOW || rc == RC_UNDERFLOW)

@noinline _basefloatrange(::Type{T}, buf, i::Int, j::Int) where {T <: _FLOATS} =
    Base.tryparse(T, _spanstring(buf, i, j))

@inline function _tryparsefloat(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                                decimal::UInt8, groupmark,
                                ::Val{Throw}) where {T <: _FLOATS, Throw}
    orig_i, orig_j = i, j
    i, j = _stripws(buf, i, j)
    v, rc = _parsefloatspan(T, buf, i, j, decimal, groupmark)
    if rc == RC_OK
        return v
    end
    if _checkbasefloatrange(rc, decimal, groupmark)
        basevalue = _basefloatrange(T, buf, i, j)
        basevalue === nothing || return basevalue
    end
    # The kernel still holds the rounded ±Inf / ±0 for callers that want it.
    # Base rejects these ERANGE results on non-Windows platforms.
    Throw || return nothing
    throw(ArgumentError("cannot parse $(_q(_spanstring(buf, orig_i, orig_j))) as $T"))
end

# --- bools --------------------------------------------------------------------------

@inline function _tryparsebool(buf::AbstractVector{UInt8}, i::Int, j::Int, trues, falses,
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
    special, isspecial = gm === nothing ? (0.0, false) : _matchspecial(buf, i, j)
    isspecial && return (BigFloat(special; precision=precision(BigFloat)), RC_OK)
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

@inline _mpfrrounding(rounding::Base.MPFR.MPFRRoundingMode) = rounding
@inline _mpfrrounding(rounding::RoundingMode) =
    convert(Base.MPFR.MPFRRoundingMode, rounding)

@inline function _mpfr_strtofr!(value::BigFloat, ptr::Ptr{UInt8},
                                rounding::Base.MPFR.MPFRRoundingMode)
    endpoint = Ref{Ptr{UInt8}}()
    ccall((:mpfr_strtofr, Base.MPFR.libmpfr), Cint,
          (Ref{BigFloat}, Cstring, Ref{Ptr{UInt8}}, Cint, Base.MPFR.MPFRRoundingMode),
          value, ptr, endpoint, 0, rounding)
    return endpoint[]
end

@inline function _finishmpfr(ptr::Ptr{UInt8}, n::Int,
                            rounding::Base.MPFR.MPFRRoundingMode)
    value = BigFloat(; precision=precision(BigFloat))
    endpoint = _mpfr_strtofr!(value, ptr, rounding)
    return (value, endpoint == ptr + n ? RC_OK : RC_INVALID)
end

const _BIGFLOAT_POW10 = ntuple(i -> UInt64(10)^(i - 1), 20)

@inline function _magnituderounding(rounding::Base.MPFR.MPFRRoundingMode, neg::Bool)
    neg || return rounding
    rounding == Base.MPFR.MPFRRoundUp && return Base.MPFR.MPFRRoundDown
    rounding == Base.MPFR.MPFRRoundDown && return Base.MPFR.MPFRRoundUp
    return rounding
end

# A short decimal with an exactly representable UInt64 significand needs one
# result allocation and a small number of MPFR arithmetic operations. This
# avoids the general MPFR string scanner for the dominant BigFloat shapes
# without changing precision or directed-rounding semantics. Inputs that would
# round the significand before scaling stay on the general path.
@inline function _smallbigfloat(parts::DecParts,
                                rounding::Base.MPFR.MPFRRoundingMode)
    (!parts.truncated && parts.ndig <= 19) || return nothing
    q = Int(parts.exp10)
    abs(q) <= 19 || return nothing
    factor = @inbounds _BIGFLOAT_POW10[abs(q) + 1]
    factor <= typemax(Culong) || return nothing
    mant = parts.mant
    mant <= typemax(Culong) || return nothing
    prec = precision(BigFloat)
    (mant == 0 || 64 - leading_zeros(mant) <= prec) || return nothing

    value = BigFloat(; precision=prec)
    magrounding = _magnituderounding(rounding, parts.neg)
    ccall((:mpfr_set_ui, Base.MPFR.libmpfr), Cint,
          (Ref{BigFloat}, Culong, Base.MPFR.MPFRRoundingMode),
          value, Culong(mant), magrounding)
    if q > 0
        ccall((:mpfr_mul_ui, Base.MPFR.libmpfr), Cint,
              (Ref{BigFloat}, Ref{BigFloat}, Culong, Base.MPFR.MPFRRoundingMode),
              value, value, Culong(factor), magrounding)
    elseif q < 0
        ccall((:mpfr_div_ui, Base.MPFR.libmpfr), Cint,
              (Ref{BigFloat}, Ref{BigFloat}, Culong, Base.MPFR.MPFRRoundingMode),
              value, value, Culong(factor), magrounding)
    end
    if parts.neg
        ccall((:mpfr_neg, Base.MPFR.libmpfr), Cint,
              (Ref{BigFloat}, Ref{BigFloat}, Base.MPFR.MPFRRoundingMode),
              value, value, rounding)
    end
    return (value, RC_OK)
end

function _parsebigfloatpublic(buf, i::Int, j::Int, decimal::UInt8, groupmark,
                              rounding)
    i <= j || return (BigFloat(0), RC_INVALID)
    mpfrrounding = _mpfrrounding(rounding)
    gm = _floatgroupbyte(groupmark, decimal)
    n = j - i + 1

    special, isspecial = _matchspecial(buf, i, j)
    isspecial && return (BigFloat(special; precision=precision(BigFloat)), RC_OK)

    k = i
    @inbounds (buf[k] == UInt8('-') || buf[k] == UInt8('+')) && (k += 1)
    @inbounds ishex = k + 1 <= j && buf[k] == UInt8('0') &&
                      _lower(buf[k + 1]) == UInt8('x')
    normalizegroup = !ishex && gm !== nothing && _hasbyte(buf, i, j, gm)
    normalizedecimal = !ishex && decimal != UInt8('.')
    defaultgrammar = gm === nothing && decimal == UInt8('.')

    # MPFR is the authority for Base's default BigFloat grammar. Preserve the
    # one-allocation short-decimal path, but send longer default values directly
    # to MPFR instead of scanning them twice. A rejected short default scan also
    # falls through because MPFR accepts Base spellings such as `1@2`, binary
    # floats, and NaN payloads that `_decompose` intentionally does not model.
    # Custom decimal/group syntax still needs exact validation before it is
    # normalized for MPFR.
    if !ishex && (!defaultgrammar || n <= 20)
        parts, rc = normalizegroup ? _decomposegrouped(buf, i, j, decimal, gm) :
                                     _decompose(buf, i, j, decimal)
        if rc == RC_OK
            fast = _smallbigfloat(parts, mpfrrounding)
            fast === nothing || return fast
        elseif !defaultgrammar
            return (BigFloat(0), rc)
        end
    end

    # Julia Strings carry a trailing NUL. The whole-string/default-decimal path
    # can therefore go straight to MPFR with no temporary byte buffer.
    if !normalizegroup && !normalizedecimal &&
       buf isa Base.CodeUnits{UInt8, String} && j == length(buf)
        GC.@preserve buf begin
            return _finishmpfr(pointer(buf.s, i), n, mpfrrounding)
        end
    end

    scratch = Vector{UInt8}(undef, n + 1)
    if normalizegroup
        m = degroup!(scratch, buf, i, j, gm, decimal)
        m >= 0 || return (BigFloat(0), RC_INVALID)
        n = m
    else
        copyto!(scratch, 1, buf, i, n)
    end
    if normalizedecimal
        @inbounds for k in 1:n
            scratch[k] == decimal && (scratch[k] = UInt8('.'))
        end
    end
    @inbounds scratch[n + 1] = 0x00
    GC.@preserve scratch begin
        return _finishmpfr(pointer(scratch), n, mpfrrounding)
    end
end

function _tryparsebig(::Type{BigFloat}, buf, i, j, decimal::UInt8, groupmark,
                      rounding, ::Val{Throw}) where {Throw}
    orig_i, orig_j = i, j
    i, j = _stripws(buf, i, j)
    v, rc = _parsebigfloatpublic(buf, i, j, decimal, groupmark, rounding)
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

@inline _datepattern(::Nothing, ::Type{Dates.Date}) = ISO_DATE
@inline _datepattern(::Nothing, ::Type{Dates.DateTime}) = ISO_DATETIME
@inline _datepattern(::Nothing, ::Type{Dates.Time}) = ISO_TIME
@inline _datepattern(fmt::AbstractString, ::Type) = compilepattern(fmt)
@inline _datepattern(fmt::Dates.DateFormat, ::Type) = compilepattern(fmt)
@inline _datepattern(p::DatePattern, ::Type) = p

@inline _todates(::Type{Dates.Date}, c::CivilParts) = todate(c)
@inline _todates(::Type{Dates.DateTime}, c::CivilParts) = todatetime(c)
@inline _todates(::Type{Dates.Time}, c::CivilParts) = totime(c)

# Keep the dominant default shapes out of the generic pattern interpreter.
# `parsecivil` retains the same fast paths for kernel callers, but reaching it
# through an abstract DatePattern argument costs more than parsing the fixed
# ISO fields themselves.
@inline function _dateparts(::Type{Dates.Date}, buf, i, j, ::Nothing)
    if j - i == 9
        c, rc = parseiso10(buf, i)
        rc == RC_OK && return (c, rc)
    end
    return parsecivil(buf, i, j, ISO_DATE)
end
@inline function _dateparts(::Type{Dates.DateTime}, buf, i, j, ::Nothing)
    if j - i == 18
        c, rc = parseiso19(buf, i)
        rc == RC_OK && return (c, rc)
    end
    return parsecivil(buf, i, j, ISO_DATETIME)
end
@inline function _dateparts(::Type{Dates.Time}, buf, i, j, ::Nothing)
    if j - i == 7
        c, rc = parseiso8(buf, i)
        rc == RC_OK && return (c, rc)
    end
    return parsecivil(buf, i, j, ISO_TIME)
end
@inline function _dateparts(::Type{T}, buf, i, j, pat::DatePattern) where {T <: Dates.TimeType}
    if pat.fixed.nbytes != 0
        c, rc = _parsefixeddate(buf, i, j, pat)
        rc == RC_OK && return (c, rc)
    end
    # Fixed parsing deliberately falls through on failure. The interpreter
    # accepts cases such as a signed fixed-width year and remains the single
    # source of truth for every non-fixed or locale-aware pattern.
    return parsecivil(buf, i, j, pat)
end
@inline _dateparts(::Type{T}, buf, i, j, dateformat) where {T <: Dates.TimeType} =
    parsecivil(buf, i, j, _datepattern(dateformat, T))

@inline function _tryparsedate(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int, dateformat,
                               ::Val{Throw}) where {T <: Dates.TimeType, Throw}
    c, rc = _dateparts(T, buf, i, j, dateformat)
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
ASCII whitespace; dates and UUIDs must fill the span exactly. Byte vectors must
use one-based axes.

Keywords:
  * `base`      fixed integers and `BigInt`: 2 ≤ base ≤ 62; when omitted,
                `0x`/`0o`/`0b` prefixes select 16/8/2 (Base's rule)
  * `decimal`   floats: the decimal separator character (default `'.'`)
  * `groupmark` numbers: a digit-group separator to ignore (`1,000,000`)
  * `rounding`  `BigFloat`: a supported `RoundingMode` (current MPFR mode by default)
  * `trues`/`falses`  Bool: nonempty replacement spelling lists (`["yes"]`, `["no"]`)
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
          rounding=Base.MPFR.rounding_raw(BigFloat)) =
    _tryparsebig(BigFloat, buf, i, j, _decimalbyte(decimal), groupmark, rounding, throwing)
_dispatch(::Type{Base.UUID}, buf, i, j, throwing) = _tryparseuuid(buf, i, j, throwing)
_dispatch(::Type{T}, buf, i, j, throwing; dateformat=nothing) where {T <: Dates.TimeType} =
    _tryparsedate(T, buf, i, j, dateformat, throwing)
_dispatch(::Type{T}, buf, i, j, throwing) where {T} =
    throw(ArgumentError("Parsers does not know how to parse $T (supported: integers of every " *
                        "width, Bool, Float16/32/64, BigInt, BigFloat, UUID, Date, DateTime, Time)"))

# Empty keyword splats were still visible in Julia 1.10 scalar calls. Keep the
# common no-keyword route positional so each destination reaches its hot parser
# without constructing or dispatching through a keyword wrapper.
@inline _dispatchdefault(::Type{T}, buf, i, j, throwing) where {T <: _INTS} =
    _tryparseint(T, buf, i, j, nothing, nothing, throwing)
@inline _dispatchdefault(::Type{T}, buf, i, j, throwing) where {T <: _FLOATS} =
    _tryparsefloat(T, buf, i, j, UInt8('.'), nothing, throwing)
@inline _dispatchdefault(::Type{Bool}, buf, i, j, throwing) =
    _tryparsebool(buf, i, j, nothing, nothing, throwing)
@inline _dispatchdefault(::Type{BigInt}, buf, i, j, throwing) =
    _tryparsebig(BigInt, buf, i, j, nothing, nothing, throwing)
@inline _dispatchdefault(::Type{BigFloat}, buf, i, j, throwing) =
    _tryparsebig(BigFloat, buf, i, j, UInt8('.'), nothing,
                 Base.MPFR.rounding_raw(BigFloat), throwing)
@inline _dispatchdefault(::Type{Base.UUID}, buf, i, j, throwing) =
    _tryparseuuid(buf, i, j, throwing)
@inline _dispatchdefault(::Type{T}, buf, i, j, throwing) where {T <: Dates.TimeType} =
    _tryparsedate(T, buf, i, j, nothing, throwing)
@inline _dispatchdefault(::Type{T}, buf, i, j, throwing) where {T} =
    _dispatch(T, buf, i, j, throwing)

@inline _sentinellengthbytes(s::AbstractString) = ncodeunits(s)
@inline _sentinellengthbytes(s) = length(s)
@inline function _checkbytelist(xs)
    for s in xs
        _sentinellengthbytes(s) > 0 ||
            throw(ArgumentError("Bool spellings must not be empty"))
    end
    return xs
end

@inline _bytelist(::Nothing) = nothing
@inline _bytelist(xs::AbstractVector{<:Union{String, SubString{String}}}) =
    _checkbytelist(xs)
@inline _bytelist(xs::Tuple{Vararg{Union{String, SubString{String}}}}) =
    _checkbytelist(xs)
@inline _bytelist(xs::Vector{Vector{UInt8}}) = _checkbytelist(xs)
@inline function _bytelist(xs)
    normalized = Vector{UInt8}[Vector{UInt8}(codeunits(String(x))) for x in xs]
    return _checkbytelist(normalized)
end

# Fixed-width integers are the most common scalar target. Give their two
# keywords a concrete public method so Julia 1.10 does not retain the generic
# keyword-splat dispatch in short whole-value and byte-span calls.
@inline function parse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}};
                       base=nothing, groupmark=nothing) where {T <: _INTS}
    GC.@preserve s begin
        buf = _bytes(s)
        return _tryparseint(T, buf, 1, length(buf), base, groupmark, Val(true))::T
    end
end
@inline function tryparse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}};
                          base=nothing, groupmark=nothing) where {T <: _INTS}
    GC.@preserve s begin
        buf = _bytes(s)
        return _tryparseint(T, buf, 1, length(buf), base, groupmark, Val(false))
    end
end
@inline function parse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer;
                       base=nothing, groupmark=nothing) where {T <: _INTS}
    checkbounds(buf, first:last)
    bytes = _bytes(buf)
    return _tryparseint(T, bytes, Int(first), Int(last), base, groupmark, Val(true))::T
end
@inline function tryparse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer;
                          base=nothing, groupmark=nothing) where {T <: _INTS}
    checkbounds(buf, first:last)
    bytes = _bytes(buf)
    return _tryparseint(T, bytes, Int(first), Int(last), base, groupmark, Val(false))
end

# Fixed-width floats need the same concrete wrapper on Julia 1.10. Keeping the
# supported keywords explicit also rejects misspellings before parser work.
@inline function parse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}};
                       decimal::Char='.', groupmark=nothing) where {T <: _FLOATS}
    GC.@preserve s begin
        buf = _bytes(s)
        return _tryparsefloat(T, buf, 1, length(buf), _decimalbyte(decimal),
                              groupmark, Val(true))::T
    end
end
@inline function tryparse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}};
                          decimal::Char='.', groupmark=nothing) where {T <: _FLOATS}
    GC.@preserve s begin
        buf = _bytes(s)
        return _tryparsefloat(T, buf, 1, length(buf), _decimalbyte(decimal),
                              groupmark, Val(false))
    end
end
@inline function parse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer;
                       decimal::Char='.', groupmark=nothing) where {T <: _FLOATS}
    checkbounds(buf, first:last)
    bytes = _bytes(buf)
    return _tryparsefloat(T, bytes, Int(first), Int(last), _decimalbyte(decimal),
                          groupmark, Val(true))::T
end
@inline function tryparse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer;
                          decimal::Char='.', groupmark=nothing) where {T <: _FLOATS}
    checkbounds(buf, first:last)
    bytes = _bytes(buf)
    return _tryparsefloat(T, bytes, Int(first), Int(last), _decimalbyte(decimal),
                          groupmark, Val(false))
end

# Date and time targets also need a concrete keyword wrapper on Julia 1.10.
# Keep the reusable DatePattern path visible to inference so compiled fixed
# formats can reach their direct field readers without a generic keyword splat.
@inline function parse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}};
                       dateformat=nothing) where {T <: Dates.TimeType}
    GC.@preserve s begin
        buf = _bytes(s)
        return _tryparsedate(T, buf, 1, length(buf), dateformat, Val(true))::T
    end
end
@inline function tryparse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}};
                          dateformat=nothing) where {T <: Dates.TimeType}
    GC.@preserve s begin
        buf = _bytes(s)
        return _tryparsedate(T, buf, 1, length(buf), dateformat, Val(false))
    end
end
@inline function parse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer;
                       dateformat=nothing) where {T <: Dates.TimeType}
    checkbounds(buf, first:last)
    bytes = _bytes(buf)
    return _tryparsedate(T, bytes, Int(first), Int(last), dateformat, Val(true))::T
end
@inline function tryparse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer;
                          dateformat=nothing) where {T <: Dates.TimeType}
    checkbounds(buf, first:last)
    bytes = _bytes(buf)
    return _tryparsedate(T, bytes, Int(first), Int(last), dateformat, Val(false))
end

# whole-input forms: hold the source alive across the zero-copy byte view
function parse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}}; kw...) where {T}
    GC.@preserve s begin
        buf = _bytes(s)
        return (isempty(kw) ? _dispatchdefault(T, buf, 1, length(buf), Val(true)) :
                              _dispatch(T, buf, 1, length(buf), Val(true); kw...))::T
    end
end
function tryparse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}}; kw...) where {T}
    GC.@preserve s begin
        buf = _bytes(s)
        return isempty(kw) ? _dispatchdefault(T, buf, 1, length(buf), Val(false)) :
                             _dispatch(T, buf, 1, length(buf), Val(false); kw...)
    end
end
# byte-span forms
function parse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer; kw...) where {T}
    checkbounds(buf, first:last)
    bytes = _bytes(buf)
    return (isempty(kw) ? _dispatchdefault(T, bytes, Int(first), Int(last), Val(true)) :
                          _dispatch(T, bytes, Int(first), Int(last), Val(true); kw...))::T
end
function tryparse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer; kw...) where {T}
    checkbounds(buf, first:last)
    bytes = _bytes(buf)
    return isempty(kw) ? _dispatchdefault(T, bytes, Int(first), Int(last), Val(false)) :
                         _dispatch(T, bytes, Int(first), Int(last), Val(false); kw...)
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
`groupmark`, and `trues`/`falses` grammar rules match the whole-input parsers.
Custom Bool lists replace the default spellings. `BigFloat` tokenization uses
the bounded low-level kernel and accepts its `RoundingMode` values. It reports
values outside that kernel's documented decimal prove-out range with a range
code instead of using the public whole-input MPFR fallback.
"""
function parsenext(::Type{T}, buf::AbstractVector{UInt8}, pos::Integer,
                   last::Integer; kw...) where {T}
    b = _bytes(buf)
    (typemin(Int) <= pos <= typemax(Int) &&
     typemin(Int) <= last <= typemax(Int)) ||
        throw(BoundsError(b, pos:last))
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

@inline function _sentinelprefix(buf, i::Int, j::Int, s::AbstractString)
    n = ncodeunits(s)
    (n > 0 && i + n - 1 <= j) || return false
    @inbounds for k in 1:n
        buf[i + k - 1] == codeunit(s, k) || return false
    end
    return true
end

@inline _sentinellength(s::AbstractString) = ncodeunits(s)
@inline _sentinellength(s) = length(s)

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
        _sentinelprefix(buf, i, j, s) && (stop = max(stop, i + _sentinellength(s) - 1))
    end
    fs !== nothing && for s in fs
        _sentinelprefix(buf, i, j, s) && (stop = max(stop, i + _sentinellength(s) - 1))
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
