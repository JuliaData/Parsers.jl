module Parsers

export PosLen

using Dates

include("utils.jl")

struct Format
    tokens::Vector{Dates.AbstractDateToken}
    locale::Dates.DateLocale
end

const SupportedFloats = Union{Float16, Float32, Float64, BigFloat}
const SupportedTypes = Union{Integer, SupportedFloats, Dates.TimeType, Bool, AbstractString}

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

Base.show(io::IO, x::Result{T}) where {T} = print(io, "Parsers.Result{$T}(code=`", codes(x.code), "`, tlen=", x.tlen, ", val=", isdefined(x, :val) ? x.val : "#undefined", ")")

@enum StripWhitespace STRIP DEFAULT KEEP
StripWhitespace(x::Union{Nothing, Bool}) = x === nothing ? DEFAULT : x ? STRIP : KEEP

"""
    `Parsers.Options` is a structure for holding various parsing settings when calling `Parsers.parse`, `Parsers.tryparse`, and `Parsers.xparse`. They include:

  * `sentinel=nothing`: valid values include: `nothing` meaning don't check for sentinel values; `missing` meaning an "empty field" should be considered a sentinel value; or a `Vector{String}` of the various string values that should each be checked as a sentinel value. Note that sentinels will always be checked longest to shortest, with the longest valid match taking precedence.
  * `openquotechar='"'`: the ascii character that signals a "quoted" field while parsing; subsequent characters will be treated as non-significant until a valid `closequotechar` is detected
  * `closequotechar='"'`: the ascii character that signals the end of a quoted field
  * `escapechar='"'`: an ascii character used to "escape" a `closequotechar` within a quoted field
  * `delim=','`: if `nothing`, no delimiter will be checked for; if a `Char` or `String`, a delimiter will be checked for directly after parsing a value or `closequotechar`; a newline (`\\n`), return (`\\r`), or CRLF (`"\\r\\n"`) are always considered "delimiters", in addition to EOF
  * `decimal='.'`: an ascii character to be used when parsing float values that separates a decimal value
  * `trues=nothing`: if `nothing`, `Bool` parsing will only check for the string `true` or an `Integer` value of `1` as valid values for `true`; as a `Vector{String}`, each string value will be checked to indicate a valid `true` value
  * `falses=nothing`: if `nothing`, `Bool` parsing will only check for the string `false` or an `Integer` value of `0` as valid values for `false`; as a `Vector{String}`, each string value will be checked to indicate a valid `false` value
  * `dateformat=nothing`: if `nothing`, `Date`, `DateTime`, and `Time` parsing will use a default `Dates.DateFormat` object while parsing; a `String` or `Dates.DateFormat` object can be provided for custom format parsing
  * `ignorerepeated=false`: if `true`, consecutive delimiter characters or strings will be consumed until a non-delimiter is encountered; if `false`, only a single delimiter character/string will be consumed. Useful for fixed-width delimited files where fields are padded with delimiters
  * `quoted=true`: whether parsing should check for `openquotechar` and `closequotechar` characters to signal quoted fields
  * `comment=nothing`: a string which, if matched at the start of a line, will make parsing consume the rest of the line
  * `ignoreemptylines=false`: after parsing a value, if a newline is detected, another immediately proceeding newline will be checked for and consumed
  * `stripwhitespace=nothing`: if true, leading and trailing whitespace is stripped from string fields, note that for *quoted* strings however, whitespace is preserved within quotes (but ignored before/after quote characters). To also strip *within* quotes, see `stripquoted`
  * `stripquoted=false`: if true, whitespace is also stripped within quoted strings. If true, `stripwhitespace` is also set to true.
  * `groupmark=nothing`: optionally specify a single-byte character denoting the number grouping mark, this allows parsing of numbers that have, e.g., thousand separators (`1,000.00`).
"""
struct Options
    stripwhitespace::StripWhitespace
    stripquoted::Bool
    checkquoted::Bool
    checksentinel::Bool
    checkdelim::Bool
    ignorerepeated::Bool
    ignoreemptylines::Bool
    decimal::UInt8
    oq::Token
    cq::Token
    e::Token
    sentinel::Vector{Token}
    delim::Token
    cmt::Token
    trues::Union{Nothing, Vector{String}}
    falses::Union{Nothing, Vector{String}}
    dateformat::Union{Nothing, Format}
    groupmark::Union{Nothing,UInt8}
