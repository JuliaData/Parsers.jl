# =============================================================================
# arbitrary precision & identifiers — BigInt / BigFloat / UUID
#
# The self-contained mandate covers the PARSING: span validation, digit
# decomposition, binary extraction, and rounding are all ours. BigInt/BigFloat
# are Base types whose arithmetic is GMP/MPFR by definition — we hand them a
# finished, correctly-rounded value (never a string), so mpz_set_str /
# mpfr_strtofr are never involved.
# =============================================================================

# Powers of five for the BigFloat scaling path, built at precompile time.
# Covers every exponent reachable from ~150 significant digits around the
# double range; rarer exponents compute fresh. Entries are READ-ONLY — the
# scaling code must never hand them to an in-place GMP op's output slot.
for f in (:set_si!, :mul!, :mul_ui!, :add_ui!, :mul_2exp!, :tdiv_qr!,
          :fdiv_q_2exp!, :tstbit, :scan1, :sizeinbase, :pow_ui, :neg!, :limbs_finish!,
          :realloc2!)
    isdefined(Base.GMP.MPZ, f) ||
        error("Parsers requires Base.GMP.MPZ.$f (Julia internals moved?)")
end

const _POW5BIG = [BigInt(5)^k for k in 0:512]
@inline _pow5big(k::Int) = k <= 512 ? @inbounds(_POW5BIG[k + 1]) : BigInt(5)^k

"""
    BigWork()

Reusable workspace for `parsebigfloat`: the two BigInt temporaries (mantissa
accumulator and division remainder) live here so a column loop allocates them
once instead of per value — GMP objects are finalizer-registered, and two
fewer registrations per value is most of the distance to mpfr_strtofr's
single-allocation profile. Never share one across concurrent tasks.
"""
mutable struct BigWork
    const M::BigInt
    const R::BigInt
end
BigWork() = BigWork(BigInt(0), BigInt(0))

# One workspace per thread, handed out by atomic swap: a task takes the slot's
# workspace and leaves `nothing`, so a task that migrates threads mid-parse or
# an interleaved task on the same thread can never share it — they allocate a
# fresh one instead, and the slot keeps whichever workspace comes back last.
mutable struct BigWorkSlot
    @atomic ws::Union{Nothing, BigWork}
end
const _BIGWORKSLOTS = BigWorkSlot[]

@inline function _takebigwork()
    tid = Threads.threadid()
    tid <= length(_BIGWORKSLOTS) || return BigWork()
    slot = @inbounds _BIGWORKSLOTS[tid]
    ws = @atomicswap :acquire_release slot.ws = nothing
    return ws === nothing ? BigWork() : ws
end

@inline function _givebigwork(ws::BigWork)
    tid = Threads.threadid()
    tid <= length(_BIGWORKSLOTS) || return nothing
    slot = @inbounds _BIGWORKSLOTS[tid]
    @atomic :release slot.ws = ws
    return nothing
end

function __init__()
    append!(_BIGWORKSLOTS, BigWorkSlot(nothing) for _ in 1:Threads.maxthreadid())
    return nothing
end

# One correctly-rounded store into a fresh BigFloat: our prec-bit integer
# mantissa is exact under mpfr_set_z, the 2^e scale is exact under mul_2si,
# and the sign flips in place — one MPFR allocation, no ldexp/unary-minus
# temporaries.
function _assemble(M::BigInt, e::Int, neg::Bool, prec::Int)
    v = BigFloat(; precision=prec)
    ccall((:mpfr_set_z, Base.MPFR.libmpfr), Int32,
          (Ref{BigFloat}, Ref{BigInt}, Int32), v, M, 0)
    ccall((:mpfr_mul_2si, Base.MPFR.libmpfr), Int32,
          (Ref{BigFloat}, Ref{BigFloat}, Clong, Int32), v, v, e, 0)
    neg && ccall((:mpfr_neg, Base.MPFR.libmpfr), Int32,
                 (Ref{BigFloat}, Ref{BigFloat}, Int32), v, v, 0)
    return v
