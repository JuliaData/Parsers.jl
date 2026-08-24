# =============================================================================
# The public surface: parse / tryparse with the documented Base-like semantics,
# byte-span forms, and parsenext for tokenizers. Fixed-width values use the
# span-exact package kernels. Public BigFloat conversion uses the package-owned
# limb kernel where documented; MPFR handles longer default values and the
# additional validated grammar/range cases.
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
    i <= j || return (i, j)
    @inbounds (_isws(buf[i]) | _isws(buf[j])) || return (i, j)
    @inbounds while i <= j && _isws(buf[i]); i += 1; end
    @inbounds while j >= i && _isws(buf[j]); j -= 1; end
    return i, j
end
_spanstring(buf::AbstractVector{UInt8}, i::Int, j::Int) =
    i > j ? "" : String(buf[i:j])
# Base's error messages show the input through `repr` (escapes visible)
_q(s::String) = repr(s)

# --- integers ---------------------------------------------------------------------

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
    @inbounds b = buf[i]
    k = i + Int((b == UInt8('-')) | (b == UInt8('+')))
    @inbounds if k < j && buf[k] == UInt8('0')
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
        @inbounds if k < j && buf[k] == UInt8('0')
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
    ch = first(String(buf[k:(k + min(3, j - k))]))
    throw(ArgumentError("invalid base $b digit '$ch' in $(_q(s))"))
end

# --- floats -----------------------------------------------------------------------

@inline _parsefloatspan(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                        decimal::UInt8, groupmark) where {T <: _FLOATS} =
    _parsefloatspan(T, buf, i, j, decimal, groupmark, Val(false))

@inline function _parsefloatspan(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                                 decimal::UInt8, groupmark,
                                 ::Val{Whole}) where {T <: _FLOATS, Whole}
    v = zero(T)
    rc = RC_INVALID
    gm = _floatgroupbyte(groupmark, decimal)
    if i <= j
        k = i
        @inbounds if buf[k] == UInt8('-') || buf[k] == UInt8('+')
            k += 1
        end
        probespecial = @inbounds gm !== nothing && k <= j &&
            (_lower(buf[k]) == UInt8('i') || _lower(buf[k]) == UInt8('n'))
        special, isspecial = probespecial ? _matchspecial(buf, i, j) : (0.0, false)
        if isspecial
            v, rc = T(special), RC_OK
        elseif @inbounds(k < j && buf[k] == UInt8('0') &&
                         _lower(buf[k + 1]) == UInt8('x'))
            v, rc = _parsehexfloat(T, buf, i, j)
        elseif gm !== nothing && T !== Float16
            v, rc, handled = _floatgroupedsmall(T, buf, i, j, decimal, gm)
            if !handled
                if _hasbyte(buf, i, j, gm)
                    v, rc = parsegroupedfloatpublic(T, buf, i, j, decimal, gm)
                else
                    v, rc = parsefloatpublic(T, buf, i, j, decimal)
                end
            end
        elseif gm !== nothing && _hasbyte(buf, i, j, gm)
            v, rc = parsegroupedfloatpublic(T, buf, i, j, decimal, gm)
        else
            v, rc = Whole ? parsefloatwholepublic(T, buf, i, j, decimal) :
                            parsefloatpublic(T, buf, i, j, decimal)
        end
    end
    return (v, rc)
end

@inline function _tryparsefloat(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                                decimal::UInt8, groupmark,
                                ::Val{Throw}) where {T <: _FLOATS, Throw}
    return _tryparsefloat(T, buf, i, j, decimal, groupmark, Val(Throw), Val(false))
end

@inline function _tryparsefloat(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                                decimal::UInt8, groupmark, ::Val{Throw},
                                whole::Val{Whole}) where {T <: _FLOATS, Throw, Whole}
    orig_i, orig_j = i, j
    i, j = _stripws(buf, i, j)
    v, rc = _parsefloatspan(T, buf, i, j, decimal, groupmark, whole)
    if rc == RC_OK
        return v
    end
    # The kernel still holds the rounded ±Inf / ±0 for callers that want it.
    # Whole-value parsing rejects every nonzero spelling outside the finite
    # target range. This policy is deterministic across platforms and never
    # delegates fixed-float conversion to Julia's private C parser.
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
        if i == j
            @inbounds b = buf[i]
            ((b == UInt8('1')) | (b == UInt8('0'))) && return b == UInt8('1')
        else
            v, rc = parsebool(buf, i, j)
            rc == RC_OK && return v
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

