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

@inline _load8(buf::Base.CodeUnits{UInt8, <:Union{String, SubString{String}}},
               i::Int) =
    GC.@preserve buf ltoh(unsafe_load(Ptr{UInt64}(pointer(buf.s, i))))

@inline _load8(buf::SubArray{UInt8, 1, P, Tuple{I}, true}, i::Int) where
              {P <: Vector{UInt8}, I <: AbstractUnitRange{Int}} =
    GC.@preserve buf ltoh(unsafe_load(Ptr{UInt64}(pointer(buf, i))))

# Low-level kernels also accept arbitrary byte vectors. Those may be strided
# or lack a stable pointer, so gather their logical elements instead of using
# the contiguous fast load above.
@inline function _load8(buf::AbstractVector{UInt8}, i::Int)
    @inbounds return UInt64(buf[i]) |
                     (UInt64(buf[i + 1]) << 8) |
                     (UInt64(buf[i + 2]) << 16) |
                     (UInt64(buf[i + 3]) << 24) |
                     (UInt64(buf[i + 4]) << 32) |
                     (UInt64(buf[i + 5]) << 40) |
                     (UInt64(buf[i + 6]) << 48) |
                     (UInt64(buf[i + 7]) << 56)
end

# Eight bytes from buf[k] with every index clamped to `j`: a word for spans
# shorter than eight bytes without reading past the span.
@inline function _gather8(buf::AbstractVector{UInt8}, k::Int, j::Int)
    available = j - k
    @inbounds return UInt64(buf[k]) |
                     (UInt64(buf[available >= 1 ? k + 1 : j]) << 8) |
                     (UInt64(buf[available >= 2 ? k + 2 : j]) << 16) |
                     (UInt64(buf[available >= 3 ? k + 3 : j]) << 24) |
                     (UInt64(buf[available >= 4 ? k + 4 : j]) << 32) |
                     (UInt64(buf[available >= 5 ? k + 5 : j]) << 40) |
                     (UInt64(buf[available >= 6 ? k + 6 : j]) << 48) |
                     (UInt64(buf[available >= 7 ? k + 7 : j]) << 56)
end

const _POW10U64 = ntuple(k -> UInt64(10)^(k - 1), 20)

# Index (0-7) of the lowest-address non-digit byte in `w`, 8 when every byte
# is a digit. Digit bytes never carry into their neighbour, so the first flag
# is exact even though flags above it may be spurious.
@inline function _firstnondigit8(w::UInt64)
    t = w ⊻ 0x3030303030303030
    flags = ((t + 0x7676767676767676) | t) & 0x8080808080808080
    return trailing_zeros(flags) >> 3
end

# Position of the first non-digit in buf[k:j], or j + 1.
@inline function _digitrunend(buf::AbstractVector{UInt8}, k::Int, j::Int)
    @inbounds while k <= j && j - k >= 7
        nd = _firstnondigit8(_load8(buf, k))
        nd < 8 && return k + nd
        k += 8
    end
    @inbounds while k <= j && (buf[k] - UInt8('0')) <= 0x09
        k += 1
    end
    return k
end

# Value of the n (1 ≤ n ≤ 19) bytes at buf[k : k+n-1] as decimal digits, and
# whether every byte was a digit: whole words eight digits at a time, then a
# clamped-gather tail that never reads past k+n-1.
@inline function _digits19(buf::AbstractVector{UInt8}, k::Int, n::Int)
    v = zero(UInt64)
    ok = true
    while n >= 8
        w = _load8(buf, k)
        ok &= _alldigits8(w)
        v = v * 100_000_000 + _digits8(w)
        k += 8
        n -= 8
    end
    if n > 0
        d, okt = _rundigits(_gather8(buf, k, k + n - 1), n)
        ok &= okt
        v = v * @inbounds(_POW10U64[n + 1]) + d
    end
    return (v, ok)
end

"""
    parseint64(buf, i, j) -> (Int64, rc)

Parse `buf[i:j]` as a base-10 `Int64`: optional single `-`/`+` sign, then one or
more ASCII digits, nothing else. Leading zeros are accepted (a caller's
inference policy for zero-padded identifiers lives above this). `rc` is
OVERFLOW when the digits are well-formed but exceed Int64, INVALID otherwise.
"""
@inline function parseint64(buf::AbstractVector{UInt8}, i::Int, j::Int)
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        return _parseint64exact(window, first, final)
    end
    return _parseint64exact(buf, i, j)
