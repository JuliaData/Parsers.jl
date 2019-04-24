module Parsers

using Dates

include("utils.jl")

struct Options{ignorerepeated, Q, debug, S, D, DF}
    sentinel::S # Union{Nothing, Missing, Vector{Tuple{Ptr{UInt8}, Int}}}
    wh1::UInt8
    wh2::UInt8
    oq::UInt8
    cq::UInt8
    e::UInt8
    delim::D # Union{Nothing, UInt8, Tuple{Ptr{UInt8}, Int}}
    decimal::UInt8
    trues::Union{Nothing, Vector{Tuple{Ptr{UInt8}, Int}}}
    falses::Union{Nothing, Vector{Tuple{Ptr{UInt8}, Int}}}
    dateformat::DF # Union{Nothing, Dates.DateFormat}
    strict::Bool
    silencewarnings::Bool
end

prepare(x::Vector{String}) = sort!(map(ptrlen, x), by=x->x[2], rev=true)

function Options(
            sentinel::Union{Nothing, Missing, Vector{String}}, 
            wh1::Union{UInt8, Char},
            wh2::Union{UInt8, Char},
            oq::Union{UInt8, Char},
            cq::Union{UInt8, Char},
            e::Union{UInt8, Char},
            delim::Union{Nothing, UInt8, Char, String},
            decimal::Union{UInt8, Char},
            trues::Union{Nothing, Vector{String}},
            falses::Union{Nothing, Vector{String}},
            dateformat::Union{Nothing, String, Dates.DateFormat},
            ignorerepeated, quoted, debug, strict=false, silencewarnings=false)
    sent = sentinel === nothing || sentinel === missing ? sentinel : prepare(sentinel)
    del = delim === nothing ? nothing : delim isa String ? ptrlen(delim) : delim % UInt8
    trues = trues === nothing ? nothing : prepare(trues)
    falses = falses === nothing ? nothing : prepare(falses)
    df = dateformat === nothing ? nothing : dateformat isa String ? Dates.DateFormat(dateformat) : dateformat
    return Options{ignorerepeated, quoted, debug, typeof(sent), typeof(del), typeof(df)}(sent, wh1 % UInt8, wh2 % UInt8, oq % UInt8, cq % UInt8, e % UInt8, del, decimal % UInt8, trues, falses, df, strict, silencewarnings)
end

const OPTIONS = Options(nothing, UInt8(' '), UInt8('\t'), UInt8('"'), UInt8('"'), UInt8('"'), nothing, UInt8('.'), nothing, nothing, nothing, false, false, false)
const XOPTIONS = Options(missing, UInt8(' '), UInt8('\t'), UInt8('"'), UInt8('"'), UInt8('"'), UInt8(','), UInt8('.'), nothing, nothing, nothing, false, true, false)

# high-level convenience functions like in Base
"Attempt to parse a value of type `T` from string `str`. Throws `Parsers.Error` on parser failures and invalid values."
function parse(::Type{T}, buf::Union{AbstractVector{UInt8}, AbstractString, IO}; pos::Int64=1, len::Int64=buf isa IO ? 0 : sizeof(buf), sentinel=nothing, wh1::Union{UInt8, Char}=UInt8(' '), wh2::Union{UInt8, Char}=UInt8('\t'), quoted::Bool=false, openquotechar::Union{UInt8, Char}=UInt8('"'), closequotechar::Union{UInt8, Char}=UInt8('"'), escapechar::Union{UInt8, Char}=UInt8('"'), ignorerepeated::Bool=false, delim::Union{UInt8, Char, Tuple{Ptr{UInt8}, Int}, AbstractString, Nothing}=nothing, decimal::Union{UInt8, Char}=UInt8('.'), trues=nothing, falses=nothing, dateformat::Union{Nothing, String, Dates.DateFormat}=nothing, debug::Bool=false) where {T}
    options = Options(sentinel, wh1, wh2, openquotechar, closequotechar, escapechar, delim, decimal, trues, falses, dateformat, ignorerepeated, quoted, debug)
    x, code, vpos, vlen, tlen = xparse(T, buf isa AbstractString ? codeunits(buf) : buf, pos, len, options)
    return ok(code) ? x : throw(Error(buf, T, code, pos, tlen))
end

function parse(::Type{T}, buf::Union{AbstractVector{UInt8}, AbstractString, IO}, pos::Int64, len::Int64, options::Options=OPTIONS) where {T}
    x, code, vpos, vlen, tlen = xparse(T, buf isa AbstractString ? codeunits(buf) : buf, pos, len, options)
    return ok(code) ? x : throw(Error(buf, T, code, pos, tlen))
end