# A short decimal whose UInt64 significand is exact at the target precision,
# or needs no later decimal scaling, needs one result allocation and a small
# number of MPFR operations. This avoids the general MPFR string scanner.
# A significand that would round before a nontrivial scale stays on the
# general path, which prevents double rounding.
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
    # With q == 0, mpfr_set_ui is the only rounding operation. It can round
    # the exact UInt64 directly even when the coefficient is wider than prec.
    (mant == 0 || q == 0 || 64 - leading_zeros(mant) <= prec) || return nothing

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

# The kernel's rounding modes; MPFR's faithful mode has no kernel equivalent.
@inline _kernelsupports(rounding::Base.MPFR.MPFRRoundingMode) =
    rounding == Base.MPFR.MPFRRoundNearest || rounding == Base.MPFR.MPFRRoundToZero ||
    rounding == Base.MPFR.MPFRRoundUp || rounding == Base.MPFR.MPFRRoundDown ||
    rounding == Base.MPFR.MPFRRoundFromZero

@noinline function _bigfloatfromdecimalpartswide(
        buf, i::Int, j::Int, decimal::UInt8, parts::DecParts,
        rounding::Base.MPFR.MPFRRoundingMode)
    workspace = _takebigwork()
    try
        return _bigfloatfromparts(buf, i, j, decimal, parts, workspace,
                                  precision(BigFloat), rounding)
    finally
        _givebigwork(workspace)
    end
end

@inline function _bigfloatfromdecimalparts(
        buf, i::Int, j::Int, decimal::UInt8, parts::DecParts,
        rounding::Base.MPFR.MPFRRoundingMode)
    if j - i + 1 <= 20
        fast = _smallbigfloat(parts, rounding)
        fast === nothing || return fast
    end
    return _bigfloatfromdecimalpartswide(buf, i, j, decimal, parts, rounding)
end

# A decimal spelling converts in Julia: the short exact path, then the limb
# kernel with a per-thread workspace. OVERFLOW means the magnitude is beyond
# the kernel's scaling range; INVALID means the decimal grammar rejected it.
function _bigfloatdecimal(buf, i::Int, j::Int, decimal::UInt8,
                          rounding::Base.MPFR.MPFRRoundingMode)
    parts, rc = _decompose(buf, i, j, decimal)
    rc == RC_OK || return (BigFloat(0), rc)
    return _bigfloatfromdecimalparts(buf, i, j, decimal, parts, rounding)
end

function _bigfloatgrouped(buf, i::Int, j::Int, decimal::UInt8, gm::UInt8,
                          rounding::Base.MPFR.MPFRRoundingMode)
    scratch = Vector{UInt8}(undef, j - i + 1)
    m = degroup!(scratch, buf, i, j, gm, decimal)
    m >= 0 || return (BigFloat(0), RC_INVALID)
    return _bigfloatdecimal(scratch, 1, m, decimal, rounding)
end

@inline function _obviousmpfrdefault(buf, k::Int, j::Int)
    k <= j || return false
    @inbounds begin
        byte = buf[k]
        lower = _lower(byte)
        (byte == UInt8('@') || lower == UInt8('i') ||
         lower == UInt8('n')) && return true
        return byte == UInt8('0') && k < j &&
               _lower(buf[k + 1]) == UInt8('b')
    end
end

# `_digitrunend` returns one-past the digit run. Avoid that unrepresentable
# sentinel only for a whole-value source whose final index is typemax(Int).
@inline function _alldecimaldigits(buf, k::Int, j::Int)
    j < typemax(Int) && return _digitrunend(buf, k, j) > j
    @inbounds while k < j
        buf[k] - UInt8('0') <= 0x09 || return false
        k += 1
    end
    return @inbounds buf[j] - UInt8('0') <= 0x09
end

