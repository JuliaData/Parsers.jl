# =============================================================================
# floats — three self-contained tiers:
#   1. exact small case (mantissa ≤ 15 digits, small exponent): one fma-free
#      multiply/divide by an exactly-representable power of ten
#   2. Eisel–Lemire: 128-bit product against the precomputed powers-of-five
#      table; bails (rarely) on rounding-boundary ambiguity
#   3. Tao's simple decimal conversion over a fixed 800-digit buffer — total,
#      exact, covers subnormals and every ambiguous case
# =============================================================================

# --- decimal decomposition ---------------------------------------------------

struct DecParts
    mant::UInt64      # up to 19 significant digits (truncated beyond)
    exp10::Int32      # power of ten applied to mant
    ndig::Int32       # significant digits seen (may exceed 19)
    truncated::Bool   # digits beyond 19 were dropped (a nonzero one ⇒ sticky)
    neg::Bool
    digstart::Int32   # buf offset of the first significant digit (tier 3 re-read)
end

# Split [i,j] into sign/digits/point/exponent. Returns (parts, rc) with
# rc=INVALID for structure errors; special spellings handled by caller.
function _decompose(buf::AbstractVector{UInt8}, i::Int, j::Int, decimal::UInt8)
    # Phase-structured: sign → integer run → decimal point → fraction run →
    # (>19-digit tail) → exponent. Each digit run gathers eight digits per word
    # while the 19-digit significand has room (and a whole word is in bounds);
    # the tail past 19 significant digits is scanned eight bytes at a time for
    # validity and any-nonzero (all it needs to know), so 400-digit mantissas
    # cost ~50 word steps instead of 400 byte steps.
    neg = false
    @inbounds if i <= j
        b = buf[i]
        neg = b == UInt8('-')
        (neg | (b == UInt8('+'))) && (i += 1)
    end
    i > j && return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
    mant = zero(UInt64)
    ndig = 0
    exp10 = 0
    truncated = false
    sawdigit = false
    digstart = 0
    lastw = j - 7                            # last position with a whole word inside the span
    # -- integer part ---------------------------------------------------------
    @inbounds while i <= j && buf[i] == UInt8('0')      # leading zeros: value-neutral
        sawdigit = true
        i += 1
    end
    @inbounds if i <= j && buf[i] - UInt8('0') <= 0x09
        digstart = i
        while i <= lastw && ndig <= 11                   # ndig + 8 <= 19
            w = _load8(buf, i)
            _alldigits8(w) || break
            mant = mant * 100_000_000 + _digits8(w)
            ndig += 8
            i += 8
        end
        while i <= j
            d = buf[i] - UInt8('0')
            d > 0x09 && break
            if ndig < 19
                mant = mant * 10 + d
            else
                truncated |= d != 0x00
                exp10 += 1                               # dropped integer digit
            end
            ndig += 1
            i += 1
            # past the significand: the rest of the run only needs "all digits"
            # and "any nonzero" — eight bytes at a time
            if ndig >= 19
                while i <= lastw
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
    # -- fraction ------------------------------------------------------------
    @inbounds if i <= j && buf[i] == decimal
        i += 1
        if ndig == 0                                     # zeros before the first significant digit
            while i <= j && buf[i] == UInt8('0')
                sawdigit = true
                exp10 -= 1
                i += 1
            end
            i <= j && buf[i] - UInt8('0') <= 0x09 && (digstart = i)
        end
        while i <= lastw && ndig <= 11
            w = _load8(buf, i)
            _alldigits8(w) || break
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
                mant = mant * 10 + d
                exp10 -= 1
            else
                truncated |= d != 0x00                   # dropped fraction digit: scale unchanged
            end
            ndig += 1
            sawdigit = true
            i += 1
            if ndig >= 19
                while i <= lastw
                    w = _load8(buf, i)
                    _alldigits8(w) || break
                    truncated |= w != 0x3030303030303030
                    ndig += 8
                    i += 8
                end
            end
        end
    end
    sawdigit || return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
    # -- exponent -------------------------------------------------------------
    @inbounds if i <= j
        b = buf[i]
        (b == UInt8('e')) | (b == UInt8('E')) ||
            return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
        i += 1
        eneg = false
        if i <= j
            eb = buf[i]
            eneg = eb == UInt8('-')
            (eneg | (eb == UInt8('+'))) && (i += 1)
        end
        i > j && return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
        e = 0
        while i <= j
            ed = buf[i] - UInt8('0')
            ed > 0x09 && return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
            e < 100_000 && (e = e * 10 + Int(ed))       # clamp: beyond ±99999 saturates
            i += 1
        end
        exp10 += eneg ? -e : e
    end
    return (DecParts(mant, Int32(exp10), Int32(ndig), truncated, neg, Int32(digstart)), RC_OK)
