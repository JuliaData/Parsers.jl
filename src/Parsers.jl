__precompile__(true)
module Parsers

using Dates
Dates.default_format(T) = Dates.dateformat""

function __init__()
    Threads.resize_nthreads!(INTERNED_STRINGS_POOL)
    for results in RESULTS
        Threads.resize_nthreads!(results)
    end
    return
end

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
    Possible return codes to be used in `Parsers.Result`
        * `OK=0x00`: parsing succeeded
        * `EOF=0x01`: `eof(io)` was encountered before parsing was able to succeed
        * `OVERFLOW=0x02`: parsing of numeric type failed due to overflow (i.e. value to parse exceeded range of requested type)
        * `INVALID=0x03`: parsing failed
        * `INVALID_QUOTED_FIELD=0x04`: for use with the `Parsers.Quoted` layer; indicates an invalid quoted field where an opening quote was found, but no valid closing quote
"""
const ReturnCode = UInt8
const OK = 0x00
const EOF = 0x01
const OVERFLOW = 0x02
const INVALID = 0x03
const INVALID_QUOTED_FIELD = 0x04

"""
    Parsers.Result{T}(x::Union{T, Missing}, ::Parsers.ReturnCode, b::UInt8)
    Parsers.Result(::Type{T}, code, byte)

    A result type used by `Parsers.parse!` to signal the result of trying to parse a certain type. Fields include:
        * `result::Union{T, Missing}`: holds the parsed result of type `T` or `missing` if unable to parse or a valid `Parsers.Sentinel` value was found
        * `code::Parsers.ReturnCode`: a value signaling whether parsing succeeded (`Parsers.OK`) or not (`Parsers.INVALID`); see `?Parsers.ReturnCode` for all possible codes
        * `b::UInt8`: the last byte parsed
"""
mutable struct Result{T}
    result::Union{T, Missing}
    code::ReturnCode
    b::UInt8
end

# pre-allocated Results for default supported types
const DEFAULT_TYPES = (Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128,
    Float16, Float32, Float64,
    Tuple{Ptr{UInt8}, Int}, String,
    Date, DateTime, Time,
    Bool)

const RESULTS = Tuple([Result{T}(missing, OK, 0x00)] for T in DEFAULT_TYPES)

for (i, T) in enumerate(DEFAULT_TYPES)
    @eval index(::Type{$T}) = $i
end
index(T) = length(RESULTS) + 1

@inline @generated function Result(::Type{T}) where {T}
    i = index(T)
    i > length(RESULTS) && return Result{T}(missing, OK, 0x00)
    if i > length(RESULTS)
        return :(Result{$T}(missing, OK, 0x00))
    else
        return :($(RESULTS[i])[Threads.threadid()])
    end
end

include("tries.jl")

struct Error <: Exception
    result::Result
end

"""
    An interface to define custom "parsing support" layers to be used in `Parsers.parse!`. Examples implementations include:
      * Parsers.Delimited
      * Parsers.Quoted
      * Parsers.Strip
      * Parsers.Sentinel

    The interface to implement for a `Layer` is:
      * `Parsers.parse!(x::MyLayer, io::IO, r::Result{T}; kwargs...) where {T}`: implementation of your custom `MyLayer` type, including calling down to the next layer
      * Include a parameterized `next::I` field, to allow parsing the next layer
"""
abstract type Layer end

"function used by Parsers to dispatch to default type parser implementations"
function defaultparser end

"""
    Parsers.parse!(l::Parsers.Layer, io::IO, r::Result{T}; kwargs...)::Parsers.Result{T}

    Internal parsing function that returns a full `Parsers.Result` type to indicate the success of parsing a `T` from `io`.
    
    A custom parsing function `f` can be passed, as the innermost "layer", which should have the form `f(io::IO, ::Type{T}, r::Result{T}, args...)::Result{T}`, i.e. it takes an `IO` stream, attemps to parse type `T`, takes a pre-allocated `Result{T}` and should return it after parsing.
