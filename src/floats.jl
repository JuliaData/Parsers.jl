using Base.GMP, Base.GMP.MPZ

const ONES = [BigInt(1)]
const NUMS = [BigInt()]
const QUOS = [BigInt()]
const REMS = [BigInt()]
const SCLS = [BigInt()]

const BIG_E = UInt8('E')
const LITTLE_E = UInt8('e')

const bipows5 = [big(5)^x for x = 0:325]

function roundQuotient(num, den)
    @inbounds quo, rem = MPZ.tdiv_qr!(QUOS[Threads.threadid()], REMS[Threads.threadid()], num, den)
    q = Int64(quo)
    cmpflg = cmp(MPZ.mul_2exp!(rem, 1), den)
    return ((q & 1) == 0 ? 1 == cmpflg : -1 < cmpflg) ? q + 1 : q
end

maxsig(::Type{Float16}) = 2048
maxsig(::Type{Float32}) = 16777216
maxsig(::Type{Float64}) = 9007199254740992

ceillog5(::Type{Float16}) = 5
ceillog5(::Type{Float32}) = 11
ceillog5(::Type{Float64}) = 23

const F16_SHORT_POWERS = [exp10(Float16(x)) for x = 0:2ceillog5(Float16)-1]
const F32_SHORT_POWERS = [exp10(Float32(x)) for x = 0:2ceillog5(Float32)-1]
const F64_SHORT_POWERS = [exp10(Float64(x)) for x = 0:2ceillog5(Float64)-1]

pow10(::Type{Float16}, e) = (@inbounds v = F16_SHORT_POWERS[e+1]; return v)
pow10(::Type{Float32}, e) = (@inbounds v = F32_SHORT_POWERS[e+1]; return v)
pow10(::Type{Float64}, e) = (@inbounds v = F64_SHORT_POWERS[e+1]; return v)

significantbits(::Type{Float16}) = 11
significantbits(::Type{Float32}) = 24
significantbits(::Type{Float64}) = 53

bitlength(this) = GMP.MPZ.sizeinbase(this, 2)
bits(::Type{T}) where {T <: Union{Float16, Float32, Float64}} = 8sizeof(T)

BigInt!(y::BigInt, x::BigInt) = x
BigInt!(y::BigInt, x::Union{Clong,Int32}) = MPZ.set_si!(y, x)
# copied from gmp.jl:285
function BigInt!(y::BigInt, x::Integer)
    x == 0 && return y
    nd = ndigits(x, base=2)
    z = GMP.MPZ.realloc2!(y, nd)
    s = sign(x)
    s == -1 && (x = -x)
    x = unsigned(x)
    size = 0
    limbnbits = sizeof(GMP.Limb) << 3
    while nd > 0
        size += 1
        unsafe_store!(z.d, x % GMP.Limb, size)
        x >>>= limbnbits
        nd -= limbnbits
    end
    z.size = s*size
    z
end

@inline function scale(::Type{T}, v, exp) where {T <: Union{Float16, Float32, Float64}}
    ms = maxsig(T)
    cl = ceillog5(T)
    if v < ms
        # fastest path
        if 0 <= exp < cl
            return T(v) * pow10(T, exp)
        elseif -cl < exp < 0
            return T(v) / pow10(T, -exp)
        end
    end
    v == 0 && return zero(T)
    @inbounds mant = BigInt!(NUMS[Threads.threadid()], v)
    if 0 <= exp < 327
        num = MPZ.mul!(mant, bipows5[exp+1])
        bex = bitlength(num) - significantbits(T)
        bex <= 0 && return ldexp(T(num), exp)
        @inbounds one = MPZ.mul_2exp!(MPZ.set_si!(ONES[Threads.threadid()], 1), bex)
        quo = roundQuotient(num, one)
        return ldexp(T(quo), bex + exp)
    elseif -327 < exp < 0
        maxpow = length(bipows5) - 1
        @inbounds scl = SCLS[Threads.threadid()]
        if -exp <= maxpow
            MPZ.set!(scl, bipows5[-exp+1])
        else
            MPZ.set!(scl, bipows5[maxpow+1])
            MPZ.mul!(scl, bipows5[-exp-maxpow+1])
        end
        bex = bitlength(mant) - bitlength(scl) - significantbits(T)
        num = MPZ.mul_2exp!(mant, -bex)
        quo = roundQuotient(num, scl)
        # @info "debug" mant=mant exp=exp num=num quo=quo lh=(bits(T) - leading_zeros(quo)) rh=significantbits(T) bex=bex
        if (bits(T) - leading_zeros(quo) > significantbits(T)) || exp == -324
            bex += 1
            quo = roundQuotient(num, MPZ.mul_2exp!(scl, 1))
        end
        if exp <= -324
            return T(ldexp(BigFloat(quo), bex + exp))
        else
            return ldexp(T(quo), bex + exp)
        end
    else
        return exp > 0 ? T(Inf) : T(0)
    end
end

@inline function scale(::Type{T}, lmant, exp, neg) where {T <: Union{Float16, Float32, Float64}}
    result = scale(T, lmant, exp)
    return ifelse(neg, -result, result)
