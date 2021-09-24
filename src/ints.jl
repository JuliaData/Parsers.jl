overflows(::Type{T}) where {T} = true
overflows(::Type{BigInt}) = false
overflowval(::Type{T}) where {T <: Integer} = div(typemax(T) - T(9), T(10))
# if we eventually support non-base 10
# overflowval(::Type{T}, base) where {T <: Integer} = div(typemax(T) - base + 1, base)

@inline function typeparser(::Type{T}, source, pos, len, b, code, options) where {T <: Integer}
    x = zero(T)
    neg = false
    # start actual int parsing
    neg = b == UInt8('-')
    if neg || b == UInt8('+')
        pos += 1
        incr!(source)
    end
    if eof(source, pos, len)
        code |= INVALID | EOF
        @goto done
    end
    b = peekbyte(source, pos) - UInt8('0')
    if b > 0x09
        # character isn't a digit, INVALID value
        code |= INVALID
        @goto done
    end
    while true
        x = T(10) * x + unsafe_trunc(T, b)
        pos += 1
        incr!(source)
        if eof(source, pos, len)
            x = ifelse(neg, -x, x)
            code |= OK | EOF
            @goto done
        end
        b = peekbyte(source, pos) - UInt8('0')
        if b > 0x09
            # detected a non-digit, time to bail on value parsing
            x = ifelse(neg, -x, x)
            code |= OK
            @goto done
        end
        overflows(T) && x > overflowval(T) && break
    end
    # extra loop because we got too close to overflowing while parsing digits
    x = ifelse(neg, -x, x)
    while true
        x, ov_mul = Base.mul_with_overflow(x, T(10))
        x, ov_add = Base.add_with_overflow(x, ifelse(neg, -T(b), T(b)))
        if ov_mul | ov_add
            # we overflowed, mark as OVERFLOW
            code |= OVERFLOW
            # in this case, we know b is a digit that caused us
            # to overflow, so we don't really want to consider it for
            # a close quote character or delimiter, so if b is the last character
            # let's just bail as eof
            pos += 1
            incr!(source)
            if eof(source, pos, len)
                code |= EOF
            end
            @goto done
        end
        pos += 1
        incr!(source)
        if eof(source, pos, len)
            code |= OK | EOF
            @goto done
        end
        b = peekbyte(source, pos) - UInt8('0')
        if b > 0x09
            code |= OK
            @goto done
        end
    end

@label done
    return x, code, pos
end
