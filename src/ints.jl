overflows(::Type{T}) where {T} = true
overflows(::Type{BigInt}) = false
overflowval(::Type{T}) where {T <: Integer} = div(typemax(T) - T(9), T(10))
# if we eventually support non-base 10
# overflowval(::Type{T}, base) where {T <: Integer} = div(typemax(T) - base + 1, base)

@inline function typeparser(::Type{T}, source, pos, len, b, code, pl, opts) where {T <: Integer}
    x = zero(T)
    neg = false
    has_groupmark = opts.groupmark !== nothing
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
        if has_groupmark
            b, nb = dpeekbyte(source, pos) .- UInt8('0')
            if (opts.groupmark)::UInt8 - UInt8('0') == b && nb <= 0x09
                incr!(source)
                pos += 1
                b = nb
            end
        else
            b = peekbyte(source, pos) - UInt8('0')
        end
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
        if has_groupmark
            b, nb = dpeekbyte(source, pos) .- UInt8('0')
            if (opts.groupmark)::UInt8 - UInt8('0') == b && nb <= 0x09
                incr!(source)
                pos += 1
                b = nb
            end
        else
            b = peekbyte(source, pos) - UInt8('0')
        end
        if b > 0x09
            code |= OK
            @goto done
        end
    end

@label done
    return pos, code, PosLen(pl.pos, pos - pl.pos), x
end

@inline function typeparser(::Type{Number}, source, pos, len, b, code, pl, opts)
    x = Ref{Number}()
    pos, code = parsenumber(source, pos, len, b, y -> (x[] = y), opts)
    return pos, code, PosLen(pl.pos, pos - pl.pos), x[]
end

@inline function parsenumber(source, pos, len, b, f::F, opts=OPTIONS) where {F}
    startpos = pos
    code = startcode = SUCCESS
    # begin parsing
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
    # parse rest of number
    _, code, pos = parsedigits(Number, source, pos, len, b, code, OPTIONS, Int64(0), neg, startpos, true, f)
    if invalid(code)
        # by default, parsedigits only has up to Float64 precision; if we overflow
        # let's try BigFloat
        pos, code, _, x = typeparser(BigFloat, source, startpos, len, b, startcode, poslen(pos, 0), opts)
        if ok(code)
            f(x)
        end
    end

@label done
    return pos, code
end