const BIG_N = UInt8('N')
const LITTLE_N = UInt8('n')
const BIG_A = UInt8('A')
const LITTLE_A = UInt8('a')
const BIG_I = UInt8('I')
const LITTLE_I = UInt8('i')
const BIG_F = UInt8('F')
const LITTLE_F = UInt8('f')
const BIG_T = UInt8('T')
const LITTLE_T = UInt8('t')
const BIG_Y = UInt8('Y')
const LITTLE_Y = UInt8('y')
const BIG_E = UInt8('E')
const LITTLE_E = UInt8('e')

const bipows5 = BigInt[big(5)^x for x = 0:325]

function roundQuotient(num, den)
    quo, rem = divrem(num, den)
    q = Int64(quo)
    cmpflg = cmp(rem << 1, den)
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

pow10(::Type{Float16}, e) = F16_SHORT_POWERS[e+1]
pow10(::Type{Float32}, e) = F32_SHORT_POWERS[e+1]
pow10(::Type{Float64}, e) = F64_SHORT_POWERS[e+1]

significantbits(::Type{Float16}) = 11
significantbits(::Type{Float32}) = 24
significantbits(::Type{Float64}) = 53

bitlength(this) = Base.GMP.MPZ.sizeinbase(this, 2)
Base.bits(::Type{T}) where {T <: Union{Float16, Float32, Float64}} = 8sizeof(T)

@inline function scale(::Type{T}, lmant, point) where {T <: Union{Float16, Float32, Float64}}
    ms = maxsig(T)
    cl = ceillog5(T)
    if lmant < ms
        # fastest path
        if 0 <= point < cl
            return T(lmant) * pow10(T, point)
        elseif -cl < point < 0
            return T(lmant) / pow10(T, -point)
        end
    end
    if lmant < 2ms
        if 0 <= point < 2cl
            return T(Base.twiceprecision(Base.TwicePrecision{T}(lmant) * pow10(T, point), significantbits(T)))
        elseif -2cl < point < 0
            return T(Base.twiceprecision(Base.TwicePrecision{T}(lmant) / pow10(T, -point), significantbits(T)))
        end
    end
    mant = big(lmant)
    if point >= 0
        num = mant * bipows5[point+1]
        bex = bitlength(num) - significantbits(T)
        bex <= 0 && return ldexp(T(num), point)
        quo = roundQuotient(num, big(1) << bex)
        return ldexp(T(quo), bex + point)
    end
    maxpow = length(bipows5) - 1
    scl = (-point <= maxpow) ? bipows5[-point+1] :
        bipows5[maxpow+1] * bipows5[-point-maxpow+1]
    bex = bitlength(mant) - bitlength(scl) - significantbits(T)
    num = mant << -bex
    quo = roundQuotient(num, scl)
    if bits(T) - leading_zeros(quo) > significantbits(T)
        bex += 1
        quo = roundQuotient(num, scl << 1)
    end
    return ldexp(T(quo), bex + point)
end

function scale(::Type{T}, lmant, point, neg) where {T <: Union{Float16, Float32, Float64}}
    result = scale(T, lmant, point)
    return Result(ifelse(neg, -result, result))
end

function xparse(io::IO, ::Type{T})::Result{T} where {T <: Union{Float16, Float32, Float64}}
    eof(io) && return Result(T, EOF)
    b = peekbyte(io)
    negative = false
    if b == MINUS # check for leading '-' or '+'
        negative = true
        incr!(io)
        eof(io) && return Result(T, EOF, b)
        b = peekbyte(io)
    elseif b == PLUS
        incr!(io)
        eof(io) && return Result(T, EOF, b)
        b = peekbyte(io)
    end
    # float digit parsing
    v = zero(Int64)
    parseddigits = false
    while NEG_ONE < b < TEN
        incr!(io)
        parseddigits = true
        # process digits
        v *= Int64(10)
        v += Int64(b - ZERO)
        eof(io) && return Result(T(ifelse(negative, -v, v)))
        b = peekbyte(io)
    end
    # if we didn't get any digits, check for NaN/Inf or leading dot
    if !parseddigits && !eof(io)
        if b == BIG_N || b == LITTLE_N
            b = readbyte(io)
            if !eof(io) && (b == LITTLE_A || b == BIG_A)
                b = readbyte(io)
                if b == BIG_N || b == LITTLE_N
                    return Result(T(NaN))
                end
            end
            @goto error
        elseif b == LITTLE_I || b == BIG_I
            b = readbyte(io)
            if !eof(io) && (b == LITTLE_N || b == BIG_N)
                b = readbyte(io)
                if b == LITTLE_F || b == BIG_F
                    resuilt = Result(T(ifelse(negative, -Inf, Inf)))
                    eof(io) && return result
                    b = peekbyte(io)
                    if b == LITTLE_I || b == BIG_I
                        # read the rest of INFINITY
                        readbyte(io)
                        eof(io) && return result
                        b = peekbyte(io)
                        b == LITTLE_N || b == BIG_N || return result
                        readbyte(io)
                        eof(io) && return result
                        b = readbyte(io)
                        b == LITTLE_I || b == BIG_I || return result
                        readbyte(io)
                        eof(io) && return result
                        b = peekbyte(io)
                        b == LITTLE_T || b == BIG_T || return result
                        readbyte(io)
                        eof(io) && return result
                        b = peekbyte(io)
                        b == LITTLE_Y || b == BIG_Y || return result
                        readbyte(io)
                        eof(io) && return result
                        b = peekbyte(io)
                    end
                    return result
                end
            end
            @goto error
        elseif b == PERIOD
            # keep parsing fractional part below
        else
            @goto error
        end
    end
    # parse fractional part
    frac = 0
    result = Result(T(ifelse(negative, -v, v)))
    if b == PERIOD
        if eof(io)
            if parseddigits
                return result
            else
                @goto error
            end
        end
        incr!(io)
        b = peekbyte(io)
    elseif b == LITTLE_E || b == BIG_E
        @goto parseexp
    else
        return result
    end

    while NEG_ONE < b < TEN
        incr!(io)
        frac += 1
        # process digits
        v *= Int64(10)
        v += Int64(b - ZERO)
        eof(io) && return scale(T, v, -frac, negative)
        b = peekbyte(io)
    end
    # parse potential exp
    if b == LITTLE_E || b == BIG_E
        @label parseexp
        eof(io) && return scale(T, v, -frac, negative)
        readbyte(io)
        b = peekbyte(io)
        exp = zero(Int64)
        negativeexp = false
        if b == MINUS
            negativeexp = true
            readbyte(io)
            b = peekbyte(io)
        elseif b == PLUS
            readbyte(io)
            b = peekbyte(io)
        end
        parseddigits = false
        while NEG_ONE < b < TEN
            b = readbyte(io)
            parseddigits = true
            # process digits
            exp *= Int64(10)
            exp += Int64(b - ZERO)
            eof(io) && return scale(T, v, ifelse(negativeexp, -exp, exp) - frac, negative)
            b = peekbyte(io)
        end
        return parseddigits ? scale(T, v, ifelse(negativeexp, -exp, exp) - frac, negative) : scale(T, v, -frac, negative)
    else
        return scale(T, v, -frac, negative)
    end

    @label error
    return Result(T, INVALID, b)
end