end

@inline _roundup(::RoundingMode{:Nearest}, neg, rbit, sticky, odd) =
    rbit && (sticky || odd)
@inline _roundup(::RoundingMode{:ToZero}, neg, rbit, sticky, odd) = false
@inline _roundup(::RoundingMode{:FromZero}, neg, rbit, sticky, odd) = rbit || sticky
@inline _roundup(::RoundingMode{:Up}, neg, rbit, sticky, odd) =
    !neg && (rbit || sticky)
@inline _roundup(::RoundingMode{:Down}, neg, rbit, sticky, odd) =
    neg && (rbit || sticky)
_roundup(mode::RoundingMode, neg, rbit, sticky, odd) =
    throw(ArgumentError("BigFloat does not support rounding mode $mode"))
# MPFR's enum keeps the public path free of a RoundingMode type union.
@inline function _roundup(mode::Base.MPFR.MPFRRoundingMode, neg, rbit, sticky, odd)
    mode == Base.MPFR.MPFRRoundNearest && return rbit && (sticky || odd)
    mode == Base.MPFR.MPFRRoundToZero && return false
    mode == Base.MPFR.MPFRRoundFromZero && return rbit || sticky
    mode == Base.MPFR.MPFRRoundUp && return !neg && (rbit || sticky)
    mode == Base.MPFR.MPFRRoundDown && return neg && (rbit || sticky)
    throw(ArgumentError("BigFloat does not support rounding mode $mode"))
end
const _ROUNDING = Union{RoundingMode, Base.MPFR.MPFRRoundingMode}

# Round the nonnegative integer magnitude `M * 2^e2` once at `prec` bits, then
# apply the sign. `sticky` states that nonzero bits exist below M's low bit.
function _roundbig!(M::BigInt, e2::Int, neg::Bool, prec::Int,
                    mode::_ROUNDING, sticky::Bool=false)
    MPZ = Base.GMP.MPZ
    nb = Int(MPZ.sizeinbase(M, 2))
    if nb > prec
        drop = nb - prec
        rbit = MPZ.tstbit(M, (drop - 1) % Culong)
        sticky = sticky || (drop > 1 && Int(MPZ.scan1(M, 0)) < drop - 1)
        MPZ.fdiv_q_2exp!(M, drop % Culong)
        odd = MPZ.tstbit(M, Culong(0))
        if _roundup(mode, neg, rbit, sticky, odd)
            MPZ.add_ui!(M, 1)
            if Int(MPZ.sizeinbase(M, 2)) > prec
                MPZ.fdiv_q_2exp!(M, Culong(1))
                drop += 1
            end
        end
        return _assemble(M, Base.checked_add(e2, drop), neg, prec)
    end
    # Decimal division always keeps guard bits, so a sticky remainder cannot
    # reach this exact branch. Validate the mode here as well for exact inputs.
    _roundup(mode, neg, false, false, false)
    return _assemble(M, e2, neg, prec)
end

# --- decimal digits to limbs, in Julia --------------------------------------------
# Digits gather eight at a time into base-10^19 chunks, and each chunk
# multiply-accumulates into the result's own limb storage. GMP only ever sees
# finished limbs (mpz_limbs_finish), never a digit string.
const _CHUNK19 = UInt64(10)^19

# limbs ← limbs × mult + add over `size` little-endian limbs; the new size
@inline function _mulacc!(limbs::Ptr{UInt64}, size::Int, mult::UInt64, add::UInt64)
    carry = add
    for l in 1:size
        p = UInt128(unsafe_load(limbs, l)) * mult + carry
        unsafe_store!(limbs, p % UInt64, l)
        carry = (p >> 64) % UInt64
    end
    if carry != 0
        size += 1
        unsafe_store!(limbs, carry, size)
    end
    return size
