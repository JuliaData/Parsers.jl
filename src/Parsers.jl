__precompile__(true)
module Parsers

using InternedStrings, Dates

const RETURN  = UInt8('\r')
const NEWLINE = UInt8('\n')
const COMMA   = UInt8(',')
const QUOTE   = UInt8('"')
const ESCAPE  = UInt8('\\')
const PERIOD  = UInt8('.')
const SPACE   = UInt8(' ')
const TAB     = UInt8('\t')
const MINUS   = UInt8('-')
const PLUS    = UInt8('+')
const NEG_ONE = UInt8('0')-UInt8(1)
const ZERO    = UInt8('0')
const TEN     = UInt8('9')+UInt8(1)
const UNDERSCORE = UInt8('_')

Dates.default_format(T) = Dates.dateformat""

"""
    Parsers.readbyte(io::IO)::UInt8

    Consume a single byte from an `IO` without checking `eof(io)`.
"""
function readbyte end

"""
    Parsers.peekbyte(io::IO)::UInt8

    Return, but do not consume, the next byte from an `IO` without checking `eof(io)`.
"""
function peekbyte end

readbyte(from::IO) = Base.read(from, UInt8)
peekbyte(from::IO) = Base.peek(from)

function readbyte(from::IOBuffer)
    @inbounds byte = from.data[from.ptr]
    from.ptr = from.ptr + 1
    return byte
end

function peekbyte(from::IOBuffer)
    @inbounds byte = from.data[from.ptr]
    return byte
end

"""
    Parsers.fastseek!(io::IO, n::Integer)

    Without valididty checks, seek an `IO` to desired byte position `n`.
"""
function fastseek! end

fastseek!(io::IO, n::Integer) = seek(io, n)
function fastseek!(io::IOBuffer, n::Integer)
    io.ptr = n+1
    return
end

"""
    Parsers.getio(io)::IO

    Get the actual underlying `IO` that may be wrapped in various `Parsers` layers.
"""
function getio end

getio(io::IO) = io

"""
    Enumeration of possible return codes to be used in `Parsers.Result`
        * `OK`: parsing succeeded
        * `EOF`: `eof(io)` was encountered before parsing was able to succeed
        * `OVERFLOW`: parsing of numeric type failed due to overflow (i.e. value to parse exceeded range of requested type)
        * `INVALID`: parsing failed
        * `INVALID_QUOTED_FIELD`: for use with the `Parsers.Quoted` layer; indicates an invalid quoted field where an opening quote was found, but no valid closing quote
"""
const ReturnCode = UInt8
const OK = 0x00
const EOF = 0x01
const OVERFLOW = 0x02
const INVALID = 0x03
const INVALID_QUOTED_FIELD = 0x04

"""
    Parsers.Result(x::T, ::Parsers.ReturnCode, b::UInt8)
    Parsers.Result(::Type{T}, code, byte)

    A result type used by `Parsers.xparse` to signal the result of trying to parse a certain type. Fields include:
        * `result::Union{T, Missing}`: holds the parsed result of type `T` or `missing` if unable to parse or a valid `Parsers.Sentinel` value was found
        * `code::Parsers.ReturnCode`: a value signaling whether parsing succeeded (`Parsers.OK`) or not (`Parsers.INVALID`); see `?Parsers.ReturnCode` for all possible codes
        * `b::UInt8`: the last byte parsed
"""
mutable struct Result{T}
    result::Union{T, Missing}
    code::ReturnCode
    b::UInt8
end

Result(::Type{T}, r::ReturnCode=OK, b::UInt8=0x00) where {T} = Result{T}(missing, r, b)

include("tries.jl")

struct Error <: Exception
    result::Result
end

include("parse.jl")

"empty function used by Parsers to dispatch to default type parsers"
function defaultparser end

"""
    Parsers.xparse!(f::Function=Parsers.defaultparser, io, ::Type{T}, r::Result{T}, args...)::Parsers.Result{T}

    Internal parsing function that returns a full `Parsers.Result` type to indicate the success of parsing a `T` from `io`.
    
    A custom parsing function `f` can be passed, which should have the form `f(io::IO, ::Type{T}, r::Result{T}, args...)::Result{T}`, i.e. it takes an `IO` stream, attemps to parse type `T`, takes a pre-allocated `Result{T}` and shoudl return it after parsing.
    
    The `io` argument may be a plain `IO` type, or one of the custom "IO layers" defined in Parsers (`Parsers.Delimited`, `Parsers.Quoted`, `Parsers.Strip`, `Parsers.Sentinel`).
"""
function xparse! end

