# =============================================================================
# arbitrary precision & identifiers — BigInt / BigFloat / UUID
#
# The low-level decimal kernels own span validation, digit decomposition,
# binary extraction, and rounding. BigInt/BigFloat are Base types whose
# arithmetic is GMP/MPFR by definition; these kernels hand them a finished,
# correctly rounded value and never call mpz_set_str or mpfr_strtofr. Public
# BigFloat parsing can use MPFR's string grammar for syntax outside that
# decimal contract.
# =============================================================================

# Powers of five for the BigFloat scaling path, built at precompile time.
# Covers every exponent reachable from ~150 significant digits around the
# double range; rarer exponents compute fresh. Entries are READ-ONLY — the
# scaling code must never hand them to an in-place GMP op's output slot.
for f in (:set_si!, :mul!, :mul_ui!, :add_ui!, :mul_2exp!, :tdiv_qr!,
          :fdiv_q_2exp!, :tstbit, :scan1, :sizeinbase, :pow_ui, :neg!, :realloc2!)
    isdefined(Base.GMP.MPZ, f) ||
        error("Parsers requires Base.GMP.MPZ.$f (Julia internals moved?)")
end

const _POW5BIG = [BigInt(5)^k for k in 0:512]

# GMP declares the low-level limb count `mp_size_t` as a C `long`. This is
# distinct from the C `int` fields in Julia's BigInt wrapper on LP64 systems.
const _GMP_SIZE_T = Clong

"""
    BigWork()

Reusable workspace for `parsebigfloat`: the coefficient, division remainder,
long power of five, and decimal-digit buffer live here so a column loop grows
them once instead of allocating them per value. GMP objects are
finalizer-registered. Never share one workspace across concurrent tasks.
"""
mutable struct BigWork
    const M::BigInt
    const R::BigInt
    const P::BigInt
    pow5exponent::Int
    const digits::Vector{UInt8}
end
BigWork() = BigWork(BigInt(0), BigInt(0), BigInt(1), 0, UInt8[])

@inline function _pow5big(ws::BigWork, k::Int)
    k <= 512 && return @inbounds(_POW5BIG[k + 1])
    if ws.pow5exponent != k
        Base.GMP.MPZ.set_si!(ws.P, 5)
        Base.GMP.MPZ.pow_ui!(ws.P, ws.P, k % Culong)
        ws.pow5exponent = k
    end
    return ws.P
end

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
struct _MPFRScaleRange <: Exception
    exponent::Int128
end

@inline function _cexponent(::Type{C}, exponent::Integer) where {C <: Signed}
    wide = Int128(exponent)
    typemin(C) <= wide <= typemax(C) || throw(_MPFRScaleRange(wide))
    return C(wide)
end

function _assemble(M::BigInt, e::Int, neg::Bool, prec::Int)
    v = BigFloat(; precision=prec)
    ccall((:mpfr_set_z, Base.MPFR.libmpfr), Int32,
          (Ref{BigFloat}, Ref{BigInt}, Int32), v, M, 0)
    ce = _cexponent(Clong, e)
    ccall((:mpfr_mul_2si, Base.MPFR.libmpfr), Int32,
          (Ref{BigFloat}, Ref{BigFloat}, Clong, Int32), v, v, ce, 0)
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
# Digits gather eight at a time into chunks of _chunkdigits(L) decimal digits
# (19 for 64-bit limbs, 9 for 32-bit), and each chunk multiply-accumulates into
# the BigInt's own limb storage. GMP never sees a digit string: it allocates,
# and the finished limb count is written to the size field.
const _Limb = Base.GMP.Limb
@inline _chunkdigits(::Type{UInt64}) = 19
@inline _chunkdigits(::Type{UInt32}) = 9
@inline _chunkmult(::Type{UInt64}) = UInt64(10)^19
@inline _chunkmult(::Type{UInt32}) = UInt32(10)^9
@inline _widelimb(::Type{UInt64}) = UInt128
@inline _widelimb(::Type{UInt32}) = UInt64

# limbs ← limbs × mult + add over `size` little-endian limbs; the new size
@inline function _mulacc!(limbs::Ptr{L}, size::Int, mult::L, add::L) where {L <: Unsigned}
    W = _widelimb(L)
    carry = W(add)
    for l in 1:size
        p = W(unsafe_load(limbs, l)) * W(mult) + carry
        unsafe_store!(limbs, p % L, l)
        carry = p >> (8 * sizeof(L))
    end
    if carry != 0
        size += 1
        unsafe_store!(limbs, carry % L, size)
    end
    return size