end

const OPTIONS = Options(STRIP, false, false, false, false, false, false, UInt8('.'),
    Token(UInt8('"')), Token(UInt8('"')), Token(UInt8('"')), Token[], Token(""), Token(""),
    nothing, nothing, nothing, nothing)
const XOPTIONS = Options(DEFAULT, false, true, true, true, false, false, UInt8('.'),
    Token(UInt8('"')), Token(UInt8('"')), Token(UInt8('"')), Token[], Token(UInt8(',')), Token(""),
    nothing, nothing, nothing, nothing)

prepare!(x::Vector) = sort!(x, by=x->sizeof(x), rev=true)
asciival(c::Char) = isascii(c)
asciival(b::UInt8) = b < 0x80

const MaybeToken = Union{Nothing, UInt8, Char, String, Regex}

function Options(
            sentinel::Union{Nothing, Missing, Vector},
            wh1::Union{UInt8, Char},
            wh2::Union{UInt8, Char},
            openquotechar::MaybeToken,
            closequotechar::MaybeToken,
            escapechar::MaybeToken,
            delim::MaybeToken,
            decimal::Union{UInt8, Char},
            trues::Union{Nothing, Vector{String}},
            falses::Union{Nothing, Vector{String}},
            dateformat::Union{Nothing, String, Dates.DateFormat, Format},
            ignorerepeated, ignoreemptylines, comment, quoted, stripwhitespace=nothing, stripquoted=false, groupmark::Union{Nothing,Char,UInt8}=nothing)

    if sentinel isa Vector{String}
        for sent in sentinel
            if stripwhitespace !== true && (startswith(sent, string(Char(wh1))) || startswith(sent, string(Char(wh2))))
                throw(ArgumentError("sentinel value isn't allowed to start with wh1 or wh2 characters"))
            end
            if quoted && (startswith(sent, string(Char(openquotechar))) || startswith(sent, string(Char(closequotechar))))
                throw(ArgumentError("sentinel value isn't allowed to start with openquotechar, closequotechar, or escapechar characters"))
            end
            if (delim isa UInt8 || delim isa Char) && startswith(sent, string(Char(delim)))
                throw(ArgumentError("sentinel value isn't allowed to start with a delimiter character"))
            elseif delim isa String && startswith(sent, delim)
                throw(ArgumentError("sentinel value isn't allowed to start with a delimiter string"))
            end
        end
    end

    wh1 = token(wh1, "wh1")
    wh2 = token(wh2, "wh2")
    if wh1.token != UInt8(' ') || wh2.token != UInt8('\t')
        stripwhitespace = false
    end
    oq = token(openquotechar, "openquotechar")
    cq = token(closequotechar, "closequotechar")
    e = token(escapechar, "escapechar")
    e.token isa UInt8 || throw(ArgumentError("escapechar must be a single ascii character"))
    quoted && (isempty(oq) || isempty(cq) || isempty(e)) && throw(ArgumentError("quoted=true requires openquotechar, closequotechar, and escapechar to be specified"))
    sent = (sentinel === nothing || sentinel === missing) ? Token[] : map(x -> token(x, "sentinel"), prepare!(sentinel))
    checksentinel = sentinel !== nothing
    del = delim
    delim = token(delim, "delim")
    checkdelim = delim !== nothing && !isempty(delim)
    if checkdelim && (_contains(delim, " ") || _contains(delim, "\t"))
        stripwhitespace = false
    end
    if trues !== nothing
        trues = prepare!(trues)
    end
    if falses !== nothing
        falses = prepare!(falses)
    end
    if groupmark !== nothing && (groupmark == decimal || isnumeric(groupmark) || (del == groupmark && !quoted) || (openquotechar == groupmark) || (closequotechar == groupmark))
        throw(ArgumentError("`groupmark` cannot be a number, a quoting char, coincide with `decimal` and `delim` unless `quoted=true`."))
    end
    df = dateformat === nothing ? nothing : dateformat isa String ? Format(dateformat) : dateformat isa Dates.DateFormat ? Format(dateformat) : dateformat
    return Options(StripWhitespace(stripwhitespace === true || stripquoted ? true : stripwhitespace), stripquoted, quoted, checksentinel, checkdelim, ignorerepeated, ignoreemptylines, decimal, oq, cq, e, sent, delim, token(comment, "comment"), trues, falses, df, groupmark === nothing ? nothing : UInt8(groupmark))
