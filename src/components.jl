# must be outermost layer
function Result(parser)
    function(::Type{T}, source, pos, len, ::Type{RT}=T) where {T, RT}
        Base.@_inline_meta
        startpos = pos
        code = SUCCESS
        b = eof(source, pos, len) ? 0x00 : peekbyte(source, pos)
        pl = poslen(pos, 0)
        pos, code, pl, x = parser(T, source, pos, len, b, code, pl)
        tlen = pos - startpos
        if valueok(code)
            y = x::T
            return Result{RT}(code, tlen, y)
        else
            return Result{RT}(code, tlen)
        end
    end
end

emptysentinel(opts::Options2) = emptysentinel(opts.checksentinel && isempty(opts.sentinel))
function emptysentinel(checksent)
    function(parser)
        function checkemptysentinel(::Type{T}, source, pos, len, b, code, pl) where {T}
            Base.@_inline_meta
            if eof(source, pos, len)
                if checksent
                    code |= SENTINEL | EOF
                    pl = withmissing(pl)
                else
                    code |= INVALID | EOF
                end
                return pos, code, pl, nothing
            end
            pos, code, pl, x = parser(T, source, pos, len, b, code, pl)
            if checksent && pos == pl.pos
                code &= ~(OK | INVALID)
                code |= SENTINEL
                pl = withmissing(pl)
            end
            return pos, code, pl, x
        end
    end
end

# just ' ' and '\t'
whitespace(opts::Options2) = whitespace(opts.stripwhitespace, opts.stripquoted)
function whitespace(stripwh, stripquoted)
    function(parser)
        function stripwhitespace(::Type{T}, source, pos, len, b, code, pl) where {T}
            Base.@_inline_meta
            # strip leading whitespace
            if stripwh
                while b == UInt8(' ') || b == UInt8('\t')
                    pos += 1
                    incr!(source)
                    if isgreedy(T) && (!quoted(code) || stripquoted)
                        # we're in a quoted string and user has requested
                        # to strip whitespace inside, OR user has requested
                        # to strip whitespace outside of quoted strings
                        pl = poslen(pos, 0)
                    end
                    if eof(source, pos, len)
                        code |= INVALID | EOF
                        return pos, code, pl, nothing
                    end
                    b = peekbyte(source, pos)
                end
            end
            pos, code, pl, x = parser(T, source, pos, len, b, code, pl)
            # strip trailing whitespace
            if stripwh && !eof(source, pos, len) && (!isgreedy(T) || (quoted(code) && escapedstring(code)))
                b = peekbyte(source, pos)
                while b == UInt8(' ') || b == UInt8('\t')
                    pos += 1
                    incr!(source)
                    if eof(source, pos, len)
                        code |= EOF
                        return pos, code, pl, x
                    end
                    b = peekbyte(source, pos)
                end
            end
            return pos, code, pl, x
        end
    end
end

function findendquoted(::Type{T}, source, pos, len, b, code, pl, isquoted, cq, e, stripquoted) where {T}
    # for quoted fields, find the closing quote character
    # we should be positioned at the correct place to find the closing quote character if everything is as it should be
    # if we don't find the quote character immediately, something's wrong, so mark INVALID
    if isquoted
        same = cq == e
        first = true
        # b is the first byte after oq for greedy
        while true
            # if stripquoted, we need to handle it here
            # instead of in the whitespace parser for strings
            if isgreedy(T) && (!stripquoted || (b != UInt8(' ') && b != UInt8('\t')))
                pl = poslen(pl.pos, (pos - pl.pos) + 1)
            end
            match, pos = checktoken(source, pos, len, b, e)
            if same && match
                # cq = '"', e = '"', and b = '"', so we might be done
                if eof(source, pos, len)
                    # we're done! cq was last possible byte
                    code |= EOF
                    if !first && !isgreedy(T)
                        # this means we've parsed something like a number,
                        # then immediately expected to find the closing quote
                        # character, but didn't (!first), so something's wrong
                        code |= INVALID
                    end
                    break
                end
                match, pos = checktoken(source, pos, len, b, cq)
                if !match
                    # we're done! e wasn't followed by cq
                    if !first && !isgreedy(T)
                        code |= INVALID
                    end
                    break
                end
                # this means we had e followed by cq
                # so the next byte is escaped
                code |= ESCAPED_STRING
                pl = withescaped(pl)
                pos += 1
                incr!(source)
            elseif match
                if eof(source, pos, len)
                    # "dangling" e, invalid
                    code |= INVALID_QUOTED_FIELD | EOF
                    break
                end
                # e, so next byte is escaped
                code |= ESCAPED_STRING
                pl = withescaped(pl)
                pos += 1
                incr!(source)
            end
            match, pos = checktoken(source, pos, len, b, cq)
            if match
                if !first && !isgreedy(T)
                    code |= INVALID
                end
                if eof(source, pos, len)
                    code |= EOF
                    break
                end
                # found cq, so we're done
                break
            end
            if eof(source, pos, len)
                code |= INVALID_QUOTED_FIELD | EOF
                break
            end
            first = false
            b = peekbyte(source, pos)
        end
    end
    return pos, code, pl
end