end

# Limbs that hold `ndig` decimal digits: ⌈ndig·log2(10)⌉ bits, rounded up.
@inline function _limbsfordigits(::Type{L}, ndig::Int) where {L <: Unsigned}
    ndig >= 0 || throw(ArgumentError("digit count must be nonnegative"))
    bits = (widemul(ndig, 3402) >> 10) + 1
    limbs = cld(bits, 8 * sizeof(L))
    limbs <= typemax(Int) ||
        throw(OverflowError("BigInt limb count is not representable"))
    return Int(limbs)
end

@noinline _gmpcapacityoverflow() =
    throw(OverflowError("BigInt value exceeds GMP's representable limb capacity"))

@inline function _gmpbitsforlimbs(nlimbs::Int, limbbits::Int=8 * sizeof(_Limb))
    limbbits > 0 || throw(ArgumentError("limb width must be positive"))
    0 <= nlimbs <= typemax(Cint) || _gmpcapacityoverflow()
    bits = UInt128(nlimbs) * UInt128(limbbits)
    bits <= UInt128(typemax(Int)) || _gmpcapacityoverflow()
    bits <= UInt128(typemax(Culong)) || _gmpcapacityoverflow()
    return Int(bits)
end

@inline _gmpmaxvaluebits() = min(UInt128(typemax(Int)),
                                 UInt128(typemax(Culong)),
                                 UInt128(typemax(Cint)) * UInt128(8 * sizeof(_Limb)))

@inline function _gmpcheckedaddbits(bits::Int, add::Int)
    bits >= 0 && add >= 0 || _gmpcapacityoverflow()
    total = UInt128(bits) + UInt128(add)
    total <= _gmpmaxvaluebits() || _gmpcapacityoverflow()
    return Int(total)
end

@inline function _gmpsize(size::Int)
    -typemax(Cint) <= size <= typemax(Cint) || _gmpcapacityoverflow()
    return Cint(size)
end

@inline function _gmpgrowcapacity(size::Int, capacity::Int)
    size < typemax(Cint) || _gmpcapacityoverflow()
    needed = size + 1
    doubled = capacity <= typemax(Cint) ÷ 2 ? 2capacity : Int(typemax(Cint))
    return max(needed, max(4, doubled))
end

# Feed buf[k : stop-1] into chunks; `acc`/`nacc` carry a partial chunk between
# calls so a decimal point can split a digit run. Completed chunks flush into
# the limbs. Returns (size, acc, nacc, ok).
@inline function _feeddigits!(limbs::Ptr{L}, size::Int, acc::UInt64, nacc::Int,
                              buf::AbstractVector{UInt8}, k::Int, stop::Int) where {L <: Unsigned}
    while k < stop
        t = min(_chunkdigits(L) - nacc, stop - k)
        v, ok = _digits19(buf, k, t)
        ok || return (size, acc, nacc, false)
        acc = acc * @inbounds(_POW10U64[t + 1]) + v
        nacc += t
        k += t
        if nacc == _chunkdigits(L)
            size = _mulacc!(limbs, size, _chunkmult(L), acc % L)
            acc = zero(UInt64)
            nacc = 0
        end
    end
    return (size, acc, nacc, true)
end

@inline function _flushdigits!(limbs::Ptr{L}, size::Int, acc::UInt64, nacc::Int) where {L <: Unsigned}
    nacc == 0 && return size
    return _mulacc!(limbs, size, @inbounds(_POW10U64[nacc + 1]) % L, acc % L)
end

"""
    parsebigint(buf, i, j) -> (BigInt, rc)

Exact-span BigInt: sign and decimal digits only (the strict integer grammar,
same as `parseint64` without the width limit). The digits become limb-sized
decimal chunks that multiply-accumulate straight into the BigInt's limbs, so
the only GMP involvement is the allocation.
"""
function parsebigint(buf::AbstractVector{UInt8}, i::Int, j::Int)
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        return _parsebigintdecimalexact(window, first, final)
    end
    return _parsebigintdecimalexact(buf, i, j)
end

function _parsebigintdecimalexact(buf::AbstractVector{UInt8}, i::Int, j::Int)
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
    nlimbs = _limbsfordigits(_Limb, j - i + 1)
    big = BigInt(; nbits=_gmpbitsforlimbs(nlimbs))
    GC.@preserve big begin
        limbs = big.d
        size, acc, nacc, ok = _feeddigits!(limbs, 0, zero(UInt64), 0, buf, i, j + 1)
        ok || return (BigInt(0), RC_INVALID)
        size = _flushdigits!(limbs, size, acc, nacc)
    end
    big.size = _gmpsize(neg ? -size : size)          # the top limb is nonzero, as GMP requires
    return (big, RC_OK)
