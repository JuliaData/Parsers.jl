# =============================================================================
# floats — three package-owned tiers:
#   1. exact small case (type-specific Clinger mantissa and exponent bounds):
#      one fma-free multiply/divide by an exactly-representable power of ten
#   2. Eisel–Lemire: 128-bit product against the precomputed powers-of-five
#      table; bails (rarely) on rounding-boundary ambiguity
#   3. exact midpoint comparison in four UInt64 limbs, then Tao's simple
#      decimal conversion over a fixed 800-digit buffer for larger cases
# =============================================================================

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

# --- decimal decomposition ---------------------------------------------------

struct DecParts
    mant::UInt64      # up to 19 significant digits (truncated beyond)
    exp10::Int32      # power of ten applied to mant, saturated at ±typemax(Int32)
    ndig::Int32       # significant digits seen, saturated at typemax(Int32)
    truncated::Bool   # digits beyond 19 were dropped (a nonzero one ⇒ sticky)
    neg::Bool
    digoffset::Int32  # positive exact offset; zero unknown; negative out of range
end

const _DECPARTS_OFFSET_SENTINEL = Int32(-1)
const _DECPARTS_NO_DIGIT = typemin(Int)
const _DECPARTS_EXPONENT_CAP = UInt64(typemax(Int)) +
                               UInt64(typemax(Int32)) + UInt64(1)
const _HEX_EXPONENT_CAP = UInt128(4) * UInt128(typemax(Int)) + UInt128(4096)

@inline function _decimalexponentdigit(value::UInt64, digit::UInt8)
    limit = _DECPARTS_EXPONENT_CAP
    value > (limit - UInt64(digit)) ÷ UInt64(10) && return limit
    return UInt64(10) * value + UInt64(digit)
end

@inline _signeddecimalexponent(value::UInt64, neg::Bool) =
    neg ? -Int128(value) : Int128(value)

@inline function _hexexponentdigit(value::UInt128, digit::UInt8)
    limit = _HEX_EXPONENT_CAP
    value > (limit - UInt128(digit)) ÷ UInt128(10) && return limit
    return UInt128(10) * value + UInt128(digit)
end

@inline function _hexexponentdigit(value::UInt64, digit::UInt8)
    limit = _DECPARTS_EXPONENT_CAP
    value > (limit - UInt64(digit)) ÷ UInt64(10) && return limit
    return UInt64(10) * value + UInt64(digit)
end

@inline _signedhexexponent(value::UInt128, neg::Bool) =
    neg ? -Int128(value) : Int128(value)
@inline _signedhexexponent(value::UInt64, neg::Bool) =
    neg ? -Int128(value) : Int128(value)
@inline _hexexponentzero(::Type{Int}) = zero(UInt64)
@inline _hexexponentzero(::Type{Int128}) = zero(UInt128)

@inline function _boundedint(value::Int128)
    value > typemax(Int) && return typemax(Int)
    value < typemin(Int) && return typemin(Int)
    return Int(value)
end

@inline function _decpartsint32(value::Int)
    value > typemax(Int32) && return typemax(Int32)
    value < typemin(Int32) && return typemin(Int32)
    return Int32(value)
end

@inline function _decpartsexp32(value::Integer)
    limit = Int128(typemax(Int32))
    wide = Int128(value)
    wide > limit && return typemax(Int32)
    wide < -limit && return -typemax(Int32)
    return Int32(wide)
end

@inline function _decpartsdigoffset(digstart::Int, spanstart::Int)
    (digstart == _DECPARTS_NO_DIGIT ||
     (digstart == 0 && spanstart > 0)) && return Int32(0)
    digstart < spanstart && return _DECPARTS_OFFSET_SENTINEL
    delta = Int128(digstart) - Int128(spanstart)
    delta >= typemax(Int32) && return _DECPARTS_OFFSET_SENTINEL
    return Int32(delta + 1)
end

@inline function _decparts(mant::UInt64, exp10::Integer, ndig::Int,
                           truncated::Bool, neg::Bool, digstart::Int,
                           spanstart::Int)
    return DecParts(mant, _decpartsexp32(exp10), _decpartsint32(ndig),
                    truncated, neg, _decpartsdigoffset(digstart, spanstart))
end

# Exact decimal spans use the same grammar engine as prefix parsing. The
# wrapper accepts only a token that consumes the full span; incomplete
# exponents and trailing bytes remain invalid for the exact kernel.
@inline function _decompose(buf::AbstractVector{UInt8}, i::Int, j::Int,
                            decimal::UInt8)
    parts, nextpos, rc = _decomposeplainprefix(buf, i, j, decimal)
    rc == RC_OK && nextpos > j && return (parts, RC_OK)
    return (DecParts(0, 0, 0, false, parts.neg, 0), RC_INVALID)
end

@inline function _decomposegrouped(buf::AbstractVector{UInt8}, i::Int, j::Int,
                                   decimal::UInt8, groupmark::UInt8)
    parts, nextpos, rc = _decomposeprefix(buf, i, j, decimal, groupmark)
    rc == RC_OK && nextpos > j && return (parts, RC_OK)
    return (DecParts(0, 0, 0, false, parts.neg, 0), RC_INVALID)
end

# Parse an ungrouped decimal token and build its conversion state in the same
# pass. This keeps the exact decomposer's eight-byte digit gathering, but a
# delimiter ends the span and an incomplete exponent remains uncommitted.
function _decomposeplainprefix(buf::AbstractVector{UInt8}, i::Int, j::Int,
                               decimal::UInt8)
    spanstart = i
    neg = false
    @inbounds if i <= j
        b = buf[i]
        neg = b == UInt8('-')
        (neg | (b == UInt8('+'))) && (i += 1)
    end
    i > j && return (DecParts(0, 0, 0, false, neg, 0), spanstart, RC_INVALID)

    mant = zero(UInt64)
    ndig = 0
    exp10 = 0
    truncated = false
    sawdigit = false
    digstart = _DECPARTS_NO_DIGIT
    @inbounds while i <= j && buf[i] == UInt8('0')
        sawdigit = true
        i += 1
    end
    @inbounds if i <= j && buf[i] - UInt8('0') <= 0x09
        digstart = i
        while i <= j && j - i >= 7 && ndig <= 11
            w = _load8(buf, i)
            if !_alldigits8(w)
                take = _firstnondigit8(w)
                d, _ = _rundigits(w, take)
                mant = mant * @inbounds(_POW10U64[take + 1]) + d
                ndig += take
                i += take
                break
            end
            mant = mant * 100_000_000 + _digits8(w)
            ndig += 8
            i += 8
        end
        while i <= j
            d = buf[i] - UInt8('0')
            d > 0x09 && break
            if ndig < 19
                mant = 10mant + d
            else
                truncated |= d != 0x00
                exp10 += 1
            end
            ndig += 1
            i += 1
            if ndig >= 19
                while i <= j && j - i >= 7
                    w = _load8(buf, i)
                    _alldigits8(w) || break
                    truncated |= w != 0x3030303030303030
                    ndig += 8
                    exp10 += 8
                    i += 8
                end
            end
        end
        sawdigit = true
    end

    @inbounds if i <= j && buf[i] == decimal
        i += 1
        if ndig == 0
            while i <= j && buf[i] == UInt8('0')
                sawdigit = true
                exp10 -= 1
                i += 1
            end
            i <= j && buf[i] - UInt8('0') <= 0x09 && (digstart = i)
        end
        while i <= j && j - i >= 7 && ndig <= 11
            w = _load8(buf, i)
            if !_alldigits8(w)
                take = _firstnondigit8(w)
                d, _ = _rundigits(w, take)
                mant = mant * @inbounds(_POW10U64[take + 1]) + d
                ndig += take
                exp10 -= take
                sawdigit |= take > 0
                i += take
                break
            end
            mant = mant * 100_000_000 + _digits8(w)
            ndig += 8
            exp10 -= 8
            sawdigit = true
            i += 8
        end
        while i <= j
            d = buf[i] - UInt8('0')
            d > 0x09 && break
            if ndig < 19
                mant = 10mant + d
                exp10 -= 1
            else
                truncated |= d != 0x00
            end
            ndig += 1
            sawdigit = true
            i += 1
            if ndig >= 19
                while i <= j && j - i >= 7
                    w = _load8(buf, i)
                    _alldigits8(w) || break
                    truncated |= w != 0x3030303030303030
                    ndig += 8
                    i += 8
                end
            end
        end
    end
    sawdigit || return (DecParts(0, 0, 0, false, neg, 0), spanstart, RC_INVALID)

    commit = i
    @inbounds if i <= j && _lower(buf[i]) == UInt8('e')
        k = i + 1
        eneg = false
        if k <= j
            b = buf[k]
            eneg = b == UInt8('-')
            (eneg | (b == UInt8('+'))) && (k += 1)
        end
        estart = k
        e = zero(UInt64)
        while k <= j
            d = buf[k] - UInt8('0')
            d <= 0x09 || break
            e = _decimalexponentdigit(e, d)
            k += 1
        end
        if k > estart
            exp10 = Int128(exp10) + _signeddecimalexponent(e, eneg)
            commit = k
        end
    end

    parts = _decparts(mant, exp10, ndig, truncated, neg, digstart, spanstart)
    return (parts, commit, RC_OK)
end

# Grouped decimal prefixes remain scalar because every mark needs neighbour
# validation. Both paths recognize grammar and conversion state only once.
function _decomposeprefix(buf::AbstractVector{UInt8}, i::Int, j::Int,
                          decimal::UInt8, groupmark)
    groupmark === nothing && return _decomposeplainprefix(buf, i, j, decimal)
    orig = i
    neg = false
    @inbounds if i <= j
        b = buf[i]
        neg = b == UInt8('-')
        (neg | (b == UInt8('+'))) && (i += 1)
    end
    i > j && return (DecParts(0, 0, 0, false, neg, 0), orig, RC_INVALID)

    mant = zero(UInt64)
    ndig = 0
    exp10 = 0
    truncated = false
    sawdigit = false
    significant = false
    digstart = _DECPARTS_NO_DIGIT
    intstart = i

    # Integer digits. A mark whose right neighbour is not a digit is a
    # delimiter; it is never consumed speculatively.
    @inbounds while i <= j
        b = buf[i]
        d = b - UInt8('0')
        if d <= 0x09
            sawdigit = true
            if significant || d != 0
                !significant && (digstart = i)
                significant = true
                if ndig < 19
                    mant = 10mant + d
                else
                    truncated |= d != 0
                    exp10 += 1
                end
                ndig += 1
            end
            i += 1
        elseif groupmark !== nothing && b == groupmark && i > intstart && i < j &&
               (buf[i - 1] - UInt8('0')) <= 0x09 &&
               (buf[i + 1] - UInt8('0')) <= 0x09
            i += 1
        else
            break
        end
    end

    # Fraction digits. Marks never apply after the decimal byte.
    @inbounds if i <= j && buf[i] == decimal
        i += 1
        while i <= j
            d = buf[i] - UInt8('0')
            d <= 0x09 || break
            sawdigit = true
            if !significant && d == 0
                exp10 -= 1
            else
                !significant && (digstart = i)
                significant = true
                if ndig < 19
                    mant = 10mant + d
                    exp10 -= 1
                else
                    truncated |= d != 0
                end
                ndig += 1
            end
            i += 1
        end
    end
    sawdigit || return (DecParts(0, 0, 0, false, neg, 0), orig, RC_INVALID)

    commit = i
    # Do not consume an incomplete exponent. This makes `1e,` a token `1`
    # followed by `e,`, while `1e2,` commits the complete exponent.
    @inbounds if i <= j && _lower(buf[i]) == UInt8('e')
        k = i + 1
        eneg = false
        if k <= j
            b = buf[k]
            eneg = b == UInt8('-')
            (eneg | (b == UInt8('+'))) && (k += 1)
        end
        estart = k
        e = zero(UInt64)
        while k <= j
            d = buf[k] - UInt8('0')
            d <= 0x09 || break
            e = _decimalexponentdigit(e, d)
            k += 1
        end
        if k > estart
            exp10 = Int128(exp10) + _signeddecimalexponent(e, eneg)
            commit = k
        end
    end

    parts = _decparts(mant, exp10, ndig, truncated, neg, digstart, orig)
    return (parts, commit, RC_OK)