end

# Limbs that hold `ndig` decimal digits: ⌈ndig·log2(10)⌉ bits, rounded up.
@inline _limbsfordigits(ndig::Int) = (((ndig * 3402) >> 10) + 64) >> 6

# Feed buf[k : stop-1] into 19-digit chunks; `acc`/`nacc` carry a partial
# chunk between calls so a decimal point can split a digit run. Completed
# chunks flush into the limbs. Returns (size, acc, nacc, ok).
@inline function _feeddigits!(limbs::Ptr{UInt64}, size::Int, acc::UInt64, nacc::Int,
                              buf::AbstractVector{UInt8}, k::Int, stop::Int)
    while k < stop
        t = min(19 - nacc, stop - k)
        v, ok = _digits19(buf, k, t)
        ok || return (size, acc, nacc, false)
        acc = acc * @inbounds(_POW10U64[t + 1]) + v
        nacc += t
        k += t
        if nacc == 19
            size = _mulacc!(limbs, size, _CHUNK19, acc)
            acc = zero(UInt64)
            nacc = 0
        end
    end
    return (size, acc, nacc, true)
end

@inline function _flushdigits!(limbs::Ptr{UInt64}, size::Int, acc::UInt64, nacc::Int)
    nacc == 0 && return size
    return _mulacc!(limbs, size, @inbounds(_POW10U64[nacc + 1]), acc)
end

"""
    parsebigint(buf, i, j) -> (BigInt, rc)

Exact-span BigInt: sign and decimal digits only (the strict integer grammar,
same as `parseint64` without the width limit). The digits become base-10^19
chunks that multiply-accumulate straight into the BigInt's limbs, so the only
GMP involvement is the allocation and the final size update.
"""
function parsebigint(buf::AbstractVector{UInt8}, i::Int, j::Int)
    i > j && return (BigInt(0), RC_INVALID)
    neg = false
    @inbounds begin
        b = buf[i]
        if b == UInt8('-') || b == UInt8('+')
            neg = b == UInt8('-')
            i += 1
        end
    end
    i > j && return (BigInt(0), RC_INVALID)
    @inbounds while i < j && buf[i] == UInt8('0')
        i += 1
    end
    nlimbs = _limbsfordigits(j - i + 1)
    big = BigInt(; nbits=64 * nlimbs)
    GC.@preserve big begin
        limbs = big.d
        size, acc, nacc, ok = _feeddigits!(limbs, 0, zero(UInt64), 0, buf, i, j + 1)
        ok || return (BigInt(0), RC_INVALID)
        size = _flushdigits!(limbs, size, acc, nacc)
    end
    Base.GMP.MPZ.limbs_finish!(big, neg ? -size : size)
    return (big, RC_OK)
end

"""
    parsebigint(buf, i, j, base) -> (BigInt, rc, badpos)

Exact-span arbitrary-radix BigInt parser for bases 2 through 62. The digit
mapping is identical to [`parseint`](@ref). `badpos` identifies an invalid
digit; arbitrary precision means this overload cannot return `RC_OVERFLOW`.
"""
function parsebigint(buf::AbstractVector{UInt8}, i::Int, j::Int, base::Int)
    2 <= base <= 62 || throw(ArgumentError("base must be between 2 and 62"))
    i > j && return (BigInt(0), RC_INVALID, i)
    neg = false
    @inbounds begin
        b = buf[i]
        if b == UInt8('-') || b == UInt8('+')
            neg = b == UInt8('-')
            i += 1
        end
    end
    i > j && return (BigInt(0), RC_INVALID, i)
    big = BigInt(0)
    MPZ = Base.GMP.MPZ
    @inbounds while i <= j
        d = _digitvalue(buf[i], base)
        (d == 0xff || d >= base) && return (BigInt(0), RC_INVALID, i)
        MPZ.mul_ui!(big, base % UInt)
        MPZ.add_ui!(big, d % UInt)
        i += 1
    end
    neg && MPZ.neg!(big)
    return (big, RC_OK, 0)