end

"""
    parsebigint(buf, i, j, base) -> (BigInt, rc, badpos)

Exact-span arbitrary-radix BigInt parser for bases 2 through 62. The digit
mapping is identical to `parseint`. `badpos` identifies an invalid
digit; arbitrary precision means this overload cannot return `RC_OVERFLOW`.
"""
function parsebigint(buf::AbstractVector{UInt8}, i::Int, j::Int, base::Int)
    2 <= base <= 62 || throw(ArgumentError("base must be between 2 and 62"))
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        result = _parsebigintradixexact(window, first, final, base)
        return _restoreexactposition(window, result)
    end
    return _parsebigintradixexact(buf, i, j, base)
end

function _parsebigintradixexact(buf::AbstractVector{UInt8}, i::Int, j::Int,
                                base::Int)
    i > j && return (BigInt(0), RC_INVALID, i)
    orig = i
    neg = false
    @inbounds begin
        b = buf[i]
        if b == UInt8('-') || b == UInt8('+')
            neg = b == UInt8('-')
            i += 1
        end
    end
    i > j && return (BigInt(0), RC_INVALID, orig)
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

# Largest count whose radix power fits in one GMP limb. Prefix parsing gathers
# this many digits before one limb-wise multiply-add. It therefore discovers
# the token end and builds the BigInt in the same pass, without a digit-string
# rescan or a call to GMP's string parser.
const _BIGINT_RADIX_CHUNK_DIGITS = ntuple(61) do n
    b = _Limb(n + 1)
    power = one(_Limb)
    count = 0
    while power <= typemax(_Limb) ÷ b
        power *= b
        count += 1
    end
    count
end
const _BIGINT_PREFIX_STACK_LIMBS = 4
const _ZERO_BIGINT_PREFIX_LIMBS = ntuple(_ -> zero(_Limb), Val(5))

@inline function _bigintprefixmulacc(limbs::NTuple{5, L}, size::Int,
                                     mult::L, add::L) where {L <: Unsigned}
    W = _widelimb(L)
    carry = W(add)
    @inbounds for l in 1:size
        product = W(limbs[l]) * W(mult) + carry
        limbs = Base.setindex(limbs, product % L, l)
        carry = product >> (8 * sizeof(L))
    end
    if carry != 0
        size += 1
        limbs = Base.setindex(limbs, carry % L, size)
    end
    return (limbs, size)
end

function _bigintprefixfromlimbs(limbs::NTuple{5, L}, size::Int,
                                capacity::Int) where {L <: Unsigned}
    limbbits = 8 * sizeof(L)
    big = BigInt(; nbits=_gmpbitsforlimbs(max(capacity, 1), limbbits))
    GC.@preserve big begin
        @inbounds for l in 1:size
            unsafe_store!(big.d, limbs[l], l)
        end
    end
    big.size = _gmpsize(size)
    return big
end

@inline function _bigintprefixcapacity!(big::BigInt, size::Int, capacity::Int,
                                        limbbits::Int)
    size < capacity && return (big.d, capacity)
    # GMP must know how many manually-written limbs to preserve if it moves
    # the allocation.
    big.size = _gmpsize(size)
    capacity = _gmpgrowcapacity(size, capacity)
    Base.GMP.MPZ.realloc2!(big, _gmpbitsforlimbs(capacity, limbbits))
    return (big.d, capacity)
end

@inline function _bigintprefixmulacc!(big::BigInt, size::Int, capacity::Int,
                                      mult::_Limb, add::_Limb, limbbits::Int)
    GC.@preserve big begin
        limbs, capacity =
            _bigintprefixcapacity!(big, size, capacity, limbbits)
        size = _mulacc!(limbs, size, mult, add)
    end
    big.size = _gmpsize(size)
    return (size, capacity)
end

