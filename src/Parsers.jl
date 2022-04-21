module Parsers

export PosLen

using Dates

include("utils.jl")

struct Format
    tokens::Vector{Dates.AbstractDateToken}
    locale::Dates.DateLocale
end

const PtrLen = Tuple{Ptr{UInt8}, Int}

const SupportedFloats = Union{Float16, Float32, Float64, BigFloat}
const SupportedTypes = Union{Integer, SupportedFloats, Dates.TimeType, Bool}

"""
    Parsers.Result{T}(code::Parsers.ReturnCode, tlen[, val])

Struct for holding the results of a parsing operations, returned from `Parsers.xparse`.
Contains 3 fields:
  * `code`: parsing bitmask with various flags set based on parsing (see [ReturnCode](@ref))
  * `tlen`: the total number of bytes consumed while parsing
  * `val`: the parsed value; note that `val` is optional when constructing; users *MUST* check `!Parsers.invalid(result.code)` before accessing `result.val`; if parsing fails, `result.val` is undefined
"""
struct Result{T}
    code::ReturnCode
    tlen::Int64
    val::T
    Result{T}(code::ReturnCode, tlen::Integer) where {T} = new{T}(code, tlen)
    Result{T}(code::ReturnCode, tlen::Integer, val) where {T} = new{T}(code, tlen, val)
end

# Result(code::ReturnCode, tlen::Integer, val::T) where {T} = Result{T}(code, tlen, val)

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
  * `comment=nothing`: a string which, if matched at the start of a line, will make parsing consume the rest of the line
  * `ignoreemptylines=false`: after parsing a value, if a newline is detected, another immediately proceeding newline will be checked for and consumed
  * `stripwhitespace=false`: if true, leading and trailing whitespace is stripped from string fields, note that for *quoted* strings however, whitespace is preserved within quotes (but ignored before/after quote characters). To also strip *within* quotes, see `stripquoted`
  * `stripquoted=false`: if true, whitespace is also stripped within quoted strings. If true, `stripwhitespace` is also set to true.
  * `debug=false`: if `true`, various debug logging statements will be printed while parsing; useful when diagnosing why parsing returns certain `Parsers.ReturnCode` values
"""
struct Options
    refs::Vector{String} # for holding references to sentinel, trues, falses, cmt strings
    sentinel::Union{Nothing, Missing, Vector{PtrLen}}
    ignorerepeated::Bool
    ignoreemptylines::Bool
    wh1::UInt8
    wh2::UInt8
    quoted::Bool
    oq::UInt8
    cq::UInt8
    e::UInt8
    delim::Union{Nothing, UInt8, PtrLen}
    decimal::UInt8
    trues::Union{Nothing, Vector{PtrLen}}
    falses::Union{Nothing, Vector{PtrLen}}
    dateformat::Union{Nothing, Format}
    cmt::Union{Nothing, PtrLen}
    stripwhitespace::Bool
    stripquoted::Bool
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
            dateformat::Union{Nothing, String, Dates.DateFormat, Format},
            ignorerepeated, ignoreemptylines, comment, quoted, debug, stripwhitespace=false, stripquoted=false)
    asciival(wh1) && asciival(wh2) || throw(ArgumentError("whitespace characters must be ASCII"))
    asciival(oq) && asciival(cq) && asciival(e) || throw(ArgumentError("openquotechar, closequotechar, and escapechar must be ASCII characters"))
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
        refs = copy(sentinel)
    else
        refs = [""]
    end
    sent = sentinel === nothing || sentinel === missing ? sentinel : prepare(sentinel)
    del = delim === nothing ? nothing : delim isa String ? ptrlen(delim) : delim % UInt8
    if del isa UInt8
        ((wh1 % UInt8) == del || (wh2 % UInt8) == del) && throw(ArgumentError("whitespace characters (`wh1=' '` and `wh2='\\t'` default keyword arguments) must be different than delim argument"))
    end
    if trues !== nothing
        append!(refs, trues)
        trues = prepare(trues)
    end
    if falses !== nothing
        append!(refs, falses)
        falses = prepare(falses)
    end
    if comment === nothing
        cmt = nothing
    else
        push!(refs, comment)
        cmt = ptrlen(comment)
    end
    df = dateformat === nothing ? nothing : dateformat isa String ? Format(dateformat) : dateformat isa Dates.DateFormat ? Format(dateformat) : dateformat
    return Options(refs, sent, ignorerepeated, ignoreemptylines, wh1 % UInt8, wh2 % UInt8, quoted, oq % UInt8, cq % UInt8, e % UInt8, del, decimal % UInt8, trues, falses, df, cmt, stripwhitespace || stripquoted, stripquoted)
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
    dateformat::Union{Nothing, String, Dates.DateFormat, Format}=nothing,
    ignorerepeated::Bool=false,
    ignoreemptylines::Bool=false,
    comment::Union{Nothing, String}=nothing,
    quoted::Bool=false,
    debug::Bool=false,
    stripwhitespace::Bool=false,
    stripquoted::Bool=false,
) = Options(sentinel, wh1, wh2, openquotechar, closequotechar, escapechar, delim, decimal, trues, falses, dateformat, ignorerepeated, ignoreemptylines, comment, quoted, debug, stripwhitespace, stripquoted)

const OPTIONS = Options(nothing, UInt8(' '), UInt8('\t'), UInt8('"'), UInt8('"'), UInt8('"'), nothing, UInt8('.'), nothing, nothing, nothing, false, false, nothing, false, false, false)
const XOPTIONS = Options(missing, UInt8(' '), UInt8('\t'), UInt8('"'), UInt8('"'), UInt8('"'), UInt8(','), UInt8('.'), nothing, nothing, nothing, false, false, nothing, true, false, false)

# high-level convenience functions like in Base
"""
    Parsers.parse(T, source[, options, pos, len]) => T

