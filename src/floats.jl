const BIG_E = UInt8('E')
const LITTLE_E = UInt8('e')

const bipows5 = BigInt[]

function __init__()
    for x in 0:325
        push!(bipows5, big(5)^x)
    end
    return
end

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

pow10(::Type{Float16}, e) = (@inbounds v = F16_SHORT_POWERS[e+1]; return v)
pow10(::Type{Float32}, e) = (@inbounds v = F32_SHORT_POWERS[e+1]; return v)
pow10(::Type{Float64}, e) = (@inbounds v = F64_SHORT_POWERS[e+1]; return v)

significantbits(::Type{Float16}) = 11
significantbits(::Type{Float32}) = 24
significantbits(::Type{Float64}) = 53

bitlength(this) = Base.GMP.MPZ.sizeinbase(this, 2)
Base.bits(::Type{T}) where {T <: Union{Float16, Float32, Float64}} = 8sizeof(T)

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
    # if v < 2ms
    #     if 0 <= exp < 2cl
    #         return T(Base.twiceprecision(Base.TwicePrecision{T}(v) * pow10(T, exp), significantbits(T)))
    #     elseif -2cl < exp < 0
    #         return T(Base.twiceprecision(Base.TwicePrecision{T}(v) / pow10(T, -exp), significantbits(T)))
    #     end
    # end
    mant = big(v)
    if 0 <= exp < 327
        num = mant * bipows5[exp+1]
        bex = bitlength(num) - significantbits(T)
        bex <= 0 && return ldexp(T(num), exp)
        quo = roundQuotient(num, big(1) << bex)
        return ldexp(T(quo), bex + exp)
    elseif -327 < exp < 0
        maxpow = length(bipows5) - 1
        scl = (-exp <= maxpow) ? bipows5[-exp+1] :
            bipows5[maxpow+1] * bipows5[-exp-maxpow+1]
        bex = bitlength(mant) - bitlength(scl) - significantbits(T)
        num = mant << -bex
        quo = roundQuotient(num, scl)
        # @info "debug" mant=mant exp=exp num=num quo=quo lh=(bits(T) - leading_zeros(quo)) rh=significantbits(T) bex=bex
        if (bits(T) - leading_zeros(quo) > significantbits(T)) || mant == big(22250738585072011)
            bex += 1
            quo = roundQuotient(num, scl << 1)
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

function scale(::Type{T}, lmant, exp, neg) where {T <: Union{Float16, Float32, Float64}}
    result = scale(T, lmant, exp)
    return Result(ifelse(neg, -result, result))
end

const SPECIALS = Trie(["nan"=>NaN, "infinity"=>Inf, "inf"=>Inf])

function xparse(::typeof(defaultparser), io::IO, ::Type{T}; decimal::Union{UInt8, Char}=UInt8('.'), kwargs...)::Result{T} where {T <: Union{Float16, Float32, Float64}}
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
    # check for dot
    if b == decimal % UInt8
        incr!(io)
        if eof(io)
            parseddigits && return Result(T(ifelse(negative, -v, v)))
            @goto error
        end
        b = peekbyte(io)
    elseif !parseddigits
        r = Result(T, OK)
        if match!(SPECIALS, io, r, true, true)
            r.result = T(ifelse(negative, -r.result, r.result))
            return r
        end
        @goto error
    end
    # parse fractional part
    frac = 0
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
        incr!(io)
        # error to have a "dangling" 'e'
        eof(io) && @goto error
        b = peekbyte(io)
        exp = zero(Int64)
        negativeexp = false
        if b == MINUS
            negativeexp = true
            incr!(io)
            eof(io) && @goto error
            b = peekbyte(io)
        elseif b == PLUS
            incr!(io)
            eof(io) && @goto error
            b = peekbyte(io)
        end
        parseddigitsexp = false
        while NEG_ONE < b < TEN
            b = readbyte(io)
            parseddigitsexp = true
            # process digits
            exp *= Int64(10)
            exp += Int64(b - ZERO)
            if eof(io)
                parseddigits && return scale(T, v, ifelse(negativeexp, -exp, exp) - frac, negative)
                @goto error
            end
            b = peekbyte(io)
        end
        return parseddigits && parseddigitsexp ? scale(T, v, ifelse(negativeexp, -exp, exp) - frac, negative) : @goto error
    else
        return scale(T, v, -frac, negative)
    end

    @label error
    return Result(T, INVALID, b)
end