end

"""
    parsebigfloat(buf, i, j, decimal=UInt8('.'); prec=precision(BigFloat)) -> (BigFloat, rc)

Correctly rounded BigFloat at `prec` bits, with `rounding` defaulting to the
current MPFR rounding mode. It accepts the decimal and hexadecimal grammar and
special spellings of `parsefloat64`. The high-precision decimal machinery from
tier 3 generalizes: scale the exact decimal into [1, 2), generate `prec`
binary digits, round once with the sticky bit. MPFR only STORES the result —
the value is assembled from an exactly-representable prec-bit integer and an
exact `ldexp`, so this layer performs the single rounding itself.

Prove-out range bound: decimal magnitudes beyond ~10^±65536 return
RC_OVERFLOW (binary scaling is bit-at-a-time here; the upstream Parsers form
gets power-of-ten jump tables the way Eisel-Lemire's POW5 works). No
subnormal handling is needed inside that range — BigFloat's exponent field
dwarfs it.
"""
function parsebigfloat(buf::AbstractVector{UInt8}, i::Int, j::Int, decimal::UInt8=UInt8('.');
                       prec::Int=precision(BigFloat),
                       rounding::RoundingMode=Base.Rounding.rounding(BigFloat))
    ws = _takebigwork()
    result = parsebigfloat(buf, i, j, decimal, ws; prec, rounding)
    _givebigwork(ws)
    return result
end