end

const SPECIALS = Trie(["nan"=>NaN, "infinity"=>Inf, "inf"=>Inf])

wider(::Type{Int64}) = Int128
wider(::Type{Int128}) = BigInt

@inline defaultparser(io::IO, r::Result{T}; kwargs...) where {T <: Union{Float16, Float32, Float64}} = _defaultparser(io, r, Int64; kwargs...)

@inline function _defaultparser(io::IO, r::Result{T}, ::Type{IntType}; decimal::Union{Char, UInt8}=UInt8('.'), kwargs...) where {T <: Union{Float16, Float32, Float64}, IntType}
    setfield!(r, 1, missing)
    setfield!(r, 3, Int64(position(io)))
    b = 0x00
    code = SUCCESS
    eof(io) && (code |= INVALID | EOF; @goto done)
    b = peekbyte(io)
    negative = false
    if b == MINUS # check for leading '-' or '+'
        negative = true
        readbyte(io)
        eof(io) && (code |= INVALID | EOF; @goto done)
        b = peekbyte(io)
    elseif b == PLUS
        readbyte(io)
        eof(io) && (code |= INVALID | EOF; @goto done)
        b = peekbyte(io)
    end
    # float digit parsing
    v = zero(IntType)
    parseddigits = false
    while NEG_ONE < b < TEN
        readbyte(io)
        parseddigits = true
        # process digits
        v, ov_mul = Base.mul_with_overflow(v, IntType(10))
        v, ov_add = Base.add_with_overflow(v, IntType(b - ZERO))
        (ov_mul | ov_add) && (fastseek!(io, r.pos); return _defaultparser(io, r, wider(IntType); decimal=decimal))
        if eof(io)
            r.result = T(ifelse(negative, -v, v))
            code |= OK | EOF
            @goto done
        end
        b = peekbyte(io)
    end
    # check for dot
    if b == decimal % UInt8
        readbyte(io)
        if eof(io)
            if parseddigits
                r.result = T(ifelse(negative, -v, v))
                code |= OK | EOF
            else
                code |= INVALID | EOF
            end
            @goto done
        end
        b = peekbyte(io)
    elseif !parseddigits
        if match!(SPECIALS, io, r, true, true)
            v2 = r.result::Float64
            r.result = T(ifelse(negative, -v2, v2))
            eof(io) && (r.code |= EOF)
            return r
        else
            code |= INVALID | ifelse(eof(io), EOF, SUCCESS)
        end
        @goto done
    end
    # parse fractional part
    frac = 0
    parseddigitsfrac = false
    while NEG_ONE < b < TEN
        readbyte(io)
        frac += 1
        parseddigitsfrac = true
        # process digits
        v, ov_mul = Base.mul_with_overflow(v, IntType(10))
        v, ov_add = Base.add_with_overflow(v, IntType(b - ZERO))
        (ov_mul | ov_add) && (fastseek!(io, r.pos); return _defaultparser(io, r, wider(IntType); decimal=decimal))
        if eof(io)
            r.result = scale(T, v, -frac, negative)
            code |= OK | EOF
            @goto done
        end
        b = peekbyte(io)
    end
    # parse potential exp
    if b == LITTLE_E || b == BIG_E
        readbyte(io)
        # error to have a "dangling" 'e'
        if eof(io)
            code |= INVALID | EOF
            @goto done
        end
        b = peekbyte(io)
        exp = zero(IntType)
        negativeexp = false
        if b == MINUS
            negativeexp = true
            readbyte(io)
            if eof(io)
                code |= INVALID | EOF
                @goto done
            end
            b = peekbyte(io)
        elseif b == PLUS
            readbyte(io)
            if eof(io)
                code |= INVALID | EOF
                @goto done
            end
            b = peekbyte(io)
        end
        parseddigitsexp = false
        while NEG_ONE < b < TEN
            b = readbyte(io)
            parseddigitsexp = true
            # process digits
            exp, ov_mul = Base.mul_with_overflow(exp, IntType(10))
            exp, ov_add = Base.add_with_overflow(exp, IntType(b - ZERO))
            (ov_mul | ov_add) && (fastseek!(io, r.pos); return _defaultparser(io, r, wider(IntType); decimal=decimal))
            if eof(io)
                if (parseddigits | parseddigitsfrac)
                    r.result = scale(T, v, ifelse(negativeexp, -exp, exp) - frac, negative)
                    code |= OK | EOF
                else
                    code |= INVALID | EOF
                end
                @goto done
            end
            b = peekbyte(io)
        end
        if (parseddigits | parseddigitsfrac) & parseddigitsexp
            r.result = scale(T, v, ifelse(negativeexp, -exp, exp) - frac, negative)
            code |= OK | EOF
        else
            code |= INVALID | ifelse(eof(io), EOF, SUCCESS)
        end
    else
        r.result = scale(T, v, -frac, negative)
        code |= OK | ifelse(eof(io), EOF, SUCCESS)
    end

@label done
    r.code |= code
    return r
end