end

# --- tier 2: Eisel–Lemire ------------------------------------------------------

# Powers of five, 128-bit truncated significands, q ∈ POW5MIN:POW5MAX.
const POW5MIN = -342
const POW5MAX = 308

# Minimal limb machinery — exists solely to build the table at precompile time.
# Little-endian Vector{UInt64} limbs; operations: multiply by 5, bit length,
# extract top-128, and shifted compare/subtract driving one restoring division.
function _mul5!(a::Vector{UInt64})
    carry = zero(UInt64)
    @inbounds for k in eachindex(a)
        hi, lo = _mul64(a[k], UInt64(5))
        s = lo + carry
        a[k] = s
        carry = hi + (s < lo)
    end
    carry != 0 && push!(a, carry)
    return a
end
@inline function _mul64(x::UInt64, y::UInt64)
    p = UInt128(x) * UInt128(y)
    return (UInt64(p >> 64), UInt64(p & typemax(UInt64)))
end
function _bitlen(a::Vector{UInt64})
    @inbounds for k in length(a):-1:1
        a[k] != 0 && return 64 * (k - 1) + (64 - leading_zeros(a[k]))
    end
    return 0
end
@inline function _getbit(a::Vector{UInt64}, bit::Int)  # 0-based
    limb = bit >> 6 + 1
    limb > length(a) && return false
    return (a[limb] >> (bit & 63)) & 1 == 1
end
# top 128 bits of `a` (normalized so bit (bitlen-1) is the msb of hi)
function _top128(a::Vector{UInt64})
    bl = _bitlen(a)
    hi = zero(UInt64); lo = zero(UInt64)
    for b in 0:127
        src = bl - 1 - b
        bit = src >= 0 ? _getbit(a, src) : false
        if b < 64
            hi |= UInt64(bit) << (63 - b)
        else
            lo |= UInt64(bit) << (127 - b)
        end
    end
    sticky = false
    for b in 0:(bl - 129)
        if _getbit(a, b)
            sticky = true
            break
        end
    end
    return hi, lo, sticky
end
# is (a << s) <= r ?
function _shiftedle(a::Vector{UInt64}, s::Int, r::Vector{UInt64})
    bla = _bitlen(a) + s
    blr = _bitlen(r)
    bla != blr && return bla < blr
    for b in (blr - 1):-1:0
        ab = b - s >= 0 ? _getbit(a, b - s) : false
        rb = _getbit(r, b)
        ab != rb && return rb        # first difference: a<r iff r has the 1
    end
    return true
end
# r -= a << s   (requires (a<<s) ≤ r)
function _subshifted!(r::Vector{UInt64}, a::Vector{UInt64}, s::Int)
    limbshift = s >> 6
    bitshift = s & 63
    borrow = zero(UInt64)
    @inbounds for k in 1:length(r)
        ak = k - limbshift
        av = zero(UInt64)
        if 1 <= ak <= length(a)
            av = a[ak] << bitshift
            bitshift != 0 && ak > 1 && (av |= a[ak - 1] >> (64 - bitshift))
        elseif bitshift != 0 && 1 <= ak - 1 <= length(a) && ak == length(a) + 1
            av = a[ak - 1] >> (64 - bitshift)
        end
        d = r[k] - av
        b2 = d > r[k]
        d2 = d - borrow
        borrow = UInt64(b2 | (d2 > d))
        r[k] = d2
    end
    return r
end

function _buildpow5()
    n = POW5MAX - POW5MIN + 1
    HI = Vector{UInt64}(undef, n)
    LO = Vector{UInt64}(undef, n)
    # positive q (and q = 0): truncated top-128 of 5^q
    p = UInt64[1]
    for q in 0:POW5MAX
        hi, lo, _ = _top128(p)
        HI[q - POW5MIN + 1] = hi
        LO[q - POW5MIN + 1] = lo
        _mul5!(p)
    end
    # negative q: floor(2^(bitlen(5^p)+127) / 5^p) + 1  (reference table rule)
    p = UInt64[1]
    for q in -1:-1:POW5MIN
        _mul5!(p)                                 # p = 5^(-q)
        k = _bitlen(p) + 127
        # restoring division: quotient of 2^k / p has exactly 128 bits
        r = zeros(UInt64, (k >> 6) + 2)
        r[(k >> 6) + 1] |= UInt64(1) << (k & 63)
        qhi = zero(UInt64); qlo = zero(UInt64)
        for bit in 127:-1:0
            if _shiftedle(p, bit, r)
                _subshifted!(r, p, bit)
                if bit >= 64
                    qhi |= UInt64(1) << (bit - 64)
                else
                    qlo |= UInt64(1) << bit
                end
            end
        end
        qlo += 1                                   # the +1 (never overflows: quotient is odd-truncated)
        qlo == 0 && (qhi += 1)
        HI[q - POW5MIN + 1] = qhi
        LO[q - POW5MIN + 1] = qlo
    end
    return HI, LO
end

const POW5HI, POW5LO = _buildpow5()

# Eisel–Lemire core: value = mant × 10^q (mant ≠ 0, not truncated unless
# `truncated`). Returns reinterpretable bits, or -1 ⇒ tier 3 decides.
# Binary-format constants (fast_float's binary_format<T>): the same Eisel–
# Lemire and simple-decimal-conversion code serves Float64 and Float32 —
# Float32 is parsed NATIVELY (never Float64-then-round, which double-rounds).
@inline _mantbits(::Type{Float64}) = 52
@inline _mantbits(::Type{Float32}) = 23
@inline _mantbits(::Type{Float16}) = 10
@inline _bias(::Type{Float64}) = 1023
@inline _bias(::Type{Float32}) = 127
@inline _bias(::Type{Float16}) = 15
@inline _maxexp(::Type{Float64}) = 2047      # biased exponent of ±Inf
@inline _maxexp(::Type{Float32}) = 255
@inline _maxexp(::Type{Float16}) = 31
@inline _elshift(::Type{Float64}) = 9         # 64 - mantbits - 3: keeps mantbits+2 product bits
@inline _elshift(::Type{Float32}) = 38
@inline _tiemin(::Type{Float64}) = -4         # q range where the 128-bit product is exact
@inline _tiemax(::Type{Float64}) = 23
@inline _tiemin(::Type{Float32}) = -17
@inline _tiemax(::Type{Float32}) = 10
@inline _infbits(::Type{Float64}) = 0x7ff0000000000000
@inline _infbits(::Type{Float32}) = UInt64(0x7f800000)
@inline _infbits(::Type{Float16}) = UInt64(0x7c00)

_eisel_lemire(mant::UInt64, q::Int) = _eisel_lemire(Float64, mant, q)

# Returns the (unsigned) bit pattern of T as an Int64 ≥ 0, or a negative code:
# -1 ambiguous (tier 3 decides), -2 exponent outside the table (certain
# under/overflow — the caller decides which by q's sign), -3 overflow (±Inf).
# A ZERO bit pattern here means underflow-to-zero: mant is nonzero on entry.
@inline function _eisel_lemire(::Type{T}, mant::UInt64, q::Int) where {T <: Union{Float64, Float32}}
    (q < POW5MIN || q > POW5MAX) && return Int64(-2)   # certain under/overflow, sign applied by caller
    lz = leading_zeros(mant)
    w = mant << lz
    idx = q - POW5MIN + 1
    @inbounds t = UInt128(w) * UInt128(POW5HI[idx])
    hi = UInt64(t >> 64)
    lo = UInt64(t & typemax(UInt64))
    if (hi & 0x1ff) == 0x1ff                            # need more precision
        @inbounds t2 = UInt128(w) * UInt128(POW5LO[idx])
        hi2 = UInt64(t2 >> 64)
        lo0 = lo
        lo += hi2
        lo < lo0 && (hi += 1)
        (hi & 0x1ff) == 0x1ff && lo + 1 == 0 && return Int64(-1)  # still ambiguous
    end
    MB = _mantbits(T)
    upper = hi >> 63
    shift = Int(upper) + _elshift(T)
    m = hi >> shift                                     # MB+2 bits: MB+1 significand + round bit
    e2 = ((217706 * q) >> 16) + 63 + Int(upper) - lz    # unbiased binary exponent of hi's msb
    e2 += _bias(T)                                      # bias
    if e2 <= 0
        # Shift the guard-bit mantissa into the denormal range, then round it.
        # A carry can promote the result to the smallest normal. This is the
        # standard Eisel-Lemire subnormal step; rejecting here sends every
        # shortest subnormal through the cold exact-decimal tier.
        shift = -e2 + 1
        shift >= 64 && return Int64(0)                  # certain underflow
        m >>= shift
        m = (m + (m & 1)) >> 1
        e2 = m < (UInt64(1) << MB) ? 0 : 1
        return Int64((UInt64(e2) << MB) | (m & ((UInt64(1) << MB) - 1)))
    end
    # Exact halfway values in the small-power range: for -4 <= q <= 23 the
    # 128-bit product is EXACT (5^|q| fits; Mushtak & Lemire, "Fast Number
    # Parsing Without Fallback"), so a detected tie is a true tie and
    # round-half-even is applied here by clearing the low bit, without entering
    # the cold exact-conversion tier.
    if lo <= 1 && _tiemin(T) <= q <= _tiemax(T) && (m & 0b11) == 0b01 && (m << shift) == hi
        m &= ~UInt64(1)                                  # tie → even (do not round up)
    end
    m = (m + (m & 1)) >> 1                              # round to nearest, ties away resolved below
    if m == (UInt64(1) << (MB + 1))
        m >>= 1
        e2 += 1
    end
    e2 >= _maxexp(T) && return Int64(-3)                # overflow ⇒ ±Inf
    return Int64((UInt64(e2) << MB) | (m & ((UInt64(1) << MB) - 1)))