"Attempt to parse a value of type `T` from `IO` `io`. Returns `nothing` on parser failures and invalid values."
function tryparse(::Type{T}, buf::Union{AbstractVector{UInt8}, AbstractString, IO}; pos::Int64=1, len::Int64=buf isa IO ? 0 : sizeof(buf), sentinel=nothing, wh1::Union{UInt8, Char}=UInt8(' '), wh2::Union{UInt8, Char}=UInt8('\t'), quoted::Bool=false, openquotechar::Union{UInt8, Char}=UInt8('"'), closequotechar::Union{UInt8, Char}=UInt8('"'), escapechar::Union{UInt8, Char}=UInt8('"'), ignorerepeated::Bool=false, delim::Union{UInt8, Char, Tuple{Ptr{UInt8}, Int}, AbstractString, Nothing}=nothing, decimal::Union{UInt8, Char}=UInt8('.'), trues=nothing, falses=nothing, dateformat::Union{Nothing, String, Dates.DateFormat}=nothing, debug::Bool=false) where {T}
    options = Options(sentinel, wh1, wh2, openquotechar, closequotechar, escapechar, delim, decimal, trues, falses, dateformat, ignorerepeated, quoted, debug)
    x, code, vpos, vlen, tlen = xparse(T, buf isa AbstractString ? codeunits(buf) : buf, pos, len, options)
    return ok(code) ? x : nothing
end

function tryparse(::Type{T}, buf::Union{AbstractVector{UInt8}, AbstractString, IO}, pos::Int64, len::Int64, options::Options=OPTIONS) where {T}
    x, code, vpos, vlen, tlen = xparse(T, buf isa AbstractString ? codeunits(buf) : buf, pos, len, options)
    return ok(code) ? x : nothing
end

default(::Type{T}) where {T <: Integer} = zero(T)
default(::Type{T}) where {T <: AbstractFloat} = T(0.0)
default(::Type{T}) where {T <: Dates.TimeType} = T(0)

function xparse(::Type{T}, buf::Union{AbstractVector{UInt8}, AbstractString, IO}; pos::Int64=1, len::Int64=buf isa IO ? 0 : sizeof(buf), sentinel=nothing, wh1::Union{UInt8, Char}=UInt8(' '), wh2::Union{UInt8, Char}=UInt8('\t'), quoted::Bool=true, openquotechar::Union{UInt8, Char}=UInt8('"'), closequotechar::Union{UInt8, Char}=UInt8('"'), escapechar::Union{UInt8, Char}=UInt8('"'), ignorerepeated::Bool=false, delim::Union{UInt8, Char, Tuple{Ptr{UInt8}, Int}, AbstractString, Nothing}=UInt8(','), decimal::Union{UInt8, Char}=UInt8('.'), trues=nothing, falses=nothing, dateformat::Union{Nothing, String, Dates.DateFormat}=nothing, debug::Bool=false) where {T}
    options = Options(sentinel, wh1, wh2, openquotechar, closequotechar, escapechar, delim, decimal, trues, falses, dateformat, ignorerepeated, quoted, debug)
    return xparse(T, buf isa AbstractString ? codeunits(buf) : buf, pos, len, options)
end

function xparse(::Type{T}, buf::AbstractString, pos, len, options::Options=XOPTIONS) where {T}
    return xparse(T, codeunits(buf), pos, len, options)
end

@inline function xparse(::Type{T}, source::Union{AbstractVector{UInt8}, IO}, pos, len, options::Options{ignorerepeated, Q, debug, S, D, DF}=XOPTIONS) where {T, ignorerepeated, Q, debug, S, D, DF}
    startpos = vstartpos = vpos = pos
    sentinel = options.sentinel
    code = SUCCESS
    x = default(T)
    quoted = false
    sentinelpos = 0
    if debug
        println("parsing $T, pos=$pos, len=$len")
    end
    if eof(source, pos, len)
        code = (sentinel === missing ? SENTINEL : INVALID) | EOF
        @goto donedone
    end
    b = peekbyte(source, pos)
    if debug
        println("1) parsed: '$(escape_string(string(Char(b))))'")
    end
    # strip leading whitespace
    while b == options.wh1 || b == options.wh2
        if debug
            println("stripping leading whitespace")
        end
        pos += 1
        incr!(source)
        if eof(source, pos, len)
            code = INVALID | EOF
            @goto donedone
        end
        b = peekbyte(source, pos)
        if debug
            println("2) parsed: '$(escape_string(string(Char(b))))'")
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
                println("3) parsed: '$(escape_string(string(Char(b))))'")
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
                    println("4) parsed: '$(escape_string(string(Char(b))))'")
                end
            end
        end
    end
    # check for sentinel values if applicable
    if sentinel !== nothing && sentinel !== missing
        if debug
            println("checking for sentinel value")
        end
        sentinelpos = checksentinel(source, pos, len, sentinel, debug)
    end
    x, code, pos = typeparser(T, source, pos, len, b, code, options)
    if sentinel !== nothing && sentinel !== missing && sentinelpos >= pos
        # if we matched a sentinel value that was as long or longer than our type value
        code &= ~(OK | INVALID | OVERFLOW)
        pos = sentinelpos
        fastseek!(source, pos - 1)
        code |= SENTINEL
        if eof(source, pos, len)
            code |= EOF
        end
    elseif sentinel === missing && pos == startpos
        code &= ~(OK | INVALID | OVERFLOW)
        code |= SENTINEL
        if eof(source, pos, len)
            code |= EOF
        end
    end
    vpos = pos
    if (code & EOF) == EOF
        if quoted
            # if we detected a quote character, it's an invalid quoted field due to eof in the middle
            code |= INVALID_QUOTED_FIELD
        end
        @goto donedone
    end

