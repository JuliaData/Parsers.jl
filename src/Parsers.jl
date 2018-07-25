__precompile__(true)
module Parsers

import InternedStrings, Dates

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
@enum ReturnCode OK EOF OVERFLOW INVALID INVALID_QUOTED_FIELD

"""
    Parsers.Result(x::T, ::Parsers.ReturnCode, b::UInt8)
    Parsers.Result(::Type{T}, code, byte)

    A result type used by `Parsers.xparse` to signal the result of trying to parse a certain type. Fields include:
        * `result::Union{T, Missing}`: holds the parsed result of type `T` or `missing` if unable to parse or a valid `Parsers.Sentinel` value was found
        * `code::Parsers.ReturnCode`: an enum value signaling whether parsing succeeded (`Parsers.OK`) or not (`Parsers.INVALID`); see `?Parsers.ReturnCode` for all possible codes
        * `b::UInt8`: the last byte parsed
"""
mutable struct Result{T}
    result::Union{T, Missing}
    code::ReturnCode
    b::UInt8
end

Result(::Type{T}, r::ReturnCode, b::UInt8=0x00) where {T} = Result{T}(missing, r, b)

include("tries.jl")

struct Error <: Exception
    result::Result
end

# high-level convenience functions like in Base
"Attempt to parse a value of type `T` from string `str`. Throws `Parsers.Error` on parser failures and invalid values."
function Base.parse(str::String, ::Type{T}; kwargs...) where {T}
    res = xparse(IOBuffer(str), T; kwargs...)
    return res.code === OK ? res.result : throw(Error(res))
end

function Base.parse(f::Base.Callable, str::String, ::Type{T}; kwargs...) where {T}
    res = xparse(f, IOBuffer(str), T; kwargs...)
    return res.code === OK ? res.result : throw(Error(res))
end

"Attempt to parse a value of type `T` from `IO` `io`. Throws `Parsers.Error` on parser failures and invalid values."
function Base.parse(io::IO, ::Type{T}; kwargs...) where {T}
    res = xparse(io, T; kwargs...)
    return res.code === OK ? res.result : throw(Error(res))
end

function Base.parse(f::Base.Callable, io::IO, ::Type{T}; kwargs...) where {T}
    res = xparse(f, io, T; kwargs...)
    return res.code === OK ? res.result : throw(Error(res))
end

"Attempt to parse a value of type `T` from string `str`. Returns `nothing` on parser failures and invalid values."
function Base.tryparse(str::String, ::Type{T}; kwargs...) where {T}
    res = xparse(IOBuffer(str), T; kwargs...)
    return res.code === OK ? res.result : nothing
end

function Base.tryparse(f::Base.Callable, str::String, ::Type{T}; kwargs...) where {T}
    res = xparse(f, IOBuffer(str), T; kwargs...)
    return res.code === OK ? res.result : nothing
end

"Attempt to parse a value of type `T` from `IO` `io`. Returns `nothing` on parser failures and invalid values."
function Base.tryparse(io::IO, ::Type{T}; kwargs...) where {T}
    res = xparse(io, T; kwargs...)
    return res.code === OK ? res.result : nothing
end

function Base.tryparse(f::Base.Callable, io::IO, ::Type{T}; kwargs...) where {T}
    res = xparse(f, io, T; kwargs...)
    return res.code === OK ? res.result : nothing
end

"empty function used by Parsers to dispatch to default type parsers"
function defaultparser end

"""
    Parsers.xparse(f::Function=Parsers.defaultparser, io, ::Type{T}; kwargs...)::Parsers.Result{T}

    Internal parsing function that returns a full `Parsers.Result` type to indicate the success of parsing a `T` from `io`.
    
    A custom parsing function `f` can be passed, which should have the form `f(io::IO, ::Type{T}; kwargs...)::Result{T}`, i.e. it takes an `IO` stream, attemps to parse type `T`, and returns a `Parsers.Result` type.
    
    The `io` argument may be a plain `IO` type, or one of the custom "IO layers" defined in Parsers (`Parsers.Delimited`, `Parsers.Quoted`, `Parsers.Strip`, `Parsers.Sentinel`).
"""
function xparse end

# fallthrough for custom parser functions: user-provided function should be of the form: f(io::IO, ::Type{T}; kwargs...)::Result{T}
xparse(f::Base.Callable, io::IO, ::Type{T}; kwargs...) where {T} = f(io, T; kwargs...)
xparse(io::IO, ::Type{T}; kwargs...) where {T} = xparse(defaultparser, io, T; kwargs...)