function _parsebigintprefix(buf::AbstractVector{UInt8}, pos::Int, last::Int,
                            base, groupmark)
    k, b, gm, neg, valid = _integerprefixconfig(Val(true), buf, pos, last,
                                                base, groupmark)
    valid || return (BigInt(0), pos, RC_INVALID)
    @inbounds begin
        firstdigit = k <= last ? _digitvalue(buf[k], b) : 0xff
        firstdigit < b || return (BigInt(0), pos, RC_INVALID)
    end

    limbbits = 8 * sizeof(_Limb)
    chunkdigits = @inbounds _BIGINT_RADIX_CHUNK_DIGITS[b - 1]
    abase = _Limb(b)
    acc = zero(_Limb)
    multiplier = one(_Limb)
    nchunk = 0
    size = 0
    small = _ZERO_BIGINT_PREFIX_LIMBS
    big = nothing
    capacity = 0
    sawdigit = false

    @inbounds while k <= last
        digit = _digitvalue(buf[k], b)
        if digit < b
            sawdigit = true
            acc = acc * abase + _Limb(digit)
            multiplier *= abase
            nchunk += 1
            if nchunk == chunkdigits
                if big === nothing
                    small, size = _bigintprefixmulacc(small, size, multiplier,
                                                      acc)
                    if size > _BIGINT_PREFIX_STACK_LIMBS
                        big = _bigintprefixfromlimbs(small, size,
                            2 * _BIGINT_PREFIX_STACK_LIMBS)
                        capacity = Int(big.alloc)
                    end
                else
                    size, capacity = _bigintprefixmulacc!(big, size, capacity,
                                                          multiplier, acc,
                                                          limbbits)
                end
                acc = zero(_Limb)
                multiplier = one(_Limb)
                nchunk = 0
            end
            k += 1
        elseif gm !== nothing && sawdigit && buf[k] == gm && k < last &&
               _digitvalue(buf[k + 1], b) < b
            k += 1
        else
            break
        end
    end
    if nchunk != 0
        if big === nothing
            small, size = _bigintprefixmulacc(small, size, multiplier, acc)
            if size > _BIGINT_PREFIX_STACK_LIMBS
                big = _bigintprefixfromlimbs(small, size,
                    2 * _BIGINT_PREFIX_STACK_LIMBS)
                capacity = Int(big.alloc)
            end
        else
            size, capacity = _bigintprefixmulacc!(big, size, capacity,
                                                  multiplier, acc, limbbits)
        end
    end

    # The first-byte check above establishes this, but retain the invariant at
    # the result boundary if the loop changes later.
    sawdigit || return (BigInt(0), pos, RC_INVALID)
    big === nothing && (big = _bigintprefixfromlimbs(small, size, size))
    big.size = _gmpsize(neg ? -size : size)
    return (big, k, RC_OK)
end

"""
    parsebigfloat(buf, i, j, decimal=UInt8('.'); prec=precision(BigFloat)) -> (BigFloat, rc)

Correctly rounded BigFloat at `prec` bits, with `rounding` defaulting to the
current MPFR rounding mode. It accepts the decimal and hexadecimal grammar and
special spellings of `parsefloat64`. Decimal digits go through GMP's numeric
digit-to-limb converter, not a string parser. A long coefficient first becomes
a bounded leading interval. Equal rounded endpoints prove the result; only an
endpoint disagreement converts the full exact coefficient. Integer powers of
five and two then produce one correctly rounded value. MPFR stores that value;
it does not parse the token.

Prove-out range bound: decimal magnitudes beyond ~10^±65536 return
`RC_OVERFLOW`. This keeps package-owned integer scaling bounded. No subnormal
handling is needed inside that range — BigFloat's exponent field dwarfs it.
"""
function parsebigfloat(buf::AbstractVector{UInt8}, i::Int, j::Int, decimal::UInt8=UInt8('.');
                       prec::Int=precision(BigFloat),
                       rounding::RoundingMode=Base.Rounding.rounding(BigFloat))
    return _withbigwork() do ws
        parsebigfloat(buf, i, j, decimal, ws; prec, rounding)
    end
end

function parsebigfloat(buf::AbstractVector{UInt8}, i::Int, j::Int,
                       decimal::UInt8, ws::BigWork; prec::Int=precision(BigFloat),
                       rounding::RoundingMode=Base.Rounding.rounding(BigFloat))
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        return _parsebigfloatexact(window, first, final, decimal, ws; prec,
                                   rounding)
    end
    return _parsebigfloatexact(buf, i, j, decimal, ws; prec, rounding)
end