end

# Grouped numbers are uncommon enough that a scalar scanner is smaller and
# faster than copying into a temporary byte vector. A mark is accepted only in
# the integer part and only when its immediate neighbours are decimal digits,
# exactly matching `degroup!`.
function _decomposegrouped(buf::AbstractVector{UInt8}, i::Int, j::Int,
                           decimal::UInt8, groupmark::UInt8)
    neg = false
    @inbounds if i <= j
        b = buf[i]
        neg = b == UInt8('-')
        (neg | (b == UInt8('+'))) && (i += 1)
    end
    i > j && return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
    digitstart = i

    mant = zero(UInt64)
    ndig = 0
    exp10 = 0
    truncated = false
    sawdigit = false
    significant = false

    # Integer part.
    @inbounds while i <= j
        b = buf[i]
        d = b - UInt8('0')
        if d <= 0x09
            sawdigit = true
            if significant || d != 0
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
        elseif b == groupmark
            (i > digitstart && i < j && (buf[i - 1] - UInt8('0')) <= 0x09 &&
             (buf[i + 1] - UInt8('0')) <= 0x09) ||
                return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
            i += 1
        else
            break
        end
    end

    # Fractional part. Group marks are not valid after the decimal byte.
    @inbounds if i <= j && buf[i] == decimal
        i += 1
        while i <= j
            d = buf[i] - UInt8('0')
            d <= 0x09 || break
            sawdigit = true
            if !significant && d == 0
                exp10 -= 1
            else
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
    sawdigit || return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)

    # Exponent.
    @inbounds if i <= j
        b = buf[i]
        (b == UInt8('e')) | (b == UInt8('E')) ||
            return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
        i += 1
        eneg = false
        if i <= j
            b = buf[i]
            eneg = b == UInt8('-')
            (eneg | (b == UInt8('+'))) && (i += 1)
        end
        i > j && return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
        e = 0
        while i <= j
            d = buf[i] - UInt8('0')
            d <= 0x09 || return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
            e < 100_000 && (e = 10e + Int(d))
            i += 1
        end
        exp10 += eneg ? -e : e
    end
    return (DecParts(mant, Int32(exp10), Int32(ndig), truncated, neg, 0), RC_OK)
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
@inline _bias(::Type{Float64}) = 1023
@inline _bias(::Type{Float32}) = 127
@inline _maxexp(::Type{Float64}) = 2047      # biased exponent of ±Inf
@inline _maxexp(::Type{Float32}) = 255
@inline _elshift(::Type{Float64}) = 9         # 64 - mantbits - 3: keeps mantbits+2 product bits
@inline _elshift(::Type{Float32}) = 38
@inline _tiemin(::Type{Float64}) = -4         # q range where the 128-bit product is exact
@inline _tiemax(::Type{Float64}) = 23
@inline _tiemin(::Type{Float32}) = -17
@inline _tiemax(::Type{Float32}) = 10
@inline _bitstype(::Type{Float64}) = UInt64
@inline _bitstype(::Type{Float32}) = UInt32
@inline _infbits(::Type{Float64}) = 0x7ff0000000000000
@inline _infbits(::Type{Float32}) = UInt64(0x7f800000)

_eisel_lemire(mant::UInt64, q::Int) = _eisel_lemire(Float64, mant, q)