end

function token(x::MaybeToken, arg)
    x === nothing && return Token("")
    if x isa UInt8
        asciival(x) || throw(ArgumentError("$arg argument must be ASCII"))
        return Token(x)
    elseif x isa Char
        return Token(asciival(x) ? UInt8(x) : String(x))
    elseif x isa Regex
        return Token(mkregex(x))
    else
        return Token(x)
    end
end

Options(;
    sentinel::Union{Nothing, Missing, Vector}=nothing,
    wh1::Union{UInt8, Char}=UInt8(' '),
    wh2::Union{UInt8, Char}=UInt8('\t'),
    openquotechar::MaybeToken=UInt8('"'),
    closequotechar::MaybeToken=UInt8('"'),
    escapechar::MaybeToken=UInt8('"'),
    delim::MaybeToken=UInt8(','),
    decimal::Union{UInt8, Char}=UInt8('.'),
    trues::Union{Nothing, Vector{String}}=nothing,
    falses::Union{Nothing, Vector{String}}=nothing,
    dateformat::Union{Nothing, String, Dates.DateFormat, Format}=nothing,
    ignorerepeated::Bool=false,
    ignoreemptylines::Bool=false,
    comment::MaybeToken=nothing,
    quoted::Bool=true,
    debug::Bool=false,
    stripwhitespace::Union{Bool, Nothing}=nothing,
    stripquoted::Bool=false,
    groupmark::Union{Nothing,Char,UInt8}=nothing,
) = Options(sentinel, wh1, wh2, openquotechar, closequotechar, escapechar, delim, decimal, trues, falses, dateformat, ignorerepeated, ignoreemptylines, comment, quoted, stripwhitespace, stripquoted, groupmark)

include("components.jl")

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
function xparse(::Type{T}, buf::Union{AbstractVector{UInt8}, AbstractString, IO}; pos::Integer=1, len::Integer=buf isa IO ? 0 : sizeof(buf), kw...) where {T}
    options = Options(; kw...)
    return xparse(T, buf, pos, len, options)
end

xparse(::Type{T}, buf::AbstractString, pos, len, options=XOPTIONS, ::Type{S}=(T <: AbstractString) ? PosLen : T) where {T <: SupportedTypes, S} =
    xparse(T, codeunits(buf), pos, len, options, S)

xparse(::Type{T}, source::Union{AbstractVector{UInt8}, IO}, pos, len, options::Options=XOPTIONS, ::Type{S}=(T <: AbstractString) ? PosLen : T) where {T <: SupportedTypes, S} =
    Result(delimiter(options)(emptysentinel(options)(whitespace(options)(
        quoted(options)(whitespace(options)(sentinel(options)(typeparser(options)
    )))))))(T, source, pos, len, S)

# generic fallback calls Base.tryparse
function xparse(::Type{T}, source::Union{AbstractVector{UInt8}, IO}, pos, len, options, ::Type{S}=T) where {T, S}
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

# condensed version of xparse that doesn't worry about quoting or delimiters; called from Parsers.parse/Parsers.tryparse
@inline xparse2(::Type{T}, source::Union{AbstractVector{UInt8}, IO}, pos, len, opts::Options=XOPTIONS2, ::Type{S}=T) where {T <: SupportedTypes, S} =
    Result(whitespace(STRIP, false)(typeparser(opts)))(T, source, pos, len, S)

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

function checkdelim!(source::AbstractVector{UInt8}, pos, len, options::Options)
    eof(source, pos, len) && return pos
    delim = options.delim
    b = peekbyte(source, pos)
    if !options.ignorerepeated
        # we're checking for a single appearance of a delimiter
        match, pos = checktoken(source, pos, len, b, delim)
    else
        # keep parsing as long as we keep matching delim
        while !eof(source, pos, len)
            match, pos = checktoken(source, pos, len, b, delim)
            match || break
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
    resize!(empty!(BIGINT), Threads.nthreads())
    resize!(empty!(BIGFLOAT), Threads.nthreads())
    return
end

include("precompile.jl")

end # module