Parse a value of type `T` from `source`, which may be a byte buffer (`AbstractVector{UInt8}`), string, or `IO`. Optional arguments include `options`, a [`Parsers.Options`](@ref)
struct, `pos` which indicates the byte position where parsing should begin in a byte buffer `source`, and `len` which is the byte position where parsing should stop in a byte
buffer `source`. If parsing fails for any reason, either invalid value or non-value characters encountered before/after a value, an error will be thrown. To return `nothing`
instead of throwing an error, use [`Parsers.tryparse`](@ref).
"""
function parse(::Type{T}, buf::Union{AbstractVector{UInt8}, AbstractString, IO}, options=OPTIONS, pos::Integer=1, len::Integer=buf isa IO ? 0 : sizeof(buf)) where {T}
    res = xparse2(T, buf isa AbstractString ? codeunits(buf) : buf, pos, len, options)
    code = res.code
    tlen = res.tlen
    fin = buf isa IO || (tlen == (len - pos + 1))
    return ok(code) && fin ? (res.val::T) : throw(Error(buf, T, code, pos, tlen))
end

"""
    Parsers.tryparse(T, source[, options, pos, len]) => Union{T, Nothing}

Parse a value of type `T` from `source`, which may be a byte buffer (`AbstractVector{UInt8}`), string, or `IO`. Optional arguments include `options`, a [`Parsers.Options`](@ref)
struct, `pos` which indicates the byte position where parsing should begin in a byte buffer `source`, and `len` which is the byte position where parsing should stop in a byte
buffer `source`. If parsing fails for any reason, either invalid value or non-value characters encountered before/after a value, `nothing` will be returned. To instead throw
an error, use [`Parsers.parse`](@ref).
"""
function tryparse(::Type{T}, buf::Union{AbstractVector{UInt8}, AbstractString, IO}, options=OPTIONS, pos::Integer=1, len::Integer=buf isa IO ? 0 : sizeof(buf)) where {T}
    res = xparse2(T, buf isa AbstractString ? codeunits(buf) : buf, pos, len, options)
    fin = buf isa IO || (res.tlen == (len - pos + 1))
    return ok(res.code) && fin ? (res.val::T) : nothing
end

"""
    Parsers.xparse(T, buf, pos, len, options) => Parsers.Result{T}

