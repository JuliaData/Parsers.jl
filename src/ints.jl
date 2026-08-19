# =============================================================================
# integers — SWAR digit gathering; exact-span Int64/Int128; digit-group marks
#
# All the fixed-width kernels here are total: `(value, rc)` with rc one of
# RC_OK / RC_INVALID / RC_OVERFLOW, no exceptions, no allocation.
# =============================================================================

# All eight bytes of `w` are ASCII digits? (exact: borrow-free formulation)
@inline function _alldigits8(w::UInt64)
    return ((w & 0xf0f0f0f0f0f0f0f0) |
            (((w + 0x0606060606060606) & 0xf0f0f0f0f0f0f0f0) >> 4)) ==
           0x3333333333333333
end

# Convert eight ASCII digits (already validated) to their integer value — the
# classic two-multiply SWAR gather.
@inline function _digits8(w::UInt64)
    w -= 0x3030303030303030
    w = (w * 10) + (w >> 8)                     # pairs
    w = (((w & 0x000000ff000000ff) * 0x000f424000000064) +
         (((w >> 16) & 0x000000ff000000ff) * 0x0000271000000001)) >> 32
    return w
end

@inline _load8(buf::Vector{UInt8}, i::Int) =
    GC.@preserve buf ltoh(unsafe_load(Ptr{UInt64}(pointer(buf, i))))

"""
    parseint64(buf, i, j) -> (Int64, rc)

Parse `buf[i:j]` as a base-10 `Int64`: optional single `-`/`+` sign, then one or
more ASCII digits, nothing else. Leading zeros are accepted (a caller's
inference policy for zero-padded identifiers lives above this). `rc` is
OVERFLOW when the digits are well-formed but exceed Int64, INVALID otherwise.
"""
function parseint64(buf::Vector{UInt8}, i::Int, j::Int)
    i > j && return (zero(Int64), RC_INVALID)
    @inbounds b = buf[i]
    neg = b == UInt8('-')
    (neg | (b == UInt8('+'))) && (i += 1)
    i > j && return (zero(Int64), RC_INVALID)
    # skip (but count) leading zeros so the digit-count overflow bound is exact
    z = i
    @inbounds while i <= j && buf[i] == UInt8('0')
        i += 1
    end
    i > j && return (zero(Int64), RC_OK)         # all zeros ("0", "-000")
    ndig = j - i + 1
    if ndig > 19
        return _digitsonly(buf, i, j) ? (zero(Int64), RC_OVERFLOW) :
                                        (zero(Int64), RC_INVALID)
    end
    v = zero(UInt64)
    @inbounds while i + 7 <= j
        w = _load8(buf, i)
        _alldigits8(w) || return (zero(Int64), RC_INVALID)
        v = v * 100_000_000 + _digits8(w)
        i += 8
    end
    @inbounds while i <= j
        d = buf[i] - UInt8('0')
        d > 0x09 && return (zero(Int64), RC_INVALID)
        v = v * 10 + d
        i += 1
    end
    # 19 digits can exceed typemax; check against the signed bound
    if ndig == 19
        lim = neg ? UInt64(9223372036854775808) : UInt64(9223372036854775807)
        v > lim && return (zero(Int64), RC_OVERFLOW)
    end
    return (neg ? -reinterpret(Int64, v) : reinterpret(Int64, v), RC_OK)
end

"""
    parseint128(buf, i, j) -> (Int128, rc)

Parse the strict integer grammar as `Int128`. This is the exact-width fallback
after `parseint64` reports overflow.
"""
function parseint128(buf::Vector{UInt8}, i::Int, j::Int)
    i > j && return (zero(Int128), RC_INVALID)
    @inbounds b = buf[i]
    neg = b == UInt8('-')
    (neg | (b == UInt8('+'))) && (i += 1)
    i > j && return (zero(Int128), RC_INVALID)
    @inbounds while i <= j && buf[i] == UInt8('0')
        i += 1
    end
    i > j && return (zero(Int128), RC_OK)
    ndig = j - i + 1
    if ndig > 39
        return _digitsonly(buf, i, j) ? (zero(Int128), RC_OVERFLOW) :
                                       (zero(Int128), RC_INVALID)
    end
    lim = UInt128(typemax(Int128)) + UInt128(neg)
    v = zero(UInt128)
    @inbounds while i <= j
        d = buf[i] - UInt8('0')
        d > 0x09 && return (zero(Int128), RC_INVALID)
        v > (lim - UInt128(d)) ÷ UInt128(10) &&
            return (zero(Int128), RC_OVERFLOW)
        v = v * UInt128(10) + UInt128(d)
        i += 1
    end
    if neg
        v == UInt128(typemax(Int128)) + 1 && return (typemin(Int128), RC_OK)
        return (-Int128(v), RC_OK)
    end
    return (Int128(v), RC_OK)