# fallthrough for custom parser functions: user-provided function should be of the form: f(io::IO, ::Type{T}; kwargs...)::Result{T}
xparse!(f::Base.Callable, io::IO, ::Type{T}, r::Result{T}, args...) where {T} = f(io, T, r, args...)
xparse(io, ::Type{T};
    delims::Union{Trie, Nothing}=nothing,
    openquotechar::Union{Char, UInt8, Nothing}=nothing,
    closequotechar::Union{Char, UInt8, Nothing}=nothing,
    escapechar::Union{Char, UInt8, Nothing}=nothing,
    bools::Trie=BOOLS,
    dateformat::Union{String, Dates.DateFormat}=Dates.default_format(T),
    decimal::Union{Char, UInt8}=UInt8('.'),
    kwargs...) where {T} = xparse!(defaultparser, io, T, Result(T), delims, openquotechar, closequotechar, escapechar, bools, dateformat, decimal, values(kwargs)...)

xparse(f::Base.Callable, io, ::Type{T};
    delims::Union{Trie, Nothing}=nothing,
    openquotechar::Union{Char, UInt8, Nothing}=nothing,
    closequotechar::Union{Char, UInt8, Nothing}=nothing,
    escapechar::Union{Char, UInt8, Nothing}=nothing,
    bools::Trie=BOOLS,
    dateformat::Union{String, Dates.DateFormat}=Dates.default_format(T),
    decimal::Union{Char, UInt8}=UInt8('.'),
    kwargs...) where {T} = xparse!(defaultparser, io, T, Result(T), delims, openquotechar, closequotechar, escapechar, bools, dateformat, decimal, values(kwargs)...)
xparse!(io, ::Type{T}, r::Result{T}, args...) where {T} = xparse!(defaultparser, io, T, r)

"""
    An interface to define custom "parsing support" layers to be used in `Parsers.xparse`. Examples implementations include:
      * Parsers.Delimited
      * Parsers.Quoted
      * Parsers.Strip
      * Parsers.Sentinel

    The interface to implement for an `IOWrapper` is:
      * `Parsers.xparse!(f::Base.Callable, io::MyIOWrapper, ::Type{T}, r::Result{T}, args...) where {T}`: implementation of your custom `MyIOWrapper` type, including calling down to the next layer
      * `struct MyIOWrapper <: Parsers.IOWrapper`: subtype `Parsers.IOWrapper` (optional, but recommended)
      * `Parsers.getio(io::MyIOWrapper)`: function to get the actual underlying `IO` stream; default `IOWrapper` definition is `Parsers.getio(io.next)` (assuming your type includes a field called `next`)
      * `Parsers.eof(io::MyIOWrapper)`: to indicate if `eof` is true on your IOWrapper; default is `eof(getio(io))`
"""
abstract type IOWrapper end

getio(io::IOWrapper) = getio(io.next)
Base.eof(io::IOWrapper) = eof(getio(io))

"""
    Parsers.Delimited(next, delims::Union{Char, String}...=',')

    A custom Parsers "IO wrapper" used to support parsing delimited values in `IO` streams. `delims` can be any number of `Char` or `String` arguments that should collectively be used as "delimiters".

    Parsing on a `Parsers.Delimited` will first call `Parsers.xparse(d.next, T; kwargs...)`, then expect the next bytes to be one of the expected `delims` arguments.
    If one of `delims` is not found, the result is `Parsers.INVALID`, but parsing will continue until a valid `delims` is found. An `eof(io)` is _always_ considered a valid termination state in place of a delimiter.
"""
struct Delimited{I} <: IOWrapper
    next::I
    delims::Trie{Missing}
end
Delimited(next, delims::Union{Char, String}...=',') = Delimited(next, Trie(String[string(d) for d in delims]))

function xparse!(f::Base.Callable, d::Delimited, ::Type{T}, r::Result{T}, delims=nothing, args...) where {T}
    # @debug "xparse Delimited - $T"
    xparse!(f, d.next, T, r, d.delims, args...)
    # @debug "Delimited - $T: r.code=$(r.code), r.result=$(r.result)"
    io = getio(d)
    eof(io) && return r
    match!(d.delims, io, r, false) && return r
    # @debug "didn't find delimiters at expected location; result is invalid, parsing until delimiter is found"
    b = 0x00
    while true
        b = readbyte(io)
        if eof(io)
            r.b = b
            break
        end
        match!(d.delims, io, r, false) && break
    end
    r.code = INVALID
    return r
