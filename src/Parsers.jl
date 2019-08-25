module Parsers

using Dates

include("utils.jl")

"""
    `Parsers.Options` is a structure for holding various parsing settings when calling `Parsers.parse`, `Parsers.tryparse`, and `Parsers.xparse`. They include:

  * `sentinel=nothing`: valid values include: `nothing` meaning don't check for sentinel values; `missing` meaning an "empty field" should be considered a sentinel value; or a `Vector{String}` of the various string values that should each be checked as a sentinel value. Note that sentinels will always be checked longest to shortest, with the longest valid match taking precedence.
  * `wh1=' '`: the first ascii character to be considered when ignoring leading/trailing whitespace in value parsing
  * `wh2='\t'`: the second ascii character to be considered when ignoring leading/trailing whitespace in value parsing
  * `openquotechar='"'`: the ascii character that signals a "quoted" field while parsing; subsequent characters will be treated as non-significant until a valid `closequotechar` is detected
  * `closequotechar='"'`: the ascii character that signals the end of a quoted field
  * `escapechar='"'`: an ascii character used to "escape" a `closequotechar` within a quoted field
  * `delim=nothing`: if `nothing`, no delimiter will be checked for; if a `Char` or `String`, a delimiter will be checked for directly after parsing a value or `closequotechar`; a newline (`\n`), return (`\r`), or CRLF (`"\r\n"`) are always considered "delimiters", in addition to EOF
  * `decimal='.'`: an ascii character to be used when parsing float values that separates a decimal value
  * `trues=nothing`: if `nothing`, `Bool` parsing will only check for the string `true` or an `Integer` value of `1` as valid values for `true`; as a `Vector{String}`, each string value will be checked to indicate a valid `true` value
  * `falses=nothing`: if `nothing`, `Bool` parsing will only check for the string `false` or an `Integer` value of `0` as valid values for `false`; as a `Vector{String}`, each string value will be checked to indicate a valid `false` value
  * `dateformat=nothing`: if `nothing`, `Date`, `DateTime`, and `Time` parsing will use a default `Dates.DateFormat` object while parsing; a `String` or `Dates.DateFormat` object can be provided for custom format parsing
  * `ignorerepeated=false`: if `true`, consecutive delimiter characters or strings will be consumed until a non-delimiter is encountered; if `false`, only a single delimiter character/string will be consumed. Useful for fixed-width delimited files where fields are padded with delimiters
  * `quoted=false`: whether parsing should check for `openquotechar` and `closequotechar` characters to signal quoted fields
  * `debug=false`: if `true`, various debug logging statements will be printed while parsing; useful when diagnosing why parsing returns certain `Parsers.ReturnCode` values
"""
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
asciival(c::Char) = isascii(c)
asciival(b::UInt8) = b < 0x80

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
    asciival(wh1) && asciival(wh2) || throw(ArgumentError("whitespace characters must be ASCII"))
    asciival(oq) && asciival(cq) && asciival(e) || throw(ArgumentError("openquotechar, closequotechar, and escapechar must be ASCII characters"))
    (wh1 == delim) || (wh2 == delim) && throw(ArgumentError("whitespace characters must be different than delim argument"))
    (oq == delim) || (cq == delim) || (e == delim) && throw(ArgumentError("delim argument must be different than openquotechar, closequotechar, and escapechar arguments"))
    if sentinel isa Vector{String}
        for sent in sentinel
            if startswith(sent, string(Char(wh1))) || startswith(sent, string(Char(wh2)))
                throw(ArgumentError("sentinel value isn't allowed to start with wh1 or wh2 characters"))
            end
            if startswith(sent, string(Char(oq))) || startswith(sent, string(Char(cq)))
                throw(ArgumentError("sentinel value isn't allowed to start with openquotechar, closequotechar, or escapechar characters"))
            end
            if (delim isa UInt8 || delim isa Char) && startswith(sent, string(Char(delim)))
                throw(ArgumentError("sentinel value isn't allowed to start with a delimiter character"))
            elseif delim isa String && startswith(sent, delim)
                throw(ArgumentError("sentinel value isn't allowed to start with a delimiter string"))
            end
        end
    end
    sent = sentinel === nothing || sentinel === missing ? sentinel : prepare(sentinel)
    del = delim === nothing ? nothing : delim isa String ? ptrlen(delim) : delim % UInt8
    trues = trues === nothing ? nothing : prepare(trues)
    falses = falses === nothing ? nothing : prepare(falses)
    df = dateformat === nothing ? nothing : dateformat isa String ? Dates.DateFormat(dateformat) : dateformat
    return Options{ignorerepeated, quoted, debug, typeof(sent), typeof(del), typeof(df)}(sent, wh1 % UInt8, wh2 % UInt8, oq % UInt8, cq % UInt8, e % UInt8, del, decimal % UInt8, trues, falses, df, strict, silencewarnings)
end