end

@inline function _digitsonly(buf::Vector{UInt8}, i::Int, j::Int)
    @inbounds for k in i:j
        (buf[k] - UInt8('0')) > 0x09 && return false
    end
    return true
end

"""
    degroup!(scratch, buf, i, j, groupmark, decimal) -> n

Copy the numeric span `[i, j]` into `scratch` with digit-group separators
removed. A separator is valid only BETWEEN two digits in the integer part
(before the decimal point or exponent); group widths are deliberately not
enforced — "1,234,567" and Indian-style "12,34,567" both pass, matching the
lenient behavior tabular data has. Returns the degrouped length, `-1` when
the span contains no separator at all (parse the original span — the common
case costs one scan), or `-2` when a separator is misplaced (leading, trailing,
adjacent to another separator, or in the fraction/exponent).
"""
function degroup!(scratch::Vector{UInt8}, buf::Vector{UInt8}, i::Int, j::Int,
                  gm::UInt8, decimal::UInt8)
    _hasbyte(buf, i, j, gm) || return -1
    n = j - i + 1
    length(scratch) < n && resize!(scratch, max(n, 64))
    m = 0
    intpart = true
    @inbounds for k in i:j
        b = buf[k]
        if b == gm
            intpart || return -2
            (k > i && (buf[k-1] - UInt8('0')) <= 0x09 &&
             k < j && (buf[k+1] - UInt8('0')) <= 0x09) || return -2
        else
            (b == decimal || b == UInt8('e') || b == UInt8('E')) && (intpart = false)
            m += 1
            scratch[m] = b
        end
    end
    return m
end

# Does `buf[i:j]` contain byte `b`? Word-at-a-time (eq-mask) while eight bytes
# remain inside the buffer, byte tail otherwise — the mark pre-scan every cell
# of a grouped column pays, so it must be nearly free when there are no marks.
@inline function _hasbyte(buf::Vector{UInt8}, i::Int, j::Int, b::UInt8)
    k = i
    lim = min(j, length(buf)) - 7
    @inbounds while k <= lim
        _eqmask8(_load8(buf, k), b) != 0 && return true
        k += 8
    end
    @inbounds while k <= j
        buf[k] == b && return true
        k += 1
    end
    return false
end

"""
    parsegroupedint64(buf, i, j, gm) -> (Int64, rc)

`parseint64` for spans that may carry digit-group marks `gm` (`1,234,567`):
exactly `degroup!` + `parseint64` (marks only BETWEEN digits, no leading/
trailing/adjacent marks; group widths lenient), without the scratch copy —
each digit run gathers straight out of the loaded word. Runs longer than
eight digits, or spans within eight bytes of the buffer's end, take the
reference path so nothing reads past the buffer.
"""
parsegroupedint64(buf::Vector{UInt8}, i::Int, j::Int, gm::UInt8) =
    parsegroupedint64(buf, i, j, gm, Vector{UInt8}(undef, 64))

function parsegroupedint64(buf::Vector{UInt8}, i::Int, j::Int, gm::UInt8, scratch::Vector{UInt8})
    i > j && return (zero(Int64), RC_INVALID)
    i0 = i                                       # the reference path re-reads the sign itself
    @inbounds b = buf[i]
    neg = b == UInt8('-')
    (neg | (b == UInt8('+'))) && (i += 1)
    i > j && return (zero(Int64), RC_INVALID)
    j + 8 > length(buf) && return _parsegroupedint64_slow(buf, i0, j, gm, scratch)
    v = zero(UInt64)
    ndig = 0            # significant digits (leading zeros of the whole number excluded)
    k = i
    @inbounds while true
        w = _load8(buf, k)
        # position of the first non-digit lane (exact for the lowest flagged
        # lane; a misclassified high byte only lengthens a run that
        # _rundigits then rejects)
        d = w ⊻ 0x3030303030303030
        nondig = ((d + 0x7676767676767676) & 0x8080808080808080)
        avail = j - k + 1
        firstbad = nondig == 0 ? 8 : (trailing_zeros(nondig) >> 3)
        r = min(firstbad, avail)
        r == 0 && return (zero(Int64), RC_INVALID)   # mark/garbage where a digit must be
        # a run longer than the word (ninth byte still a digit) → reference path
        r == 8 && k + 8 <= j && (buf[k + 8] - UInt8('0')) <= 0x09 &&
            return _parsegroupedint64_slow(buf, i0, j, gm, scratch)
        run, ok = _rundigits(w, r)
        ok || return (zero(Int64), RC_INVALID)
        # digit accounting with the parseint64 leading-zero rule
        if ndig == 0
            lz = 0
            while lz < r && buf[k + lz] == UInt8('0')
                lz += 1
            end
            ndig = r - lz
        else
            ndig += r
        end
        ndig > 19 && return _parsegroupedint64_slow(buf, i0, j, gm, scratch)
        v = v * _P10U[r + 1] + run
        k += r
        k > j && break
        # the byte after a run must be a mark, followed by another digit run
        (buf[k] == gm && k < j) || return (zero(Int64), RC_INVALID)
        k += 1
        (buf[k] - UInt8('0')) <= 0x09 || return (zero(Int64), RC_INVALID)
    end
    if ndig == 19
        lim = neg ? UInt64(9223372036854775808) : UInt64(9223372036854775807)
        v > lim && return (zero(Int64), RC_OVERFLOW)
    end
    return (neg ? -reinterpret(Int64, v) : reinterpret(Int64, v), RC_OK)