"""
function parse! end

# fallthrough for custom parser functions: user-provided function should be of the form: f(io::IO, ::Type{T}; kwargs...)::Result{T}
@inline parse!(f::Base.Callable, io::IO, r::Result{T}; kwargs...) where {T} = f(io, r; kwargs...)
@inline parse!(io::IO, r::Result{T}; kwargs...) where {T} = parse!(defaultparser, io, r; kwargs...)
@inline parse(layer::Union{typeof(defaultparser), Layer}, io::IO, ::Type{T}; kwargs...) where {T} = parse!(layer, io, Result(T); kwargs...)

# high-level convenience functions like in Base
"Attempt to parse a value of type `T` from string `str`. Throws `Parsers.Error` on parser failures and invalid values."
function parse end

"Attempt to parse a value of type `T` from `IO` `io`. Returns `nothing` on parser failures and invalid values."
function tryparse end

function parse(str::String, ::Type{T}; kwargs...) where {T}
    res = parse(defaultparser, IOBuffer(str), T; kwargs...)
    return res.code === OK ? res.result : throw(Error(res))
end
function parse(io::IO, ::Type{T}; kwargs...) where {T}
    res = parse(defaultparser, io, T; kwargs...)
    return res.code === OK ? res.result : throw(Error(res))
end
function parse(f::Base.Callable, str::String, ::Type{T}; kwargs...) where {T}
    res = parse!(f, IOBuffer(str), Result(T); kwargs...)
    return res.code === OK ? res.result : throw(Error(res))
end
function parse(f::Base.Callable, io::IO, ::Type{T}; kwargs...) where {T}
    res = parse!(f, io, Result(T); kwargs...)
    return res.code === OK ? res.result : throw(Error(res))
end

function tryparse(str::String, ::Type{T}; kwargs...) where {T}
    res = parse(defaultparser, IOBuffer(str), T; kwargs...)
    return res.code === OK ? res.result : nothing
end
function tryparse(io::IO, ::Type{T}; kwargs...) where {T}
    res = parse(defaultparser, io, T; kwargs...)
    return res.code === OK ? res.result : nothing
end
function tryparse(f::Base.Callable, str::String, ::Type{T}; kwargs...) where {T}
    res = parse!(f, IOBuffer(str), Result(T); kwargs...)
    return res.code === OK ? res.result : nothing
end
function tryparse(f::Base.Callable, io::IO, ::Type{T}; kwargs...) where {T}
    res = parse!(f, io, Result(T); kwargs...)
    return res.code === OK ? res.result : nothing
end

"""
    Parsers.Delimited(next, delims::Union{Char, String}...=',')

    A custom `Parsers.Layer` used to support parsing delimited values in `IO` streams. `delims` can be any number of `Char` or `String` arguments that should collectively be used as "delimiters".

    Parsing on a `Parsers.Delimited` will first call `Parsers.parse!(d.next, io, result; kwargs...)`, then expect the next bytes to be one of the expected `delims` arguments.
    If one of `delims` is not found, the result is `Parsers.INVALID`, but parsing will continue until a valid `delims` is found. An `eof(io)` is _always_ considered a valid termination state in place of a delimiter.
"""
struct Delimited{I, T <: Trie} <: Layer
    next::I
    delims::T
end
Delimited(next, delims::Union{Char, String}...=',') = Delimited(next, Trie(String[string(d) for d in delims]))
Delimited(delims::Union{Char, String}...=',') = Delimited(defaultparser, Trie(String[string(d) for d in delims]))

@inline function parse!(d::Delimited, io::IO, r::Result{T}; kwargs...) where {T}
    # @debug "xparse Delimited - $T"
    parse!(d.next, io, r; kwargs...)
    # @debug "Delimited - $T: r.code=$(r.code), r.result=$(r.result)"
    eof(io) && return r
    match!(d.delims, io, r, false) && return r
    # @debug "didn't find delimiters at expected location; result is invalid, parsing until delimiter is found"
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

    A custom `Parsers.Layer` used to support parsing potentially "quoted" values. Parsing with a `Parsers.Quoted` does not _require_ the value to be quoted, but will always check for an initial quote and, if found, will then expect (and continue parsing until) a corresponding close quote is found.
    A single `quotechar` can be given, indicating the quoted field will start and end with the same character.
    Both `quotechar` and `escapechar` arguments are limited to ASCII characters.
"""
struct Quoted{I} <: Layer
    next::I
    openquotechar::UInt8
    closequotechar::UInt8
    escapechar::UInt8
end
Quoted(next, q::Union{Char, UInt8}='"', e::Union{Char, UInt8}='\\') = Quoted(next, UInt8(q), UInt8(q), UInt8(e))
Quoted(next, q1::Union{Char, UInt8}, q2::Union{Char, UInt8}, e::Union{Char, UInt8}) = Quoted(next, UInt8(q1), UInt8(q2), UInt8(e))
Quoted(q::Union{Char, UInt8}='"', e::Union{Char, UInt8}='\\') = Quoted(defaultparser, UInt8(q), UInt8(q), UInt8(e))
Quoted(q1::Union{Char, UInt8}, q2::Union{Char, UInt8}, e::Union{Char, UInt8}) = Quoted(defaultparser, UInt8(q1), UInt8(q2), UInt8(e))

