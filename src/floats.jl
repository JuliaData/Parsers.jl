wider(::Type{Int64}) = Int128
wider(::Type{Int128}) = BigInt

# Base.exponent_max(T) + Base.significand_bits(T) + 3 # "-0."
maxdigits(::Type{Float64}) = 1079
maxdigits(::Type{Float32}) = 154
maxdigits(::Type{Float16}) = 29
maxdigits(::Type{BigFloat}) = typemax(Int64)

# include a non-inlined version in case of widening (otherwise, all widened cases would fully inline)
@noinline _typeparser(::Type{T}, source, pos, len, b, code, options::Options{ignorerepeated, ignoreemptylines, Q, debug, S, D, DF}, ::Type{IntType}) where {T <: SupportedFloats, ignorerepeated, ignoreemptylines, Q, debug, S, D, DF, IntType} =
    typeparser(T, source, pos, len, b, code, options, IntType)

@inline function typeparser(::Type{T}, source, pos, len, b, code, options::Options{ignorerepeated, ignoreemptylines, Q, debug, S, D, DF}, ::Type{IntType}=Int64) where {T <: SupportedFloats, ignorerepeated, ignoreemptylines, Q, debug, S, D, DF, IntType}
    startpos = pos
    origb = b
    x = zero(T)
    digits = zero(IntType)
    ndigits = 0
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
        ndigits += 1
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
        elseif ndigits > maxdigits(T)
            fastseek!(source, startpos)
            code |= INVALID
            @goto done
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
            code |= ((startpos + 1) == pos ? INVALID : OK) | EOF
            @goto done
        end
        b = peekbyte(source, pos)
        if b - UInt8('0') > 0x09 && !(b == UInt8('e') || b == UInt8('E') || b == UInt8('f') || b == UInt8('F'))
            if ndigits == 0
                code |= INVALID
                @goto done
            else
                x = T(ifelse(neg, -digits, digits))
                code |= OK
                @goto done
            end
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

using BitFloats

const POW10s = [exp10(Float128(i)) for i = 0:340]

pow10(e) = (@inbounds x = POW10s[e+1]; return x)

function scale(::Type{T}, v::Union{Int64, Int128}, exp, neg) where {T <: Union{Float16, Float32, Float64}}
    # @show typeof(v), v, exp
    exp = (exp > 309) ? 309 : (exp < -340) ? -340 : exp
    v == 0 && return zero(T)
    if exp < 0
        x = v / pow10(-exp)
    else
        x = v * pow10(exp)
    end
    # @show x
    return T(neg ? -x : x)
end

# slow fallback
function scale(::Type{T}, v, exp, neg) where {T}
    if exp < 0
        return T((neg ? -v : v) / BigFloat(10)^(-exp))
    else
        return T((neg ? -v : v) * BigFloat(10)^exp)
    end
end