end

@inline function _parseint64exact(buf::AbstractVector{UInt8}, i::Int, j::Int)
    i > j && return (zero(Int64), RC_INVALID)
    @inbounds b = buf[i]
    neg = b == UInt8('-')
    (neg | (b == UInt8('+'))) && (i += 1)
    i > j && return (zero(Int64), RC_INVALID)
    # skip (but count) leading zeros so the digit-count overflow bound is exact
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
    @inbounds while i <= j && j - i >= 7
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
@inline function parseint128(buf::AbstractVector{UInt8}, i::Int, j::Int)
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        return _parseint128exact(window, first, final)
    end
    return _parseint128exact(buf, i, j)
end

@inline function _parseint128exact(buf::AbstractVector{UInt8}, i::Int, j::Int)
    i > j && return (zero(Int128), RC_INVALID)
    @inbounds b = buf[i]
    neg = b == UInt8('-')
    (neg | (b == UInt8('+'))) && (i += 1)
    i > j && return (zero(Int128), RC_INVALID)
    v, rc = _parseuint128exact(buf, i, j)
    rc == RC_OK || return (zero(Int128), rc)
    lim = UInt128(typemax(Int128)) + UInt128(neg)
    v <= lim || return (zero(Int128), RC_OVERFLOW)
    if neg
        v == lim && return (typemin(Int128), RC_OK)
        return (-Int128(v), RC_OK)
    end
    return (Int128(v), RC_OK)
end