# The short MPFR scanner is cheaper than the limb workspace for a 20-digit
# integer, which cannot use `_smallbigfloat`. Leading-zero spellings stay on
# the small package path.
@inline function _prefermpfrdefault(buf, k::Int, j::Int)
    bodybytes = j - k + 1
    bodybytes >= 20 || return false
    @inbounds buf[k] == UInt8('0') && return false
    return _alldecimaldigits(buf, k, j)
end

function _parsebigfloatpublic(buf, i::Int, j::Int, decimal::UInt8, groupmark,
                              rounding)
    i <= j || return (BigFloat(0), RC_INVALID)
    mpfrrounding = _mpfrrounding(rounding)
    gm = _floatgroupbyte(groupmark, decimal)
    n = j - i + 1

    special, isspecial = _matchspecial(buf, i, j)
    isspecial && return (BigFloat(special; precision=precision(BigFloat)), RC_OK)

    @inbounds b = buf[i]
    k = i + Int((b == UInt8('-')) | (b == UInt8('+')))
    @inbounds ishex = k < j && buf[k] == UInt8('0') &&
                      _lower(buf[k + 1]) == UInt8('x')
    normalizegroup = !ishex && gm !== nothing && _hasbyte(buf, i, j, gm)
    normalizedecimal = !ishex && decimal != UInt8('.')
    defaultgrammar = gm === nothing && decimal == UInt8('.')
    kernelrounding = _kernelsupports(mpfrrounding)

    directmpfr = defaultgrammar && n <= 20 &&
                 (_obviousmpfrdefault(buf, k, j) ||
                  (!(buf isa Base.CodeUnits{UInt8,String} &&
                     j == length(buf)) &&
                   _prefermpfrdefault(buf, k, j)))

    # In-range custom decimal/group syntax converts in Julia because it needs
    # Parsers' grammar. Short default decimals use the same package-owned path.
    # Longer default whole values go straight to MPFR: it is BigFloat's native
    # conversion engine and avoids constructing a full-size BigInt coefficient
    # before rounding it back to the requested precision. This boundary does
    # not affect `parsebigfloat` or prefix parsing, which stay self-contained.
    # A validated configured value outside the limb kernel's range is
    # normalized below and then passed to MPFR.
    if !ishex && kernelrounding && !directmpfr &&
       (!defaultgrammar || n <= 20)
        if defaultgrammar
            parts, rc = _decompose(buf, i, j, decimal)
            if rc == RC_OK
                value, rc = _bigfloatfromdecimalparts(
                    buf, i, j, decimal, parts, mpfrrounding)
                rc == RC_OK && return (value, RC_OK)
            end
        else
            value, rc = normalizegroup ?
                _bigfloatgrouped(buf, i, j, decimal, gm, mpfrrounding) :
                _bigfloatdecimal(buf, i, j, decimal, mpfrrounding)
            rc == RC_OK && return (value, RC_OK)
            rc == RC_INVALID && return (value, rc)
        end
    end

    # MPFR's faithful mode has no package-kernel equivalent. Configured
    # decimal grammar must still be Parsers grammar: validate it before the
    # native conversion so MPFR-only forms such as `1@2` and `nan(payload)` do
    # not become valid only because the rounding mode changed. When a group
    # mark is present, validate the normalized span and reuse it immediately.
    if !ishex && !defaultgrammar && !kernelrounding
        if normalizegroup
            scratch = Vector{UInt8}(undef, n + 1)
            m = degroup!(scratch, buf, i, j, gm, decimal)
            m >= 0 || return (BigFloat(0), RC_INVALID)
            _, rc = _decompose(scratch, 1, m, decimal)
            rc == RC_OK || return (BigFloat(0), rc)
            if normalizedecimal
                @inbounds for index in 1:m
                    scratch[index] == decimal && (scratch[index] = UInt8('.'))
                end
            end
            @inbounds scratch[m + 1] = 0x00
            GC.@preserve scratch begin
                return _finishmpfr(pointer(scratch), m, mpfrrounding)
            end
        end
        _, rc = _decompose(buf, i, j, decimal)
        rc == RC_OK || return (BigFloat(0), rc)
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
        @inbounds for offset in 0:(n - 1)
            scratch[offset + 1] = buf[i + offset]
        end
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

