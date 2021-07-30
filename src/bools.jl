@inline function typeparser(::Type{Bool}, source, pos, len, b, code, options::Options)
    x = false
    trues = options.trues
    falses = options.falses
    if trues === nothing
        if b == UInt8('t')
            pos += 1
            incr!(source)
            if eof(source, pos, len)
                code |= INVALID | EOF
                @goto done
            end
            b = peekbyte(source, pos)
            if b == UInt8('r')
                pos += 1
                incr!(source)
                if eof(source, pos, len)
                    code |= INVALID | EOF
                    @goto done
                end
                b = peekbyte(source, pos)
                if b == UInt8('u')
                    pos += 1
                    incr!(source)
                    if eof(source, pos, len)
                        code |= INVALID | EOF
                        @goto done
                    end
                    b = peekbyte(source, pos)
                    if b == UInt8('e')
                        pos += 1
                        incr!(source)
                        x = true
                        code |= OK
                        if eof(source, pos, len)
                            code |= EOF
                        end
                        @goto done
                    end
                end
            end
        else
            intx, intcode, intpos = typeparser(UInt8, source, pos, len, b, code, options)
            if ok(intcode) && intx < 0x02
                x = intx == 0x01 ? true : false
                code = intcode
                pos = intpos
                @goto done
            end
        end
    else
        if source isa AbstractVector{UInt8}
            startptr = pointer(source, pos)
            for (i, (ptr, ptrlen)) in enumerate(trues)
                if pos + ptrlen - 1 <= len
                    match = memcmp(startptr, ptr, ptrlen)
                    if match
                        x = true
                        code |= OK
                        pos = pos + ptrlen
                        if eof(source, pos, len)
                            code |= EOF
                        end
                        @goto done
                    end
                end
            end
        else # source isa IO
            for (i, (ptr, ptrlen)) in enumerate(trues)
                matched = match!(source, ptr, ptrlen)
                if matched
                    x = true
                    code |= OK
                    pos = pos + ptrlen
                    if eof(source, pos, len)
                        code |= EOF
                    end
                    @goto done
                end
            end
        end
    end
    if falses === nothing
        if b == UInt8('f')
            pos += 1
            incr!(source)
            if eof(source, pos, len)
                code |= INVALID | EOF
                @goto done
            end
            b = peekbyte(source, pos)
            if b == UInt8('a')
                pos += 1
                incr!(source)
                if eof(source, pos, len)
                    code |= INVALID | EOF
                    @goto done
                end
                b = peekbyte(source, pos)
                if b == UInt8('l')
                    pos += 1
                    incr!(source)
                    if eof(source, pos, len)
                        code |= INVALID | EOF
                        @goto done
                    end
                    b = peekbyte(source, pos)
                    if b == UInt8('s')
                        pos += 1
                        incr!(source)
                        if eof(source, pos, len)
                            code |= INVALID | EOF
                            @goto done
                        end
                        b = peekbyte(source, pos)
                        if b == UInt8('e')
                            pos += 1
                            incr!(source)
                            code |= OK
                            if eof(source, pos, len)
                                code |= EOF
                            end
                            @goto done
                        end
                    end
                end
            end
        end
    else
        if source isa AbstractVector{UInt8}
            startptr = pointer(source, pos)
            for (i, (ptr, ptrlen)) in enumerate(falses)
                if pos + ptrlen - 1 <= len
                    match = memcmp(startptr, ptr, ptrlen)
                    if match
                        x = false
                        code |= OK
                        pos = pos + ptrlen
                        if eof(source, pos, len)
                            code |= EOF
                        end
                        @goto done
                    end
                end
            end
        else # source isa IO
            for (i, (ptr, ptrlen)) in enumerate(falses)
                matched = match!(source, ptr, ptrlen)
                if matched
                    x = false
                    code |= OK
                    pos = pos + ptrlen
                    if eof(source, pos, len)
                        code |= EOF
                    end
                    @goto done
                end
            end
        end
    end
    fastseek!(source, pos - 1)
    code |= INVALID

@label done
    return x, code, pos
end