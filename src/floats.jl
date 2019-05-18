wider(::Type{Int64}) = Int128
wider(::Type{Int128}) = BigInt

# include a non-inlined version in case of widening (otherwise, all widened cases would fully inline)
@noinline _typeparser(::Type{T}, source, pos, len, b, code, options::Options{ignorerepeated, Q, debug, S, D, DF}, ::Type{IntType}) where {T <: AbstractFloat, ignorerepeated, Q, debug, S, D, DF, IntType} =
    typeparser(T, source, pos, len, b, code, options, IntType)

@inline function typeparser(::Type{T}, source, pos, len, b, code, options::Options{ignorerepeated, Q, debug, S, D, DF}, ::Type{IntType}=Int64) where {T <: AbstractFloat, ignorerepeated, Q, debug, S, D, DF, IntType}
    startpos = pos
    origb = b
    x = zero(T)
    digits = zero(IntType)
    if debug
        println("float parsing")
    end
    neg = b == UInt8('-')
    if neg || b == UInt8('+')
        pos += 1
        incr!(source)
    end
    if eof(source, pos, len)
        code |= INVALID | EOF
        @goto done
    end
    b = peekbyte(source, pos)
    if b == options.decimal
        @goto decimalcheck
    end
    b -= UInt8('0')
    if debug
        println("float 1) $(b + UInt8('0'))")
    end
    if b > 0x09
        # character isn't a digit, check for special values, otherwise INVALID
        b += UInt8('0')
        if b == UInt8('n') || b == UInt8('N')
            pos += 1
            incr!(source)
            if eof(source, pos, len)
                code |= EOF
                @goto invalid
            end
            b = peekbyte(source, pos)
            if b == UInt8('a') || b == UInt8('A')
                pos += 1
                incr!(source)
                if eof(source, pos, len)
                    code |= EOF
                    @goto invalid
                end
                b = peekbyte(source, pos)
                if b == UInt8('n') || b == UInt8('N')
                    x = T(NaN)
                    pos += 1
                    incr!(source)
                    if eof(source, pos, len)
                        code |= EOF
                    end
                    code |= OK
                    @goto done
                end
            end
        elseif b == UInt8('i') || b == UInt8('I')
            pos += 1
            incr!(source)
            if eof(source, pos, len)
                code |= EOF
                @goto invalid
            end
            b = peekbyte(source, pos)
            if b == UInt8('n') || b == UInt8('N')
                pos += 1
                incr!(source)
                if eof(source, pos, len)
                    code |= EOF
                    @goto invalid
                end
                b = peekbyte(source, pos)
                if b == UInt8('f') || b == UInt8('F')
                    x = ifelse(neg, T(-Inf), T(Inf))
                    code |= OK
                    pos += 1
                    incr!(source)
                    if eof(source, pos, len)
                        code |= EOF
                        @goto done
                    end
                    b = peekbyte(source, pos)
                    if b == UInt8('i') || b == UInt8('I')
                        pos += 1
                        incr!(source)
                        if eof(source, pos, len)
                            code |= EOF
                            @goto done
                        end
                        b = peekbyte(source, pos)
                        if b == UInt8('n') || b == UInt8('N')
                            pos += 1
                            incr!(source)
                            if eof(source, pos, len)
                                code |= EOF
                                @goto done
                            end
                            b = peekbyte(source, pos)
                            if b == UInt8('i') || b == UInt8('I')
                                pos += 1
                                incr!(source)
                                if eof(source, pos, len)
                                    code |= EOF
                                    @goto done
                                end
                                b = peekbyte(source, pos)
                                if b == UInt8('t') || b == UInt8('T')
                                    pos += 1
                                    incr!(source)
                                    if eof(source, pos, len)
                                        code |= EOF
                                        @goto done
                                    end
                                    b = peekbyte(source, pos)
                                    if b == UInt8('y') || b == UInt8('Y')
                                        pos += 1
                                        incr!(source)
                                        if eof(source, pos, len)
                                            code |= EOF
                                        end
                                        @goto done
                                    end
                                end
                            end
                        end
                    end
                    @goto done
                end
            end
        else
        end