@inline function _validbigfloatstart(buf, i::Int, j::Int, decimal::UInt8)
    i <= j || return false
    @inbounds begin
        byte = buf[i]
        (byte == UInt8('-') || byte == UInt8('+')) && (i += 1)
        i <= j || return false
        byte = buf[i]
        lower = _lower(byte)
        return byte - UInt8('0') <= 0x09 || byte == decimal ||
               lower == UInt8('i') || lower == UInt8('n') || byte == UInt8('@')
    end
end

@noinline _throwbigfloat(buf, i::Int, j::Int) =
    throw(ArgumentError("cannot parse $(_q(_spanstring(buf, i, j))) as BigFloat"))

function _tryparsebig(::Type{BigFloat}, buf, i, j, decimal::UInt8, groupmark,
                      rounding, ::Val{Throw}) where {Throw}
    orig_i, orig_j = i, j
    i, j = _stripws(buf, i, j)
    if !_validbigfloatstart(buf, i, j, decimal)
        Throw || return nothing
        return _throwbigfloat(buf, orig_i, orig_j)
    end
    if buf isa Base.CodeUnits{UInt8,String} && j == length(buf) &&
       decimal == UInt8('.') && groupmark === nothing
        @inbounds byte = buf[i]
        k = i + Int((byte == UInt8('-')) | (byte == UInt8('+')))
        if _prefermpfrdefault(buf, k, j)
            n = j - i + 1
            mpfrrounding = _mpfrrounding(rounding)
            value, rc = GC.@preserve buf begin
                _finishmpfr(pointer(buf.s, i), n, mpfrrounding)
            end
            rc == RC_OK && return value
        end
    end
    v, rc = _parsebigfloatpublic(buf, i, j, decimal, groupmark, rounding)
    rc == RC_OK && return v
    Throw || return nothing
    return _throwbigfloat(buf, orig_i, orig_j)
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
@inline _datepattern(fmt::AbstractString, ::Type) = _cachedpattern(fmt)
@inline _datepattern(fmt::Dates.DateFormat, ::Type) = _translatedpattern(fmt)
@inline _datepattern(p::DatePattern, ::Type) = p

@inline _todates(::Type{Dates.Date}, c::CivilParts) = todate(c)
@inline _todates(::Type{Dates.DateTime}, c::CivilParts) = todatetime(c)
@inline _todates(::Type{Dates.Time}, c::CivilParts) = totime(c)

@inline _civilvalidation(::Type{Dates.Date}) = _HAS_DATE
@inline _civilvalidation(::Type{Dates.DateTime}) = _HAS_DATE | _HAS_TIME
@inline _civilvalidation(::Type{Dates.Time}) = _HAS_TIME

@inline _dateparts(::Type{T}, buf, i, j, dateformat) where {T <: Dates.TimeType} =
    _parsecivilvalidated(buf, i, j, _datepattern(dateformat, T), _civilvalidation(T))

@inline function _tryparsedate(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int, dateformat,
                               ::Val{Throw}) where {T <: Dates.TimeType, Throw}
    if i > j
        Throw || return nothing
        throw(ArgumentError("cannot parse \"\" as $T" *
                            (dateformat === nothing ? "" :
                             " with format $(repr(dateformat))")))
    end
    c, rc = _dateparts(T, buf, i, j, dateformat)
    rc == RC_OK && return _todates(T, c)
    Throw || return nothing
    throw(ArgumentError("cannot parse \"$(_spanstring(buf, i, j))\" as $T" *
                        (dateformat === nothing ? "" : " with format $(repr(dateformat))")))
end

# Large DateFormat types resolve to the same pointer-sized DatePattern. Keep
# execution behind one type-erased plan barrier so inference does not rebuild
# the civil executor for every tuple-shaped DateFormat type.
Base.@constprop :none @noinline function _tryparsedateruntime(
        ::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
        pattern::DatePattern) where {T <: Dates.TimeType}
    return _tryparsedate(T, buf, i, j, pattern, Val(false))
end

