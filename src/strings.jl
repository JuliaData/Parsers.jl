# this is mostly copy-pasta from Parsers.jl main xparse function
@inline function xparse(::Type{T}, source::Union{AbstractVector{UInt8}, IO}, pos, len, options::Options{ignorerepeated, Q, debug, S, D, DF}) where {T <: AbstractString, ignorerepeated, Q, debug, S, D, DF}
    startpos = vstartpos = vpos = pos
    sentinelpos = 0
    code = SUCCESS
    sentinel = options.sentinel
    quoted = false
    if debug
        println("parsing $T, pos=$pos, len=$len")
    end
    if eof(source, pos, len)
        code = (sentinel === missing ? SENTINEL : OK) | EOF
        @goto donedone
    end
    b = peekbyte(source, pos)
    if debug
        println("string 1) parsed: '$(escape_string(string(Char(b))))'")
    end
    # strip leading whitespace
    while b == options.wh1 || b == options.wh2
        if debug
            println("stripping leading whitespace")
        end
        pos += 1
        incr!(source)
        if eof(source, pos, len)
            code |= EOF
            @goto donedone
        end
        b = peekbyte(source, pos)
        if debug
            println("string 2) parsed: '$(escape_string(string(Char(b))))'")
        end
    end
    # check for start of quoted field
    if Q
        quoted = b == options.oq
        if quoted
            if debug
                println("detected open quote character")
            end
            code = QUOTED
            pos += 1
            vstartpos = pos
            incr!(source)
            if eof(source, pos, len)
                code |= INVALID_QUOTED_FIELD
                @goto donedone
            end
            b = peekbyte(source, pos)
            if debug
                println("string 3) parsed: '$(escape_string(string(Char(b))))'")
            end
            # ignore whitespace within quoted field
            while b == options.wh1 || b == options.wh2
                if debug
                    println("stripping whitespace within quoted field")
                end
                pos += 1
                incr!(source)
                if eof(source, pos, len)
                    code |= INVALID_QUOTED_FIELD | EOF
                    @goto donedone
                end
                b = peekbyte(source, pos)
                if debug
                    println("string 4) parsed: '$(escape_string(string(Char(b))))'")
                end
            end
        end
    end
    # check for sentinel values if applicable
    if sentinel !== nothing && sentinel !== missing
        if debug
            println("checking for sentinel value")
        end
        sentstart = pos
        sentinelpos = checksentinel(source, pos, len, sentinel, debug)
    end
    vpos = pos
    if Q
        # for quoted fields, find the closing quote character
        # we should be positioned at the correct place to find the closing quote character if everything is as it should be
        # if we don't find the quote character immediately, something's wrong, so mark INVALID
        if quoted
            if debug
                println("looking for close quote character")
            end
            same = options.cq == options.e
            while true
                vpos = pos
                pos += 1
                incr!(source)
                if same && b == options.e
                    if eof(source, pos, len)
                        code |= EOF
                        @goto donedone
                    elseif peekbyte(source, pos) != options.cq
                        break
                    end
                    code |= ESCAPED_STRING
                    pos += 1
                    incr!(source)
                elseif b == options.e
                    if eof(source, pos, len)
                        code |= INVALID_QUOTED_FIELD | EOF
                        @goto donedone
                    end
                    code |= ESCAPED_STRING
                    pos += 1
                    incr!(source)
                elseif b == options.cq
                    if eof(source, pos, len)
                        code |= EOF
                        @goto donedone
                    end
                    break
                end
                if eof(source, pos, len)
                    code |= INVALID_QUOTED_FIELD | EOF
                    @goto donedone
                end
                b = peekbyte(source, pos)
                if debug
                    println("string 9) parsed: '$(escape_string(string(Char(b))))'")
                end
            end
            b = peekbyte(source, pos)
            if debug
                println("string 10) parsed: '$(escape_string(string(Char(b))))'")
            end
            # ignore whitespace after quoted field
            while b == options.wh1 || b == options.wh2
                if debug
                    println("stripping trailing whitespace after close quote character")
                end
                pos += 1
                incr!(source)
                if eof(source, pos, len)
                    code |= EOF
                    @goto donedone
                end
                b = peekbyte(source, pos)
                if debug
                    println("string 11) parsed: '$(escape_string(string(Char(b))))'")
                end
            end
        end
    end
    if options.delim !== nothing
        delim = options.delim
        quo = Int(!quoted)
        # now we check for a delimiter; if we don't find it, keep parsing until we do
        if debug
            println("checking for delimiter: pos=$pos")
        end
        while true
            if !ignorerepeated
                if delim isa UInt8
                    if b == delim
                        pos += 1
                        incr!(source)
                        code |= DELIMITED
                        @goto donedone
                    end
                else
                    predelimpos = pos
                    pos = checkdelim(source, pos, len, delim)
                    if pos > predelimpos
                        # found the delimiter we were looking for
                        code |= DELIMITED
                        @goto donedone
                    end
                end
            else
                if delim isa UInt8
                    matched = false
                    while b == delim
                        matched = true
                        pos += 1
                        incr!(source)
                        if eof(source, pos, len)
                            code |= DELIMITED
                            @goto donedone
                        end
                        b = peekbyte(source, pos)
                        if debug
                            println("string 14) parsed: '$(escape_string(string(Char(b))))'")
                        end
                    end
                    if matched
                        code |= DELIMITED
                        @goto donedone
                    end
                else
                    matched = false
                    predelimpos = pos
                    pos = checkdelim(source, pos, len, delim)
                    while pos > predelimpos
                        matched = true
                        if eof(source, pos, len)
                            code |= DELIMITED
                            @goto donedone
                        end
                        predelimpos = pos
                        pos = checkdelim(source, pos, len, delim)
                    end
                    if matched
                        code |= DELIMITED
                        @goto donedone
                    end
                end
            end
            # didn't find delimiter, but let's check for a newline character
            if b == UInt8('\n')
                pos += 1
                incr!(source)
                code |= NEWLINE | ifelse(eof(source, pos, len), EOF, SUCCESS)
                @goto donedone
            elseif b == UInt8('\r')
                pos += 1
                incr!(source)
                if !eof(source, pos, len) && peekbyte(source, pos) == UInt8('\n')
                    pos += 1
                    incr!(source)
                end
                code |= NEWLINE | ifelse(eof(source, pos, len), EOF, SUCCESS)
                @goto donedone
            end
            # didn't find delimiter nor newline, so increment and check the next byte
            pos += 1
            vpos += quo
            incr!(source)
            if eof(source, pos, len)
                code |= EOF
                @goto donedone
            end
            b = peekbyte(source, pos)
        end
    end

@label donedone
    if sentinel !== nothing && sentinel !== missing && sentstart == vstartpos && sentinelpos == vpos
        # if we matched a sentinel value that was as long or longer than our type value
        code |= SENTINEL
    elseif sentinel === missing && startpos == vpos
        code |= SENTINEL
    else
        code |= OK
    end
    if debug
        println("finished parsing: $(codes(code))")
    end
    return code, code, Int64(vstartpos), Int64(vpos - vstartpos), Int64(pos - startpos)
end