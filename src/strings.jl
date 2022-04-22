# this is mostly copy-pasta from Parsers.jl main xparse function
function xparse(::Type{T}, source::Union{AbstractVector{UInt8}, IO}, pos, len, options, ::Type{S}=PosLen) where {T <: AbstractString, S}
    startpos = vstartpos = vpos = lastnonwhitespacepos = pos
    sentstart = sentinelpos = 0
    code = SUCCESS
    sentinel = options.sentinel
    quoted = false
    if eof(source, pos, len)
        code = (sentinel === missing ? SENTINEL : OK) | EOF
        @goto donedone
    end
    b = peekbyte(source, pos)
    # strip leading whitespace
    while b == options.wh1 || b == options.wh2
        pos += 1
        incr!(source)
        vpos = pos
        if options.stripwhitespace
            vstartpos = pos
        end
        if eof(source, pos, len)
            code |= EOF
            @goto donedone
        end
        b = peekbyte(source, pos)
    end
    # check for start of quoted field
    if options.quoted
        quoted = b == options.oq
        if quoted
            code = QUOTED
            pos += 1
            incr!(source)
            # since we're in quoted mode, reset vstartpos & vpos
            vstartpos = vpos = pos
            if eof(source, pos, len)
                code |= INVALID_QUOTED_FIELD
                @goto donedone
            end
            b = peekbyte(source, pos)
            # ignore whitespace within quoted field
            while b == options.wh1 || b == options.wh2
                pos += 1
                incr!(source)
                vpos = pos
                if options.stripquoted
                    vstartpos = pos
                end
                if eof(source, pos, len)
                    code |= INVALID_QUOTED_FIELD | EOF
                    @goto donedone
                end
                b = peekbyte(source, pos)
            end
        end
    end
    # check for sentinel values if applicable
    if sentinel !== nothing && sentinel !== missing
        sentstart = pos
        sentinelpos = checksentinel(source, pos, len, sentinel)
    end
    vpos = lastnonwhitespacepos = pos
    if options.quoted
        # for quoted fields, find the closing quote character
        if quoted
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
                # Always treat space ' ' and tab '\t' as whitespace when quoted
                if options.stripquoted && b != options.wh1 && b != options.wh2 && b != UInt8(' ') && b != UInt8('\t')
                    lastnonwhitespacepos = pos
                end
                b = peekbyte(source, pos)
            end
            b = peekbyte(source, pos)
            # ignore whitespace after quoted field
            while b == options.wh1 || b == options.wh2
                pos += 1
                incr!(source)
                if eof(source, pos, len)
                    code |= EOF
                    @goto donedone
                end
                b = peekbyte(source, pos)
            end
        end
    end
    if options.delim !== nothing
        delim = options.delim
        unquoted = Int(!quoted)
        # now we check for a delimiter; if we don't find it, keep parsing until we do
        while true
            if !options.ignorerepeated
                if delim isa UInt8
                    if b == delim
                        pos += 1
                        incr!(source)
                        code |= DELIMITED
                        @goto donedone
                    end
                elseif delim isa PtrLen
                    predelimpos = pos
                    pos = checkdelim(source, pos, len, delim)
                    if pos > predelimpos
                        # found the delimiter we were looking for
                        code |= DELIMITED
                        @goto donedone
                    end
                else
                    error()
                end
            else
                if delim isa UInt8
                    matched = false
                    matchednewline = false
                    while true
                        if b == delim
                            matched = true
                            code |= DELIMITED
                            pos += 1
                            incr!(source)
                        elseif !matchednewline && b == UInt8('\n')
                            matchednewline = matched = true
                            pos += 1
                            incr!(source)
                            pos = checkcmtemptylines(source, pos, len, options)
                            code |= NEWLINE | ifelse(eof(source, pos, len), EOF, SUCCESS)
                        elseif !matchednewline && b == UInt8('\r')
                            matchednewline = matched = true
                            pos += 1
                            incr!(source)
                            if !eof(source, pos, len) && peekbyte(source, pos) == UInt8('\n')
                                pos += 1
                                incr!(source)
                            end
                            pos = checkcmtemptylines(source, pos, len, options)
                            code |= NEWLINE | ifelse(eof(source, pos, len), EOF, SUCCESS)
                        else
                            break
                        end
                        if eof(source, pos, len)
                            @goto donedone
                        end
                        b = peekbyte(source, pos)
                    end
                    if matched
                        @goto donedone
                    end
                elseif delim isa PtrLen
                    matched = false
                    matchednewline = false
                    while true
                        predelimpos = pos
                        pos = checkdelim(source, pos, len, delim)
                        if pos > predelimpos
                            matched = true
                            code |= DELIMITED
                        elseif !matchednewline && b == UInt8('\n')
                            matchednewline = matched = true
                            pos += 1
                            incr!(source)
                            pos = checkcmtemptylines(source, pos, len, options)
                            code |= NEWLINE | ifelse(eof(source, pos, len), EOF, SUCCESS)
                        elseif !matchednewline && b == UInt8('\r')
                            matchednewline = matched = true
                            pos += 1
                            incr!(source)
                            if !eof(source, pos, len) && peekbyte(source, pos) == UInt8('\n')
                                pos += 1
                                incr!(source)
                            end
                            pos = checkcmtemptylines(source, pos, len, options)
                            code |= NEWLINE | ifelse(eof(source, pos, len), EOF, SUCCESS)
                        else
                            break
                        end
                        if eof(source, pos, len)
                            @goto donedone
                        end
                        b = peekbyte(source, pos)
                    end
                    if matched
                        @goto donedone
                    end
                else
                    error()
                end
            end
            # didn't find delimiter, but let's check for a newline character
            if b == UInt8('\n')
                pos += 1
                incr!(source)
                pos = checkcmtemptylines(source, pos, len, options)
                code |= NEWLINE | ifelse(eof(source, pos, len), EOF, SUCCESS)
                @goto donedone
            elseif b == UInt8('\r')
                pos += 1
                incr!(source)
                if !eof(source, pos, len) && peekbyte(source, pos) == UInt8('\n')
                    pos += 1
                    incr!(source)
                end
                pos = checkcmtemptylines(source, pos, len, options)
                code |= NEWLINE | ifelse(eof(source, pos, len), EOF, SUCCESS)
                @goto donedone
            end
            # didn't find delimiter nor newline, so increment and check the next byte
            pos += 1
            vpos += unquoted
            if quoted
                code |= INVALID_DELIMITER
            end
            if options.stripwhitespace
                if !quoted && b != options.wh1 && b != options.wh2
                    lastnonwhitespacepos = vpos
                end
            end
            incr!(source)
            if eof(source, pos, len)
                code |= EOF
                @goto donedone
            end
            b = peekbyte(source, pos)
        end
    elseif !quoted
        # no delimiter, so read until EOF
        while !eof(source, pos, len)
            pos += 1
            incr!(source)
            if options.stripwhitespace
                b = peekbyte(source, pos)
                if !quoted && b != options.wh1 && b != options.wh2
                    lastnonwhitespacepos = vpos
                end
            end
            vpos += 1
        end
    end

@label donedone
    ismissing = false
    if sentinel !== nothing && sentinel !== missing && sentstart == vstartpos && sentinelpos == vpos
        # if we matched a sentinel value that was as long or longer than our type value
        code |= SENTINEL
        ismissing = true
    elseif sentinel === missing && vstartpos == vpos
        code |= SENTINEL
        ismissing = true
    else
        code |= OK
    end
    if eof(source, pos, len)
        code |= EOF
    end
    if options.stripquoted || (options.stripwhitespace && !quoted)
        vpos = lastnonwhitespacepos
    end
    poslen = PosLen(vstartpos, vpos - vstartpos, ismissing, escapedstring(code))
    tlen = pos - startpos
    return Result{S}(code, tlen, poslen)
end