@noinline function _throwdateformatfailure(::Type{T}, buf::AbstractVector{UInt8},
                                           i::Int, j::Int,
                                           dateformat::Dates.DateFormat) where {T <: Dates.TimeType}
    Base.@nospecialize dateformat
    throw(ArgumentError("cannot parse \"$(_spanstring(buf, i, j))\" as $T" *
                        " with format $(repr(dateformat))"))
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
  * `trues`/`falses`  Bool: replacement lists of nonempty spellings (`["yes"]`, `["no"]`)
  * `dateformat` Date/DateTime/Time: a format string, `Dates.DateFormat`, or
                 compiled `Parsers.DatePattern`

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
    i, j = Int(first), Int(last)
    if _needsindexwindow(j)
        window, i, j = _indexwindow(bytes, i, j)
        return _tryparseint(T, window, i, j, base, groupmark, Val(true))::T
    end
    return _tryparseint(T, bytes, i, j, base, groupmark, Val(true))::T
end
@inline function tryparse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer;
                          base=nothing, groupmark=nothing) where {T <: _INTS}
    checkbounds(buf, first:last)
    bytes = _bytes(buf)
    i, j = Int(first), Int(last)
    if _needsindexwindow(j)
        window, i, j = _indexwindow(bytes, i, j)
        return _tryparseint(T, window, i, j, base, groupmark, Val(false))
    end
    return _tryparseint(T, bytes, i, j, base, groupmark, Val(false))
end

# Fixed-width floats need the same concrete wrapper on Julia 1.10. Keeping the
# supported keywords explicit also rejects misspellings before parser work.
@inline function parse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}};
                       decimal::Char='.', groupmark=nothing) where {T <: _FLOATS}
    GC.@preserve s begin
        buf = _bytes(s)
        return _tryparsefloat(T, buf, 1, length(buf), _decimalbyte(decimal),
                              groupmark, Val(true), Val(true))::T
    end
end
@inline function tryparse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}};
                          decimal::Char='.', groupmark=nothing) where {T <: _FLOATS}
    GC.@preserve s begin
        buf = _bytes(s)
        return _tryparsefloat(T, buf, 1, length(buf), _decimalbyte(decimal),
                              groupmark, Val(false), Val(true))
    end
end
@inline function parse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer;
                       decimal::Char='.', groupmark=nothing) where {T <: _FLOATS}
    checkbounds(buf, first:last)
    bytes = _bytes(buf)
    i, j = Int(first), Int(last)
    if _needsindexwindow(j)
        window, i, j = _indexwindow(bytes, i, j)
        return _tryparsefloat(T, window, i, j, _decimalbyte(decimal),
                              groupmark, Val(true))::T
    end
    return _tryparsefloat(T, bytes, i, j, _decimalbyte(decimal), groupmark,
                          Val(true))::T
end
@inline function tryparse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer;
                          decimal::Char='.', groupmark=nothing) where {T <: _FLOATS}
    checkbounds(buf, first:last)
    bytes = _bytes(buf)
    i, j = Int(first), Int(last)
    if _needsindexwindow(j)
        window, i, j = _indexwindow(bytes, i, j)
        return _tryparsefloat(T, window, i, j, _decimalbyte(decimal),
                              groupmark, Val(false))
    end
    return _tryparsefloat(T, bytes, i, j, _decimalbyte(decimal), groupmark,
                          Val(false))
end

# Date and time targets need concrete keyword wrappers on Julia 1.10. Keep the
# keyword sorter shallow. DateFormat translation selects its compiled plan;
# execution then crosses a bounded positional barrier.

Base.@constprop :none @noinline function _executedateplan(
        ::Type{T}, s, pattern::DatePattern) where {T <: Dates.TimeType}
    GC.@preserve s begin
        buf = _bytes(s)
        return _tryparsedateruntime(T, buf, 1, length(buf), pattern)
    end
end

@noinline function _throwdateformatwhole(::Type{T}, s,
                                         dateformat::Dates.DateFormat) where
                                         {T <: Dates.TimeType}
    Base.@nospecialize dateformat
    GC.@preserve s begin
        buf = _bytes(s)
        return _throwdateformatfailure(T, buf, 1, length(buf), dateformat)
    end
end

Base.@constprop :none @noinline function _executedatespanplan(
        ::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer,
        pattern::DatePattern) where {T <: Dates.TimeType}
    bytes = _bytes(buf)
    i, j = Int(first), Int(last)
    if _needsindexwindow(j)
        window, i, j = _indexwindow(bytes, i, j)
        return _tryparsedateruntime(T, window, i, j, pattern)
    end
    return _tryparsedateruntime(T, bytes, i, j, pattern)