end

"""
    Parsers.Quoted(next, quotechar='"', escapechar='\\')
    Parsers.Quoted(next, openquote, closequote, escapechar)

    A custom Parsers "IO wrapper" used to support parsing potentially "quoted" values. Parsing with a `Parsers.Quoted` does not _require_ the value to be quoted, but will always check for an initial quote and, if found, will then expect (and continue parsing until) a corresponding close quote is found.
    A single `quotechar` can be given, indicating the quoted field will start and end with the same character.
    Both `quotechar` and `escapechar` arguments are limited to ASCII characters.
"""
struct Quoted{I} <: IOWrapper
    next::I
    openquotechar::UInt8
    closequotechar::UInt8
    escapechar::UInt8
end
Quoted(next, q::Union{Char, UInt8}='"', e::Union{Char, UInt8}='\\') = Quoted(next, UInt8(q), UInt8(q), UInt8(e))
Quoted(next, q1::Union{Char, UInt8}, q2::Union{Char, UInt8}, e::Union{Char, UInt8}) = Quoted(next, UInt8(q1), UInt8(q2), UInt8(e))

function xparse!(f::Base.Callable, q::Quoted, ::Type{T}, r::Result{T}, delims=nothing, o=nothing, c=nothing, e=nothing, args...) where {T}
    # @debug "xparse Quoted - $T"
    io = getio(q)
    if !eof(io) && peekbyte(io) === q.openquotechar
        readbyte(io)
        quoted = true
        xparse!(f, q.next, T, r, delims, q.openquotechar, q.closequotechar, q.escapechar, args...)
    else
        xparse!(f, q.next, T, r, delims, nothing, nothing, nothing, args...)
        quoted = false
    end
    # @debug "Quoted - $T: result.code=$(result.code), result.result=$(result.result)"
    if quoted
        if eof(io)
            r.code = INVALID_QUOTED_FIELD
            return r
        end
        b = peekbyte(io)
        if b !== q.closequotechar
            # @debug "invalid quoted field; parsing should have consumed until quotechar"
            same = q.closequotechar === q.escapechar
            while true
                if same && b === q.escapechar
                    readbyte(io)
                    if (eof(io) || peekbyte(io) !== q.closequotechar) 
                        r.code = INVALID
                        r.b = b
                        return r
                    end
                elseif b === q.escapechar
                    readbyte(io)
                    if eof(io)
                        r.code = INVALID_QUOTED_FIELD
                        r.b = b
                        return r
                    end
                elseif b === q.closequotechar
                    readbyte(io)
                    r.code = INVALID
                    r.b = b
                    return r
                end
                b = readbyte(io)
                eof(io) && break
                b = peekbyte(io)
            end
            r.code = INVALID_QUOTED_FIELD
            r.b = b
        else
            r.b = b
            readbyte(io)
        end
    end
    return r
end

"""
    Parsers.Strip(next, wh1=' ', wh2='\t')

    A custom Parsers "IO wrapper" used to remove leading and trailing whitespace.
    By default, only `' '` (space) and `'\t'` (tab) characters are skipped over.
    Any two valid ASCII characters may be used to skip.
"""
struct Strip{I} <: IOWrapper
    next::I
    wh1::UInt8
    wh2::UInt8
end
Strip(io::I, wh1=' ', wh2='\t') where {I} = Strip{I}(io, wh1 % UInt8, wh2 % UInt8)

function wh!(io, wh1, wh2)
    if !eof(io)
        b = peekbyte(io)
        while b == wh1 | b == wh2
            readbyte(io)
            eof(io) && break
            b = peekbyte(io)
        end
    end
    return
end

function xparse!(f::Base.Callable, s::Strip, ::Type{T}, r::Result{T}, args...) where {T}
    # @debug "xparse Strip - $T"
    io = getio(s)
    wh!(io, s.wh1, s.wh2)
    xparse!(f, s.next, T, r, args...)
    # @debug "Strip - $T: result.code=$(result.code), result.result=$(result.result), result.b=$(result.b)"
    wh!(io, s.wh1, s.wh2)
    return r
end

# don't strip whitespace for Strings
xparse!(f::Base.Callable, s::Strip, ::Type{Tuple{Ptr{UInt8}, Int}}, r::Result{Tuple{Ptr{UInt8}, Int}}, args...) =
    xparse!(f, s.next, Tuple{Ptr{UInt8}, Int}, r, args...)