# Returns the (unsigned) bit pattern of T as an Int64 ≥ 0, or a negative code:
# -1 ambiguous (tier 3 decides), -2 exponent outside the table (certain
# under/overflow — the caller decides which by q's sign), -3 overflow (±Inf).
# A ZERO bit pattern here means underflow-to-zero: mant is nonzero on entry.
function _eisel_lemire(::Type{T}, mant::UInt64, q::Int) where {T <: Union{Float64, Float32}}
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
        # standard Eisel-Lemire subnormal step; rejecting here made every
        # shortest subnormal pay the exact-decimal tier's ~1,000 scaling loops.
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
    # round-half-even is applied here by clearing the low bit — no tier-3
    # trip. (Delegating instead cost 2.4 µs per value on the band of odd
    # 16-digit integers just above 2^53: 188x slower than fast_float.)
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

# --- tier 3: simple decimal conversion ----------------------------------------

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

function _hpd(buf::AbstractVector{UInt8}, i::Int, j::Int, decimal::UInt8)
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
        else # exponent (structure already validated by _decompose)
            k += 1
            eneg = false
            @inbounds if k <= j && (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
                eneg = buf[k] == UInt8('-')
                k += 1
            end
            e = 0
            @inbounds while k <= j
                e < 100_000 && (e = e * 10 + Int(buf[k] - UInt8('0')))
                k += 1
            end
            dp += eneg ? -e : e
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

# @noinline is load-bearing: this is the ~1-in-10^4 cold tier, and letting it
# inline bloats parsefloat64's hot path ~7x (measured 29ns -> 203ns per value).
_sdc(buf::AbstractVector{UInt8}, i::Int, j::Int, neg::Bool, decimal::UInt8) =
    _sdc(Float64, buf, i, j, neg, decimal)

@noinline function _sdc(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int, neg::Bool,
                        decimal::UInt8) where {T <: Union{Float64, Float32}}
    MB = _mantbits(T)
    h = _hpd(buf, i, j, decimal)
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

# --- special spellings ---------------------------------------------------------

@inline _lower(b::UInt8) = b | 0x20
function _matchspecial(buf::AbstractVector{UInt8}, i::Int, j::Int)
    # returns (Float64, matched)
    neg = false
    @inbounds if i <= j
        b = buf[i]
        neg = b == UInt8('-')
        (neg | (b == UInt8('+'))) && (i += 1)
    end
    n = j - i + 1
    @inbounds if n == 3
        if _lower(buf[i]) == UInt8('n') && _lower(buf[i+1]) == UInt8('a') && _lower(buf[i+2]) == UInt8('n')
            return (neg ? -NaN : NaN, true)
        elseif _lower(buf[i]) == UInt8('i') && _lower(buf[i+1]) == UInt8('n') && _lower(buf[i+2]) == UInt8('f')
            return (neg ? -Inf : Inf, true)
        end
    elseif n == 8
        ok = true
        for (k, c) in enumerate((UInt8('i'), UInt8('n'), UInt8('f'), UInt8('i'), UInt8('n'), UInt8('i'), UInt8('t'), UInt8('y')))
            ok &= _lower(buf[i + k - 1]) == c
        end
        ok && return (neg ? -Inf : Inf, true)
    end
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

# A short scalar loop beats the word-mask setup for common whole values such as
# "1", "1.5", "-0.25", and short exponents. Clinger-range values convert
# directly; other accepted values use the shared exact conversion path.
@inline function _floatsmall(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                             decimal::UInt8) where {T <: Union{Float64, Float32}}
    i <= j || return (zero(T), false)
    neg = false
    @inbounds begin
        b = buf[i]
        neg = b == UInt8('-')
        (neg | (b == UInt8('+'))) && (i += 1)
    end
    n = j - i + 1
    1 <= n <= 15 || return (zero(T), false)
    mant = zero(UInt64)
    ndig = 0
    frac = 0
    sawdigit = false
    sawpoint = false
    exponent = 0
    k = i
    @inbounds while k <= j
        b = buf[k]
        d = b - UInt8('0')
        if d <= 0x09
            sawdigit = true
            mant = 10mant + d
            ndig += 1
            sawpoint && (frac += 1)
        elseif b == decimal && !sawpoint
            sawpoint = true
        elseif (b == UInt8('e') || b == UInt8('E')) && sawdigit
            k += 1
            eneg = false
            if k <= j
                b = buf[k]
                eneg = b == UInt8('-')
                (eneg | (b == UInt8('+'))) && (k += 1)
            end
            k <= j || return (zero(T), false)
            e = 0
            while k <= j
                d = buf[k] - UInt8('0')
                d <= 0x09 || return (zero(T), false)
                e < 100_000 && (e = 10e + Int(d))
                k += 1
            end
            exponent = eneg ? -e : e
            break
        else
            return (zero(T), false)
        end
        k += 1
    end
    sawdigit || return (zero(T), false)
    q = exponent - frac
    clinger = T === Float64 ? (-22 <= q <= 22 && mant <= UInt64(1) << 53) :
                             (-10 <= q <= 10 && mant <= UInt64(1) << 24)
    if !clinger
        parts = DecParts(mant, Int32(q), Int32(ndig), false, neg, 0)
        value, rc, done = _convertparts(T, parts)
        rc == RC_OK && done && return (value, true)
        return (zero(T), false)
    end
    f = T(mant)
    if q != 0
        f = T === Float64 ? (q > 0 ? f * _POW10[q + 1] : f / _POW10[-q + 1]) :
                            (q > 0 ? f * _POW10F32[q + 1] : f / _POW10F32[-q + 1])
    end
    return (neg ? -f : f, true)
end

@inline function _floatgroupedsmall(::Type{T}, buf::AbstractVector{UInt8}, i::Int,
                                    j::Int, decimal::UInt8,
                                    groupmark::UInt8) where {T <: Union{Float64, Float32}}
    i <= j || return (zero(T), false)
    neg = false
    @inbounds begin
        b = buf[i]
        neg = b == UInt8('-')
        (neg | (b == UInt8('+'))) && (i += 1)
    end
    start = i
    1 <= j - i + 1 <= 15 || return (zero(T), false)
    mant = zero(UInt64)
    frac = 0
    exponent = 0
    sawdigit = false
    sawpoint = false
    k = i
    @inbounds while k <= j
        b = buf[k]
        d = b - UInt8('0')
        if d <= 0x09
            sawdigit = true
            mant = 10mant + d
            sawpoint && (frac += 1)
        elseif b == groupmark && !sawpoint
            (k > start && k < j && (buf[k - 1] - UInt8('0')) <= 0x09 &&
             (buf[k + 1] - UInt8('0')) <= 0x09) || return (zero(T), false)
        elseif b == decimal && !sawpoint
            sawpoint = true
        elseif (b == UInt8('e') || b == UInt8('E')) && sawdigit
            k += 1
            eneg = false
            if k <= j
                b = buf[k]
                eneg = b == UInt8('-')
                (eneg | (b == UInt8('+'))) && (k += 1)
            end
            k <= j || return (zero(T), false)
            e = 0
            while k <= j
                d = buf[k] - UInt8('0')
                d <= 0x09 || return (zero(T), false)
                e < 100_000 && (e = 10e + Int(d))
                k += 1
            end
            exponent = eneg ? -e : e
            break
        else
            return (zero(T), false)
        end
        k += 1
    end
    sawdigit || return (zero(T), false)
    q = exponent - frac
    if T === Float64
        (-22 <= q <= 22 && mant <= UInt64(1) << 53) || return (zero(T), false)
    else
        (-10 <= q <= 10 && mant <= UInt64(1) << 24) || return (zero(T), false)
    end
    value = T(mant)
    if q != 0
        value = T === Float64 ?
            (q > 0 ? value * _POW10[q + 1] : value / _POW10[-q + 1]) :
            (q > 0 ? value * _POW10F32[q + 1] : value / _POW10F32[-q + 1])
    end
    return (neg ? -value : value, true)
end

# The dominant whole-value shapes fit in 15 bytes. A bounded scalar scan is
# faster than word-mask setup on every supported Julia release, and it can
# hand scientific and wide-mantissa cases directly to the shared conversion
# core. Specials are recognized before numeric syntax so they do not scan
# twice. Longer or unresolved spellings fall through to the general parser.
@inline _float_fast(buf::AbstractVector{UInt8}, i::Int, j::Int, decimal::UInt8) =
    _float_fast(Float64, buf, i, j, decimal)

@inline function _float_fast(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                             decimal::UInt8) where {T <: Union{Float64, Float32}}
    orig_i = i
    @inbounds if i <= j
        b = buf[i]
        (b == UInt8('-') || b == UInt8('+')) && (i += 1)
    end
    @inbounds if i <= j
        first = _lower(buf[i])
        if first == UInt8('n') || first == UInt8('i')
            special, matched = _matchspecial(buf, orig_i, j)
            matched && return (T(special), true)
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
            f = q >= 0 ? f * _POW10[q + 1] : f / _POW10[-q + 1]
            return (parts.neg ? -f : f, RC_OK, true)
        end
    else
        if untrunc && -10 <= q <= 10 && mant <= 16777216             # 2^24
            f = Float32(mant)
            f = q >= 0 ? f * _POW10F32[q + 1] : f / _POW10F32[-q + 1]
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
        # pattern is overflow (Base.parse rejects both — ERANGE); the value
        # is still ±0 / ±Inf for callers that want it
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
    v, handled = _float_fast(T, buf, i, j, decimal)   # dominant [sign]digits[.digits] shape
    handled && return (v, RC_OK, true)
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
    parsefloat(T, buf, i, j, decimal=UInt8('.')) -> (T, rc)      T ∈ Float64, Float32
    parsefloat64(buf, i, j, decimal=UInt8('.')) -> (Float64, rc)

Parse `buf[i:j]` as `T` with correct (round-half-even) rounding for every
input — no C, no BigFloat: Clinger's exact small case, then Eisel–Lemire,
then simple-decimal-conversion for the rare ambiguous/subnormal cases.
`Float32` is parsed natively (never via Float64, which double-rounds).
Accepts sign, digits, one `decimal` byte, optional e/E exponent, and the
case-insensitive spellings Inf/Infinity/NaN.

`rc` is `RC_OK`, `RC_INVALID`, or one of the two RANGE codes: `RC_OVERFLOW`
(the value rounded to ±Inf) and `RC_UNDERFLOW` (a nonzero spelling rounded to
±0). The value returned alongside a range code is that ±Inf / ±0, so a caller
that wants C/strtod semantics simply treats both as success; `Parsers.parse`
follows `Base.parse` and rejects them.

Structured as an @inline hot core plus a thin wrapper owning the cold tier-3
tail (kept @noinline so its ~1000-step scaling loops never bloat the hot path).
"""
@inline function parsefloat(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                            decimal::UInt8=UInt8('.')) where {T <: Union{Float64, Float32}}
    v, rc, done = _parsefloat_core(T, buf, i, j, decimal)
    done && return (v, rc)
    r = _sdc(T, buf, i, j, v < 0, decimal)
    rc = r == 0 ? RC_UNDERFLOW : isinf(r) ? RC_OVERFLOW : RC_OK   # mant ≠ 0 on this path
    return (r, rc)
end
parsefloat64(buf::AbstractVector{UInt8}, i::Int, j::Int, decimal::UInt8=UInt8('.')) =
    parsefloat(Float64, buf, i, j, decimal)

# Public whole-value parsing can delegate only the rare unresolved rounding
# boundary to Julia's bounded C parser. The supported low-level `parsefloat`
# kernel above stays self-contained and uses SDC, so its contract is unchanged.
@inline _trycfloat(::Type{Float64}, ptr::Ptr{UInt8}, n::Int) =
    ccall(:jl_try_substrtod, Tuple{Bool, Float64},
          (Ptr{UInt8}, Csize_t, Csize_t), ptr, 0, n)
@inline _trycfloat(::Type{Float32}, ptr::Ptr{UInt8}, n::Int) =
    ccall(:jl_try_substrtof, Tuple{Bool, Float32},
          (Ptr{UInt8}, Csize_t, Csize_t), ptr, 0, n)

@noinline function _pointerfloatfallback(::Type{T}, buf, i::Int, j::Int,
                                         neg::Bool, decimal::UInt8) where {T <: Union{Float64, Float32}}
    decimal == UInt8('.') || return _sdc(T, buf, i, j, neg, decimal)
    GC.@preserve buf begin
        ok, value = _trycfloat(T, pointer(buf, i), j - i + 1)
        ok && return value
    end
    return _sdc(T, buf, i, j, neg, decimal)
end

_publicfloatfallback(::Type{T}, buf::Vector{UInt8}, i::Int, j::Int, neg::Bool,
                     decimal::UInt8) where {T <: Union{Float64, Float32}} =
    _pointerfloatfallback(T, buf, i, j, neg, decimal)
_publicfloatfallback(::Type{T}, buf::Base.CodeUnits{UInt8, S}, i::Int, j::Int, neg::Bool,
                     decimal::UInt8) where {T <: Union{Float64, Float32}, S <: Union{String, SubString{String}}} =
    _pointerfloatfallback(T, buf, i, j, neg, decimal)
_publicfloatfallback(::Type{T},
                     buf::SubArray{UInt8, 1, P, Tuple{I}, true},
                     i::Int, j::Int, neg::Bool,
                     decimal::UInt8) where {T <: Union{Float64, Float32},
                                             P <: Vector{UInt8},
                                             I <: AbstractUnitRange{Int}} =
    _pointerfloatfallback(T, buf, i, j, neg, decimal)
_publicfloatfallback(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int, neg::Bool,
                     decimal::UInt8) where {T <: Union{Float64, Float32}} =
    _sdc(T, buf, i, j, neg, decimal)

@inline function parsefloatpublic(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                                  decimal::UInt8) where {T <: Union{Float64, Float32}}
    value, rc, done = _parsefloat_core(T, buf, i, j, decimal)
    done && return (value, rc)
    value = _publicfloatfallback(T, buf, i, j, value < 0, decimal)
    return (value, RC_OK)
end

@inline function parsegroupedfloatpublic(::Type{T}, buf::AbstractVector{UInt8}, i::Int,
                                         j::Int, decimal::UInt8,
                                         groupmark::UInt8) where {T <: Union{Float64, Float32}}
    value, handled = _floatgroupedsmall(T, buf, i, j, decimal, groupmark)
    handled && return (value, RC_OK)
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
# C99 / strtod syntax, which `Base.parse(Float64, "0x1p3")` accepts. The
# mantissa accumulates up to 16 hex digits exactly (further digits fold into a
# sticky bit), the binary exponent tracks fraction digits and the `p` part, and
# one round-half-even from the wide integer gives the correctly rounded T.
function _parsehexfloat(::Type{T}, buf::AbstractVector{UInt8}, i::Int,
                        j::Int) where {T <: Union{Float64, Float32}}
    neg = false
    @inbounds if i <= j
        b = buf[i]
        neg = b == UInt8('-')
        (neg | (b == UInt8('+'))) && (i += 1)
    end
    @inbounds (i + 1 <= j && buf[i] == UInt8('0') && _lower(buf[i + 1]) == UInt8('x')) ||
        return (zero(T), RC_INVALID)
    i += 2
    mant = zero(UInt64)
    nd = 0                 # hex digits accumulated into mant
    e2 = 0                 # binary exponent adjustment
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
            nd += mant != 0 || d != 0 ? 1 : 0     # leading zeros are free
            infrac && (e2 -= 4)
        else
            sticky |= d != 0
            infrac || (e2 += 4)                   # dropped integer hex digit
        end
        i += 1
    end
    sawdigit || return (zero(T), RC_INVALID)
    @inbounds if i <= j
        _lower(buf[i]) == UInt8('p') || return (zero(T), RC_INVALID)
        i += 1
        eneg = false
        if i <= j
            eb = buf[i]
            eneg = eb == UInt8('-')
            (eneg | (eb == UInt8('+'))) && (i += 1)
        end
        i > j && return (zero(T), RC_INVALID)
        e = 0
        while i <= j
            ed = buf[i] - UInt8('0')
            ed > 0x09 && return (zero(T), RC_INVALID)
            e < 100_000 && (e = e * 10 + Int(ed))
            i += 1
        end
        e2 += eneg ? -e : e
    end
    mant == 0 && return (neg ? -zero(T) : zero(T), sticky ? RC_UNDERFLOW : RC_OK)
    return _binaryround(T, mant, e2, sticky, neg)
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