quoted(opts::Options2) = quoted(opts.checkquoted, opts.oq, opts.cq, opts.e, opts.stripquoted)
function quoted(checkquoted, oq, cq, e, stripquoted)
    function(parser)
        function findquoted(::Type{T}, source, pos, len, b, code, pl) where {T}
            Base.@_inline_meta
            isquoted = false
            if checkquoted
                isquoted, pos = checktoken(source, pos, len, b, oq)
            end
            if isquoted
                code |= QUOTED
                pl = poslen(pos, 0)
                if eof(source, pos, len)
                    # "dangling" oq, not valid
                    code |= INVALID_QUOTED_FIELD
                    return pos, code, pl, nothing
                end
                b = peekbyte(source, pos)
            end
            pos, code, pl, x = parser(T, source, pos, len, b, code, pl)
            if isgreedy(T) && isquoted
                return pos, code, pl, x
            end
            if eof(source, pos, len)
                if isquoted
                    # if we detected a quote character, it's an invalid quoted field due to eof in the middle
                    code |= INVALID_QUOTED_FIELD
                end
                return pos, code, pl, x
            end
            b = peekbyte(source, pos)
            pos, code, pl = findendquoted(T, source, pos, len, b, code, pl, isquoted, cq, e, stripquoted)
            return pos, code, pl, x
        end
    end
end

sentinel(opts::Options2) = sentinel(opts.checksentinel, opts.sentinel)
function sentinel(checksentinel, sentinel)
    function(parser)
        function checkforsentinel(::Type{T}, source, pos, len, b, code, pl) where {T}
            Base.@_inline_meta
            match, sentinelpos = (!checksentinel || isempty(sentinel)) ? (false, 0) : checksentinel(source, pos, len, sentinel)
            pos, code, pl, x = parser(T, source, pos, len, b, code, pl)
            if match && sentinelpos >= pos
                # if we matched a sentinel value that was as long or longer than our type value
                code &= ~(OK | INVALID | OVERFLOW)
                pos = sentinelpos
                fastseek!(source, pos - 1)
                code |= SENTINEL
                pl = withmissing(pl)
                if eof(source, pos, len)
                    code |= EOF
                end
            end
            return pos, code, pl, x
        end
    end
end

function finddelimiter(::Type{T}, source, pos, len, b, code, pl, delim, ignorerepeated, cmt, ignoreemptylines, stripwhitespace) where {T}
    # now we check for a delimiter; if we don't find it, keep parsing until we do
    while true
        if !ignorerepeated
            # we're checking for a single appearance of a delimiter
            match, pos = checktoken(source, pos, len, b, delim)
            if match
                code |= DELIMITED
                break
            end
        else
            # keep parsing as long as we keep matching delims/newlines
            matched = false
            matchednewline = false
            while true
                match, pos = checktoken(source, pos, len, b, delim)
                if match
                    matched = true
                    code |= DELIMITED
                    break
                elseif !matchednewline && b == UInt8('\n')
                    matchednewline = matched = true
                    pos += 1
                    incr!(source)
                    pos = checkcmtemptylines(source, pos, len, cmt, ignoreemptylines)
                    code |= NEWLINE | ifelse(eof(source, pos, len), EOF, SUCCESS)
                elseif !matchednewline && b == UInt8('\r')
                    matchednewline = matched = true
                    pos += 1
                    incr!(source)
                    if !eof(source, pos, len) && peekbyte(source, pos) == UInt8('\n')
                        pos += 1
                        incr!(source)
                    end
                    pos = checkcmtemptylines(source, pos, len, cmt, ignoreemptylines)
                    code |= NEWLINE | ifelse(eof(source, pos, len), EOF, SUCCESS)
                else
                    break
                end
                if eof(source, pos, len)
                    code |= EOF
                    break
                end
                b = peekbyte(source, pos)
            end
            if matched || eof(code)
                break
            end
        end
        # didn't find delimiter, but let's check for a newline character
        if b == UInt8('\n')
            pos += 1
            incr!(source)
            pos = checkcmtemptylines(source, pos, len, cmt, ignoreemptylines)
            code |= NEWLINE | ifelse(eof(source, pos, len), EOF, SUCCESS)
            break
        elseif b == UInt8('\r')
            pos += 1
            incr!(source)
            if !eof(source, pos, len) && peekbyte(source, pos) == UInt8('\n')
                pos += 1
                incr!(source)
            end
            pos = checkcmtemptylines(source, pos, len, cmt, ignoreemptylines)
            code |= NEWLINE | ifelse(eof(source, pos, len), EOF, SUCCESS)
            break
        end
        if !isgreedy(T) || quoted(code)
            # didn't find delimiter or newline, so we're invalid, keep parsing until we find delimiter, newline, or len
            code |= INVALID_DELIMITER
        end
        if isgreedy(T) && (!stripwhitespace || (b != UInt8(' ') && b != UInt8('\t')))
            pl = poslen(pl.pos, (pos - pl.pos) + 1)
        end
        pos += 1
        incr!(source)
        if eof(source, pos, len)
            code |= EOF
            break
        end
        b = peekbyte(source, pos)
    end
    return pos, code, pl
end

delimiter(opts::Options2) = delimiter(opts.checkdelim, opts.delim, opts.ignorerepeated, opts.cmt, opts.ignoreemptylines, opts.stripwhitespace)
function delimiter(checkdelim, delim, ignorerepeated, cmt, ignoreemptylines, stripwhitespace)
    function(parser)
        function findelimiter(::Type{T}, source, pos, len, b, code, pl) where {T}
            Base.@_inline_meta
            pos, code, pl, x = parser(T, source, pos, len, b, code, pl)
            if eof(code) || !checkdelim || delimited(code) # greedy case
                return pos, code, pl, x
            end
            b = peekbyte(source, pos)
            pos, code, pl = finddelimiter(T, source, pos, len, b, code, pl, delim, ignorerepeated, cmt, ignoreemptylines, stripwhitespace)
            return pos, code, pl, x
        end
    end
end

function typeparser(opts)
    function(::Type{T}, source, pos, len, b, code, pl) where {T}
        Base.@_inline_meta
        return typeparser(T, source, pos, len, b, code, pl, opts)
    end
end