end

# reference semantics for the guarded cases: degroup the WHOLE span (sign
# included) into the caller's scratch (degroup! grows it if needed), then
# parseint64 — allocation-free on the column loop's per-chunk scratch
@noinline function _parsegroupedint64_slow(buf::Vector{UInt8}, i::Int, j::Int, gm::UInt8,
                                           scratch::Vector{UInt8})
    n = degroup!(scratch, buf, i, j, gm, 0xff)
    n == -2 && return (zero(Int64), RC_INVALID)
    return n == -1 ? parseint64(buf, i, j) : parseint64(scratch, 1, n)
end

# =============================================================================
# every integer width, unsigned, arbitrary base — the Base.parse surface
# =============================================================================

const _SIGNED   = Union{Int8, Int16, Int32, Int64, Int128}
const _UNSIGNED = Union{UInt8, UInt16, UInt32, UInt64, UInt128}

# UInt64: the parseint64 SWAR core without a sign, with the 20-digit bound
function _parseuint64(buf::Vector{UInt8}, i::Int, j::Int)
    i > j && return (zero(UInt64), RC_INVALID)          # no sign of any kind (Base's rule for unsigned)
    @inbounds while i <= j && buf[i] == UInt8('0')
        i += 1
    end
    i > j && return (zero(UInt64), RC_OK)
    ndig = j - i + 1
    if ndig > 20
        return _digitsonly(buf, i, j) ? (zero(UInt64), RC_OVERFLOW) : (zero(UInt64), RC_INVALID)
    end
    v = zero(UInt64)
    @inbounds while i + 7 <= j
        w = _load8(buf, i)
        _alldigits8(w) || return (zero(UInt64), RC_INVALID)
        v = v * 100_000_000 + _digits8(w)      # < 10^16 · 10^8 fits until the 20th digit
        i += 8
    end
    @inbounds while i <= j
        d = buf[i] - UInt8('0')
        d > 0x09 && return (zero(UInt64), RC_INVALID)
        if ndig == 20 && i == j
            # the 20th digit can overflow: typemax(UInt64) = 18446744073709551615
            v > 1844674407370955161 && return (zero(UInt64), RC_OVERFLOW)
            v == 1844674407370955161 && d > 0x05 && return (zero(UInt64), RC_OVERFLOW)
        end
        v = v * 10 + d
        i += 1
    end
    return (v, RC_OK)
end

# UInt128: 8-digit blocks with checked accumulation (39 digits max)
function _parseuint128(buf::Vector{UInt8}, i::Int, j::Int)
    i > j && return (zero(UInt128), RC_INVALID)
    @inbounds while i <= j && buf[i] == UInt8('0')
        i += 1
    end
    i > j && return (zero(UInt128), RC_OK)
    (j - i + 1) > 39 && return (_digitsonly(buf, i, j) ? (zero(UInt128), RC_OVERFLOW) :
                                                       (zero(UInt128), RC_INVALID))
    v = zero(UInt128)
    @inbounds while i + 7 <= j
        w = _load8(buf, i)
        _alldigits8(w) || return (zero(UInt128), RC_INVALID)
        v, o1 = Base.mul_with_overflow(v, UInt128(100_000_000))
        v, o2 = Base.add_with_overflow(v, UInt128(_digits8(w)))
        (o1 | o2) && return (zero(UInt128), RC_OVERFLOW)
        i += 8
    end
    @inbounds while i <= j
        d = buf[i] - UInt8('0')
        d > 0x09 && return (zero(UInt128), RC_INVALID)
        v, o1 = Base.mul_with_overflow(v, UInt128(10))
        v, o2 = Base.add_with_overflow(v, UInt128(d))
        (o1 | o2) && return (zero(UInt128), RC_OVERFLOW)
        i += 1
    end
    return (v, RC_OK)