@inline function _digitsonly(buf::AbstractVector{UInt8}, i::Int, j::Int)
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
function degroup!(scratch::Vector{UInt8}, buf::AbstractVector{UInt8}, i::Int, j::Int,
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
@inline function _hasbyte(buf::AbstractVector{UInt8}, i::Int, j::Int, b::UInt8)
    k = i
    lim = min(j, lastindex(buf)) - 7
    @inbounds while k <= lim
        _eqmask8(_load8(buf, k), b) != 0 && return true
        k += 8
    end
    @inbounds for tail in k:j
        buf[tail] == b && return true
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
parsegroupedint64(buf::AbstractVector{UInt8}, i::Int, j::Int, gm::UInt8) =
    parsegroupedint64(buf, i, j, gm, Vector{UInt8}(undef, 64))

function parsegroupedint64(buf::AbstractVector{UInt8}, i::Int, j::Int, gm::UInt8,
                           scratch::Vector{UInt8})
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        return _parsegroupedint64exact(window, first, final, gm, scratch)
    end
    return _parsegroupedint64exact(buf, i, j, gm, scratch)
end

function _parsegroupedint64exact(buf::AbstractVector{UInt8}, i::Int, j::Int,
                                 gm::UInt8, scratch::Vector{UInt8})
    i > j && return (zero(Int64), RC_INVALID)
    i0 = i                                       # the reference path re-reads the sign itself
    @inbounds b = buf[i]
    neg = b == UInt8('-')
    (neg | (b == UInt8('+'))) && (i += 1)
    i > j && return (zero(Int64), RC_INVALID)
    lastindex(buf) - j < 8 &&
        return _parsegroupedint64_slow(buf, i0, j, gm, scratch)
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
        r == 8 && j - k >= 8 && (buf[k + 8] - UInt8('0')) <= 0x09 &&
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
@noinline function _parsegroupedint64_slow(buf::AbstractVector{UInt8}, i::Int, j::Int, gm::UInt8,
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
@inline function _parseuint64(buf::AbstractVector{UInt8}, i::Int, j::Int)
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        return _parseuint64exact(window, first, final)
    end
    return _parseuint64exact(buf, i, j)
end

@inline function _parseuint64exact(buf::AbstractVector{UInt8}, i::Int, j::Int)
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
    @inbounds while i <= j && j - i >= 7
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
@inline function _parseuint128(buf::AbstractVector{UInt8}, i::Int, j::Int)
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        return _parseuint128exact(window, first, final)
    end
    return _parseuint128exact(buf, i, j)
end

@inline function _parseuint128exact(buf::AbstractVector{UInt8}, i::Int, j::Int)
    i > j && return (zero(UInt128), RC_INVALID)
    @inbounds while i <= j && buf[i] == UInt8('0')
        i += 1
    end
    i > j && return (zero(UInt128), RC_OK)
    (j - i + 1) > 39 && return (_digitsonly(buf, i, j) ? (zero(UInt128), RC_OVERFLOW) :
                                                       (zero(UInt128), RC_INVALID))
    v = zero(UInt128)
    @inbounds while i <= j && j - i >= 7
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

Exact-span base-10 integer of any width: an optional sign for signed targets,
and digits only for unsigned targets. `rc` is `RC_OK`, `RC_INVALID`, or
`RC_OVERFLOW` (well-formed digits outside `T`'s range — the code a caller's
type lattice uses to widen). Int64/UInt64 and narrower go through the SWAR
kernels; Int128/UInt128 through 8-digit checked blocks.
"""
@inline function parseint(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int) where {T <: _SIGNED}
    if T === Int128
        return parseint128(buf, i, j)
    end
    v, rc = parseint64(buf, i, j)
    T === Int64 && return (v, rc)
    rc == RC_OK || return (zero(T), rc)
    typemin(T) <= v <= typemax(T) || return (zero(T), RC_OVERFLOW)
    return (T(v), RC_OK)
end
@inline function parseint(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int) where {T <: _UNSIGNED}
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
    degroupint!(scratch, buf, i, j, groupmark, base) -> n

Copy an integer span into `scratch` and remove valid group marks. A mark must
sit between two digits that are valid in `base`; signs are copied unchanged.
Returns the same sentinel values as `degroup!`.
"""
function degroupint!(scratch::Vector{UInt8}, buf::AbstractVector{UInt8},
                     i::Int, j::Int, gm::UInt8, base::Int)
    _hasbyte(buf, i, j, gm) || return -1
    n = j - i + 1
    length(scratch) < n && resize!(scratch, max(n, 64))
    m = 0
    @inbounds for k in i:j
        b = buf[k]
        if b == gm
            if k <= i || k >= j
                return -2
            end
            prev = _digitvalue(buf[k - 1], base)
            next = _digitvalue(buf[k + 1], base)
            (prev < base && next < base) || return -2
        else
            m += 1
            scratch[m] = b
        end
    end
    return m
end

@inline function _parsegroupeddecimal(::Type{Int64}, buf::AbstractVector{UInt8},
                                      i::Int, j::Int, gm::UInt8, neg::Bool,
                                      parsesign::Bool)
    if parsesign && i <= j
        @inbounds b = buf[i]
        if b == UInt8('-') || b == UInt8('+')
            neg = b == UInt8('-')
            i += 1
        end
    end
    i > j && return (Int64(0), RC_INVALID, i)

    # A group mark must follow a digit, so validate the first byte once. This
    # invariant lets the hot loop validate only the byte after each mark.
    @inbounds (buf[i] - UInt8('0')) <= 0x09 ||
        return (Int64(0), RC_INVALID, i)

    # Leading zeros do not count toward the overflow bound. Consume them and
    # any marks between them before starting the significant-digit loop.
    k = i
    @inbounds while k <= j
        b = buf[k]
        if b == UInt8('0')
            k += 1
        elseif b == gm
            k == j && return (Int64(0), RC_INVALID, k)
            (buf[k + 1] - UInt8('0')) <= 0x09 ||
                return (Int64(0), RC_INVALID, k)
            k += 1
        else
            (b - UInt8('0')) <= 0x09 || return (Int64(0), RC_INVALID, k)
            break
        end
    end
    k > j && return (Int64(0), RC_OK, 0)

    value = UInt64(0)
    ndigits = 0
    @inbounds while k <= j
        b = buf[k]
        bad = k
        if b == gm
            k == j && return (Int64(0), RC_INVALID, k)
            k += 1
            b = buf[k]
            bad = k - 1
        end
        digit = b - UInt8('0')
        digit <= 0x09 || return (Int64(0), RC_INVALID, bad)
        ndigits += 1
        ndigits <= 19 && (value = 10value + digit)
        k += 1
    end

    ndigits > 19 && return (Int64(0), RC_OVERFLOW, 0)
    limit = neg ? UInt64(9223372036854775808) : UInt64(9223372036854775807)
    value > limit && return (Int64(0), RC_OVERFLOW, 0)
    if neg
        value == limit && return (typemin(Int64), RC_OK, 0)
        return (-Int64(value), RC_OK, 0)
    end
    return (Int64(value), RC_OK, 0)
end

@generated function _parsegroupeddecimal(::Type{T}, buf::AbstractVector{UInt8},
                                         i::Int, j::Int, gm::UInt8, neg::Bool,
                                         parsesign::Bool) where
                                         {T <: Union{_SIGNED, _UNSIGNED}}
    A = sizeof(T) <= 8 ? UInt64 : UInt128
    signed = T <: _SIGNED
    poslimit = A(typemax(T))
    neglimit = signed ? poslimit + one(A) : zero(A)
    maxdigits = ndigits(signed ? neglimit : poslimit)
    poscutoff, poscutlim = divrem(poslimit, A(10))
    negcutoff, negcutlim = signed ? divrem(neglimit, A(10)) : (zero(A), zero(A))
    return :(_parsegroupeddecimal(T, $A, Val($maxdigits), $poscutoff, $poscutlim,
                                  $negcutoff, $negcutlim, Val($signed), buf, i, j,
                                  gm, neg, parsesign))
end

@inline function _parsegroupeddecimal(::Type{T}, ::Type{A}, ::Val{MAXDIGITS},
                                      poscutoff::A, poscutlim::A,
                                      negcutoff::A, negcutlim::A, ::Val{SIGNED},
                                      buf::AbstractVector{UInt8}, i::Int, j::Int,
                                      gm::UInt8, neg::Bool,
                                      parsesign::Bool) where
                                      {T <: Union{_SIGNED, _UNSIGNED},
                                       A <: Union{UInt64, UInt128}, MAXDIGITS, SIGNED}
    if parsesign && i <= j
        @inbounds b = buf[i]
        if b == UInt8('-') || b == UInt8('+')
            SIGNED || return (zero(T), RC_INVALID, i)
            neg = b == UInt8('-')
            i += 1
        end
    end
    i > j && return (zero(T), RC_INVALID, i)

    @inbounds (buf[i] - UInt8('0')) <= 0x09 ||
        return (zero(T), RC_INVALID, i)

    k = i
    @inbounds while k <= j
        b = buf[k]
        if b == UInt8('0')
            k += 1
        elseif b == gm
            k == j && return (zero(T), RC_INVALID, k)
            (buf[k + 1] - UInt8('0')) <= 0x09 ||
                return (zero(T), RC_INVALID, k)
            k += 1
        else
            (b - UInt8('0')) <= 0x09 || return (zero(T), RC_INVALID, k)
            break
        end
    end
    k > j && return (zero(T), RC_OK, 0)

    value = zero(A)
    ndigits = 0
    overflow = false
    cutoff = neg ? negcutoff : poscutoff
    cutlim = neg ? negcutlim : poscutlim
    @inbounds while k <= j
        b = buf[k]
        bad = k
        if b == gm
            k == j && return (zero(T), RC_INVALID, k)
            k += 1
            b = buf[k]
            bad = k - 1
        end
        digit = b - UInt8('0')
        digit <= 0x09 || return (zero(T), RC_INVALID, bad)
        ndigits += 1
        if ndigits < MAXDIGITS
            value = A(10) * value + A(digit)
        elseif ndigits == MAXDIGITS
            if value > cutoff || (value == cutoff && digit > cutlim)
                overflow = true
            else
                value = A(10) * value + A(digit)
            end
        else
            overflow = true
        end
        k += 1
    end

    overflow && return (zero(T), RC_OVERFLOW, 0)
    if SIGNED && neg
        value == A(typemax(T)) + one(A) && return (typemin(T), RC_OK, 0)
        return (-T(value), RC_OK, 0)
    end
    return (T(value), RC_OK, 0)
end

function _parsegroupedint(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                          gm::UInt8, base::Int, neg::Bool,
                          parsesign::Bool) where {T <: Union{_SIGNED, _UNSIGNED}}
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        result = _parsegroupedintexact(T, window, first, final, gm, base, neg,
                                       parsesign)
        return _restoreexactposition(window, result)
    end
    return _parsegroupedintexact(T, buf, i, j, gm, base, neg, parsesign)
end

function _parsegroupedintexact(::Type{T}, buf::AbstractVector{UInt8}, i::Int,
                               j::Int, gm::UInt8, base::Int, neg::Bool,
                               parsesign::Bool) where {T <: Union{_SIGNED, _UNSIGNED}}
    base == 10 && return _parsegroupeddecimal(T, buf, i, j, gm, neg, parsesign)
    if parsesign && i <= j
        @inbounds b = buf[i]
        if b == UInt8('-') || b == UInt8('+')
            T <: _UNSIGNED && return (zero(T), RC_INVALID, i)
            neg = b == UInt8('-')
            i += 1
        end
    end
    i > j && return (zero(T), RC_INVALID, i)
    A = sizeof(T) <= 8 ? UInt64 : UInt128
    limit = T <: _SIGNED ? A(typemax(T)) + A(neg) : A(typemax(T))
    abase = A(base)
    cutoff, cutlim = divrem(limit, abase)
    value = zero(A)
    sawdigit = false
    prevdigit = false
    overflow = false
    @inbounds for k in i:j
        b = buf[k]
        if b == gm
            if !prevdigit || k == j
                return (zero(T), RC_INVALID, k)
            end
            nextdigit = _digitvalue(buf[k + 1], base)
            nextdigit < base || return (zero(T), RC_INVALID, k)
            prevdigit = false
            continue
        end
        digit = _digitvalue(b, base)
        digit < base || return (zero(T), RC_INVALID, k)
        sawdigit = true
        prevdigit = true
        if !overflow
            d = A(digit)
            if value > cutoff || (value == cutoff && d > cutlim)
                overflow = true
            else
                value = value * abase + d
            end
        end
    end
    sawdigit || return (zero(T), RC_INVALID, i)
    overflow && return (zero(T), RC_OVERFLOW, 0)
    if T <: _SIGNED && neg
        value == limit && return (typemin(T), RC_OK, 0)
        return (-T(value), RC_OK, 0)
    end
    return (T(value), RC_OK, 0)
end

parsegroupedint(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                gm::UInt8, base::Int) where {T <: Union{_SIGNED, _UNSIGNED}} =
    _parsegroupedint(T, buf, i, j, gm, base, false, true)

parsegroupedprefixedint(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                        gm::UInt8, base::Int, neg::Bool) where {T <: _SIGNED} =
    _parsegroupedint(T, buf, i, j, gm, base, neg, false)

"""
    parseint(T, buf, i, j, base) -> (T, rc, badpos)

Integer in `base` (2 ≤ base ≤ 62; base 10 takes the SWAR path above), any
width; `badpos` is the position of the offending byte when `rc == RC_INVALID`
(0 otherwise) so the caller can name it the way `Base.parse` does. Overflow
is detected with checked arithmetic.
"""
function parseint(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                  base::Int) where {T <: Union{_SIGNED, _UNSIGNED}}
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        result = _parseradixint(T, window, first, final, base)
        return _restoreexactposition(window, result)
    end
    return _parseradixint(T, buf, i, j, base)
end

function _parseradixint(::Type{T}, buf::AbstractVector{UInt8}, i::Int, j::Int,
                        base::Int) where {T <: Union{_SIGNED, _UNSIGNED}}
    if base == 10
        v, rc = parseint(T, buf, i, j)
        return (v, rc, rc == RC_INVALID ? _firstbad10(buf, i, j) : 0)
    end
    i > j && return (zero(T), RC_INVALID, i)
    orig = i
    neg = false
    @inbounds begin
        b = buf[i]
        if b == UInt8('-') || b == UInt8('+')
            T <: _UNSIGNED && return (zero(T), RC_INVALID, i)   # Base: a sign is an invalid digit for unsigned
            neg = b == UInt8('-')
            i += 1
        end
    end
    i > j && return (zero(T), RC_INVALID, orig) # sign only: the sign is the offending byte
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

# A radix prefix sits between the sign and the digits, so the ordinary
# exact-span kernel cannot see both at once. Parse a negative magnitude as the
# corresponding unsigned type, then apply the one-extra-value signed bound so
# `-0x80` and its wider forms produce `typemin(T)`.
@inline function parseprefixedint(::Type{T}, buf::AbstractVector{UInt8},
                                  i::Int, j::Int, base::Int,
                                  neg::Bool) where {T <: _SIGNED}
    # Base rejects a second sign between the radix prefix and the digits, so
    # the sign grammar must not run again on the digit span
    if i <= j
        @inbounds b = buf[i]
        (b == UInt8('-') || b == UInt8('+')) && return (zero(T), RC_INVALID, i)
    end
    neg || return parseint(T, buf, i, j, base)
    U = unsigned(T)
    mag, rc, bad = parseint(U, buf, i, j, base)
    rc == RC_OK || return (zero(T), rc, bad)
    limit = U(typemax(T)) + one(U)
    mag > limit && return (zero(T), RC_OVERFLOW, 0)
    mag == limit && return (typemin(T), RC_OK, 0)
    return (-T(mag), RC_OK, 0)
end

# position of the first byte that is not part of a base-10 integer (for the
# error message); i when the span is empty/sign-only
function _firstbad10(buf::AbstractVector{UInt8}, i::Int, j::Int)
    k = i
    @inbounds if k <= j && (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
        k += 1
    end
    @inbounds while k <= j && buf[k] - UInt8('0') <= 0x09
        k += 1
    end
    return k <= j ? k : i
end

# --- prefix parsing ------------------------------------------------------------
#
# `parsenext` needs both the value and the first byte after it. Keep that work
# in one pass: the same loop recognizes the integer grammar, validates group
# marks, accumulates the magnitude, and records overflow. Span-exact kernels
# above remain separate because their SWAR paths are faster when the end is
# already known.

@inline _normalizebase(::Nothing) = nothing
@inline function _normalizebase(base)
    base isa Integer ||
        throw(ArgumentError("base must be an integer, got $(repr(base))"))
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

# Prefixes are recognized only when no explicit base is present. They follow
# an optional sign and use lowercase `0x`, `0o`, or `0b`, matching Base.
@inline function _intprefix(buf::AbstractVector{UInt8}, i::Int, j::Int,
                            base::Union{Nothing, Int})
    base === nothing || return (i, base, false)
    k = i
    @inbounds if k <= j && (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
        k += 1
    end
    @inbounds if k < j && buf[k] == UInt8('0')
        c = buf[k + 1]
        b = c == UInt8('x') ? 16 : c == UInt8('o') ? 8 :
            c == UInt8('b') ? 2 : 0
        b != 0 && return (k + 2, b, true)
    end
    return (i, 10, false)
end

@inline function _integerprefixconfig(::Val{SIGNED}, buf::AbstractVector{UInt8},
                                      pos::Int, last::Int, base,
                                      groupmark) where {SIGNED}
    bkw = _normalizebase(base)
    @inbounds if !SIGNED &&
                 (buf[pos] == UInt8('-') || buf[pos] == UInt8('+'))
        return (pos, 10, nothing, false, false)
    end
    dstart, b, prefixed = _intprefix(buf, pos, last, bkw)
    if prefixed
        @inbounds firstdigit = dstart <= last ? _digitvalue(buf[dstart], b) : 0xff
        if firstdigit >= b
            dstart, b, prefixed = pos, 10, false
        end
    end
    gm = _intgroupbyte(groupmark, b)
    neg = false
    k = prefixed ? dstart : pos
    @inbounds if prefixed
        neg = SIGNED && buf[pos] == UInt8('-')
    elseif SIGNED && k <= last &&
           (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
        neg = buf[k] == UInt8('-')
        k += 1
    end
    return (k, b, gm, neg, true)
end

@inline @generated function _parseintprefix(::Type{T}, buf::AbstractVector{UInt8},
                                            pos::Int, last::Int, base,
                                            groupmark) where
                                            {T <: Union{_SIGNED, _UNSIGNED}}
    A = sizeof(T) <= 8 ? UInt64 : UInt128
    signed = T <: _SIGNED
    return :(_parseintprefix(T, $A, Val($signed), buf, pos, last, base,
                             groupmark))
end

@inline function _parseintprefix(::Type{T}, ::Type{A}, ::Val{SIGNED},
                                 buf::AbstractVector{UInt8}, pos::Int,
                                 last::Int, base, groupmark) where
                                 {T <: Union{_SIGNED, _UNSIGNED},
                                  A <: Union{UInt64, UInt128}, SIGNED}
    k, b, gm, neg, valid = _integerprefixconfig(Val(SIGNED), buf, pos, last,
                                                base, groupmark)
    valid || return (zero(T), pos, RC_INVALID)

    if b == 10 && gm === nothing &&
       (A === UInt128 || T === Int64 || T === UInt64)
        return _parseintprefixdecimal(T, Val(SIGNED), buf, pos, k, last, neg)
    elseif b == 10 && gm !== nothing && (T === Int64 || T === UInt64)
        return _parseintprefixgroupeddecimal64(T, Val(SIGNED), buf, pos, k,
                                               last, neg, gm)
    end

    limit = SIGNED ? A(typemax(T)) + A(neg) : A(typemax(T))
    abase = A(b)
    cutoff, cutlim = divrem(limit, abase)
    value = zero(A)
    sawdigit = false
    overflow = false

    @inbounds while k <= last
        digit = _digitvalue(buf[k], b)
        if digit < b
            sawdigit = true
            if !overflow
                d = A(digit)
                if value > cutoff || (value == cutoff && d > cutlim)
                    overflow = true
                else
                    value = value * abase + d
                end
            end
            k += 1
        elseif gm !== nothing && sawdigit && buf[k] == gm && k < last &&
               _digitvalue(buf[k + 1], b) < b
            k += 1
        else
            break
        end
    end

    sawdigit || return (zero(T), pos, RC_INVALID)
    overflow && return (zero(T), k, RC_OVERFLOW)
    if SIGNED && neg
        value == limit && return (typemin(T), k, RC_OK)
        return (-T(value), k, RC_OK)
    end
    return (T(value), k, RC_OK)
end

# Decimal 64- and 128-bit prefixes use the same eight-digit SWAR gather as the
# exact-span kernels while advancing the token end. This keeps recognition and
# conversion in one pass, but avoids a wide cutoff and multiply for every
# digit on the common ungrouped path.
@inline @generated function _parseintprefixdecimal(
        ::Type{T}, ::Val{SIGNED}, buf::AbstractVector{UInt8}, pos::Int,
        k::Int, last::Int, neg::Bool) where
        {T <: Union{Int64, UInt64, Int128, UInt128}, SIGNED}
    A = sizeof(T) <= 8 ? UInt64 : UInt128
    poslimit = A(typemax(T))
    neglimit = SIGNED ? poslimit + one(A) : zero(A)
    poscutoff, poscutlim = divrem(poslimit, A(10))
    negcutoff, negcutlim = divrem(neglimit, A(10))
    posblockcutoff, posblockcutlim = divrem(poslimit, A(100_000_000))
    negblockcutoff, negblockcutlim = divrem(neglimit, A(100_000_000))
    return :(_parseintprefixdecimal(
        T, $A, Val($SIGNED), buf, pos, k, last, neg,
        $(negcutoff), $(negcutlim), $(poscutoff), $(poscutlim),
        $(negblockcutoff), $(negblockcutlim), $(posblockcutoff),
        $(posblockcutlim)))
end

@inline function _parseintprefixdecimal(::Type{T}, ::Type{A}, ::Val{SIGNED},
                                        buf::AbstractVector{UInt8},
                                        pos::Int, k::Int, last::Int,
                                        neg::Bool,
                                        negcutoff::A, negcutlim::A,
                                        poscutoff::A, poscutlim::A,
                                        negblockcutoff::A,
                                        negblockcutlim::A,
                                        posblockcutoff::A,
                                        posblockcutlim::A) where
                                        {T <: Union{Int64, UInt64, Int128, UInt128},
                                         A <: Union{UInt64, UInt128}, SIGNED}
    cutoff = neg ? negcutoff : poscutoff
    cutlim = neg ? negcutlim : poscutlim
    blockcutoff = neg ? negblockcutoff : posblockcutoff
    blockcutlim = neg ? negblockcutlim : posblockcutlim
    value = zero(A)
    sawdigit = false
    overflow = false

    @inbounds while k <= last && last - k >= 7
        w = _load8(buf, k)
        if _alldigits8(w)
            sawdigit = true
            if !overflow
                digits = A(_digits8(w))
                if value > blockcutoff ||
                   (value == blockcutoff && digits > blockcutlim)
                    overflow = true
                else
                    value = value * A(100_000_000) + digits
                end
            end
            k += 8
        else
            # The first flagged lane is exact. Finish its preceding digit
            # prefix scalarly, then leave the non-digit byte unconsumed.
            stop = k + _firstnondigit8(w)
            while k < stop
                digit = A(buf[k] - UInt8('0'))
                sawdigit = true
                if !overflow
                    if value > cutoff || (value == cutoff && digit > cutlim)
                        overflow = true
                    else
                        value = A(10) * value + digit
                    end
                end
                k += 1
            end
            break
        end
    end

    @inbounds while k <= last
        digit = buf[k] - UInt8('0')
        digit <= 0x09 || break
        sawdigit = true
        if !overflow
            d = A(digit)
            if value > cutoff || (value == cutoff && d > cutlim)
                overflow = true
            else
                value = A(10) * value + d
            end
        end
        k += 1
    end

    sawdigit || return (zero(T), pos, RC_INVALID)
    overflow && return (zero(T), k, RC_OVERFLOW)
    if SIGNED && neg
        value == A(typemax(T)) + one(A) &&
            return (typemin(T), k, RC_OK)
        return (-T(value), k, RC_OK)
    end
    return (T(value), k, RC_OK)
end

# Grouped decimal Int64/UInt64 prefixes can defer their range check until the
# last significant digit: nineteen decimal digits always fit the UInt64
# accumulator, and UInt64 needs a cutoff check only for its twentieth digit.
# The loop still owns grammar recognition and continues to the token end after
# overflow, so this is not a scan followed by a second parse.
@inline @generated function _parseintprefixgroupeddecimal64(
        ::Type{T}, ::Val{SIGNED}, buf::AbstractVector{UInt8}, pos::Int,
        k::Int, last::Int, neg::Bool, gm::UInt8) where
        {T <: Union{Int64, UInt64}, SIGNED}
    poslimit = UInt64(typemax(T))
    neglimit = SIGNED ? poslimit + one(UInt64) : zero(UInt64)
    poscutoff, poscutlim = divrem(poslimit, UInt64(10))
    return :(_parseintprefixgroupeddecimal64(
        T, Val($SIGNED), buf, pos, k, last, neg, gm, $(poslimit),
        $(neglimit), $(poscutoff), $(poscutlim)))
end

@inline function _parseintprefixgroupeddecimal64(
        ::Type{T}, ::Val{SIGNED}, buf::AbstractVector{UInt8}, pos::Int,
        k::Int, last::Int, neg::Bool, gm::UInt8, poslimit::UInt64,
        neglimit::UInt64, poscutoff::UInt64, poscutlim::UInt64) where
        {T <: Union{Int64, UInt64}, SIGNED}
    value = zero(UInt64)
    ndigits = 0
    sawdigit = false
    overflow = false

    @inbounds while k <= last
        digit = buf[k] - UInt8('0')
        if digit <= 0x09
            sawdigit = true
            if !overflow && (ndigits != 0 || digit != 0)
                ndigits += 1
                if SIGNED
                    if ndigits <= 19
                        value = UInt64(10) * value + UInt64(digit)
                    else
                        overflow = true
                    end
                elseif ndigits < 20
                    value = UInt64(10) * value + UInt64(digit)
                elseif ndigits == 20
                    if value > poscutoff ||
                       (value == poscutoff && digit > poscutlim)
                        overflow = true
                    else
                        value = UInt64(10) * value + UInt64(digit)
                    end
                else
                    overflow = true
                end
            end
            k += 1
        elseif sawdigit && buf[k] == gm && k < last &&
               (buf[k + 1] - UInt8('0')) <= 0x09
            k += 1
        else
            break
        end
    end

    sawdigit || return (zero(T), pos, RC_INVALID)
    limit = neg ? neglimit : poslimit
    (overflow || value > limit) && return (zero(T), k, RC_OVERFLOW)
    if SIGNED && neg
        value == neglimit && return (typemin(T), k, RC_OK)
        return (-T(value), k, RC_OK)
    end
    return (T(value), k, RC_OK)
end