end

@generated function _parsedatewhole(::Type{T},
                                    s::S, dateformat::F,
                                    ::Val{Throw}) where
                                    {T <: Dates.TimeType,
                                     S <: Union{AbstractString, AbstractVector{UInt8}},
                                     F, Throw}
    if F <: Dates.DateFormat
        resolve = :(_datepattern(dateformat, T))
        execute = :(_executedateplan(T, s, $resolve))
        Throw || return execute
        return quote
            value = $execute
            value === nothing && _throwdateformatwhole(T, s, dateformat)
            return value::T
        end
    end
    return quote
        GC.@preserve s begin
            buf = _bytes(s)
            return _tryparsedate(T, buf, 1, length(buf), dateformat,
                                 Val(Throw))
        end
    end
end

@inline function parse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}};
                       dateformat=nothing) where {T <: Dates.TimeType}
    return _parsedatewhole(T, s, dateformat, Val(true))::T
end

@inline function tryparse(::Type{T}, s::Union{AbstractString, AbstractVector{UInt8}};
                          dateformat=nothing) where {T <: Dates.TimeType}
    return _parsedatewhole(T, s, dateformat, Val(false))
end

@generated function _parsedatespan(::Type{T}, buf::B, first::I, last::J,
                                   dateformat::F, ::Val{Throw}) where
                                   {T <: Dates.TimeType,
                                    B <: AbstractVector{UInt8}, I <: Integer,
                                    J <: Integer, F, Throw}
    isformat = F <: Dates.DateFormat
    resolve = isformat ?
              :(_datepattern(dateformat, T)) : nothing
    if isformat
        execute = :(_executedatespanplan(T, buf, first, last, pattern))
        Throw || return quote
            checkbounds(buf, first:last)
            pattern = $resolve
            return $execute
        end
        return quote
            checkbounds(buf, first:last)
            pattern = $resolve
            value = $execute
            if value === nothing
                bytes = _bytes(buf)
                i, j = Int(first), Int(last)
                if _needsindexwindow(j)
                    window, i, j = _indexwindow(bytes, i, j)
                    _throwdateformatfailure(T, window, i, j, dateformat)
                end
                _throwdateformatfailure(T, bytes, i, j, dateformat)
            end
            return value::T
        end
    end
    directvalue = :(_tryparsedate(T, bytes, i, j, dateformat, Val(Throw)))
    windowvalue = :(_tryparsedate(T, window, i, j, dateformat, Val(Throw)))
    return quote
        checkbounds(buf, first:last)
        bytes = _bytes(buf)
        i, j = Int(first), Int(last)
        if _needsindexwindow(j)
            window, i, j = _indexwindow(bytes, i, j)
            return $windowvalue
        end
        return $directvalue
    end
end

@inline function parse(::Type{T}, buf::AbstractVector{UInt8},
                       first::Integer, last::Integer;
                       dateformat=nothing) where {T <: Dates.TimeType}
    return _parsedatespan(T, buf, first, last, dateformat, Val(true))::T
end

@inline function tryparse(::Type{T}, buf::AbstractVector{UInt8},
                          first::Integer, last::Integer;
                          dateformat=nothing) where {T <: Dates.TimeType}
    return _parsedatespan(T, buf, first, last, dateformat, Val(false))
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
    i, j = Int(first), Int(last)
    if _needsindexwindow(j)
        window, i, j = _indexwindow(bytes, i, j)
        return (isempty(kw) ? _dispatchdefault(T, window, i, j, Val(true)) :
                              _dispatch(T, window, i, j, Val(true); kw...))::T
    end
    return (isempty(kw) ? _dispatchdefault(T, bytes, i, j, Val(true)) :
                          _dispatch(T, bytes, i, j, Val(true); kw...))::T
end
function tryparse(::Type{T}, buf::AbstractVector{UInt8}, first::Integer, last::Integer; kw...) where {T}
    checkbounds(buf, first:last)
    bytes = _bytes(buf)
    i, j = Int(first), Int(last)
    if _needsindexwindow(j)
        window, i, j = _indexwindow(bytes, i, j)
        return isempty(kw) ? _dispatchdefault(T, window, i, j, Val(false)) :
                             _dispatch(T, window, i, j, Val(false); kw...)
    end
    return isempty(kw) ? _dispatchdefault(T, bytes, i, j, Val(false)) :
                         _dispatch(T, bytes, i, j, Val(false); kw...)