Options(;
    sentinel::Union{Nothing, Missing, Vector{String}}=nothing,
    wh1::Union{UInt8, Char}=UInt8(' '),
    wh2::Union{UInt8, Char}=UInt8('\t'),
    openquotechar::Union{UInt8, Char}=UInt8('"'),
    closequotechar::Union{UInt8, Char}=UInt8('"'),
    escapechar::Union{UInt8, Char}=UInt8('"'),
    delim::Union{Nothing, UInt8, Char, String}=nothing,
    decimal::Union{UInt8, Char}=UInt8('.'),
    trues::Union{Nothing, Vector{String}}=nothing,
    falses::Union{Nothing, Vector{String}}=nothing,
    dateformat::Union{Nothing, String, Dates.DateFormat}=nothing,
    ignorerepeated::Bool=false,
    quoted::Bool=false,
    debug::Bool=false,
) = Options(sentinel, wh1, wh2, openquotechar, closequotechar, escapechar, delim, decimal, trues, falses, dateformat, ignorerepeated, quoted, debug)

const OPTIONS = Options(nothing, UInt8(' '), UInt8('\t'), UInt8('"'), UInt8('"'), UInt8('"'), nothing, UInt8('.'), nothing, nothing, nothing, false, false, false)
const XOPTIONS = Options(missing, UInt8(' '), UInt8('\t'), UInt8('"'), UInt8('"'), UInt8('"'), UInt8(','), UInt8('.'), nothing, nothing, nothing, false, true, false)

# high-level convenience functions like in Base
"Attempt to parse a value of type `T` from string `buf`. Throws `Parsers.Error` on parser failures and invalid values."
function parse(::Type{T}, buf::Union{AbstractVector{UInt8}, AbstractString, IO}, options=OPTIONS; pos::Integer=1, len::Integer=buf isa IO ? 0 : sizeof(buf)) where {T}
    x, code, vpos, vlen, tlen = xparse(T, buf isa AbstractString ? codeunits(buf) : buf, pos, len, options)
    return ok(code) ? x : throw(Error(buf, T, code, pos, tlen))
end

"Attempt to parse a value of type `T` from `buf`. Returns `nothing` on parser failures and invalid values."
function tryparse(::Type{T}, buf::Union{AbstractVector{UInt8}, AbstractString, IO}, options=OPTIONS; pos::Integer=1, len::Integer=buf isa IO ? 0 : sizeof(buf)) where {T}
    x, code, vpos, vlen, tlen = xparse(T, buf isa AbstractString ? codeunits(buf) : buf, pos, len, options)
    return ok(code) ? x : nothing
end

default(::Type{T}) where {T <: Integer} = zero(T)
default(::Type{T}) where {T <: AbstractFloat} = T(0.0)
default(::Type{T}) where {T <: Dates.TimeType} = T(0)

# for testing purposes only, it's much too slow to dynamically create Options for every xparse call
"""
    Parsers.xparse(T, buf, pos, len, options) => (x, code, startpos, value_len, total_len)

    The core parsing function for any type `T`. Takes a `buf`, which can be a `Vector{UInt8}`, `Base.CodeUnits`,
    or an `IO`. `pos` is the byte position to begin parsing at. `len` is the total # of bytes in `buf` (signaling eof).
    `options` is an instance of `Parsers.Options`.

    `Parsers.xparse` returns a tuple of 5 values:
      * `x` is a value of type `T`, even if parsing does not succeed
      * `code` is a bitmask of parsing codes, use `Parsers.codes(code)` or `Parsers.text(code)` to see the various bit values set. See `?Parsers.ReturnCode` for additional details on the various parsing codes
      * `startpos`: the starting byte position of the value being parsed; will always equal the start `pos` passed in, except for quoted field where it will point instead to the first byte after the open quote character
      * `value_len`: the # of bytes consumed while parsing a value, will be equal to the total number of bytes consumed, except for quoted or delimited fields where the quote and delimiter characters will be subtracted out
      * `total_len`: the total # of bytes consumed while parsing a value, including any quote or delimiter characters; this can be added to the starting `pos` to allow calling `Parsers.xparse` again for a subsequent field/value
"""
function xparse end

function xparse(::Type{T}, buf::Union{AbstractVector{UInt8}, AbstractString, IO}; pos::Integer=1, len::Integer=buf isa IO ? 0 : sizeof(buf), sentinel=nothing, wh1::Union{UInt8, Char}=UInt8(' '), wh2::Union{UInt8, Char}=UInt8('\t'), quoted::Bool=true, openquotechar::Union{UInt8, Char}=UInt8('"'), closequotechar::Union{UInt8, Char}=UInt8('"'), escapechar::Union{UInt8, Char}=UInt8('"'), ignorerepeated::Bool=false, delim::Union{UInt8, Char, Tuple{Ptr{UInt8}, Int}, AbstractString, Nothing}=UInt8(','), decimal::Union{UInt8, Char}=UInt8('.'), trues=nothing, falses=nothing, dateformat::Union{Nothing, String, Dates.DateFormat}=nothing, debug::Bool=false) where {T}
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
    elseif sentinel === missing && pos == vstartpos
        code &= ~(OK | INVALID)
        code |= SENTINEL
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
include("ryu.jl")

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