end

# --- tier 3: exact decimal conversion -----------------------------------------

# Most tier-3 calls come from a long significand whose first 19 digits put the
# value on opposite sides of one IEEE rounding boundary. Resolve that boundary
# with four package-owned UInt64 limbs. This covers the common exact-halfway
# adversaries whenever the complete scaled comparison fits in 256 bits, without
# allocation. Inputs that need more precision continue to total SDC.
const _U256 = NTuple{4, UInt64}
const _POW5U64 = ntuple(k -> UInt64(5)^(k - 1), 28) # 5^0 through 5^27
const _POW5U128 = ntuple(k -> UInt128(5)^(k - 1), 56) # 5^0 through 5^55

@inline _u256(x::UInt64) = (x, zero(UInt64), zero(UInt64), zero(UInt64))

@inline function _u256mul(x::_U256, y::UInt64)
    mask = UInt128(typemax(UInt64))
    p = UInt128(x[1]) * y
    x1 = UInt64(p & mask)
    p = UInt128(x[2]) * y + (p >> 64)
    x2 = UInt64(p & mask)
    p = UInt128(x[3]) * y + (p >> 64)
    x3 = UInt64(p & mask)
    p = UInt128(x[4]) * y + (p >> 64)
    x4 = UInt64(p & mask)
    return ((x1, x2, x3, x4), (p >> 64) == 0)
end

@inline function _u256muladd10(x::_U256, digit::UInt8)
    mask = UInt128(typemax(UInt64))
    p = UInt128(x[1]) * 10 + digit
    x1 = UInt64(p & mask)
    p = UInt128(x[2]) * 10 + (p >> 64)
    x2 = UInt64(p & mask)
    p = UInt128(x[3]) * 10 + (p >> 64)
    x3 = UInt64(p & mask)
    p = UInt128(x[4]) * 10 + (p >> 64)
    x4 = UInt64(p & mask)
    return ((x1, x2, x3, x4), (p >> 64) == 0)
end

@inline function _u256pow5(x::_U256, exponent::Int)
    exponent >= 0 || return (x, false)
    exponent <= 110 || return (x, false) # 5^111 is wider than 256 bits
    while exponent >= 27
        x, ok = _u256mul(x, _POW5U64[28])
        ok || return (x, false)
        exponent -= 27
    end
    x, ok = _u256mul(x, _POW5U64[exponent + 1])
    return (x, ok)
end

@inline function _u256shl(x::_U256, shift::Int)
    shift >= 0 || return (x, false)
    shift == 0 && return (x, true)
    shift < 256 || return (x, false)
    words = shift >> 6
    bits = shift & 63
    x1, x2, x3, x4 = x
    z = zero(UInt64)
    if bits == 0
        words == 1 && return ((z, x1, x2, x3), x4 == 0)
        words == 2 && return ((z, z, x1, x2), (x3 | x4) == 0)
        return ((z, z, z, x1), (x2 | x3 | x4) == 0)
    end
    rshift = 64 - bits
    if words == 0
        return ((x1 << bits,
                 (x2 << bits) | (x1 >> rshift),
                 (x3 << bits) | (x2 >> rshift),
                 (x4 << bits) | (x3 >> rshift)),
                (x4 >> rshift) == 0)
    elseif words == 1
        return ((z, x1 << bits,
                 (x2 << bits) | (x1 >> rshift),
                 (x3 << bits) | (x2 >> rshift)),
                x4 == 0 && (x3 >> rshift) == 0)
    elseif words == 2
        return ((z, z, x1 << bits, (x2 << bits) | (x1 >> rshift)),
                (x3 | x4) == 0 && (x2 >> rshift) == 0)
    else
        return ((z, z, z, x1 << bits),
                (x2 | x3 | x4) == 0 && (x1 >> rshift) == 0)
    end
end

@inline function _u256cmp(x::_U256, y::_U256)
    x[4] != y[4] && return x[4] < y[4] ? -1 : 1
    x[3] != y[3] && return x[3] < y[3] ? -1 : 1
    x[2] != y[2] && return x[2] < y[2] ? -1 : 1
    return x[1] == y[1] ? 0 : x[1] < y[1] ? -1 : 1
end

# Parse the exact decimal as `significand * 10^exponent`. Pending zero digits
# are committed only when followed by a nonzero digit, so trailing zeros do not
# consume limb capacity.
function _u256decimal(buf::AbstractVector{UInt8}, i::Int, j::Int,
                      decimal::UInt8, groupmark=nothing)
    @inbounds if i <= j && (buf[i] == UInt8('-') || buf[i] == UInt8('+'))
        i += 1
    end
    x = _u256(zero(UInt64))
    started = false
    point = false
    fraction = 0
    pendingzeros = 0
    exponent = Int128(0)
    @inbounds while i <= j
        byte = buf[i]
        digit = byte - UInt8('0')
        if digit <= 0x09
            point && (fraction += 1)
            if !started
                if digit != 0
                    x, ok = _u256muladd10(x, digit)
                    ok || return (x, 0, false)
                    started = true
                end
            elseif digit == 0
                pendingzeros += 1
            else
                pendingzeros <= 76 || return (x, 0, false)
                for _ in 1:pendingzeros
                    x, ok = _u256muladd10(x, 0x00)
                    ok || return (x, 0, false)
                end
                x, ok = _u256muladd10(x, digit)
                ok || return (x, 0, false)
                pendingzeros = 0
            end
        elseif byte == decimal
            point = true
        elseif groupmark !== nothing && byte == groupmark
            # The prefix or grouped-span decomposer already validated that
            # marks occur only between integer digits. Exact rounding rereads
            # digits, not grammar.
        else
            i += 1
            eneg = false
            @inbounds if i <= j && (buf[i] == UInt8('-') || buf[i] == UInt8('+'))
                eneg = buf[i] == UInt8('-')
                i += 1
            end
            e = zero(UInt64)
            @inbounds while i <= j
                e = _decimalexponentdigit(e, buf[i] - UInt8('0'))
                i += 1
            end
            exponent = _signeddecimalexponent(e, eneg)
            break
        end
        i += 1
    end
    started || return (x, 0, false)
    decimalplaces = fraction - pendingzeros
    # The fixed-limb comparison necessarily overflows outside this range.
    # Check before subtracting so even a lazy, enormous byte vector cannot wrap.
    q = exponent - Int128(decimalplaces)
    -110 <= q <= 110 || return (x, 0, false)
    return (x, Int(q), true)
end

@inline function _floatmidpoint(::Type{T}, bits::UInt64) where {T <: Union{Float64, Float32, Float16}}
    MB = _mantbits(T)
    mask = (UInt64(1) << MB) - 1
    biased = Int(bits >> MB)
    mant = bits & mask
    if biased == 0
        exponent = 1 - _bias(T) - MB
    else
        mant |= UInt64(1) << MB
        exponent = biased - _bias(T) - MB
    end
    return (2mant + 1, exponent - 1)
end

function _u256midpointcmp(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                          decimal::UInt8,
                          lowerbits::UInt64, groupmark=nothing) where
                          {T <: Union{Float64, Float32, Float16}}
    real, exponent10, ok = _u256decimal(buf, i, j, decimal, groupmark)
    ok || return (0, false)
    midpoint, exponent2 = _floatmidpoint(T, lowerbits)
    theoretical = _u256(midpoint)
    if exponent10 >= 0
        real, ok = _u256pow5(real, exponent10)
    else
        theoretical, ok = _u256pow5(theoretical, -exponent10)
    end
    ok || return (0, false)
    shift = exponent10 - exponent2
    if shift >= 0
        real, ok = _u256shl(real, shift)
    else
        theoretical, ok = _u256shl(theoretical, -shift)
    end
    ok || return (0, false)
    return (_u256cmp(real, theoretical), true)
end

# Short Float16 boundaries fit in one UInt128. Reusing the exact decimal parts
# avoids a second digit-by-digit fixed-limb parse on this latency-sensitive
# midpoint path.
@inline function _u128midpointcmp(parts::DecParts, lowerbits::UInt64)
    parts.truncated && return (0, false)
    real = UInt128(parts.mant)
    midpoint, exponent2 = _floatmidpoint(Float16, lowerbits)
    theoretical = UInt128(midpoint)
    exponent10 = Int(parts.exp10)
    power = abs(exponent10)
    power <= 55 || return (0, false)
    factor = @inbounds _POW5U128[power + 1]
    if exponent10 >= 0
        real <= typemax(UInt128) ÷ factor || return (0, false)
        real *= factor
    else
        theoretical <= typemax(UInt128) ÷ factor || return (0, false)
        theoretical *= factor
    end
    shift = exponent10 - exponent2
    if shift >= 0
        shift < 128 && real <= typemax(UInt128) >> shift || return (0, false)
        real <<= shift
    else
        shift = -shift
        shift < 128 && theoretical <= typemax(UInt128) >> shift || return (0, false)
        theoretical <<= shift
    end
    return (real == theoretical ? 0 : real < theoretical ? -1 : 1, true)
end

@inline function _decimalisexactfloat64(parts::DecParts)
    exponent = Int(parts.exp10)
    power = abs(exponent)
    power <= 27 || return false
    factor = @inbounds _POW5U64[power + 1]
    if exponent < 0
        return parts.mant % factor == 0
    end
    return parts.mant <= (UInt64(1) << 53) ÷ factor
end

@noinline function _exactfloatfallback(::Type{T}, buf::AbstractVector{UInt8}, i::Int,
                                       j::Int, neg::Bool,
                                       decimal::UInt8) where {T <: Union{Float64, Float32}}
    parts, rc = _decompose(buf, i, j, decimal)
    rc == RC_OK || return _sdc(T, buf, i, j, neg, decimal)
    return _exactfloatfromparts(T, parts, buf, i, j, neg, decimal)
end

@noinline function _exactfloatfromparts(::Type{T}, parts::DecParts,
                                        buf::AbstractVector{UInt8}, i::Int,
                                        j::Int, neg::Bool,
                                        decimal::UInt8, groupmark=nothing) where
                                        {T <: Union{Float64, Float32}}
    if parts.truncated || parts.ndig > 19
        lower = _eisel_lemire(T, parts.mant, Int(parts.exp10))
        upper = _eisel_lemire(T, parts.mant + 1, Int(parts.exp10))
        if 0 <= lower < _infbits(T) && upper == lower + 1 <= _infbits(T)
            cmp, resolved = _u256midpointcmp(T, buf, i, j, decimal,
                                             UInt64(lower), groupmark)
            if resolved
                bits = cmp < 0 || (cmp == 0 && iseven(lower)) ? UInt64(lower) : UInt64(upper)
                return _sign(T, bits, neg)
            end
        end
    end
    return _sdc(T, buf, i, j, neg, decimal, groupmark)