end

# --- parsenext: the tokenizer primitive ---------------------------------------

"""
    Parsers.parsenext(T, bytes, pos, last; kw...) -> (value, nextpos, code)

Parse the longest well-formed value of `T` that starts at `bytes[pos]`.
`nextpos` is the first byte not consumed. `code` is `RC_OK`, `RC_INVALID`,
`RC_OVERFLOW`, or `RC_UNDERFLOW`; range tokens are consumed and retain the
kernel's range value. No whitespace is skipped.
If a token consumes byte `typemax(Int)`, the one-past `nextpos` cannot be
represented and the function throws `OverflowError`.

Token recognition and conversion state advance together. The implementation
does not first scan a token boundary and then call a whole-value parser on the
same span.

The supported targets are the integer types, `Float16`/`Float32`/`Float64`,
`BigInt`, `BigFloat`, and `Bool`. Their `base`, radix-prefix, `decimal`,
`groupmark`, and `trues`/`falses` rules match the corresponding package
grammars. Custom Bool lists replace the default spellings. `BigFloat`
tokenization uses the bounded low-level decimal, hexadecimal, and special-value
grammar and accepts its `RoundingMode` values. It reports values outside that
kernel's documented decimal prove-out range with a range code. It does not
accept MPFR-only spellings handled by public whole-value parsing.
"""
@inline function _prefixbounds(buf::AbstractVector{UInt8}, pos::Integer,
                               last::Integer)
    b = _bytes(buf)
    (typemin(Int) <= pos <= typemax(Int) &&
     typemin(Int) <= last <= typemax(Int)) ||
        throw(BoundsError(b, pos:last))
    i, j = Int(pos), Int(last)
    n = length(b)
    nonempty = i <= j && 1 <= i && j <= n
    emptyend = i > j && j == n && i > 0 && i - 1 == n
    (nonempty || emptyend) ||
        throw(BoundsError(b, i:j))
    return b, i, j
end

# Prefix kernels use an ordinary `Int` as their cursor and therefore need room
# for bounded lookahead plus one index after the input span. Very high public
# spans are rebased to a window that starts near `typemin(Int)` with bounded
# low-side guard space. This keeps every internal index and lookahead
# representable and leaves normal one-based hot paths unchanged. Position state
# distinguishes a real index zero from its no-position marker. The public result
# is translated back once. Consuming the final addressable byte has no
# representable `nextpos`, so report that fact instead of wrapping the cursor.
@noinline _prefixendoverflow() =
    throw(OverflowError("parsenext consumed byte at typemax(Int); nextpos is not representable"))

@inline function _restoreprefix(window::_IndexWindow, result)
    value, nextpos, code = result
    offset = nextpos - _INDEX_WINDOW_FIRST
    0 <= offset <= window.len || _prefixendoverflow()
    offset <= typemax(Int) - window.origin || _prefixendoverflow()
    return (value, window.origin + offset, code)
end

@inline function _runprefix(f::F, b::AbstractVector{UInt8}, i::Int,
                            j::Int) where {F}
    if _needsindexwindow(j)
        window, first, final = _indexwindow(b, i, j)
        return _restoreprefix(window, f(window, first, final))
    end
    return f(b, i, j)
end

# Keep the rare high-index source type out of the normal fixed-float
# specialization. Passing both source types through the higher-order
# `_runprefix` seam prevents Julia from inlining the short decimal path.
@noinline function _parsenextfloatwindow(::Type{T},
                                         b::B, i::Int, j::Int,
                                         decimal::UInt8, groupmark::G) where
                                         {T <: _FLOATS,
                                          B <: AbstractVector{UInt8}, G}
    window, first, final = _indexwindow(b, i, j)
    result = _parsefloatprefix(T, window, first, final, decimal, groupmark)
    return _restoreprefix(window, result)
end

function parsenext(::Type{T}, buf::AbstractVector{UInt8}, pos::Integer,
                   last::Integer; kw...) where {T}
    _prefixbounds(buf, pos, last)
    throw(ArgumentError("parsenext does not support $T"))