@label invalid
        fastseek!(source, startpos)
        code |= INVALID
        @goto done
    end
    while true
        digits = IntType(10) * digits + b
        pos += 1
        incr!(source)
        if eof(source, pos, len)
            x = T(ifelse(neg, -digits, digits))
            code |= OK | EOF
            @goto done
        end
        b = peekbyte(source, pos) - UInt8('0')
        if debug
            println("float 2) $(b + UInt8('0'))")
        end
        b > 0x09 && break
        if overflows(IntType) && digits > overflowval(IntType)
            fastseek!(source, startpos)
            return _typeparser(T, source, startpos, len, origb, code, options, wider(IntType))
        end
    end
    b += UInt8('0')
    if debug
        println("float 3) $(Char(b))")
    end
@label decimalcheck
    if b == options.decimal
        pos += 1
        incr!(source)
        if eof(source, pos, len)
            x = T(ifelse(neg, -digits, digits))
            code |= OK | EOF
            @goto done
        end
        b = peekbyte(source, pos)
        if b - UInt8('0') > 0x09 && !(b == UInt8('e') || b == UInt8('E') || b == UInt8('f') || b == UInt8('F'))
            x = T(ifelse(neg, -digits, digits))
            code |= OK
            @goto done
        end
    end
    frac = 0
    if debug
        println("float 4) $(Char(b))")
    end
    b -= UInt8('0')
    if b < 0x0a
        while true
            digits = IntType(10) * digits + b
            pos += 1
            incr!(source)
            frac += 1
            if eof(source, pos, len)
                x = scale(T, digits, -frac, neg)
                code |= OK | EOF
                @goto done
            end
            b = peekbyte(source, pos) - UInt8('0')
            if debug
                println("float 5) $b")
            end
            b > 0x09 && break
            if overflows(IntType) && digits > overflowval(IntType)
                fastseek!(source, startpos)
                return _typeparser(T, source, startpos, len, origb, code, options, wider(IntType))
            end
        end
    end
    b += UInt8('0')
    if debug
        println("float 6) $(Char(b))")
    end
    # check for exponent notation
    if b == UInt8('e') || b == UInt8('E') || b == UInt8('f') || b == UInt8('F')
        pos += 1
        incr!(source)
        # error to have a "dangling" 'e'
        if eof(source, pos, len)
            code |= INVALID | EOF
            @goto done
        end
        b = peekbyte(source, pos)
        if debug
            println("float 7) $(Char(b))")
        end
        exp = zero(IntType)
        negexp = b == UInt8('-')
        if negexp || b == UInt8('+')
            pos += 1
            incr!(source)
        end
        b = peekbyte(source, pos) - UInt8('0')
        if debug
            println("float 8) $b")
        end
        if b > 0x09
            # invalid to have a "dangling" 'e'
            code |= INVALID
            @goto done
        end
        while true
            exp = IntType(10) * exp + b
            pos += 1
            incr!(source)
            if eof(source, pos, len)
                x = scale(T, digits, ifelse(negexp, -exp, exp) - frac, neg)
                code |= OK | EOF
                @goto done
            end
            b = peekbyte(source, pos) - UInt8('0')
            if debug
                println("float 9) $b")
            end
            if b > 0x09
                x = scale(T, digits, ifelse(negexp, -exp, exp) - frac, neg)
                code |= OK
                @goto done
            end
            if overflows(IntType) && exp > overflowval(IntType)
                fastseek!(source, startpos)
                return _typeparser(T, source, startpos, len, origb, code, options, wider(IntType))
            end
        end
    else
        x = scale(T, digits, -frac, neg)
        code |= OK
    end

@label done
    return x, code, pos
end

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
# copied from base/gmp.jl:285
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

function scale(::Type{T}, v, exp) where {T <: Union{Float16, Float32, Float64}}
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
            # this branch isn't tested
            MPZ.set!(scl, bipows5[maxpow+1])
            MPZ.mul!(scl, bipows5[-exp-maxpow+1])
        end
        bex = bitlength(mant) - bitlength(scl) - significantbits(T)
        bex = min(bex, 0)
        num = MPZ.mul_2exp!(mant, -bex)
        quo = roundQuotient(num, scl)
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