"""
    An interface to define custom "parsing support" layers to be used in `Parsers.xparse`. Examples implementations include:
      * Parsers.Delimited
      * Parsers.Quoted
      * Parsers.Strip
      * Parsers.Sentinel

    The interface to implement for an `IOWrapper` is:
      * `Parsers.xparse(io::MyIOWrapper, ::Type{T}; kwargs...) where {T} = Parsers.xparse(Parsers.defaultparser, io, T; kwargs...)`: default fallback method to use the `Parsers.defaultparser` function for basic types
      * `Parsers.xparse(f::Base.Callable, io::MyIOWrapper, ::Type{T}; kwargs...) where {T}`: implementation of your custom `MyIOWrapper` type, including calling down to the next layer
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

xparse(d::Delimited{I}, ::Type{T}; kwargs...) where {I, T} = xparse(defaultparser, d, T; kwargs...)

function xparse(f::Base.Callable, d::Delimited{I}, ::Type{T}; kwargs...) where {I, T}
    # @debug "xparse Delimited - $T"
    result = xparse(f, d.next, T; delims=d.delims, kwargs...)
    # @debug "Delimited - $T: result.code=$(result.code), result.result=$(result.result)"
    io = getio(d)
    eof(io) && return result
    match!(d.delims, io, result, false) && return result
    # @debug "didn't find delimiters at expected location; result is invalid, parsing until delimiter is found"
    b = 0x00
    while true
        b = readbyte(io)
        if eof(io)
            result.b = b
            break
        end
        match!(d.delims, io, result, false) && break
    end
    result.code = INVALID
    return result
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

xparse(q::Quoted{I}, ::Type{T}; kwargs...) where {I, T} = xparse(defaultparser, q, T; kwargs...)

function xparse(f::Base.Callable, q::Quoted{I}, ::Type{T};
    delims::Union{Nothing, Trie}=nothing,
    kwargs...) where {I, T}
    # @debug "xparse Quoted - $T"
    io = getio(q)
    if !eof(io) && peekbyte(io) === q.openquotechar
        readbyte(io)
        quoted = true
        result = xparse(f, q.next, T; delims=delims, openquotechar=q.openquotechar, closequotechar=q.closequotechar, escapechar=q.escapechar, kwargs...)
    else
        result = xparse(f, q.next, T; delims=delims, kwargs...)
        quoted = false
    end
    # @debug "Quoted - $T: result.code=$(result.code), result.result=$(result.result)"
    if quoted
        if eof(io)
            result.code = INVALID_QUOTED_FIELD
            return result
        end
        b = peekbyte(io)
        if b !== q.closequotechar
            # @debug "invalid quoted field; parsing should have consumed until quotechar"
            same = q.closequotechar === q.escapechar
            while true
                if same && b === q.escapechar
                    readbyte(io)
                    if (eof(io) || peekbyte(io) !== q.closequotechar) 
                        result.code = INVALID
                        result.b = b
                        return result
                    end
                elseif b === q.escapechar
                    readbyte(io)
                    if eof(io)
                        result.code = INVALID_QUOTED_FIELD
                        result.b = b
                        return result
                    end
                elseif b === q.closequotechar
                    readbyte(io)
                    result.code = INVALID
                    result.b = b
                    return result
                end
                b = readbyte(io)
                eof(io) && break
                b = peekbyte(io)
            end
            result.code = INVALID_QUOTED_FIELD
            result.b = b
        else
            result.b = b
            readbyte(io)
        end
    end
    return result
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

xparse(s::Strip, ::Type{T}; kwargs...) where {T} = xparse(defaultparser, s, T; kwargs...)

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

function xparse(f::Base.Callable, s::Strip, ::Type{T};
    openquotechar::Union{UInt8, Nothing}=nothing,
    closequotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=openquotechar,
    delims::Union{Nothing, Trie}=nothing,
    kwargs...) where {T}
    # @debug "xparse Strip - $T"
    io = getio(s)
    wh!(io, s.wh1, s.wh2)
    result = xparse(f, s.next, T; openquotechar=openquotechar, closequotechar=closequotechar, escapechar=escapechar, delims=delims, kwargs...)
    # @debug "Strip - $T: result.code=$(result.code), result.result=$(result.result), result.b=$(result.b)"
    wh!(io, s.wh1, s.wh2)
    return result
end

# don't strip whitespace for Strings
xparse(f::Base.Callable, s::Strip, ::Type{Tuple{Ptr{UInt8}, Int}}; kwargs...) = xparse(f, s.next, Tuple{Ptr{UInt8}, Int}; kwargs...)
xparse(f::Base.Callable, s::Strip, ::Type{String}; kwargs...) = xparse(f, s.next, String; kwargs...)

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

xparse(s::Sentinel{I}, ::Type{T}; kwargs...) where {I, T} = xparse(defaultparser, s, T; kwargs...)

function xparse(f::Base.Callable, s::Sentinel{I}, ::Type{T};
    openquotechar::Union{UInt8, Nothing}=nothing,
    closequotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=openquotechar,
    delims::Union{Nothing, Trie}=nothing,
    kwargs...)::Result{T} where {I, T}
    # @debug "xparse Sentinel - $T"
    io = getio(s)
    pos = position(io)
    result = xparse(f, s.next, T; openquotechar=openquotechar, closequotechar=closequotechar, escapechar=escapechar, delims=delims, kwargs...)
    # @debug "Sentinel - $T: result.code=$(result.code), result.result=$(result.result)"
    if result.code !== OK
        if isempty(s.sentinels.leaves) && position(io) == pos
            result.code = OK
        else
            fastseek!(io, pos)
            match!(s.sentinels, io, result)
        end
    end
    return result
end

# Core integer parsing function
function xparse(::typeof(defaultparser), io::IO, ::Type{T};
    openquotechar::Union{UInt8, Nothing}=nothing,
    closequotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=openquotechar,
    delims::Union{Nothing, Trie}=nothing,
    kwargs...)::Result{T} where {T <: Integer}
    # @debug "xparse Int"
    eof(io) && return Result(T, EOF)
    v = zero(T)
    b = peekbyte(io)
    negative = false
    if b == MINUS # check for leading '-' or '+'
        negative = true
        readbyte(io)
        eof(io) && return Result(T, EOF, b)
        b = peekbyte(io)
    elseif b == PLUS
        readbyte(io)
        eof(io) && return Result(T, EOF, b)
        b = peekbyte(io)
    end
    parseddigits = false
    while NEG_ONE < b < TEN || (parseddigits && b == UNDERSCORE)
        parseddigits = true
        b = readbyte(io)
        if b !== UNDERSCORE
            v, ov_mul = Base.mul_with_overflow(v, T(10))
            v, ov_add = Base.add_with_overflow(v, T(b - ZERO))
            (ov_mul | ov_add) && return Result(v, OVERFLOW, b)
        end
        eof(io) && break
        b = peekbyte(io)
    end
    if !parseddigits
        return Result(T, INVALID, b)
    else
        return Result(ifelse(negative, -v, v), OK, b)
    end
end

include("strings.jl")
include("floats.jl")

# Bool parsing
const BOOLS = Trie(["true"=>true, "false"=>false])

@inline function xparse(::typeof(defaultparser), io::IO, ::Type{Bool};
    bools::Trie=BOOLS,
    openquotechar::Union{UInt8, Nothing}=nothing,
    closequotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=openquotechar,
    delims::Union{Nothing, Trie}=nothing,
    kwargs...)::Result{Bool}
    r = Result(Bool, INVALID)
    match!(bools, io, r)
    return r
end

# Dates.TimeType parsing
make(df::Dates.DateFormat) = df
make(df::String) = Dates.DateFormat(df)

@inline function xparse(::typeof(defaultparser), io::IO, ::Type{T};
    dateformat::Union{String, Dates.DateFormat}=Dates.default_format(T),
    openquotechar::Union{UInt8, Nothing}=nothing,
    closequotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=openquotechar,
    delims::Union{Nothing, Trie}=nothing,
    kwargs...)::Result{T} where {T <: Dates.TimeType}
    pos = position(io)
    res = xparse(io, String; openquotechar=openquotechar, closequotechar=closequotechar, escapechar=escapechar, delims=delims, kwargs...)
    if res.code === OK && !isempty(res.result)
        dt = tryparse(T, res.result, make(dateformat))
        if dt === nothing
            fastseek!(io, pos)
            return Result(T, INVALID, res.b)
        else
            return Result(dt, OK, 0x00)
        end
    else
        return Result(T, INVALID, res.b)
    end
end

xparse(::typeof(defaultparser), io::IO, ::Type{Missing}; kwargs...) = Result(Missing, INVALID, 0x00)
xparse(::typeof(defaultparser), io::IO, ::Type{Union{}}; kwargs...) = Result(Missing, INVALID, 0x00)

end # module