function parsebigfloat(buf::AbstractVector{UInt8}, i::Int, j::Int,
                       decimal::UInt8, ws::BigWork; prec::Int=precision(BigFloat),
                       rounding::RoundingMode=Base.Rounding.rounding(BigFloat))
    prec >= 2 || throw(ArgumentError("prec must be ≥ 2"))
    _roundup(rounding, false, false, false, false)  # validate even for zero/specials
    k = i
    @inbounds if k <= j && (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
        k += 1
    end
    @inbounds if k + 1 <= j && buf[k] == UInt8('0') && _lower(buf[k + 1]) == UInt8('x')
        return _parsebigfloathex(buf, i, j, ws; prec, rounding)
    end
    sp, matched = _matchspecial(buf, i, j)
    matched && return (BigFloat(sp; precision=prec), RC_OK)
    parts, rc = _decompose(buf, i, j, decimal)
    rc == RC_OK || return (BigFloat(0; precision=prec), rc)
    return _bigfloatfromparts(buf, i, j, decimal, parts, ws, prec, rounding)
end

# Convert decomposed decimal parts: every significant digit into the workspace
# BigInt as limbs, one exact power-of-ten scaling, one rounding at `prec`.
function _bigfloatfromparts(buf::AbstractVector{UInt8}, i::Int, j::Int, decimal::UInt8,
                            parts::DecParts, ws::BigWork, prec::Int, rounding::_ROUNDING)
    if parts.mant == 0
        z = BigFloat(0; precision=prec)
        return (parts.neg ? -z : z, RC_OK)
    end
    # every significant digit into a BigInt (the parsebigint accumulator, with
    # the decimal byte skipped), tracking the true power of ten. The range test
    # uses the full mantissa exponent, not DecParts.exp10 (which is relative to
    # its truncated 19-digit mantissa).
    M = ws.M
    q, inrange = _bigmantissa!(M, buf, i, Int(parts.digstart), j, decimal)
    inrange || return (BigFloat(0; precision=prec), RC_OVERFLOW)
    # value = M × 10^q = M × 5^q × 2^q — pure integer scaling, one rounding:
    #   q ≥ 0: N = M·5^q is exact and value = N × 2^q
    #   q < 0: N = ⌊M·2^s / 5^-q⌋ with s sized so N keeps ≥ prec+2 bits; the
    #          remainder is the sticky. value = N × 2^(q-s)
    # in-place GMP throughout: M becomes N; rounding decisions read bits
    # without materializing masks (tstbit/scan1); ~4 allocations per value
    MPZ = Base.GMP.MPZ
    sticky = false
    if q >= 0
        q > 0 && MPZ.mul!(M, _pow5big(q))
        e2 = q
    else
        k = -q
        d5 = _pow5big(k)
        s = max(0, prec + 3 + Int(MPZ.sizeinbase(d5, 2)) - Int(MPZ.sizeinbase(M, 2)))
        MPZ.mul_2exp!(M, s % Culong)
        R = ws.R
        MPZ.tdiv_qr!(M, R, M, d5)
        sticky = !iszero(R)
        e2 = q - s
    end
    return (_roundbig!(M, e2, parts.neg, prec, rounding, sticky), RC_OK)
end

# Arbitrary-precision C99 hexadecimal float. Hexadecimal input is already a
# binary rational, so collecting every nibble into a BigInt and applying one
# `_roundbig!` operation gives exact MPFR-compatible rounding without a string
# conversion.
function _parsebigfloathex(buf::AbstractVector{UInt8}, i::Int, j::Int,
                           ws::BigWork; prec::Int, rounding::RoundingMode)
    neg = false
    @inbounds begin
        b = buf[i]
        neg = b == UInt8('-')
        (neg || b == UInt8('+')) && (i += 1)
        (i + 1 <= j && buf[i] == UInt8('0') && _lower(buf[i + 1]) == UInt8('x')) ||
            return (BigFloat(0; precision=prec), RC_INVALID)
    end
    i += 2
    M = ws.M
    MPZ = Base.GMP.MPZ
    MPZ.set_si!(M, 0)
    sawdigit = false
    infrac = false
    nfrac = 0
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
        if infrac
            if nfrac == typemax(Int)
                z = BigFloat(0; precision=prec)
                return (neg ? -z : z, RC_UNDERFLOW)
            end
            nfrac += 1
        end
        MPZ.mul_2exp!(M, Culong(4))
        MPZ.add_ui!(M, d % UInt)
        i += 1
    end
    sawdigit || return (BigFloat(0; precision=prec), RC_INVALID)
    pexp = 0
    eneg = false
    expoverflow = false
    @inbounds if i <= j
        _lower(buf[i]) == UInt8('p') || return (BigFloat(0; precision=prec), RC_INVALID)
        i += 1
        if i <= j
            b = buf[i]
            eneg = b == UInt8('-')
            (eneg || b == UInt8('+')) && (i += 1)
        end
        i > j && return (BigFloat(0; precision=prec), RC_INVALID)
        while i <= j
            d = buf[i] - UInt8('0')
            d > 0x09 && return (BigFloat(0; precision=prec), RC_INVALID)
            if !expoverflow
                if pexp > (typemax(Int) - Int(d)) ÷ 10
                    expoverflow = true
                else
                    pexp = pexp * 10 + Int(d)
                end
            end
            i += 1
        end
    end
    iszero(M) && begin
        z = BigFloat(0; precision=prec)
        return (neg ? -z : z, RC_OK)
    end
    if expoverflow
        if eneg
            z = BigFloat(0; precision=prec)
            return (neg ? -z : z, RC_UNDERFLOW)
        end
        inf = BigFloat(Inf; precision=prec)
        return (neg ? -inf : inf, RC_OVERFLOW)
    end
    ewide = Int128(eneg ? -pexp : pexp) - Int128(4) * Int128(nfrac)
    if ewide < typemin(Int)
        z = BigFloat(0; precision=prec)
        return (neg ? -z : z, RC_UNDERFLOW)
    elseif ewide > typemax(Int)
        inf = BigFloat(Inf; precision=prec)
        return (neg ? -inf : inf, RC_OVERFLOW)
    end
    v = try
        _roundbig!(M, Int(ewide), neg, prec, rounding)
    catch err
        err isa OverflowError || rethrow()
        Int(ewide) < 0 && begin
            z = BigFloat(0; precision=prec)
            return (neg ? -z : z, RC_UNDERFLOW)
        end
        inf = BigFloat(Inf; precision=prec)
        return (neg ? -inf : inf, RC_OVERFLOW)
    end
    return (v, isinf(v) ? RC_OVERFLOW : iszero(v) ? RC_UNDERFLOW : RC_OK)
end

# All significant digits from `digstart` (first significant digit, per
# _decompose) through the end of the digit run, skipping the decimal byte.
# Returns `(M, q, inrange)` with value `M × 10^q` when `inrange`; the
# boolean is false when `abs(q + ndig) > 65536`. Shape is already validated.
function _bigmantissa!(big::BigInt, buf::AbstractVector{UInt8}, i::Int, digstart::Int, j::Int,
                       decimal::UInt8)
    # A decimal point BEFORE the first significant digit ("0.001") puts the
    # whole mantissa in the fraction, and the skipped zeros between the point
    # and digstart are fractional positions too.
    frac = 0
    infrac = false
    @inbounds for p in i:(digstart - 1)
        if buf[p] == decimal
            infrac = true
            frac = digstart - p - 1
            break
        end
    end
    # digit runs (shape validated by _decompose): [digstart, stop1), then
    # after a decimal point [start2, stop2); an exponent marker may follow
    stop1 = _digitrunend(buf, digstart, j)
    infrac && (frac += stop1 - digstart)
    start2 = stop1
    stop2 = stop1
    @inbounds if stop1 <= j && buf[stop1] == decimal
        start2 = stop1 + 1
        stop2 = _digitrunend(buf, start2, j)
        frac += stop2 - start2
    end
    ndig = (stop1 - digstart) + (stop2 - start2)
    nlimbs = _limbsfordigits(ndig)
    big.alloc < nlimbs && Base.GMP.MPZ.realloc2!(big, 64 * nlimbs)
    GC.@preserve big begin
        limbs = big.d
        size, acc, nacc, _ = _feeddigits!(limbs, 0, zero(UInt64), 0, buf, digstart, stop1)
        size, acc, nacc, _ = _feeddigits!(limbs, size, acc, nacc, buf, start2, stop2)
        size = _flushdigits!(limbs, size, acc, nacc)
    end
    Base.GMP.MPZ.limbs_finish!(big, size)
    k = stop2
    expv = 0
    @inbounds if k <= j                              # exponent (validated shape)
        k += 1                                       # skip e/E
        eneg = buf[k] == UInt8('-')
        (eneg || buf[k] == UInt8('+')) && (k += 1)
        offset = ndig - frac
        if j - k + 1 <= 18
            # Every 18-digit exponent fits Int64. This branch covers normal
            # input with no bound arithmetic in the digit loop.
            while k <= j
                expv = expv * 10 + Int(buf[k] - UInt8('0'))
                k += 1
            end
        else
            # Only exponents within this bound can make |q + ndig| <= 65536.
            # Saturating against a fixed constant is unsafe: a long mantissa can
            # cancel that constant and let an enormous reconstructed q reach pow_ui.
            aoff = abs(offset)
            limit = aoff > typemax(Int) - 65536 ? typemax(Int) : aoff + 65536
            limit10, limitdigit = divrem(limit, 10)
            while k <= j
                d = Int(buf[k] - UInt8('0'))
                (expv > limit10 || (expv == limit10 && d > limitdigit)) &&
                    return (0, false)
                expv = expv * 10 + d
                k += 1
            end
        end
        signedexp = eneg ? -expv : expv
        abs(Int128(signedexp) + Int128(offset)) > 65536 && return (0, false)
        return (signedexp - frac, true)
    end
    abs(ndig - frac) > 65536 && return (0, false)
    return (-frac, true)
end

"""
    parseuuid(buf, i, j) -> (UInt128, rc)

The canonical 8-4-4-4-12 dashed hex form, case-insensitive — exactly the
spellings `Base.tryparse(UUID, s)` accepts. Returns the raw UInt128; thin
adapters construct `Base.UUID` (mirroring the CivilParts/Dates split).
"""
function parseuuid(buf::AbstractVector{UInt8}, i::Int, j::Int)
    j - i + 1 == 36 || return (UInt128(0), RC_INVALID)
    @inbounds begin
        (buf[i + 8] == UInt8('-')) & (buf[i + 13] == UInt8('-')) &
        (buf[i + 18] == UInt8('-')) & (buf[i + 23] == UInt8('-')) ||
            return (UInt128(0), RC_INVALID)
    end
    # 8-4-4-4-12 → four 8-hex-char words. The 4-char groups pair up via their
    # low 32 bits (loads at 9|14 and 19|24); every load stays inside the span.
    w1 = _load8(buf, i)
    w2 = (_load8(buf, i + 9) & 0x00000000ffffffff) | (_load8(buf, i + 14) << 32)
    w3 = (_load8(buf, i + 19) & 0x00000000ffffffff) | (_load8(buf, i + 24) << 32)
    w4 = _load8(buf, i + 28)
    v1, ok1 = _hex8(w1)
    v2, ok2 = _hex8(w2)
    v3, ok3 = _hex8(w3)
    v4, ok4 = _hex8(w4)
    ok1 & ok2 & ok3 & ok4 || return (UInt128(0), RC_INVALID)
    return ((UInt128(v1) << 96) | (UInt128(v2) << 64) | (UInt128(v3) << 32) | UInt128(v4), RC_OK)
end

# Eight ASCII hex chars (either case) in one word → (UInt32 value, valid). Byte
# k of `w` is character k, so the first character is the most significant
# nibble of the result. Branch-free: lowercase, range-test digits and a-f
# lanes with the borrow-free trick, pick the nibble as (b & 0x0f) + 9·isalpha
# ('a'..'f' have low nibbles 1..6), then fold the eight nibbles together.
@inline function _hex8(w::UInt64)
    w |= 0x2020202020202020                       # 'A'..'F' → 'a'..'f'; digits unchanged
    # digit lanes: bytes in 0x30..0x39; alpha lanes: bytes in 0x61..0x66
    d = w ⊻ 0x3030303030303030                     # digit ⇒ 0x00..0x09
    a = w ⊻ 0x6060606060606060                     # 'a'..'f' ⇒ 0x01..0x06
    isdig = ((d + 0x7676767676767676) & 0x8080808080808080) ⊻ 0x8080808080808080  # d <= 9 ⇒ no carry into bit 7
    isalp = ((a + 0x7979797979797979) & 0x8080808080808080) ⊻ 0x8080808080808080  # a <= 6
    isalp &= ((a - 0x0101010101010101) & 0x8080808080808080) ⊻ 0x8080808080808080 # a >= 1
    # each lane must be exactly one of the two, and high bytes (>= 0x80) never
    # qualify: exclude them via the byte's own high bit
    hi = w & 0x8080808080808080
    ok = ((isdig | isalp) & ~hi) == 0x8080808080808080
    nib = (w & 0x0f0f0f0f0f0f0f0f) + ((isalp >> 7) * 0x09)   # + 9 on alpha lanes
    # fold 8 nibbles (byte lanes) into 32 bits, first char most significant
    t = ((nib & 0x000f000f000f000f) << 4) | ((nib & 0x0f000f000f000f00) >> 8)
    t = ((t & 0x000000ff000000ff) << 8) | ((t & 0x00ff000000ff0000) >> 16)
    t = ((t & 0x000000000000ffff) << 16) | ((t & 0x0000ffff00000000) >> 32)
    return (UInt32(t & 0xffffffff), ok)
end