end

"""
    parseint(T, buf, i, j) -> (T, rc)

Exact-span base-10 integer of any width: optional sign (`+` only for
unsigned), digits, nothing else. `rc` is `RC_OK`, `RC_INVALID`, or
`RC_OVERFLOW` (well-formed digits outside `T`'s range — the code a caller's
type lattice uses to widen). Int64/UInt64 and narrower go through the SWAR
kernels; Int128/UInt128 through 8-digit checked blocks.
"""
@inline function parseint(::Type{T}, buf::Vector{UInt8}, i::Int, j::Int) where {T <: _SIGNED}
    if T === Int128
        return parseint128(buf, i, j)
    end
    v, rc = parseint64(buf, i, j)
    T === Int64 && return (v, rc)
    rc == RC_OK || return (zero(T), rc)
    typemin(T) <= v <= typemax(T) || return (zero(T), RC_OVERFLOW)
    return (T(v), RC_OK)
end
@inline function parseint(::Type{T}, buf::Vector{UInt8}, i::Int, j::Int) where {T <: _UNSIGNED}
    if T === UInt128
        return _parseuint128(buf, i, j)
    end
    v, rc = _parseuint64(buf, i, j)
    T === UInt64 && return (v, rc)
    rc == RC_OK || return (zero(T), rc)
    v <= typemax(T) || return (zero(T), RC_OVERFLOW)
    return (T(v), RC_OK)
end

# digit value in `base` (Base.parse's rule): 0-9, then A-Z = 10..35, and a-z =
# 10..35 for base ≤ 36 but 36..61 above it; 0xff = not a digit at all
@inline function _digitvalue(b::UInt8, base::Int)
    d = b - UInt8('0')
    d <= 0x09 && return d
    UInt8('A') <= b <= UInt8('Z') && return b - UInt8('A') + 0x0a
    UInt8('a') <= b <= UInt8('z') && return b - UInt8('a') + (base <= 36 ? 0x0a : 0x24)
    return 0xff
end

"""
    parseint(T, buf, i, j, base) -> (T, rc, badpos)

Integer in `base` (2 ≤ base ≤ 62; base 10 takes the SWAR path above), any
width; `badpos` is the position of the offending byte when `rc == RC_INVALID`
(0 otherwise) so the caller can name it the way `Base.parse` does. Overflow
is detected with checked arithmetic.
"""
function parseint(::Type{T}, buf::Vector{UInt8}, i::Int, j::Int, base::Int) where {T <: Union{_SIGNED, _UNSIGNED}}
    if base == 10
        v, rc = parseint(T, buf, i, j)
        return (v, rc, rc == RC_INVALID ? _firstbad10(buf, i, j) : 0)
    end
    i > j && return (zero(T), RC_INVALID, i)
    neg = false
    @inbounds begin
        b = buf[i]
        if b == UInt8('-') || b == UInt8('+')
            T <: _UNSIGNED && return (zero(T), RC_INVALID, i)   # Base: a sign is an invalid digit for unsigned
            neg = b == UInt8('-')
            i += 1
        end
    end
    i > j && return (zero(T), RC_INVALID, i)   # sign only: "premature end" / empty
    v = zero(T)
    bT = T(base)
    @inbounds while i <= j
        d = _digitvalue(buf[i], base)
        (d == 0xff || d >= base) && return (zero(T), RC_INVALID, i)
        v, o1 = Base.mul_with_overflow(v, bT)
        # accumulate negatively for signed so typemin parses (its magnitude overflows)
        v, o2 = neg ? Base.sub_with_overflow(v, T(d)) : Base.add_with_overflow(v, T(d))
        (o1 | o2) && return (zero(T), RC_OVERFLOW, 0)
        i += 1
    end
    return (v, RC_OK, 0)
end

# position of the first byte that is not part of a base-10 integer (for the
# error message); i when the span is empty/sign-only
function _firstbad10(buf::Vector{UInt8}, i::Int, j::Int)
    k = i
    @inbounds if k <= j && (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
        k += 1
    end
    @inbounds while k <= j && buf[k] - UInt8('0') <= 0x09
        k += 1
    end
    return k <= j ? k : i
end