function _parsebigfloatexact(buf::AbstractVector{UInt8}, i::Int, j::Int,
                             decimal::UInt8, ws::BigWork;
                             prec::Int=precision(BigFloat),
                             rounding::RoundingMode=Base.Rounding.rounding(BigFloat))
    prec >= 2 || throw(ArgumentError("prec must be ≥ 2"))
    _roundup(rounding, false, false, false, false)  # validate even for zero/specials
    k = i
    @inbounds if k <= j && (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
        k += 1
    end
    @inbounds if k < j && buf[k] == UInt8('0') && _lower(buf[k + 1]) == UInt8('x')
        return _parsebigfloathex(buf, i, j, ws; prec, rounding)
    end
    sp, matched = _matchspecial(buf, i, j)
    matched && return (BigFloat(sp; precision=prec), RC_OK)
    parts, rc = _decompose(buf, i, j, decimal)
    rc == RC_OK || return (BigFloat(0; precision=prec), rc)
    return _bigfloatfromparts(buf, i, j, decimal, parts, ws, prec, rounding)
end

# Unary minus on a BigFloat allocates at the global default precision, so
# signed zero/Inf early returns must construct the signed value at `prec`
@inline _signedzero(neg::Bool, prec::Int) = BigFloat(neg ? -0.0 : 0.0; precision=prec)
@inline _signedinf(neg::Bool, prec::Int) = BigFloat(neg ? -Inf : Inf; precision=prec)

function _scaledbigint!(M::BigInt, q::Int, neg::Bool, ws::BigWork,
                        prec::Int, rounding::_ROUNDING)
    # value = M × 10^q = M × 5^q × 2^q — pure integer scaling, one rounding:
    #   q ≥ 0: N = M·5^q is exact and value = N × 2^q
    #   q < 0: N = ⌊M·2^s / 5^-q⌋ with enough guard bits; the remainder
    #          is sticky and value = N × 2^(q-s).
    MPZ = Base.GMP.MPZ
    sticky = false
    if q >= 0
        q > 0 && MPZ.mul!(M, _pow5big(ws, q))
        e2 = q
    else
        kwide = -Int128(q)
        if kwide > typemax(Int)
            return (_signedzero(neg, prec), RC_UNDERFLOW)
        end
        k = Int(kwide)
        d5 = _pow5big(ws, k)
        s = max(0, prec + 3 + Int(MPZ.sizeinbase(d5, 2)) -
                   Int(MPZ.sizeinbase(M, 2)))
        MPZ.mul_2exp!(M, s % Culong)
        MPZ.tdiv_qr!(M, ws.R, M, d5)
        sticky = !iszero(ws.R)
        e2wide = Int128(q) - Int128(s)
        if e2wide < typemin(Int)
            return (_signedzero(neg, prec), RC_UNDERFLOW)
        elseif e2wide > typemax(Int)
            return (_signedinf(neg, prec), RC_OVERFLOW)
        end
        e2 = Int(e2wide)
    end
    value = _roundbig!(M, e2, neg, prec, rounding, sticky)
    return (value, isinf(value) ? RC_OVERFLOW : iszero(value) ? RC_UNDERFLOW : RC_OK)
end

@inline function _decimalintervaldigits(prec::Int)
    # ceil(prec*log10(2)) significant decimal digits identify a `prec`-bit
    # value. Ten more digits make the conservative interval much narrower than
    # one ulp. Endpoint agreement below is the proof; this count affects only
    # how often the exact full-coefficient fallback is needed.
    digits = cld(widemul(prec, 30103), 100000) + 10
    digits <= typemax(Int) || _gmpcapacityoverflow()
    return max(1, Int(digits))
end

# Convert decomposed decimal parts. Long coefficients first convert a bounded
# leading interval. If both interval endpoints round to the same value, every
# possible omitted suffix has that result. Only an endpoint disagreement takes
# the exact full-coefficient path.
function _bigfloatfromparts(buf::AbstractVector{UInt8}, i::Int, j::Int, decimal::UInt8,
                            parts::DecParts, ws::BigWork, prec::Int, rounding::_ROUNDING,
                            groupmark=nothing)
    if parts.mant == 0
        return (_signedzero(parts.neg, prec), RC_OK)
    end
    # Freeze significant digits and track the true power of ten. The range test
    # uses the full coefficient exponent, not DecParts.exp10 (which is relative
    # to its truncated 19-digit mantissa).
    M = ws.M
    digstart = parts.digoffset <= 0 ? _DECPARTS_NO_DIGIT :
               i + Int(parts.digoffset) - 1
    q, inrange = _collectbigmantissa!(ws.digits, buf, i, digstart, j, decimal,
                                      groupmark)
    inrange || return (_signedzero(parts.neg, prec), RC_OVERFLOW)
    digits = ws.digits
    ndig = length(digits)
    keep = min(ndig, _decimalintervaldigits(prec))
    omitted = ndig - keep
    if omitted > 0
        tailnonzero = false
        @inbounds for index in (keep + 1):ndig
            tailnonzero |= digits[index] != 0
        end
        qshortwide = Int128(q) + Int128(omitted)
        typemin(Int) <= qshortwide <= typemax(Int) || _gmpcapacityoverflow()
        qshort = Int(qshortwide)

        _setdecimaldigits!(M, digits, keep)
        lower = _scaledbigint!(M, qshort, parts.neg, ws, prec, rounding)
        tailnonzero || return lower

        _setdecimaldigits!(M, digits, keep)
        Base.GMP.MPZ.add_ui!(M, 1)
        upper = _scaledbigint!(M, qshort, parts.neg, ws, prec, rounding)
        lower[2] == upper[2] && isequal(lower[1], upper[1]) && return lower
    end

    _setdecimaldigits!(M, digits, ndig)
    return _scaledbigint!(M, q, parts.neg, ws, prec, rounding)
end

@inline function _withbigwork(f::F) where {F}
    ws = _takebigwork()
    try
        return f(ws)
    finally
        _givebigwork(ws)
    end
end

# Arbitrary-precision C99 hexadecimal float. Hexadecimal input is already a
# binary rational, so collecting every nibble into a BigInt and applying one
# `_roundbig!` operation gives exact MPFR-compatible rounding without a string
# conversion.
function _parsebigfloathex(buf::AbstractVector{UInt8}, i::Int, j::Int,
                           ws::BigWork; prec::Int, rounding::RoundingMode)
    value, nextpos, rc = _parsebigfloathexprefix(buf, i, j, ws;
                                                  prec, rounding)
    nextpos > j || return (BigFloat(0; precision=prec), RC_INVALID)
    return (value, rc)
end

function _parsebigfloathexprefix(buf::AbstractVector{UInt8}, i::Int, j::Int,
                                 ws::BigWork; prec::Int,
                                 rounding::RoundingMode)
    orig = i
    neg = false
    @inbounds begin
        b = buf[i]
        neg = b == UInt8('-')
        (neg || b == UInt8('+')) && (i += 1)
        (i < j && buf[i] == UInt8('0') &&
         _lower(buf[i + 1]) == UInt8('x')) ||
            return (BigFloat(0; precision=prec), orig, RC_INVALID)
    end
    i += 2
    M = ws.M
    MPZ = Base.GMP.MPZ
    MPZ.set_si!(M, 0)
    sawdigit = false
    infrac = false
    nfrac = 0
    coefficientbits = 0
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
                return (_signedzero(neg, prec), i + 1, RC_UNDERFLOW)
            end
            nfrac += 1
        end
        if coefficientbits == 0
            d != 0 && (coefficientbits = 8 - leading_zeros(d))
        else
            coefficientbits = _gmpcheckedaddbits(coefficientbits, 4)
        end
        MPZ.mul_2exp!(M, Culong(4))
        MPZ.add_ui!(M, d % UInt)
        i += 1
    end
    sawdigit || return (BigFloat(0; precision=prec), orig, RC_INVALID)

    commit = i
    pexp = zero(UInt128)
    eneg = false
    @inbounds if i <= j && _lower(buf[i]) == UInt8('p')
        k = i + 1
        if k <= j
            b = buf[k]
            eneg = b == UInt8('-')
            (eneg || b == UInt8('+')) && (k += 1)
        end
        estart = k
        while k <= j
            d = buf[k] - UInt8('0')
            d <= 0x09 || break
            pexp = _hexexponentdigit(pexp, d)
            k += 1
        end
        k > estart && (commit = k)
        commit == i && begin
            pexp = zero(UInt128)
            eneg = false
        end
    end

    iszero(M) && begin
        return (_signedzero(neg, prec), commit, RC_OK)
    end
    ewide = _signedhexexponent(pexp, eneg) - Int128(4) * Int128(nfrac)
    if ewide < typemin(Int)
        return (_signedzero(neg, prec), commit, RC_UNDERFLOW)
    elseif ewide > typemax(Int)
        return (_signedinf(neg, prec), commit, RC_OVERFLOW)
    end
    v = try
        _roundbig!(M, Int(ewide), neg, prec, rounding)
    catch err
        underflow = if err isa _MPFRScaleRange
            err.exponent < 0
        elseif err isa OverflowError
            # The only checked Int operation below this point adds a positive
            # rounding shift, so its overflow is necessarily above typemax.
            false
        else
            rethrow()
        end
        if underflow
            return (_signedzero(neg, prec), commit, RC_UNDERFLOW)
        end
        return (_signedinf(neg, prec), commit, RC_OVERFLOW)
    end
    rc = isinf(v) ? RC_OVERFLOW : iszero(v) ? RC_UNDERFLOW : RC_OK
    return (v, commit, rc)
end

# BigFloat prefix parsing shares the float-family token grammar and hands the
# resulting state directly to the limb converter. The converter may reread
# digits to build the arbitrary-precision mantissa, but it does not rescan the
# grammar or call a whole-value parser.
@inline function _leasedbigfloathexprefix(buf, i::Int, j::Int, prec::Int,
                                          rounding::RoundingMode)
    ws = _takebigwork()
    try
        return _parsebigfloathexprefix(buf, i, j, ws; prec, rounding)
    finally
        _givebigwork(ws)
    end
end

@inline function _leasedbigfloatfromparts(buf, i::Int, stop::Int,
                                          decimal::UInt8, parts::DecParts,
                                          prec::Int, rounding::RoundingMode,
                                          groupmark)
    ws = _takebigwork()
    try
        return _bigfloatfromparts(buf, i, stop, decimal, parts, ws, prec,
                                  rounding, groupmark)
    finally
        _givebigwork(ws)
    end
end

function _parsebigfloatprefix(buf::AbstractVector{UInt8}, i::Int, j::Int,
                              decimal::UInt8, groupmark,
                              rounding::RoundingMode)
    orig = i
    prec = precision(BigFloat)
    _roundup(rounding, false, false, false, false)
    gm = _floatgroupbyte(groupmark, decimal)

    k = i
    @inbounds if k <= j && (buf[k] == UInt8('-') || buf[k] == UInt8('+'))
        k += 1
    end
    k <= j || return (BigFloat(0; precision=prec), orig, RC_INVALID)

    @inbounds first = buf[k]
    lower = _lower(first)
    if lower == UInt8('i') || lower == UInt8('n')
        special, nextpos, matched = _matchspecialprefix(buf, i, j)
        matched && return (BigFloat(special; precision=prec), nextpos, RC_OK)
    end
    if _startshexprefix(buf, k, j)
        return _leasedbigfloathexprefix(buf, i, j, prec, rounding)
    end
    (first - UInt8('0') <= 0x09 || first == decimal) ||
        return (BigFloat(0; precision=prec), orig, RC_INVALID)

    parts, nextpos, rc = _decomposeprefix(buf, i, j, decimal, gm)
    rc == RC_OK || return (BigFloat(0; precision=prec), orig, rc)
    value, rc = _leasedbigfloatfromparts(buf, i, nextpos - 1, decimal, parts,
                                         prec, rounding, gm)
    return (value, nextpos, rc)
end

# Resolve the decimal position and first significant digit together. An
# unknown `digstart` is the cold bounded-state case: syntax is already valid,
# so this prepass only reads coefficient digits and separators and stops before
# e/E. Track the point separately because a rebased prefix window can contain
# index zero.
function _bigmantissaprepass(buf::AbstractVector{UInt8}, i::Int, j::Int,
                             digstart::Int, decimal::UInt8)
    point = 0
    pointfound = false
    if digstart != _DECPARTS_NO_DIGIT
        @inbounds for p in i:(digstart - 1)
            if buf[p] == decimal
                point = p
                pointfound = true
                break
            end
        end
    else
        @inbounds while i <= j
            byte = buf[i]
            digit = byte - UInt8('0')
            digit <= 0x09 && digit != 0 && begin
                digstart = i
                break
            end
            _lower(byte) == UInt8('e') && break
            if byte == decimal
                point = i
                pointfound = true
            end
            i += 1
        end
    end
    infrac = pointfound
    frac = infrac ? digstart - point - 1 : 0
    return (digstart, infrac, frac)
end

# Read the exponent of an already-validated decimal coefficient. UInt64 keeps
# the common 18-digit branch correct on 32-bit platforms; Int128 combines it
# with the coefficient scale before the bounded BigFloat range decision.
@inline function _bigfloatexponent(buf::AbstractVector{UInt8}, k::Int, j::Int,
                                   offset::Int, frac::Int)
    @inbounds begin
        k += 1
        eneg = buf[k] == UInt8('-')
        (eneg || buf[k] == UInt8('+')) && (k += 1)
        expv = zero(UInt64)
        if j - k + 1 <= 18
            while k <= j
                expv = 10expv + UInt64(buf[k] - UInt8('0'))
                k += 1
            end
        else
            # Only exponents within this bound can make |q + ndig| <= 65536.
            # A fixed cap would lose cancellation against a long coefficient.
            aoff = abs(Int128(offset))
            limit = UInt64(min(aoff + 65536, Int128(typemax(UInt64))))
            limit10, limitdigit = divrem(limit, UInt64(10))
            while k <= j
                d = UInt64(buf[k] - UInt8('0'))
                (expv > limit10 || (expv == limit10 && d > limitdigit)) &&
                    return (0, false)
                expv = 10expv + d
                k += 1
            end
        end
        signedexp = eneg ? -Int128(expv) : Int128(expv)
        abs(signedexp + Int128(offset)) > 65536 && return (0, false)
        q = signedexp - Int128(frac)
        typemin(Int) <= q <= typemax(Int) || return (0, false)
        return (Int(q), true)
    end
end

# Convert a numeric digit buffer to GMP limbs without invoking a string parser.
@inline function _setdecimaldigits!(big::BigInt, digits::Vector{UInt8}, ndig::Int)
    nlimbs = _limbsfordigits(_Limb, ndig)
    big.alloc < nlimbs &&
        Base.GMP.MPZ.realloc2!(big, _gmpbitsforlimbs(nlimbs))
    rawsize = GC.@preserve big digits begin
        ccall((:__gmpn_set_str, Base.GMP.libgmp), _GMP_SIZE_T,
              (Ptr{_Limb}, Ptr{UInt8}, Csize_t, Cint),
              big.d, pointer(digits), ndig, 10)
    end
    0 <= rawsize <= nlimbs || _gmpcapacityoverflow()
    big.size = _gmpsize(Int(rawsize))
    return big
end

# Collect significant digits and their decimal scale from an already validated
# token. The boolean is false when the magnitude is outside the bounded
# BigFloat kernel range.
function _collectbigmantissa!(digits::Vector{UInt8},
                              buf::AbstractVector{UInt8}, i::Int,
                              digstart::Int, j::Int, decimal::UInt8)
    # A decimal point BEFORE the first significant digit ("0.001") puts the
    # whole mantissa in the fraction, and the skipped zeros between the point
    # and digstart are fractional positions too.
    digstart, infrac, frac = _bigmantissaprepass(buf, i, j, digstart, decimal)
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
    k = stop2
    q, inrange = @inbounds(k <= j) ?
        _bigfloatexponent(buf, k, j, ndig - frac, frac) :
        (-frac, abs(ndig - frac) <= 65536)
    inrange || return (0, false)

    resize!(digits, ndig)
    target = 1
    @inbounds for source in digstart:(stop1 - 1)
        digits[target] = buf[source] - UInt8('0')
        target += 1
    end
    @inbounds for source in start2:(stop2 - 1)
        digits[target] = buf[source] - UInt8('0')
        target += 1
    end
    return (q, true)
end

@inline _collectbigmantissa!(digits::Vector{UInt8},
                             buf::AbstractVector{UInt8}, i::Int,
                             digstart::Int, j::Int, decimal::UInt8,
                             ::Nothing) =
    _collectbigmantissa!(digits, buf, i, digstart, j, decimal)

# Numeric construction for an already-validated grouped decimal token. The
# prefix grammar has already selected `j`; this pass only feeds every digit to
# GMP and derives the exact scale, skipping validated marks as it goes.
function _collectbigmantissa!(digits::Vector{UInt8},
                              buf::AbstractVector{UInt8}, i::Int,
                              digstart::Int, j::Int, decimal::UInt8,
                              groupmark::UInt8)
    digstart, infrac, frac = _bigmantissaprepass(buf, i, j, digstart, decimal)

    # Freeze significant digits into the reusable converter buffer while the
    # validated token is traversed. GMP's limb converter then builds the
    # coefficient with its subquadratic large-input algorithm. This is numeric
    # conversion, not another grammar scan or a whole-value parser call.
    empty!(digits)
    ndig = 0
    k = digstart
    @inbounds while k <= j
        b = buf[k]
        d = b - UInt8('0')
        if d <= 0x09
            ndig += 1
            push!(digits, d)
        elseif _lower(b) == UInt8('e')
            break
        elseif b == decimal
            infrac = true
        end
        infrac && d <= 0x09 && (frac += 1)
        k += 1
    end
    q, inrange = @inbounds(k <= j) ?
        _bigfloatexponent(buf, k, j, ndig - frac, frac) :
        (-frac, abs(ndig - frac) <= 65536)
    inrange || return (0, false)
    return (q, true)
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