end

function parsenext(::Type{T}, buf::AbstractVector{UInt8}, pos::Integer,
                   last::Integer; base=nothing,
                   groupmark=nothing) where {T <: _INTS}
    b, i, j = _prefixbounds(buf, pos, last)
    i > j && return (zero(T), i, RC_INVALID)
    return _runprefix(b, i, j) do source, first, final
        _parseintprefix(T, source, first, final, base, groupmark)
    end
end

function parsenext(::Type{BigInt}, buf::AbstractVector{UInt8}, pos::Integer,
                   last::Integer; base=nothing, groupmark=nothing)
    b, i, j = _prefixbounds(buf, pos, last)
    i > j && return (BigInt(0), i, RC_INVALID)
    return _runprefix(b, i, j) do source, first, final
        _parsebigintprefix(source, first, final, base, groupmark)
    end
end

@inline function parsenext(::Type{T}, buf::AbstractVector{UInt8}, pos::Integer,
                           last::Integer; decimal::Char='.',
                           groupmark=nothing) where {T <: _FLOATS}
    b, i, j = _prefixbounds(buf, pos, last)
    i > j && return (zero(T), i, RC_INVALID)
    dec = _decimalbyte(decimal)
    _needsindexwindow(j) &&
        return _parsenextfloatwindow(T, b, i, j, dec, groupmark)
    return _parsefloatprefix(T, b, i, j, dec, groupmark)
end

# The omitted keyword uses a concrete marker. Resolving the current task-local
# BigFloat mode through literal branches prevents the generated keyword wrapper
# from widening it back to abstract `RoundingMode`.
struct _DefaultBigFloatRounding end
const _DEFAULT_BIGFLOAT_ROUNDING = _DefaultBigFloatRounding()

@inline function _parsenextbigfloat(buf::AbstractVector{UInt8}, pos::Integer,
                                    last::Integer, decimal::Char, groupmark,
                                    ::_DefaultBigFloatRounding)
    rounding = Base.Rounding.rounding(BigFloat)
    rounding == RoundNearest &&
        return _parsenextbigfloat(buf, pos, last, decimal, groupmark, RoundNearest)
    rounding == RoundToZero &&
        return _parsenextbigfloat(buf, pos, last, decimal, groupmark, RoundToZero)
    rounding == RoundUp &&
        return _parsenextbigfloat(buf, pos, last, decimal, groupmark, RoundUp)
    rounding == RoundDown &&
        return _parsenextbigfloat(buf, pos, last, decimal, groupmark, RoundDown)
    rounding == RoundFromZero &&
        return _parsenextbigfloat(buf, pos, last, decimal, groupmark, RoundFromZero)
    throw(ArgumentError("unsupported BigFloat rounding mode: $rounding"))
end

# Explicit rounding modes specialize directly at the same boundary.
@inline function _parsenextbigfloat(buf::AbstractVector{UInt8}, pos::Integer,
                                    last::Integer, decimal::Char, groupmark,
                                    rounding::R) where {R <: RoundingMode}
    b, i, j = _prefixbounds(buf, pos, last)
    i > j && return (BigFloat(0), i, RC_INVALID)
    dec = _decimalbyte(decimal)
    return _runprefix(b, i, j) do source, first, final
        _parsebigfloatprefix(source, first, final, dec, groupmark, rounding)
    end
end

function parsenext(::Type{BigFloat}, buf::AbstractVector{UInt8}, pos::Integer,
                   last::Integer; decimal::Char='.', groupmark=nothing,
                   rounding::Union{RoundingMode, _DefaultBigFloatRounding}=
                       _DEFAULT_BIGFLOAT_ROUNDING)
    return _parsenextbigfloat(buf, pos, last, decimal, groupmark, rounding)
end

function parsenext(::Type{Bool}, buf::AbstractVector{UInt8}, pos::Integer,
                   last::Integer; trues=nothing, falses=nothing)
    b, i, j = _prefixbounds(buf, pos, last)
    i > j && return (false, i, RC_INVALID)
    ts = _bytelist(trues)
    fs = _bytelist(falses)
    return _runprefix(b, i, j) do source, first, final
        _parseboolprefix(source, first, final, ts, fs)
    end
end