@label donevalue
    b = peekbyte(source, pos)
    if debug
        println("finished $T value parsing: pos=$pos, current character: '$(escape_string(string(Char(b))))'")
    end
    # donevalue means we finished parsing a value or sentinel, but didn't reach len, b is still the current byte
    # strip trailing whitespace
    while b == options.wh1 || b == options.wh2
        if debug
            println("stripping trailing whitespace")
        end
        pos += 1
        vpos += 1
        incr!(source)
        if eof(source, pos, len)
            code |= EOF
            if quoted
                code |= INVALID_QUOTED_FIELD
            end
            @goto donedone
        end
        b = peekbyte(source, pos)
        if debug
            println("8) parsed: '$(escape_string(string(Char(b))))'")
        end
    end
    if Q
        # for quoted fields, find the closing quote character
        # we should be positioned at the correct place to find the closing quote character if everything is as it should be
        # if we don't find the quote character immediately, something's wrong, so mark INVALID
        if quoted
            if debug
                println("looking for close quote character")
            end
            same = options.cq == options.e
            first = true
            while true
                vpos = pos
                pos += 1
                incr!(source)
                if same && b == options.e
                    if eof(source, pos, len)
                        code |= EOF
                        if !first
                            code |= INVALID
                        end
                        @goto donedone
                    elseif peekbyte(source, pos) != options.cq
                        if !first
                            code |= INVALID
                        end
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
                    if !first
                        code |= INVALID
                    end
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
                first = false
                b = peekbyte(source, pos)
                if debug
                    println("9) parsed: '$(escape_string(string(Char(b))))'")
                end
            end
            b = peekbyte(source, pos)
            if debug
                println("10) parsed: '$(escape_string(string(Char(b))))'")
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
                    println("11) parsed: '$(escape_string(string(Char(b))))'")
                end
            end
        end
    end

    if options.delim !== nothing
        delim = options.delim
        # now we check for a delimiter; if we don't find it, keep parsing until we do
        if debug
            println("checking for delimiter: pos=$pos")
        end
        if !ignorerepeated
            # we're checking for a single appearance of a delimiter
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
            # keep parsing as long as we keep matching delim
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
                        println("12) parsed: '$(escape_string(string(Char(b))))'")
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
        # didn't find delimiter or newline, so we're invalid, keep parsing until we find delimiter, newline, or len
        quo = Int(!quoted)
        code |= INVALID_DELIMITER
        while true
            pos += 1
            vpos += quo
            incr!(source)
            if eof(source, pos, len)
                code |= EOF
                @goto donedone
            end
            b = peekbyte(source, pos)
            if debug
                println("13) parsed: '$(escape_string(string(Char(b))))'")
            end
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
                            println("12) parsed: '$(escape_string(string(Char(b))))'")
                        end
                    end
                    if matched
                        code |= DELIMITED
                        @goto donedone
                    end
                else
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
        end
    end

@label donedone
    if debug
        println("finished parsing: $(codes(code))")
    end
    return x, code, Int64(vstartpos), Int64(vpos - vstartpos), Int64(pos - startpos)
end

function checkdelim!(buf, pos, len, options::Options{ignorerepeated}) where {ignorerepeated}
    pos > len && return pos
    delim = options.delim
    @inbounds b = buf[pos]
    valuepos = pos
    if !ignorerepeated
        # we're checking for a single appearance of a delimiter
        if delim isa UInt8
            b == delim && return pos + 1
        else
            pos = checkdelim(buf, pos, len, delim)
            pos > valuepos && return pos
        end
    else
        # keep parsing as long as we keep matching delim
        if delim isa UInt8
            matched = false
            while b == delim
                matched = true
                pos += 1
                pos > len && return pos
                @inbounds b = buf[pos]
            end
            matched && return pos
        else
            matched = false
            predelimpos = pos
            pos = checkdelim(buf, pos, len, delim)
            while pos > predelimpos
                matched = true
                pos > len && return pos
                predelimpos = pos
                pos = checkdelim(buf, pos, len, delim)
            end
            matched && return pos
        end
    end
    return pos
end

include("ints.jl")
include("floats.jl")
include("strings.jl")
include("bools.jl")
include("dates.jl")

function __init__()
    # floats.jl globals
    Threads.resize_nthreads!(ONES)
    foreach(x->MPZ.init!(x), ONES)
    Threads.resize_nthreads!(NUMS)
    foreach(x->MPZ.init!(x), NUMS)
    Threads.resize_nthreads!(QUOS)
    foreach(x->MPZ.init!(x), QUOS)
    Threads.resize_nthreads!(REMS)
    foreach(x->MPZ.init!(x), REMS)
    Threads.resize_nthreads!(SCLS)
    foreach(x->MPZ.init!(x), SCLS)
    return
end

end # module