xparse!(f::Base.Callable, s::Strip, ::Type{String}, r::Result{String}, args...) =
    xparse!(f, s.next, String, r, args...)

"""
    Parses.Sentinel(next, sentinels::Union{String, Vector{String}})

    A custom Parsers "IO wrapper" to support sentinel value parsing for any type. A single string or vector of strings can be provided which, if encountered during parsing, will result in `missing` being returned with a `Parsers.ReturnCode` of `Parsers.OK`. 

    One special case of sentinel parsing is that of the "empty" sentinel, i.e. `Parsers.Sentinel(io, "")`. In this case, sentinel parsing will "succeed" only when the underlying type parsing failed to consume any bytes (i.e it immediately encountered invalid characters).
"""
struct Sentinel{I} <: IOWrapper
    next::I
    sentinels::Trie{Missing}
end
Sentinel(next, sentinels::Union{String, Vector{String}}) = Sentinel(next, Trie(sentinels))

function xparse!(f::Base.Callable, s::Sentinel, ::Type{T}, r::Result{T}, args...) where {T}
    # @debug "xparse Sentinel - $T"
    io = getio(s)
    pos = position(io)
    xparse!(f, s.next, T, r, args...)
    # @debug "Sentinel - $T: result.code=$(result.code), result.result=$(result.result)"
    if r.code !== OK
        if isempty(s.sentinels.leaves) && position(io) == pos
            r.code = OK
        else
            fastseek!(io, pos)
            match!(s.sentinels, io, r)
        end
    end
    return r
end

# Core integer parsing function
function xparse!(::typeof(defaultparser), io::IO, ::Type{T}, r::Result{T}, args...) where {T <: Integer}
    # @debug "xparse Int"
    eof(io) && (r.code = EOF; return r)
    v = zero(T)
    b = peekbyte(io)
    negative = false
    if b == MINUS # check for leading '-' or '+'
        negative = true
        readbyte(io)
        eof(io) && (r.code = EOF; r.b = b; return r)
        b = peekbyte(io)
    elseif b == PLUS
        readbyte(io)
        eof(io) && (r.code = EOF; r.b = b; return r)
        b = peekbyte(io)
    end
    parseddigits = false
    while NEG_ONE < b < TEN || (parseddigits && b == UNDERSCORE)
        parseddigits = true
        b = readbyte(io)
        if b !== UNDERSCORE
            v, ov_mul = Base.mul_with_overflow(v, T(10))
            v, ov_add = Base.add_with_overflow(v, T(b - ZERO))
            (ov_mul | ov_add) && (r.result = v; r.code = OVERFLOW; r.b = b; return r)
        end
        eof(io) && break
        b = peekbyte(io)
    end
    if !parseddigits
        r.code = INVALID
        r.b = b
    else
        r.result = ifelse(negative, -v, v)
        r.code = OK
        r.b = b
    end
    return r
end

include("strings.jl")
include("floats.jl")

# Bool parsing
const BOOLS = Trie(["true"=>true, "false"=>false])

function xparse!(::typeof(defaultparser), io::IO, ::Type{Bool}, r::Result{Bool}, d=nothing, o=nothing, c=nothing, e=nothing, bools::Trie=BOOLS, args...)
    r.code = INVALID
    match!(bools, io, r)
    return r
end

# Dates.TimeType parsing
make(df::Dates.DateFormat) = df
make(df::String) = Dates.DateFormat(df)

function xparse!(::typeof(defaultparser), io::IO, ::Type{T}, r::Result{T}, d=nothing, o=nothing, c=nothing, e=nothing, b=nothing, df::Union{String, Dates.DateFormat}=Dates.default_format(T), args...) where {T <: Dates.TimeType}
    pos = position(io)
    res = xparse!(defaultparser, io, String, Result(String), d, o, c, e)
    # @show res
    if res.code === OK && !isempty(res.result)
        dt = Base.tryparse(T, res.result, make(df))
        if dt === nothing
            fastseek!(io, pos)
            r.code = INVALID
            r.b = res.b
        else
            r.result = dt
            r.code = OK
        end
    else
        r.code = INVALID
        r.b = res.b
    end
    return r
end

xparse!(::typeof(defaultparser), io::IO, ::Type{Missing}, r::Result{Missing}, args...) = (r.code = INVALID; return r)
xparse!(::typeof(defaultparser), io::IO, ::Type{Union{}}, r::Result{Missing}, args...) = (r.code = INVALID; return r)

end # module