The core parsing function for any type `T`. Takes a `buf`, which can be an `AbstractVector{UInt8}`, `AbstractString`,
or an `IO`. `pos` is the byte position to begin parsing at. `len` is the total # of bytes in `buf` (signaling eof).
`options` is an instance of `Parsers.Options`.

A [`Parsers.Result`](@ref) struct is returned, with the following fields:
      * `res.val` is a value of type `T`, but only if parsing succeeded; for parsed `String`s, no string is returned to avoid excess allocating; if you'd like the actual parsed string value, you can call [`Parsers.getstring`](@ref)
      * `res.code` is a bitmask of parsing codes, use `Parsers.codes(code)` or `Parsers.text(code)` to see the various bit values set. See [`Parsers.ReturnCode`](@ref) for additional details on the various parsing codes
      * `res.tlen`: the total # of bytes consumed while parsing a value, including any quote or delimiter characters; this can be added to the starting `pos` to allow calling `Parsers.xparse` again for a subsequent field/value
"""
function xparse end

# for testing purposes only, it's much too slow to dynamically create Options for every xparse call
function xparse(::Type{T}, buf::Union{AbstractVector{UInt8}, AbstractString, IO}; pos::Integer=1, len::Integer=buf isa IO ? 0 : sizeof(buf), sentinel=nothing, wh1::Union{UInt8, Char}=UInt8(' '), wh2::Union{UInt8, Char}=UInt8('\t'), quoted::Bool=true, openquotechar::Union{UInt8, Char}=UInt8('"'), closequotechar::Union{UInt8, Char}=UInt8('"'), escapechar::Union{UInt8, Char}=UInt8('"'), ignorerepeated::Bool=false, ignoreemptylines::Bool=false, delim::Union{UInt8, Char, PtrLen, AbstractString, Nothing}=UInt8(','), decimal::Union{UInt8, Char}=UInt8('.'), comment=nothing, trues=nothing, falses=nothing, dateformat::Union{Nothing, String, Dates.DateFormat}=nothing, debug::Bool=false, stripwhitespace::Bool=false, stripquoted::Bool=false) where {T}
    options = Options(sentinel, wh1, wh2, openquotechar, closequotechar, escapechar, delim, decimal, trues, falses, dateformat, ignorerepeated, ignoreemptylines, comment, quoted, debug, stripwhitespace, stripquoted)
    return xparse(T, buf, pos, len, options)
end

xparse(::Type{T}, buf::AbstractString, pos, len, options=Parsers.XOPTIONS) where {T} =
    xparse(T, codeunits(buf), pos, len, options)

# generic fallback calls Base.tryparse
function xparse(::Type{T}, source, pos, len, options, ::Type{S}=T) where {T, S}
    res = xparse(String, source, pos, len, options)
    code = res.code
    poslen = res.val
    if !Parsers.invalid(code) && !Parsers.sentinel(code)
        str = getstring(source, poslen, options.e)
        x = Base.tryparse(T, str)
        if x === nothing
            return Result{S}(code | INVALID, res.tlen)
        else
            return Result{S}(code, res.tlen, x)
        end
    else
        return Result{S}(code, res.tlen)
    end
end

function xparse(::Type{Char}, source, pos, len, options, ::Type{S}=Char) where {S}
    res = xparse(String, source, pos, len, options)
    code = res.code
    poslen = res.val
    if !Parsers.invalid(code) && !Parsers.sentinel(code)
        return Result{S}(code, res.tlen, first(getstring(source, poslen, options.e)))
    else
        return Result{S}(code, res.tlen)
    end
end

function xparse(::Type{Symbol}, source, pos, len, options, ::Type{S}=Symbol) where {S}
    res = xparse(String, source, pos, len, options)
    code = res.code
    poslen = res.val
    if !Parsers.invalid(code) && !Parsers.sentinel(code)
        if source isa AbstractVector{UInt8}
            sym = ccall(:jl_symbol_n, Ref{Symbol}, (Ptr{UInt8}, Int), pointer(source, poslen.pos), poslen.len)
        else
            sym = Symbol(getstring(source, poslen, options.e))
        end
        return Result{S}(code, res.tlen, sym)
    else
        return Result{S}(code, res.tlen)
    end
end

function xparse(::Type{T}, source::Union{AbstractVector{UInt8}, IO}, pos, len, options::Options=XOPTIONS, ::Type{S}=T) where {T <: SupportedTypes, S}
    startpos = vstartpos = pos
    sentinel = options.sentinel
    wh1 = options.wh1; wh2 = options.wh2
    code = SUCCESS
    quoted = false
    sentinelpos = 0
    if eof(source, pos, len)
        code = (sentinel === missing ? SENTINEL : INVALID) | EOF
        @goto donedone
    end
    b = peekbyte(source, pos)
    # strip leading whitespace
    while b == wh1 || b == wh2
        pos += 1
        incr!(source)
        if eof(source, pos, len)
            code = INVALID | EOF
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
            vstartpos = pos
            incr!(source)
            if eof(source, pos, len)
                code |= INVALID_QUOTED_FIELD
                @goto donedone
            end
            b = peekbyte(source, pos)
            # ignore whitespace within quoted field
            while b == wh1 || b == wh2
                pos += 1
                incr!(source)
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
        sentinelpos = checksentinel(source, pos, len, sentinel)
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
    if (code & EOF) == EOF
        if quoted
            # if we detected a quote character, it's an invalid quoted field due to eof in the middle
            code |= INVALID_QUOTED_FIELD
        end
        @goto donedone
    end

@label donevalue
    b = peekbyte(source, pos)
    # donevalue means we finished parsing a value or sentinel, but didn't reach len, b is still the current byte
    # strip trailing whitespace
    while b == wh1 || b == wh2
        pos += 1
        incr!(source)
        if eof(source, pos, len)
            code |= EOF
            if quoted
                code |= INVALID_QUOTED_FIELD
            end
            @goto donedone
        end
        b = peekbyte(source, pos)
    end
    if options.quoted
        # for quoted fields, find the closing quote character
        # we should be positioned at the correct place to find the closing quote character if everything is as it should be
        # if we don't find the quote character immediately, something's wrong, so mark INVALID
        if quoted
            same = options.cq == options.e
            first = true
            while true
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
            end
            b = peekbyte(source, pos)
            # ignore whitespace after quoted field
            while b == wh1 || b == wh2
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
        # now we check for a delimiter; if we don't find it, keep parsing until we do
        if !options.ignorerepeated
            # we're checking for a single appearance of a delimiter
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
            # keep parsing as long as we keep matching delims/newlines
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
        # didn't find delimiter or newline, so we're invalid, keep parsing until we find delimiter, newline, or len
        code |= INVALID_DELIMITER
        while true
            pos += 1
            incr!(source)
            if eof(source, pos, len)
                code |= EOF
                @goto donedone
            end
            b = peekbyte(source, pos)
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
        end
    end

@label donedone
    tlen = pos - startpos
    if valueok(code)
        y::T = x
        return Result{S}(code, tlen, y)
    else
        return Result{S}(code, tlen)
    end
end

# condensed version of xparse that doesn't worry about quoting or delimiters; called from Parsers.parse/Parsers.tryparse
@inline function xparse2(::Type{T}, source::Union{AbstractVector{UInt8}, IO}, pos, len, options::Options=XOPTIONS, ::Type{S}=T) where {T <: SupportedTypes, S}
    startpos = pos
    sentinel = options.sentinel
    wh1 = options.wh1; wh2 = options.wh2
    code = SUCCESS
    quoted = false
    if eof(source, pos, len)
        code = (sentinel === missing ? SENTINEL : INVALID) | EOF
        @goto donedone
    end
    b = peekbyte(source, pos)
    # strip leading whitespace
    while b == wh1 || b == wh2
        pos += 1
        incr!(source)
        if eof(source, pos, len)
            code = INVALID | EOF
            @goto donedone
        end
        b = peekbyte(source, pos)
    end
    x, code, pos = typeparser(T, source, pos, len, b, code, options)
    if (code & EOF) == EOF
        @goto donedone
    end

@label donevalue
    b = peekbyte(source, pos)
    # donevalue means we finished parsing a value or sentinel, but didn't reach len, b is still the current byte
    # strip trailing whitespace
    while b == wh1 || b == wh2
        pos += 1
        incr!(source)
        if eof(source, pos, len)
            code |= EOF
            if quoted
                code |= INVALID_QUOTED_FIELD
            end
            @goto donedone
        end
        b = peekbyte(source, pos)
    end

@label donedone
    tlen = pos - startpos
    return valueok(code) ? Result{S}(code, tlen, x) : Result{S}(code, tlen)
end

@inline function xparse2(::Type{T}, source, pos, len, options, ::Type{S}=T) where {T, S}
    res = xparse(String, source, pos, len, options)
    code = res.code
    poslen = res.val
    if !Parsers.invalid(code) && !Parsers.sentinel(code)
        str = getstring(source, poslen, options.e)
        x = Base.tryparse(T, str)
        if x === nothing
            return Result{S}(code | INVALID, res.tlen)
        else
            return Result{S}(code, res.tlen, x)
        end
    else
        return Result{S}(code, res.tlen)
    end
end

@inline function xparse2(::Type{Char}, source, pos, len, options, ::Type{S}=Char) where {S}
    res = xparse(String, source, pos, len, options)
    code = res.code
    poslen = res.val
    if !Parsers.invalid(code) && !Parsers.sentinel(code)
        return Result{S}(code, res.tlen, first(getstring(source, poslen, options.e)))
    else
        return Result{S}(code, res.tlen)
    end
end

@inline function xparse2(::Type{Symbol}, source, pos, len, options, ::Type{S}=Symbol) where {S}
    res = xparse(String, source, pos, len, options)
    code = res.code
    poslen = res.val::PosLen
    if !Parsers.invalid(code) && !Parsers.sentinel(code)
        if source isa AbstractVector{UInt8}
            sym = ccall(:jl_symbol_n, Ref{Symbol}, (Ptr{UInt8}, Int), pointer(source, poslen.pos), poslen.len)
        else
            sym = Symbol(getstring(source, poslen, options.e))
        end
        return Result{S}(code, res.tlen, sym)
    else
        return Result{S}(code, res.tlen)
    end
end

function checkdelim!(buf, pos, len, options::Options)
    pos > len && return pos
    delim = options.delim
    @inbounds b = buf[pos]
    valuepos = pos
    if !options.ignorerepeated
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
        elseif delim isa PtrLen
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
        else
            error()
        end
    end
    return pos
end

function checkcmtemptylines(source, pos, len, options::Options)
    cmt = options.cmt
    while !eof(source, pos, len)
        skipped = false
        if options.ignoreemptylines
            b = peekbyte(source, pos)
            if b == UInt8('\n')
                pos += 1
                incr!(source)
                skipped = true
            elseif b == UInt8('\r')
                pos += 1
                incr!(source)
                if !eof(source, pos, len) && peekbyte(source, pos) == UInt8('\n')
                    pos += 1
                    incr!(source)
                end
                skipped = true
            end
        end
        matched = false
        if cmt !== nothing && !eof(source, pos, len)
            precmtpos = pos
            pos = checkdelim(source, pos, len, cmt)
            if pos > precmtpos
                matched = true
                eof(source, pos, len) && break
                b = peekbyte(source, pos)
                while b != UInt8('\n') && b != UInt8('\r')
                    pos += 1
                    incr!(source)
                    eof(source, pos, len) && break
                    b = peekbyte(source, pos)
                end
                pos += 1
                incr!(source)
                if b == UInt8('\r') && !eof(source, pos, len) && peekbyte(source, pos) == UInt8('\n')
                    pos += 1
                    incr!(source)
                end
            end
        end
        (skipped | matched) || break
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
    resize!(empty!(BIGINT), Threads.nthreads())
    resize!(empty!(BIGFLOAT), Threads.nthreads())
    return
end

include("precompile.jl")

end # module