function handlequoted!(q, io, r)
    if eof(io)
        r.code = INVALID_QUOTED_FIELD
    else
        first = true
        same = q.closequotechar === q.escapechar
        while true
            b = peekbyte(io)
            if same && b === q.escapechar
                readbyte(io)
                if eof(io) || peekbyte(io) !== q.closequotechar
                    r.b = b
                    !first && (r.code = INVALID)
                    break
                end
                # otherwise, next byte is escaped, so read it
                b = peekbyte(io)
            elseif b === q.escapechar
                readbyte(io)
                if eof(io)
                    r.code = INVALID_QUOTED_FIELD
                    r.b = b
                    break
                end
                # regular escaped byte
                b = peekbyte(io)
            elseif b === q.closequotechar
                readbyte(io)
                r.b = b
                !first && (r.code = INVALID)
                break
            end
            readbyte(io)
            if eof(io)
                r.code = INVALID_QUOTED_FIELD
                r.b = b
                break
            end
            first = false
        end
    end
    return
end

@inline function parse!(q::Quoted, io::IO, r::Result{T}; kwargs...) where {T}
    # @debug "xparse Quoted - $T"
    quoted = false
    if !eof(io) && peekbyte(io) === q.openquotechar
        readbyte(io)
        quoted = true
    end
    parse!(q.next, io, r; kwargs...)
    # @debug "Quoted - $T: result.code=$(result.code), result.result=$(result.result)"
    quoted && handlequoted!(q, io, r)
    return r
end

"""
    Parsers.Strip(next, wh1=' ', wh2='\t')

    A custom `Parsers.Layer` used to remove leading and trailing whitespace.
    By default, only `' '` (space) and `'\t'` (tab) characters are skipped over.
    Any two valid ASCII characters may be used to skip.
"""
struct Strip{I} <: Layer
    next::I
    wh1::UInt8
    wh2::UInt8
end
Strip(next, wh1::Union{Char, UInt8}=' ', wh2::Union{Char, UInt8}='\t') = Strip(next, wh1 % UInt8, wh2 % UInt8)
Strip(wh1::Union{Char, UInt8}=' ', wh2::Union{Char, UInt8}='\t') = Strip(defaultparser, wh1 % UInt8, wh2 % UInt8)

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

@inline function parse!(s::Strip, io::IO, r::Result{T}; kwargs...) where {T}
    # @debug "xparse Strip - $T"
    wh!(io, s.wh1, s.wh2)
    parse!(s.next, io, r; kwargs...)
    # @debug "Strip - $T: result.code=$(result.code), result.result=$(result.result), result.b=$(result.b)"
    wh!(io, s.wh1, s.wh2)
    return r
end

"""
    Parses.Sentinel(next, sentinels::Union{String, Vector{String}})

    A custom `Parsers.Layer` to support sentinel value parsing for any type. A single string or vector of strings can be provided which, if encountered during parsing, will result in `missing` being returned with a `Parsers.ReturnCode` of `Parsers.OK`.

    One special case of sentinel parsing is that of the "empty" sentinel, i.e. `Parsers.Sentinel(io, "")`. In this case, sentinel parsing will "succeed" only when the underlying type parsing failed to consume any bytes (i.e it immediately encountered invalid characters).
"""
struct Sentinel{I, T} <: Layer
    next::I
    sentinels::T
end
Sentinel(next, sentinels::Union{String, Vector{String}}) = Sentinel(next, Trie(sentinels))
Sentinel(sentinels::Union{String, Vector{String}}) = Sentinel(defaultparser, Trie(sentinels))

@inline function parse!(s::Sentinel, io::IO, r::Result{T}; kwargs...) where {T}
    # @debug "xparse Sentinel - $T"
    pos = position(io)
    parse!(s.next, io, r; kwargs...)
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
@inline function defaultparser(io::IO, r::Result{T}; kwargs...) where {T <: Integer}
    # @debug "xparse Int"
    setfield!(r, 1, missing)
    # r.result = missing
    eof(io) && (r.code = EOF; r.b = 0x00; return r)
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
    while NEG_ONE < b < TEN
        parseddigits = true
        b = readbyte(io)
        v, ov_mul = Base.mul_with_overflow(v, T(10))
        v, ov_add = Base.add_with_overflow(v, T(b - ZERO))
        (ov_mul | ov_add) && (r.result = v; r.code = OVERFLOW; r.b = b; return r)
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
include("dates.jl")

# Bool parsing
const BOOLS = Trie(["true"=>true, "false"=>false])

@inline function defaultparser(io::IO, r::Result{Bool}; bools::Trie=BOOLS, kwargs...)
    setfield!(r, 1, missing)
    r.code = INVALID
    r.b = 0x00
    match!(bools, io, r)
    return r
end

defaultparser(io::IO, r::Result{Missing}; kwargs...) = (r.code = INVALID; return r)
defaultparser(io::IO, r::Result{Union{}}; kwargs...) = (r.code = INVALID; return r)

end # module