end

const SDC_MAXDIG = 800   # 768-digit worst case + slack

# Fixed-size decimal 0.d₁d₂…dₙ × 10^dp with sticky truncation. All operations
# are exact except the documented truncate-at-800 (which sets `sticky` and is
# beyond the decision bound for Float64).
mutable struct HPD
    d::Vector{UInt8}
    n::Int
    dp::Int
    sticky::Bool
end

function _hpd(buf::AbstractVector{UInt8}, i::Int, j::Int, decimal::UInt8,
              groupmark=nothing)
    d = Vector{UInt8}(undef, SDC_MAXDIG)
    n = 0
    dp = 0
    sticky = false
    sawpoint = false
    sawdig = false
    k = i
    @inbounds if k <= j && (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
        k += 1
    end
    @inbounds while k <= j
        b = buf[k]
        dig = b - UInt8('0')
        if dig <= 0x09
            sawdig = true
            if n == 0 && dig == 0
                sawpoint && (dp -= 1)
            else
                if n < SDC_MAXDIG
                    n += 1
                    d[n] = dig
                else
                    sticky |= dig != 0
                end
                sawpoint || (dp += 1)
            end
        elseif b == decimal
            sawpoint = true
        elseif groupmark !== nothing && b == groupmark
            # Shape was validated by the owning decomposer.
        else # exponent (structure already validated by _decompose)
            k += 1
            eneg = false
            @inbounds if k <= j && (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
                eneg = buf[k] == UInt8('-')
                k += 1
            end
            e = zero(UInt64)
            @inbounds while k <= j
                e = _decimalexponentdigit(e, buf[k] - UInt8('0'))
                k += 1
            end
            dp = _boundedint(Int128(dp) + _signeddecimalexponent(e, eneg))
            break
        end
        k += 1
    end
    while n > 0 && d[n] == 0
        n -= 1
    end
    return HPD(d, n, dp, sticky)
end

# value ≥ 1?
_hpdge1(h::HPD) = h.n > 0 && h.dp > 0
# double in place: value *= 2  (value < 1 before call keeps digits bounded)
function _double!(h::HPD)
    carry = 0
    @inbounds for k in h.n:-1:1
        v = Int(h.d[k]) * 2 + carry
        h.d[k] = UInt8(v % 10)
        carry = v ÷ 10
    end
    if carry != 0
        # shift right one digit to prepend the carry
        n = min(h.n + 1, SDC_MAXDIG)
        h.sticky |= h.n + 1 > SDC_MAXDIG && h.d[SDC_MAXDIG] != 0
        @inbounds for k in n:-1:2
            h.d[k] = h.d[k - 1]
        end
        h.d[1] = UInt8(carry)
        h.n = n
        h.dp += 1
    end
    while h.n > 0 && h.d[h.n] == 0
        h.n -= 1
    end
    return h
end
# halve in place: value /= 2 == value*5, dp -= 1
function _halve!(h::HPD)
    carry = 0
    # multiply by 5 processing from the right
    @inbounds for k in h.n:-1:1
        v = Int(h.d[k]) * 5 + carry
        h.d[k] = UInt8(v % 10)
        carry = v ÷ 10
    end
    while carry != 0
        n = min(h.n + 1, SDC_MAXDIG)
        h.sticky |= h.n + 1 > SDC_MAXDIG && h.d[SDC_MAXDIG] != 0
        @inbounds for k in n:-1:2
            h.d[k] = h.d[k - 1]
        end
        h.d[1] = UInt8(carry % 10)
        carry ÷= 10
        h.n = n
        h.dp += 1
    end
    h.dp -= 1
    while h.n > 0 && h.d[h.n] == 0
        h.n -= 1
    end
    return h
end
# subtract 1 (requires 1 ≤ value < 2, i.e. dp == 1 and d1 ≥ 1... value<2 ⇒ d1 ∈ 1)
function _sub1!(h::HPD)
    # value = d1.d2d3… with dp == 1; subtracting 1 zeroes the integer digit
    @inbounds h.d[1] -= 1
    while h.n > 0 && h.d[h.n] == 0
        h.n -= 1
    end
    if h.n > 0 && h.d[1] == 0
        # renormalize: drop leading zeros
        lead = 0
        @inbounds while lead < h.n && h.d[lead + 1] == 0
            lead += 1
        end
        @inbounds for k in 1:(h.n - lead)
            h.d[k] = h.d[k + lead]
        end
        h.n -= lead
        h.dp -= lead
    elseif h.n == 0
        h.dp = 0
    end
    return h
end

# @noinline is load-bearing: it keeps the large, cold exact-conversion tier out
# of the common parser path.
_sdc(buf::AbstractVector{UInt8}, i::Int, j::Int, neg::Bool, decimal::UInt8,
     groupmark=nothing) = _sdc(Float64, buf, i, j, neg, decimal, groupmark)

@noinline function _sdc(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int, neg::Bool,
                        decimal::UInt8, groupmark=nothing) where
                        {T <: Union{Float64, Float32, Float16}}
    MB = _mantbits(T)
    h = _hpd(buf, i, j, decimal, groupmark)
    h.n == 0 && return _sign(T, zero(UInt64), neg)
    # scale into [1, 2): binary exponent accumulates in e2
    e2 = 0
    while !_hpdge1(h)                       # value < 1: double
        _double!(h)
        e2 -= 1
        e2 < -1200 && return _sign(T, zero(UInt64), neg)     # certain underflow to 0
    end
    while h.dp > 1 || (h.dp == 1 && h.d[1] >= 2)   # value ≥ 2: halve
        _halve!(h)
        e2 += 1
        e2 > 1100 && return _sign(T, _infbits(T), neg)       # certain overflow
    end
    # now 1 ≤ value < 2, msb bit is the leading 1
    e2biased = e2 + _bias(T)
    nbits = MB
    subnormal = e2biased <= 0
    if subnormal
        # subnormals have NO implicit bit: the leading 1 is stored, followed by
        # nbits generated bits (nbits == -1 ⇒ even the leading 1 is below bit 0
        # and becomes the rounding bit for the min-subnormal decision)
        nbits = MB + e2biased - 1
        nbits < -1 && return _sign(T, zero(UInt64), neg)
        e2biased = 0
    end
    _sub1!(h)                                # consume the leading 1
    local mant::UInt64
    local roundbit::Bool
    if subnormal && nbits == -1
        mant = zero(UInt64)
        roundbit = true                      # the leading 1 itself
    else
        mant = subnormal ? one(UInt64) : zero(UInt64)
        for _ in 1:nbits
            _double!(h)
            bit = _hpdge1(h)
            mant = (mant << 1) | UInt64(bit)
            bit && _sub1!(h)
        end
        _double!(h)
        roundbit = _hpdge1(h)
        roundbit && _sub1!(h)
    end
    stickyrest = h.n > 0 || h.sticky
    if roundbit && (stickyrest || (mant & 1) == 1)
        mant += 1
        if e2biased == 0 && mant == (UInt64(1) << MB)
            e2biased = 1                     # subnormal rounded up to normal
            mant = 0
        elseif mant == (UInt64(1) << MB)
            mant = 0
            e2biased += 1
        end
    end
    if e2biased == 0 && nbits < MB
        # subnormal: mantissa currently has `nbits+?` bits — it is already in
        # low-bit position because we generated exactly nbits of them
        return _sign(T, mant, neg)
    end
    e2biased >= _maxexp(T) && return _sign(T, _infbits(T), neg)
    return _sign(T, (UInt64(e2biased) << MB) | (mant & ((UInt64(1) << MB) - 1)), neg)
end

@inline _sign(bits::UInt64, neg::Bool) = _sign(Float64, bits, neg)
@inline _sign(::Type{Float64}, bits::UInt64, neg::Bool) =
    reinterpret(Float64, bits | (UInt64(neg) << 63))
@inline _sign(::Type{Float32}, bits::UInt64, neg::Bool) =
    reinterpret(Float32, UInt32(bits) | (UInt32(neg) << 31))
@inline _sign(::Type{Float16}, bits::UInt64, neg::Bool) =
    reinterpret(Float16, UInt16(bits) | (UInt16(neg) << 15))

# --- special spellings ---------------------------------------------------------

@inline _lower(b::UInt8) = b | 0x20

@inline function _hexprefixdigit(b::UInt8)
    d = b - UInt8('0')
    return d <= 0x09 || _lower(b) - UInt8('a') <= 0x05
end

# A hexadecimal introducer is committed only after the mantissa has one digit.
# Otherwise decimal zero is the longest well-formed prefix (`0x,` -> `0`).
@inline function _startshexprefix(buf::AbstractVector{UInt8}, k::Int, j::Int)
    @inbounds begin
        k + 2 <= j && buf[k] == UInt8('0') &&
            _lower(buf[k + 1]) == UInt8('x') || return false
        first = k + 2
        _hexprefixdigit(buf[first]) && return true
        return buf[first] == UInt8('.') && first < j &&
               _hexprefixdigit(buf[first + 1])
    end
end

const _INFINITY_BYTES = (UInt8('i'), UInt8('n'), UInt8('f'), UInt8('i'),
                         UInt8('n'), UInt8('i'), UInt8('t'), UInt8('y'))
const _INF_BYTES = (UInt8('i'), UInt8('n'), UInt8('f'))
const _NAN_BYTES = (UInt8('n'), UInt8('a'), UInt8('n'))

@inline function _matchascii(buf::AbstractVector{UInt8}, i::Int, j::Int,
                             bytes::NTuple{N, UInt8}) where {N}
    (i <= j && N <= j - i + 1) || return false
    @inbounds for k in 1:N
        _lower(buf[i + k - 1]) == bytes[k] || return false
    end
    return true
end

# Longest special spelling at `i`. The value and token boundary are found
# together, so prefix parsing does not first scan and then call `_matchspecial`.
function _matchspecialprefix(buf::AbstractVector{UInt8}, i::Int, j::Int)
    orig = i
    neg = false
    @inbounds if i <= j
        b = buf[i]
        neg = b == UInt8('-')
        (neg | (b == UInt8('+'))) && (i += 1)
    end
    _matchascii(buf, i, j, _INFINITY_BYTES) &&
        return (neg ? -Inf : Inf, i + 8, true)
    _matchascii(buf, i, j, _INF_BYTES) && return (neg ? -Inf : Inf, i + 3, true)
    _matchascii(buf, i, j, _NAN_BYTES) && return (neg ? -NaN : NaN, i + 3, true)
    return (0.0, orig, false)
end


function _matchspecial(buf::AbstractVector{UInt8}, i::Int, j::Int)
    value, nextpos, matched = _matchspecialprefix(buf, i, j)
    matched && nextpos > j && return (value, true)
    return (0.0, false)
end

# byte-equality marks (0x80 at each matching byte) — SWAR zero-byte test
@inline function _eqmask8(w::UInt64, b::UInt8)
    x = w ⊻ (0x0101010101010101 * b)
    return (x - 0x0101010101010101) & ~x & 0x8080808080808080
end

# Validate-and-gather the low `len` bytes of `w` as digits: left-align so high
# garbage falls off, back-fill ASCII zeros, one _alldigits8 + one _digits8.
@inline function _rundigits(w::UInt64, len::Int)
    s = (8 - len) << 3
    w = (w << s) | (0x3030303030303030 >>> (64 - s))
    return (_digits8(w), _alldigits8(w))
end

const _P10U = (UInt64(1), UInt64(10), UInt64(100), UInt64(1000), UInt64(10_000),
               UInt64(100_000), UInt64(1_000_000), UInt64(10_000_000), UInt64(100_000_000))

struct _ShortDecimalResult
    parts::DecParts
    nextpos::Int
    fraction::Int32
    rc::UInt8
    flags::UInt8
end

const _SHORT_FIT = UInt8(0x01)
const _SHORT_CARRY = UInt8(0x02)
const _SHORT_POINT = UInt8(0x04)

@inline _shortfit(result::_ShortDecimalResult) =
    !iszero(result.flags & _SHORT_FIT)
@inline _shortcarry(result::_ShortDecimalResult) =
    !iszero(result.flags & _SHORT_CARRY)
@inline _shortpoint(result::_ShortDecimalResult) =
    !iszero(result.flags & _SHORT_POINT)

@inline function _shortresult(parts::DecParts, nextpos::Int, rc::UInt8,
                              fit::Bool)
    flags = fit ? _SHORT_FIT : UInt8(0)
    return _ShortDecimalResult(parts, nextpos, Int32(0), rc, flags)
end

@inline function _shortcarryresult(mant::UInt64, fraction::Int,
                                   sawpoint::Bool, neg::Bool, nextpos::Int)
    flags = _SHORT_CARRY | (sawpoint ? _SHORT_POINT : UInt8(0))
    parts = DecParts(mant, 0, 0, false, neg, 0)
    return _ShortDecimalResult(parts, nextpos, Int32(fraction),
                               RC_INVALID, flags)
end

# Prefix parsing calls this only after the scalar scanner returns the first
# unconsumed coefficient byte with its nineteen-digit state. The scanner stays
# unchanged for successful short values; only its overflow result carries the
# state needed to avoid restarting the grammar engine at the original byte.
@noinline function _continuelongdecimalparts(buf::AbstractVector{UInt8},
                                             orig::Int, k::Int, j::Int,
                                             decimal::UInt8,
                                             carry::_ShortDecimalResult)
    mant = carry.parts.mant
    fraction = Int(carry.fraction)
    sawpoint = _shortpoint(carry)
    neg = carry.parts.neg
    ndig = mant >= 1_000_000_000_000_000_000 ? 19 :
           mant == 0 ? 0 : ndigits(mant)
    dropped = 0
    truncated = false

    @inbounds while k <= j
        # Once the nineteen significant coefficient digits are full, gather
        # complete eight-byte runs. A partial run stays scalar so the first
        # delimiter remains unconsumed.
        if ndig >= 19 && j - k >= 7
            word = _load8(buf, k)
            if _alldigits8(word)
                truncated |= word != 0x3030303030303030
                ndig += 8
                dropped += 8
                sawpoint && (fraction += 8)
                k += 8
                continue
            end
        end

        byte = buf[k]
        digit = byte - UInt8('0')
        if digit <= 0x09
            sawpoint && (fraction += 1)
            if ndig == 0
                if digit != 0
                    mant = UInt64(digit)
                    ndig = 1
                end
            elseif ndig < 19
                mant = 10mant + digit
                ndig += 1
            else
                truncated |= digit != 0
                ndig += 1
                dropped += 1
            end
            k += 1
        elseif byte == decimal && !sawpoint
            sawpoint = true
            k += 1
        else
            break
        end
    end

    commit = k
    exponent = Int128(0)
    @inbounds if k <= j && _lower(buf[k]) == UInt8('e')
        marker = k
        k += 1
        eneg = false
        if k <= j
            byte = buf[k]
            eneg = byte == UInt8('-')
            (eneg || byte == UInt8('+')) && (k += 1)
        end
        estart = k
        e = zero(UInt64)
        while k <= j
            digit = buf[k] - UInt8('0')
            digit <= 0x09 || break
            e = _decimalexponentdigit(e, digit)
            k += 1
        end
        if k > estart
            exponent = _signeddecimalexponent(e, eneg)
            commit = k
        else
            commit = marker
        end
    end

    q = exponent - Int128(fraction) + Int128(dropped)
    parts = _decparts(mant, q, ndig, truncated, neg,
                      _DECPARTS_NO_DIGIT, orig)
    return (parts, commit, RC_OK)
end

# One scalar grammar engine owns every short decimal path. It returns the
# first unconsumed byte, so prefix callers can use it directly and exact-span
# callers need only require `nextpos > j`. Its concrete result carries the
# live scalar state only on the twentieth coefficient digit; callers that need
# a bounded short decision can decline that result, while prefix parsing can
# resume at `nextpos` without reading the first nineteen digits again.
@inline function _shortdecimalparts(buf::AbstractVector{UInt8}, i::Int, j::Int,
                                    decimal::UInt8, groupmark=nothing)
    orig = i
    neg = false
    @inbounds begin
        byte = buf[i]
        neg = byte == UInt8('-')
        (neg || byte == UInt8('+')) && (i += 1)
    end
    i <= j || return _shortresult(DecParts(0, 0, 0, false, neg, 0),
                                  orig, RC_INVALID, true)

    intstart = i
    mant = zero(UInt64)
    ndig = 0
    fraction = 0
    exponent = 0
    sawdigit = false
    sawpoint = false
    k = i
    @inbounds while k <= j
        byte = buf[k]
        digit = byte - UInt8('0')
        if digit <= 0x09
            ndig += 1
            if ndig > 19
                if groupmark === nothing
                    return _shortcarryresult(mant, fraction, sawpoint,
                                             neg, k)
                end
                return _shortresult(DecParts(0, 0, 0, false, neg, 0),
                                    orig, RC_INVALID, false)
            end
            mant = 10mant + digit
            sawdigit = true
            sawpoint && (fraction += 1)
            k += 1
        elseif groupmark !== nothing && !sawpoint && byte == groupmark &&
               k > intstart && k < j &&
               (buf[k - 1] - UInt8('0')) <= 0x09 &&
               (buf[k + 1] - UInt8('0')) <= 0x09
            k += 1
        elseif byte == decimal && !sawpoint
            sawpoint = true
            k += 1
        elseif _lower(byte) == UInt8('e') && sawdigit
            marker = k
            k += 1
            eneg = false
            if k <= j
                byte = buf[k]
                eneg = byte == UInt8('-')
                (eneg || byte == UInt8('+')) && (k += 1)
            end
            estart = k
            e = 0
            while k <= j
                digit = buf[k] - UInt8('0')
                digit <= 0x09 || break
                e < 100_000 && (e = 10e + Int(digit))
                k += 1
            end
            if k > estart
                exponent = eneg ? -e : e
            else
                k = marker
            end
            break
        else
            break
        end
    end
    sawdigit || return _shortresult(DecParts(0, 0, 0, false, neg, 0),
                                    orig, RC_INVALID, true)
    q = exponent - fraction
    typemin(Int32) <= q <= typemax(Int32) ||
        return _shortresult(DecParts(0, 0, 0, false, neg, 0),
                            orig, RC_INVALID, false)
    return _shortresult(DecParts(mant, Int32(q), Int32(ndig), false, neg, 0),
                        k, RC_OK, true)
end

@inline function _shortclinger(::Type{T}, parts::DecParts) where
                               {T <: Union{Float64, Float32}}
    q = Int(parts.exp10)
    mant = parts.mant
    clinger = T === Float64 ?
        (-22 <= q <= 22 && mant <= UInt64(1) << 53) :
        (-10 <= q <= 10 && mant <= UInt64(1) << 24)
    clinger || return (zero(T), false)
    value = T(mant)
    if q != 0
        value = T === Float64 ?
            (q > 0 ? value * @inbounds(_POW10[q + 1]) :
                     value / @inbounds(_POW10[-q + 1])) :
            (q > 0 ? value * @inbounds(_POW10F32[q + 1]) :
                     value / @inbounds(_POW10F32[-q + 1]))
    end
    return (parts.neg ? -value : value, true)
end

# A short scalar loop beats the word-mask setup for common whole values such as
# "1", "1.5", "-0.25", and short exponents. Clinger-range values convert
# directly; other accepted values use the shared exact conversion path.
@inline function _floatsmall(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                             decimal::UInt8) where {T <: Union{Float64, Float32}}
    i <= j || return (zero(T), RC_INVALID, true)
    @inbounds first = buf[i]
    start = (first == UInt8('-') || first == UInt8('+')) ? i + 1 : i
    start <= j || return (zero(T), RC_INVALID, true)
    j - start + 1 <= 15 || return (zero(T), RC_INVALID, false)
    scan = _shortdecimalparts(buf, i, j, decimal)
    _shortfit(scan) || return (zero(T), RC_INVALID, false)
    parts, nextpos, rc = scan.parts, scan.nextpos, scan.rc
    rc == RC_OK || return (zero(T), rc, true)
    nextpos > j || return (zero(T), RC_INVALID, true)
    value, handled = _shortclinger(T, parts)
    handled && return (value, RC_OK, true)
    value, rc, handled = _convertparts(T, parts)
    handled && return (value, rc, true)
    return (zero(T), RC_INVALID, false)
end

@inline function _floatgroupedsmall(::Type{T}, buf::AbstractVector{UInt8}, i::Int,
                                    j::Int, decimal::UInt8,
                                    groupmark::UInt8) where {T <: Union{Float64, Float32}}
    i <= j || return (zero(T), RC_INVALID, true)
    @inbounds first = buf[i]
    start = (first == UInt8('-') || first == UInt8('+')) ? i + 1 : i
    start <= j || return (zero(T), RC_INVALID, true)
    j - start + 1 <= 15 || return (zero(T), RC_INVALID, false)
    scan = _shortdecimalparts(buf, i, j, decimal, groupmark)
    _shortfit(scan) || return (zero(T), RC_INVALID, false)
    parts, nextpos, rc = scan.parts, scan.nextpos, scan.rc
    rc == RC_OK || return (zero(T), rc, true)
    nextpos > j || return (zero(T), RC_INVALID, true)
    value, handled = _shortclinger(T, parts)
    handled && return (value, RC_OK, true)
    return (zero(T), RC_INVALID, false)
end

# The bounded short path avoids word-mask setup and can hand scientific and
# wide-mantissa cases directly to the shared conversion core. Specials are
# recognized before numeric syntax so they do not scan twice. Longer or
# unresolved spellings fall through to the general parser.
@inline _float_fast(buf::AbstractVector{UInt8}, i::Int, j::Int, decimal::UInt8) =
    _float_fast(Float64, buf, i, j, decimal)

@inline function _float_fast(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                             decimal::UInt8) where {T <: Union{Float64, Float32}}
    # neither a special spelling (at most 9 bytes) nor the short path (at most
    # 16 with a sign) can match a longer span; skip both probes outright
    j - i + 1 <= 16 || return (zero(T), RC_INVALID, false)
    orig_i = i
    @inbounds if i <= j
        b = buf[i]
        (b == UInt8('-') || b == UInt8('+')) && (i += 1)
    end
    @inbounds if i <= j
        first = _lower(buf[i])
        if first == UInt8('n') || first == UInt8('i')
            special, matched = _matchspecial(buf, orig_i, j)
            matched && return (T(special), RC_OK, true)
        end
    end
    return _floatsmall(T, buf, orig_i, j, decimal)
end

@inline function _convertparts(::Type{T}, parts::DecParts) where {T <: Union{Float64, Float32}}
    mant = parts.mant
    q = Int(parts.exp10)
    mant == 0 && return (parts.neg ? -zero(T) : zero(T), RC_OK, true)
    untrunc = !parts.truncated && parts.ndig <= 19
    # tier 1 (Clinger): mant and 10^|q| both exactly representable → one rounding
    if T === Float64
        if untrunc && -22 <= q <= 22 && mant <= 9007199254740992   # 2^53
            f = Float64(mant)
            f = q >= 0 ? f * @inbounds(_POW10[q + 1]) : f / @inbounds(_POW10[-q + 1])
            return (parts.neg ? -f : f, RC_OK, true)
        end
    else
        if untrunc && -10 <= q <= 10 && mant <= 16777216             # 2^24
            f = Float32(mant)
            f = q >= 0 ? f * @inbounds(_POW10F32[q + 1]) : f / @inbounds(_POW10F32[-q + 1])
            return (parts.neg ? -f : f, RC_OK, true)
        end
    end
    bits = _eisel_lemire(T, mant, q)
    if !untrunc && bits >= 0
        # truncated mantissa: decided only if mant and mant+1 round identically
        # (the reference fast_float rule); otherwise the digits must speak (tier 3)
        bits2 = _eisel_lemire(T, mant + 1, q)
        bits2 == bits || return (parts.neg ? -one(T) : one(T), RC_OK, false)
    end
    if bits >= 0
        # mant is nonzero here, so a zero pattern is underflow and the Inf
        # pattern is overflow. The value remains available for callers that
        # accept the rounded ±0 / ±Inf result.
        u = UInt64(bits)
        rc = u == 0 ? RC_UNDERFLOW : u == _infbits(T) ? RC_OVERFLOW : RC_OK
        return (_sign(T, u, parts.neg), rc, true)
    end
    if bits == Int64(-2)
        return q < 0 ? (parts.neg ? -zero(T) : zero(T), RC_UNDERFLOW, true) :
                       (parts.neg ? -T(Inf) : T(Inf), RC_OVERFLOW, true)
    elseif bits == Int64(-3)
        return (parts.neg ? -T(Inf) : T(Inf), RC_OVERFLOW, true)
    end
    return (parts.neg ? -one(T) : one(T), RC_OK, false)   # tier 3 required; sign in value
end

@inline function _parsefloat_core(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                                  decimal::UInt8) where {T <: Union{Float64, Float32}}
    v, rc, handled = _float_fast(T, buf, i, j, decimal) # dominant [sign]digits[.digits] shape
    handled && return (v, rc, true)
    parts, rc = _decompose(buf, i, j, decimal)
    rc == RC_OK || return (zero(T), rc, true)
    return _convertparts(T, parts)
end

@inline function _parsegroupedfloat_core(::Type{T}, buf::AbstractVector{UInt8}, i::Int,
                                         j::Int, decimal::UInt8,
                                         groupmark::UInt8) where {T <: Union{Float64, Float32}}
    parts, rc = _decomposegrouped(buf, i, j, decimal, groupmark)
    rc == RC_OK || return (zero(T), rc, true)
    return _convertparts(T, parts)
end

"""
    parsefloat(T, buf, i, j, decimal=UInt8('.')) -> (T, rc)
        T ∈ Float16, Float32, Float64
    parsefloat64(buf, i, j, decimal=UInt8('.')) -> (Float64, rc)

Parse `buf[i:j]` as `T` with correct (round-half-even) rounding for every
input — no C, no BigFloat: Clinger's exact small case, then Eisel–Lemire,
then an exact fixed-limb midpoint comparison or simple decimal conversion for
the rare ambiguous and subnormal cases.
`Float32` is parsed natively (never via Float64, which double-rounds).
`Float16` uses bounded wider fast stages, then compares the original decimal
exactly whenever a wider result is a Float16 rounding midpoint.
Accepts sign, digits, one `decimal` byte, optional e/E exponent, and the
case-insensitive spellings Inf/Infinity/NaN.

`rc` is `RC_OK`, `RC_INVALID`, or one of the two range codes: `RC_OVERFLOW`
(the value rounded to ±Inf) and `RC_UNDERFLOW` (a nonzero spelling rounded to
±0). The value returned alongside a range code is that ±Inf / ±0, so a caller
that wants rounded range values can treat both as success. Checked
whole-value parsing rejects both range codes on every platform.

Structured as an @inline hot core plus a thin wrapper owning the cold tier-3
tail. The tail stays @noinline so exact fallback code never bloats the hot path.
"""
@inline function parsefloat(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                            decimal::UInt8=UInt8('.')) where {T <: Union{Float64, Float32}}
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        return _parsefloatexact(T, window, first, final, decimal)
    end
    return _parsefloatexact(T, buf, i, j, decimal)
end

@inline function _parsefloatexact(::Type{T}, buf::AbstractVector{UInt8}, i::Int,
                                  j::Int, decimal::UInt8) where
                                  {T <: Union{Float64, Float32}}
    v, rc, done = _parsefloat_core(T, buf, i, j, decimal)
    done && return (v, rc)
    r = _exactfloatfallback(T, buf, i, j, v < 0, decimal)
    rc = r == 0 ? RC_UNDERFLOW : isinf(r) ? RC_OVERFLOW : RC_OK   # mant ≠ 0 on this path
    return (r, rc)
end

@noinline function _exactfloat16fallback(buf::AbstractVector{UInt8}, i::Int, j::Int,
                                         neg::Bool, decimal::UInt8,
                                         lowerbits::UInt64)
    parts, rc = _decompose(buf, i, j, decimal)
    rc == RC_OK || return _sdc(Float16, buf, i, j, neg, decimal)
    return _exactfloat16fromparts(parts, buf, i, j, neg, decimal, lowerbits)
end

@noinline function _exactfloat16fromparts(parts::DecParts,
                                          buf::AbstractVector{UInt8}, i::Int, j::Int,
                                          neg::Bool, decimal::UInt8,
                                          lowerbits::UInt64, groupmark=nothing)
    cmp, resolved = _u128midpointcmp(parts, lowerbits)
    if !resolved
        cmp, resolved = _u256midpointcmp(Float16, buf, i, j, decimal,
                                         lowerbits, groupmark)
    end
    if resolved
        bits = cmp < 0 || (cmp == 0 && iseven(lowerbits)) ? lowerbits : lowerbits + 1
        return _sign(Float16, bits, neg)
    end
    return _sdc(Float16, buf, i, j, neg, decimal, groupmark)
end

# Float64 and Float32 have enough precision to identify the only possible
# Float16 double-rounding hazard: an exact midpoint between adjacent Float16
# values. Re-read the original decimal only at that boundary.
@inline function _float16stage(value::T, rc) where {T <: Union{Float64, Float32}}
    if rc != RC_OK || !isfinite(value) || iszero(value)
        return (Float16(value), rc, false, zero(UInt64))
    end
    value16 = Float16(value)
    magnitude = abs(value)
    magnitude16 = abs(value16)
    widened16 = T(magnitude16)
    if widened16 == magnitude
        return (value16, RC_OK, false, zero(UInt64))
    end
    roundedbits = UInt64(reinterpret(UInt16, magnitude16))
    lowerbits = widened16 < magnitude ? roundedbits : roundedbits - 1
    midpoint, exponent = _floatmidpoint(Float16, lowerbits)
    exact = magnitude == ldexp(T(midpoint), exponent)
    rc16 = iszero(value16) ? RC_UNDERFLOW : isinf(value16) ? RC_OVERFLOW : RC_OK
    return (value16, rc16, exact, lowerbits)
end

# Finish a bounded decimal decomposition through Float64. A decimal with at
# most 53 coefficient bits and a small power of ten is exact enough to detect
# the sole wider-to-Float16 hazard. The coefficient then resolves that midpoint
# directly, without another grammar pass.
@inline function _smallfloat16fromparts(parts::DecParts)
    mant = parts.mant
    q = Int(parts.exp10)
    (!parts.truncated && mant <= UInt64(1) << 53 && -22 <= q <= 22) ||
        return (zero(Float16), RC_INVALID, false)

    value64 = Float64(mant)
    if q != 0
        value64 = q > 0 ? value64 * @inbounds(_POW10[q + 1]) :
                          value64 / @inbounds(_POW10[-q + 1])
    end
    parts.neg && (value64 = -value64)
    value16, rc, exact, lowerbits = _float16stage(value64, RC_OK)
    exact || return (value16, rc, true)

    if _decimalisexactfloat64(parts)
        bits = iseven(lowerbits) ? lowerbits : lowerbits + 1
    else
        cmp, resolved = _u128midpointcmp(parts, lowerbits)
        resolved || return (zero(Float16), RC_INVALID, false)
        bits = cmp < 0 || (cmp == 0 && iseven(lowerbits)) ? lowerbits : lowerbits + 1
    end
    value16 = _sign(Float16, bits, parts.neg)
    rc = iszero(value16) ? RC_UNDERFLOW : isinf(value16) ? RC_OVERFLOW : RC_OK
    return (value16, rc, true)
end

# Float16 whole-value parsing owns a compact exact scanner. Prefix parsing
# needs token-boundary state; exact parsing does not. Keeping those paths
# separate avoids carrying prefix bookkeeping through the Float16 midpoint
# proof while both paths still finish from the same DecParts state.
@inline function _float16smallfused(buf::AbstractVector{UInt8}, i::Int, j::Int,
                                    decimal::UInt8)
    1 <= j - i + 1 <= 24 || return (zero(Float16), RC_INVALID, false)
    orig = i
    neg = false
    @inbounds begin
        byte = buf[i]
        neg = byte == UInt8('-')
        (neg || byte == UInt8('+')) && (i += 1)
    end
    i <= j || return (zero(Float16), RC_INVALID, true)
    @inbounds begin
        first = _lower(buf[i])
        if first == UInt8('i') || first == UInt8('n')
            special, matched = _matchspecial(buf, orig, j)
            matched && return (Float16(special), RC_OK, true)
            buf[i] == decimal || return (zero(Float16), RC_INVALID, true)
        end
    end
    mant = zero(UInt64)
    ndig = 0
    fraction = 0
    exponent = 0
    sawdigit = false
    sawpoint = false
    k = i
    @inbounds while k <= j
        byte = buf[k]
        digit = byte - UInt8('0')
        if digit <= 0x09
            ndig += 1
            ndig <= 19 || return (zero(Float16), RC_INVALID, false)
            mant = 10mant + digit
            sawdigit = true
            sawpoint && (fraction += 1)
        elseif byte == decimal && !sawpoint
            sawpoint = true
        elseif _lower(byte) == UInt8('e') && sawdigit
            k += 1
            eneg = false
            if k <= j
                byte = buf[k]
                eneg = byte == UInt8('-')
                (eneg || byte == UInt8('+')) && (k += 1)
            end
            k <= j || return (zero(Float16), RC_INVALID, true)
            e = 0
            while k <= j
                digit = buf[k] - UInt8('0')
                digit <= 0x09 || return (zero(Float16), RC_INVALID, true)
                e < 100_000 && (e = 10e + Int(digit))
                k += 1
            end
            exponent = eneg ? -e : e
            break
        else
            return (zero(Float16), RC_INVALID, true)
        end
        k += 1
    end
    sawdigit || return (zero(Float16), RC_INVALID, true)
    q = exponent - fraction
    typemin(Int32) <= q <= typemax(Int32) ||
        return (zero(Float16), RC_INVALID, false)
    parts = DecParts(mant, Int32(q), Int32(ndig), false, neg, 0)
    value16, rc, handled = _smallfloat16fromparts(parts)
    handled && return (value16, rc, true)
    value32, rc, done = _convertparts(Float32, parts)
    done || return (zero(Float16), RC_INVALID, false)
    value16, rc, exact, lowerbits = _float16stage(value32, rc)
    exact || return (value16, rc, true)
    cmp, resolved = _u128midpointcmp(parts, lowerbits)
    resolved || return (zero(Float16), RC_INVALID, false)
    bits = cmp < 0 || (cmp == 0 && iseven(lowerbits)) ? lowerbits : lowerbits + 1
    value16 = _sign(Float16, bits, parts.neg)
    rc = iszero(value16) ? RC_UNDERFLOW : isinf(value16) ? RC_OVERFLOW : RC_OK
    return (value16, rc, true)
end

# Explicit spans and arbitrary byte-vector sources keep the shared short
# decimal state machine. Whole String/CodeUnits callers select the fused
# scanner through a compile-time marker in api.jl. No parser pays a run-time
# source-shape or span-boundary branch.
@inline function _float16small(buf::AbstractVector{UInt8}, i::Int, j::Int,
                               decimal::UInt8)
    1 <= j - i + 1 <= 24 || return (zero(Float16), RC_INVALID, false)
    k = i
    @inbounds begin
        first = buf[k]
        (first == UInt8('-') || first == UInt8('+')) && (k += 1)
        if k <= j
            lower = _lower(buf[k])
            if lower == UInt8('i') || lower == UInt8('n')
                special, matched = _matchspecial(buf, i, j)
                matched && return (Float16(special), RC_OK, true)
            end
        end
    end

    scan = _shortdecimalparts(buf, i, j, decimal)
    _shortfit(scan) || return (zero(Float16), RC_INVALID, false)
    parts, nextpos, rc = scan.parts, scan.nextpos, scan.rc
    rc == RC_OK && nextpos > j || return (zero(Float16), RC_INVALID, true)

    value16, rc, handled = _smallfloat16fromparts(parts)
    handled && return (value16, rc, true)
    value32, rc, done = _convertparts(Float32, parts)
    done || return (zero(Float16), RC_INVALID, false)
    value16, rc, exact, lowerbits = _float16stage(value32, rc)
    exact || return (value16, rc, true)
    cmp, resolved = _u128midpointcmp(parts, lowerbits)
    resolved || return (zero(Float16), RC_INVALID, false)
    bits = cmp < 0 || (cmp == 0 && iseven(lowerbits)) ? lowerbits : lowerbits + 1
    value16 = _sign(Float16, bits, parts.neg)
    rc = iszero(value16) ? RC_UNDERFLOW : isinf(value16) ? RC_OVERFLOW : RC_OK
    return (value16, rc, true)
end

# Ungrouped float prefixes start in the scalar decimal scanner. Short values
# finish from its result. A twentieth coefficient digit resumes in the wide
# gatherer from the first unconsumed byte, so long values do not replay the
# sign or their first nineteen coefficient digits.
@noinline function _tryshortfloatprefix(::Type{T},
                                        buf::AbstractVector{UInt8},
                                        i::Int, j::Int,
                                        decimal::UInt8) where
                                        {T <: Union{Float64, Float32, Float16}}
    scan = _shortdecimalparts(buf, i, j, decimal)
    if _shortcarry(scan)
        parts, nextpos, rc = _continuelongdecimalparts(
            buf, i, scan.nextpos, j, decimal, scan)
    else
        _shortfit(scan) || return (zero(T), i, RC_INVALID, false)
        parts, nextpos, rc = scan.parts, scan.nextpos, scan.rc
    end
    rc == RC_OK || return (zero(T), i, rc, true)
    if T === Float16
        value16, rc, handled = _smallfloat16fromparts(parts)
        handled && return (value16, nextpos, rc, true)
    end
    value, rc = _finishfloatprefix(T, parts, buf, i, nextpos - 1,
                                   decimal, nothing)
    return (value, nextpos, rc, true)
end

@inline function parsefloat(::Type{Float16}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                            decimal::UInt8=UInt8('.'))
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        return _parsefloat16exact(window, first, final, decimal)
    end
    return _parsefloat16exact(buf, i, j, decimal)
end

@inline function _parsefloat16exact(buf::AbstractVector{UInt8}, i::Int, j::Int,
                                    decimal::UInt8)
    value16, rc, handled = _float16small(buf, i, j, decimal)
    handled && return (value16, rc)
    value32, rc = _parsefloatexact(Float32, buf, i, j, decimal)
    value16, rc, exact, lowerbits = _float16stage(value32, rc)
    exact || return (value16, rc)
    value16 = _exactfloat16fallback(buf, i, j, signbit(value32), decimal, lowerbits)
    rc = iszero(value16) ? RC_UNDERFLOW : isinf(value16) ? RC_OVERFLOW : RC_OK
    return (value16, rc)
end

@inline function _parsefloat16whole(buf::AbstractVector{UInt8}, i::Int, j::Int,
                                    decimal::UInt8)
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        return _parsefloat16wholeexact(window, first, final, decimal)
    end
    return _parsefloat16wholeexact(buf, i, j, decimal)
end

@inline function _parsefloat16wholeexact(buf::AbstractVector{UInt8}, i::Int, j::Int,
                                         decimal::UInt8)
    value16, rc, handled = _float16smallfused(buf, i, j, decimal)
    handled && return (value16, rc)
    value32, rc = _parsefloatexact(Float32, buf, i, j, decimal)
    value16, rc, exact, lowerbits = _float16stage(value32, rc)
    exact || return (value16, rc)
    value16 = _exactfloat16fallback(buf, i, j, signbit(value32), decimal, lowerbits)
    rc = iszero(value16) ? RC_UNDERFLOW : isinf(value16) ? RC_OVERFLOW : RC_OK
    return (value16, rc)
end

@inline function _finishfloatprefix(::Type{T}, parts::DecParts,
                                    buf::AbstractVector{UInt8}, i::Int, stop::Int,
                                    decimal::UInt8, groupmark) where {T <: Union{Float64, Float32}}
    value, rc, done = _convertparts(T, parts)
    done && return (value, rc)
    value = _exactfloatfromparts(T, parts, buf, i, stop, parts.neg, decimal,
                                 groupmark)
    rc = iszero(value) ? RC_UNDERFLOW : isinf(value) ? RC_OVERFLOW : RC_OK
    return (value, rc)
end

@inline function _finishfloatprefix(::Type{Float16}, parts::DecParts,
                                    buf::AbstractVector{UInt8}, i::Int, stop::Int,
                                    decimal::UInt8, groupmark)
    value16, rc, handled = _smallfloat16fromparts(parts)
    handled && return (value16, rc)

    value32, rc, done = _convertparts(Float32, parts)
    if !done
        value32 = _exactfloatfromparts(Float32, parts, buf, i, stop,
                                       parts.neg, decimal, groupmark)
        rc = iszero(value32) ? RC_UNDERFLOW : isinf(value32) ? RC_OVERFLOW : RC_OK
    end
    value16, rc, exact, lowerbits = _float16stage(value32, rc)
    exact || return (value16, rc)
    value16 = _exactfloat16fromparts(parts, buf, i, stop, signbit(value32),
                                    decimal, lowerbits, groupmark)
    rc = iszero(value16) ? RC_UNDERFLOW : isinf(value16) ? RC_OVERFLOW : RC_OK
    return (value16, rc)
end

# Grouped numeric prefixes use the general one-pass decomposer. This is also
# the defensive fallback when an ungrouped spelling cannot produce either a
# complete short result or the explicit twentieth-digit continuation state.
@noinline function _parsefloatprefixgeneral(::Type{T},
                                            buf::AbstractVector{UInt8},
                                            i::Int, j::Int,
                                            decimal::UInt8, gm) where
                                            {T <: Union{Float64, Float32, Float16}}
    orig = i
    parts, nextpos, rc = _decomposeprefix(buf, i, j, decimal, gm)
    rc == RC_OK || return (zero(T), orig, rc)
    value, rc = _finishfloatprefix(T, parts, buf, i, nextpos - 1, decimal, gm)
    return (value, nextpos, rc)
end

# Single-pass tokenizer entry point for fixed-width floats. The obvious-invalid
# return stays small enough to inline into `parsenext`; valid input makes one
# call into the conversion body above. Keyword validation still happens first.
@inline function _parsefloatprefix(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                                   decimal::UInt8, groupmark) where
                                   {T <: Union{Float64, Float32, Float16}}
    gm = _floatgroupbyte(groupmark, decimal)
    k = i
    @inbounds if k <= j && (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
        k += 1
    end
    k <= j || return (zero(T), i, RC_INVALID)

    @inbounds first = buf[k]
    lower = _lower(first)
    if lower == UInt8('i') || lower == UInt8('n')
        special, nextpos, matched = _matchspecialprefix(buf, i, j)
        matched && return (T(special), nextpos, RC_OK)
    end
    (first - UInt8('0') <= 0x09 || first == decimal) ||
        return (zero(T), i, RC_INVALID)
    _startshexprefix(buf, k, j) && return _parsehexfloatprefix(T, buf, i, j)
    if gm === nothing
        value, nextpos, rc, handled =
            _tryshortfloatprefix(T, buf, i, j, decimal)
        handled && return (value, nextpos, rc)
    end
    return _parsefloatprefixgeneral(T, buf, i, j, decimal, gm)
end

parsefloat64(buf::AbstractVector{UInt8}, i::Int, j::Int, decimal::UInt8=UInt8('.')) =
    parsefloat(Float64, buf, i, j, decimal)

@inline function parsefloatpublic(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                                  decimal::UInt8) where {T <: Union{Float64, Float32, Float16}}
    return parsefloat(T, buf, i, j, decimal)
end

@inline parsefloatwholepublic(::Type{T}, buf::AbstractVector{UInt8}, i::Int,
                              j::Int, decimal::UInt8) where
                              {T <: Union{Float64, Float32, Float16}} =
    parsefloatpublic(T, buf, i, j, decimal)

@inline parsefloatwholepublic(::Type{Float16},
                              buf::Base.CodeUnits{UInt8, S}, i::Int,
                              j::Int, decimal::UInt8) where {S <: AbstractString} =
    _parsefloat16whole(buf, i, j, decimal)

@noinline function _exactgroupedfloat16fallback(buf::AbstractVector{UInt8}, i::Int,
                                                j::Int, decimal::UInt8,
                                                groupmark::UInt8, neg::Bool,
                                                lowerbits::UInt64)
    scratch = Vector{UInt8}(undef, max(j - i + 1, 8))
    n = degroup!(scratch, buf, i, j, groupmark, decimal)
    n >= 0 || return (zero(Float16), RC_INVALID)
    value = _exactfloat16fallback(scratch, 1, n, neg, decimal, lowerbits)
    rc = iszero(value) ? RC_UNDERFLOW : isinf(value) ? RC_OVERFLOW : RC_OK
    return (value, rc)
end

@inline function parsegroupedfloatpublic(::Type{Float16}, buf::AbstractVector{UInt8},
                                         i::Int, j::Int, decimal::UInt8,
                                         groupmark::UInt8)
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        return _parsegroupedfloat16exact(window, first, final, decimal, groupmark)
    end
    return _parsegroupedfloat16exact(buf, i, j, decimal, groupmark)
end

@inline function _parsegroupedfloat16exact(buf::AbstractVector{UInt8}, i::Int,
                                           j::Int, decimal::UInt8,
                                           groupmark::UInt8)
    value32, rc = parsegroupedfloatpublic(Float32, buf, i, j, decimal, groupmark)
    value16, rc, exact, lowerbits = _float16stage(value32, rc)
    exact || return (value16, rc)
    return _exactgroupedfloat16fallback(buf, i, j, decimal, groupmark,
                                        signbit(value32), lowerbits)
end

@inline function parsegroupedfloatpublic(::Type{T}, buf::AbstractVector{UInt8}, i::Int,
                                         j::Int, decimal::UInt8,
                                         groupmark::UInt8) where {T <: Union{Float64, Float32}}
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        return _parsegroupedfloatexact(T, window, first, final, decimal,
                                       groupmark)
    end
    return _parsegroupedfloatexact(T, buf, i, j, decimal, groupmark)
end

@inline function _parsegroupedfloatexact(::Type{T}, buf::AbstractVector{UInt8},
                                         i::Int, j::Int, decimal::UInt8,
                                         groupmark::UInt8) where
                                         {T <: Union{Float64, Float32}}
    value, rc, handled = _floatgroupedsmall(T, buf, i, j, decimal, groupmark)
    handled && return (value, rc)
    value, rc, done = _parsegroupedfloat_core(T, buf, i, j, decimal, groupmark)
    done && return (value, rc)
    # Exact grouped rounding-boundary values are rare. Keep this cold path
    # simple while the normal grouped route remains allocation-free.
    scratch = Vector{UInt8}(undef, max(j - i + 1, 8))
    n = degroup!(scratch, buf, i, j, groupmark, decimal)
    n >= 0 || return (zero(T), RC_INVALID)
    return parsefloatpublic(T, scratch, 1, n, decimal)
end

const _POW10F32 = Float32[10.0f0^k for k in 0:10]

# --- hexadecimal floats: [sign] 0x hexdigits [. hexdigits] [p [sign] digits] ----
# C99 hexadecimal-float syntax, which `Base.parse(Float64, "0x1p3")` accepts. The
# mantissa accumulates up to 16 hex digits exactly (further digits fold into a
# sticky bit), the binary exponent tracks fraction digits and the `p` part, and
# one round-half-even from the wide integer gives the correctly rounded T.
function _parsehexfloat(::Type{T}, buf::AbstractVector{UInt8}, i::Int,
                        j::Int) where {T <: Union{Float64, Float32, Float16}}
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        return _parsehexfloatexact(T, window, first, final)
    end
    return _parsehexfloatexact(T, buf, i, j)
end

function _parsehexfloatexact(::Type{T}, buf::AbstractVector{UInt8}, i::Int,
                             j::Int) where {T <: Union{Float64, Float32, Float16}}
    value, nextpos, rc = _parsehexfloatprefix(T, buf, i, j)
    nextpos > j || return (zero(T), RC_INVALID)
    return (value, rc)
end

# Prefix form of the hexadecimal parser. It converts while locating the token
# boundary. An incomplete binary exponent stays outside the committed token.
@inline function _parsehexfloatprefix(::Type{T}, buf::AbstractVector{UInt8},
                                      i::Int, j::Int) where
                                      {T <: Union{Float64, Float32, Float16}}
    E = j - i <= typemax(Int) ÷ 4 ? Int : Int128
    return _parsehexfloatprefix(T, buf, i, j, E)
end

function _parsehexfloatprefix(::Type{T}, buf::AbstractVector{UInt8}, i::Int,
                              j::Int, ::Type{E}) where
                              {T <: Union{Float64, Float32, Float16},
                               E <: Union{Int, Int128}}
    orig = i
    neg = false
    @inbounds if i <= j
        b = buf[i]
        neg = b == UInt8('-')
        (neg | (b == UInt8('+'))) && (i += 1)
    end
    @inbounds (i < j && buf[i] == UInt8('0') &&
               _lower(buf[i + 1]) == UInt8('x')) ||
        return (zero(T), orig, RC_INVALID)
    i += 2
    mant = zero(UInt64)
    nd = 0
    e2 = zero(E)
    sticky = false
    sawdigit = false
    infrac = false
    @inbounds while i <= j
        b = buf[i]
        d = b - UInt8('0')
        if d > 0x09
            d = _lower(b) - UInt8('a')
            if d > 0x05
                if b == UInt8('.') && !infrac
                    infrac = true
                    i += 1
                    continue
                end
                break
            end
            d += 0x0a
        end
        sawdigit = true
        if nd < 16
            mant = (mant << 4) | UInt64(d)
            nd += mant != 0 || d != 0 ? 1 : 0
            infrac && (e2 -= 4)
        else
            sticky |= d != 0
            infrac || (e2 += 4)
        end
        i += 1
    end
    sawdigit || return (zero(T), orig, RC_INVALID)
    commit = i
    e2wide = Int128(e2)
    @inbounds if i <= j && _lower(buf[i]) == UInt8('p')
        k = i + 1
        eneg = false
        if k <= j
            b = buf[k]
            eneg = b == UInt8('-')
            (eneg | (b == UInt8('+'))) && (k += 1)
        end
        estart = k
        e = _hexexponentzero(E)
        while k <= j
            d = buf[k] - UInt8('0')
            d <= 0x09 || break
            e = _hexexponentdigit(e, d)
            k += 1
        end
        if k > estart
            e2wide += _signedhexexponent(e, eneg)
            commit = k
        end
    end
    if mant == 0
        value = neg ? -zero(T) : zero(T)
        return (value, commit, sticky ? RC_UNDERFLOW : RC_OK)
    end
    value, rc = _binaryroundwide(T, mant, e2wide, sticky, neg)
    return (value, commit, rc)
end

@inline function _binaryroundwide(::Type{T}, mant::UInt64, e2::Int128,
                                  sticky::Bool, neg::Bool) where
                                  {T <: Union{Float64, Float32, Float16}}
    e2 > 4096 && return (neg ? -T(Inf) : T(Inf), RC_OVERFLOW)
    e2 < -4096 && return (neg ? -zero(T) : zero(T), RC_UNDERFLOW)
    return _binaryround(T, mant, Int(e2), sticky, neg)
end

# value = mant × 2^e2 (mant ≠ 0, plus a sticky "there was more below") → T,
# round-half-even, with subnormals and the range codes
function _binaryround(::Type{T}, mant::UInt64, e2::Int, sticky::Bool, neg::Bool) where {T}
    MB = _mantbits(T)
    nb = 64 - leading_zeros(mant)                  # significant bits in mant
    ebias = e2 + nb - 1 + _bias(T)                 # biased exponent of the leading bit
    # significand bits the format can hold at this exponent: MB+1 when normal,
    # MB+ebias when subnormal (ebias ≤ 0), i.e. the leading bit lands below bit MB
    keep = ebias >= 1 ? MB + 1 : MB + ebias
    if keep <= 0
        # even the leading bit is below the format: at most a rounding decision
        # to the minimum subnormal
        rbit = keep == 0
        below = keep == 0 ? (mant & ~(UInt64(1) << (nb - 1))) != 0 : mant != 0
        m = (rbit && (sticky || below)) ? one(UInt64) : zero(UInt64)
        return m == 0 ? (neg ? -zero(T) : zero(T), RC_UNDERFLOW) : (_sign(T, m, neg), RC_OK)
    end
    if nb > keep
        drop = nb - keep
        m = mant >> drop
        rbit = (mant >> (drop - 1)) & 1 == 1
        sticky |= (mant & ((UInt64(1) << (drop - 1)) - 1)) != 0
        rbit && (sticky || (m & 1) == 1) && (m += 1)
    else
        m = mant << (keep - nb)
    end
    if ebias >= 1
        if m == (UInt64(1) << (MB + 1))            # carry out of a normal significand
            m >>= 1
            ebias += 1
        end
        ebias >= _maxexp(T) && return (neg ? -T(Inf) : T(Inf), RC_OVERFLOW)
        return (_sign(T, (UInt64(ebias) << MB) | (m & ((UInt64(1) << MB) - 1)), neg), RC_OK)
    end
    # subnormal: m holds the bits below the (absent) implicit one; a carry to
    # 2^MB IS the minimum normal's bit pattern
    return (_sign(T, m, neg), RC_OK)
end

const _POW10 = Float64[10.0^k for k in 0:22]
