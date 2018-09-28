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
    Each `Parsers.Result` has a `r.code` field which has type `Parsers.ReturnCode` and is a set of bit flags for various parsing states.
    The top bit is used to indicate "SUCCESS" (0) and "INVALID" (1), so all failed parsing attempts will have a code < 0, while successful parsings will be > 0.
    Use `Parsers.ok(code)` to check if a `Parsers.Result` is successful or not.
    `Parsers.codes(code)` and `Parsers.text(code)` can also be used to get text representations of which bit flags are set in a return code.
    Various bit flags include:
      * `OK`: the innermost type parser succeeded in parsing a valid value for the type
      * `SENTINEL`: a sentinel value was matched; mutually exclusive with `OK` (sentinels are only checked for when the underlying type parser fails)
      * `QUOTED`: an opening quote character was detected while parsing (note this does not indicate a _correctly_ quoted value)
      * `DELIMITED`: a valid delimiter was found while parsing; note that EOF is always a valid delimiter
      * `NEWLINE`: a newline character was matched as a delimiter (useful for applications where newlines have special delimiting purposes)
      * `EOF`: parsing encountered the end-of-file while parsing
      * `INVALID_QUOTED_FIELD`: a corresponding closing quote character was not found for a `QUOTED` field
      * `INVALID_DELIMITER`: a delimiter was found, but not at the expected position while parsing
      * `OVERFLOW`: a numeric type overflowed while parsing its value
"""
const ReturnCode = Int16
ok(x::ReturnCode) = x > 0

const SUCCESS = 0b0000000000000000 % ReturnCode
const INVALID = 0b1000000000000000 % ReturnCode

# success flags
const OK                   = 0b0000000000000001 % ReturnCode
const SENTINEL             = 0b0000000000000010 % ReturnCode

# property flags
const QUOTED               = 0b0000000000000100 % ReturnCode
const DELIMITED            = 0b0000000000001000 % ReturnCode
const NEWLINE              = 0b0000000000010000 % ReturnCode
const EOF                  = 0b0000000000100000 % ReturnCode

# invalid flags
const INVALID_QUOTED_FIELD = 0b1000000001000000 % ReturnCode
const INVALID_DELIMITER    = 0b1000000010000000 % ReturnCode
const OVERFLOW             = 0b1000000100000000 % ReturnCode

function text(r::ReturnCode)
    str = ""
    if r & QUOTED > 0
        str = "encountered an opening quote character, initial value parsing "
    else
        str = "initial value parsing "
    end
    if r & OK > 0
        str *= "succeeded"
    else
        str *= "failed"
    end
    if r & (~INVALID & OVERFLOW) > 0
        str *= ", value overflowed"
    end
    if r & SENTINEL > 0
        str *= ", a sentinel value was parsed"
    end
    if r & (~INVALID & INVALID_QUOTED_FIELD) > 0
        str *= ", invalid quoted value"
    end
    if r & DELIMITED > 0
        str *= ", a valid delimiter was parsed"
    end
    if r & NEWLINE > 0
        str *= ", a newline was encountered"
    end
    if r & EOF > 0
        str *= ", reached EOF"
    end
    if r & (~INVALID & INVALID_DELIMITER) > 0
        str *= ", invalid delimiter"
    end
    return str
end

codes(r::ReturnCode) = chop(chop(string(
    ifelse(r > 0, "SUCCESS: ", "INVALID: "),
    ifelse(r & OK > 0, "OK, ", ""),
    ifelse(r & SENTINEL > 0, "SENTINEL, ", ""),
    ifelse(r & QUOTED > 0, "QUOTED, ", ""),
    ifelse(r & DELIMITED > 0, "DELIMITED, ", ""),
    ifelse(r & NEWLINE > 0, "NEWLINE, ", ""),
    ifelse(r & EOF > 0, "EOF, ", ""),
    ifelse(r & (~INVALID & INVALID_QUOTED_FIELD) > 0, "INVALID_QUOTED_FIELD, ", ""),
    ifelse(r & (~INVALID & INVALID_DELIMITER) > 0, "INVALID_DELIMITER, ", ""),
    ifelse(r & (~INVALID & OVERFLOW) > 0, "OVERFLOW, ", "")
)))

"""
    Parsers.Result{T}(x::Union{T, Missing}, ::Parsers.ReturnCode, b::UInt8)
    Parsers.Result(::Type{T}, code, byte)

    A result type used by `Parsers.parse!` to signal the result of trying to parse a certain type. Fields include:
        * `result::Union{T, Missing}`: holds the parsed result of type `T` or `missing` if unable to parse or a valid `Parsers.Sentinel` value was found
        * `code::Parsers.ReturnCode`: a value signaling whether parsing succeeded (`Parsers.OK`) or not (`Parsers.INVALID`); see `?Parsers.ReturnCode` for all possible codes
        * `pos::Int64`: the byte position when a parsing operation started
"""
mutable struct Result{T}
    result::Union{T, Missing}
    code::ReturnCode
    pos::Int64
end
parsetype(r::Result{T}) where {T} = T

# pre-allocated Results for default supported types
const DEFAULT_TYPES = (Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128,
    Float16, Float32, Float64,
    Tuple{Ptr{UInt8}, Int}, String,
    Date, DateTime, Time,
    Bool)

const RESULTS = Tuple([Result{T}(missing, OK, Int64(0))] for T in DEFAULT_TYPES)

for (i, T) in enumerate(DEFAULT_TYPES)
    @eval index(::Type{$T}) = $i
end
index(T) = length(RESULTS) + 1

@inline function Result(::Type{T}) where {T}
    if @generated
        i = index(T)
        if i > length(RESULTS)
            return :(Result{$T}(missing, SUCCESS, Int64(0)))
        else
            return :(r = $(RESULTS[i])[Threads.threadid()]; r.code = SUCCESS; return r)
        end
    else
        return Result{T}(missing, SUCCESS, Int64(0))
    end
end

include("tries.jl")

struct Error <: Exception
    io::IO
    result::Result
end

function Base.showerror(io::IO, e::Error)
    c = e.result.code
    println(io, "Parsers.Error ($(codes(c))):")
    println(io, text(c))
    if (c & OK > 0) | (c & SENTINEL > 0)
        pos = position(e.io)
        seek(e.io, e.result.pos)
        str = String(read(e.io, pos - e.result.pos))
        println(io, "attempted to parse $(parsetype(e.result)) from: \"$(escape_string(str))\"")
    else
        println(io, "failed to parse $(parsetype(e.result)), encountered: '$(escape_string(string(Char(peekbyte(e.io)))))'")
    end
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

function parse(str::AbstractString, ::Type{T}; kwargs...) where {T}
    io = IOBuffer(str)
    res = parse(defaultparser, io, T; kwargs...)
    return ok(res.code) ? res.result : throw(Error(io, res))
end
function parse(io::IO, ::Type{T}; kwargs...) where {T}
    res = parse(defaultparser, io, T; kwargs...)
    return ok(res.code) ? res.result : throw(Error(io, res))
end
function parse(f::Base.Callable, str::AbstractString, ::Type{T}; kwargs...) where {T}
    io = IOBuffer(str)
    res = parse!(f, io, Result(T); kwargs...)
    return ok(res.code) ? res.result : throw(Error(io, res))
end
function parse(f::Base.Callable, io::IO, ::Type{T}; kwargs...) where {T}
    res = parse!(f, io, Result(T); kwargs...)
    return ok(res.code) ? res.result : throw(Error(io, res))
end

function tryparse(str::AbstractString, ::Type{T}; kwargs...) where {T}
    res = parse(defaultparser, IOBuffer(str), T; kwargs...)
    return ok(res.code) ? res.result : nothing
end
function tryparse(io::IO, ::Type{T}; kwargs...) where {T}
    res = parse(defaultparser, io, T; kwargs...)
    return ok(res.code) ? res.result : nothing
end
function tryparse(f::Base.Callable, str::AbstractString, ::Type{T}; kwargs...) where {T}
    res = parse!(f, IOBuffer(str), Result(T); kwargs...)
    return ok(res.code) ? res.result : nothing
end
function tryparse(f::Base.Callable, io::IO, ::Type{T}; kwargs...) where {T}
    res = parse!(f, io, Result(T); kwargs...)
    return ok(res.code) ? res.result : nothing
end

"""
    Parsers.Delimited(next, delims::Union{Char, String}...=',')

    A custom `Parsers.Layer` used to support parsing delimited values in `IO` streams. `delims` can be any number of `Char` or `String` arguments that should collectively be used as "delimiters".

    Parsing on a `Parsers.Delimited` will first call `Parsers.parse!(d.next, io, result; kwargs...)`, then expect the next bytes to be one of the expected `delims` arguments.
    If one of `delims` is not found, the result is `Parsers.INVALID`, but parsing will continue until a valid `delims` is found. An `eof(io)` is _always_ considered a valid termination state in place of a delimiter.
"""
struct Delimited{IR, I, T <: Trie} <: Layer
    next::I
    delims::T
end
Delimited(ignore_repeated::Bool, next::I, delims::T) where {I, T <: Trie} = Delimited{ignore_repeated, I, T}(next, delims)
Delimited(next::Union{Layer, Base.Callable}=defaultparser, delims::Union{Char, String}...; ignore_repeated::Bool=false) = Delimited(ignore_repeated, next, Trie(String[string(d) for d in (isempty(delims) ? (",",) : delims)], DELIMITED))
Delimited(delims::Union{Char, String}...; ignore_repeated::Bool=false) = Delimited(ignore_repeated, defaultparser, Trie(String[string(d) for d in (isempty(delims) ? (",",) : delims)], DELIMITED))

@inline function parse!(d::Delimited{ignore_repeated}, io::IO, r::Result{T}; kwargs...) where {ignore_repeated, T}
    # @debug "xparse Delimited - $T"
    parse!(d.next, io, r; kwargs...)
    # @debug "Delimited - $T: r.code=$(r.code), r.result=$(r.result)"
    if eof(io)
        r.code |= EOF
        return r
    end
    if ignore_repeated
        matched = false
        while match!(d.delims, io, r, false)
            matched = true
        end
        matched && return r
    else
        match!(d.delims, io, r, false) && return r
    end
    # @debug "didn't find delimiters at expected location; result is invalid, parsing until delimiter is found"
    while true
        b = readbyte(io)
        if eof(io)
            r.code |= EOF
            break
        end
        if ignore_repeated
            matched = false
            while match!(d.delims, io, r, false)
                matched = true
            end
            matched && break
        else
            match!(d.delims, io, r, false) && break
        end
    end
    r.code |= INVALID_DELIMITER
    return r
end

"""
    Parsers.Quoted(next, quotechar='"', escapechar='\\', ignore_quoted_whitespace=false)
    Parsers.Quoted(next, openquote, closequote, escapechar, ignore_quoted_whitespace)

    A custom `Parsers.Layer` used to support parsing potentially "quoted" values. Parsing with a `Parsers.Quoted` does not _require_ the value to be quoted, but will always check for an initial quote and, if found, will then expect (and continue parsing until) a corresponding close quote is found.
    A single `quotechar` can be given, indicating the quoted field will start and end with the same character.
    Both `quotechar` and `escapechar` arguments are limited to ASCII characters.
"""
struct Quoted{I} <: Layer
    next::I
    openquotechar::UInt8
    closequotechar::UInt8
    escapechar::UInt8
    ignore_quoted_whitespace::Bool
end
Quoted(next, q::Union{Char, UInt8}='"', e::Union{Char, UInt8}='\\', i::Bool=false) = Quoted(next, UInt8(q), UInt8(q), UInt8(e), i)
Quoted(next, q1::Union{Char, UInt8}, q2::Union{Char, UInt8}, e::Union{Char, UInt8}, i::Bool) = Quoted(next, UInt8(q1), UInt8(q2), UInt8(e), i)
Quoted(q::Union{Char, UInt8}='"', e::Union{Char, UInt8}='\\', i::Bool=false) = Quoted(defaultparser, UInt8(q), UInt8(q), UInt8(e), i)
Quoted(q1::Union{Char, UInt8}, q2::Union{Char, UInt8}, e::Union{Char, UInt8}, i::Bool) = Quoted(defaultparser, UInt8(q1), UInt8(q2), UInt8(e), i)

function handlequoted!(q, io, r)
    if eof(io)
        r.code |= INVALID_QUOTED_FIELD
    else
        first = true
        same = q.closequotechar === q.escapechar
        while true
            b = peekbyte(io)
            if same && b === q.escapechar
                readbyte(io)
                if eof(io) || peekbyte(io) !== q.closequotechar
                    first || (r.code |= INVALID)
                    break
                end
                # otherwise, next byte is escaped, so read it
                b = peekbyte(io)
            elseif b === q.escapechar
                readbyte(io)
                if eof(io)
                    r.code |= INVALID_QUOTED_FIELD
                    break
                end
                # regular escaped byte
                b = peekbyte(io)
            elseif b === q.closequotechar
                readbyte(io)
                first || (r.code |= INVALID)
                break
            end
            readbyte(io)
            if eof(io)
                r.code |= INVALID_QUOTED_FIELD
                break
            end
            first = false
        end
    end
    eof(io) && (r.code |= EOF)
    return
end

@inline function parse!(q::Quoted, io::IO, r::Result{T}; kwargs...) where {T}
    # @debug "xparse Quoted - $T"
    quoted = false
    pos = 0
    b = eof(io) ? 0x00 : peekbyte(io)
    if b === q.openquotechar
        pos = position(io)
        readbyte(io)
        quoted = true
        r.code |= QUOTED
    elseif q.ignore_quoted_whitespace && (b === UInt8(' ') || b === UInt8('\t'))
        pos2 = position(io)
        while true
            readbyte(io)
            b = eof(io) ? 0x00 : peekbyte(io)
            if b === q.openquotechar
                pos = position(io)
                readbyte(io)
                quoted = true
                r.code |= QUOTED
                break
            elseif b !== UInt8(' ') && b !== UInt8('\t')
                fastseek!(io, pos2)
                break
            end
        end
    end
    parse!(q.next, io, r; kwargs...)
    quoted && (setfield!(r, 3, Int64(pos)); handlequoted!(q, io, r))
    # println("Quoted - $T: quoted=$quoted, result.code=$(codes(r.code)), result.result=$(r.result)")
    if q.ignore_quoted_whitespace
        b = eof(io) ? 0x00 : peekbyte(io)
        while b === UInt8(' ') || b === UInt8('\t')
            readbyte(io)
            b = eof(io) ? 0x00 : peekbyte(io)
        end
    end
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
    stripped = false
    if !eof(io)
        b = peekbyte(io)
        while (b == wh1) | (b == wh2)
            stripped = true
            readbyte(io)
            eof(io) && break
            b = peekbyte(io)
        end
    end
    return stripped
end

@inline function parse!(s::Strip, io::IO, r::Result{T}; kwargs...) where {T}
    # @debug "xparse Strip - $T"
    pos = Int64(position(io))
    stripped = wh!(io, s.wh1, s.wh2)
    parse!(s.next, io, r; kwargs...)
    # @debug "Strip - $T: result.code=$(result.code), result.result=$(result.result), result.b=$(result.b)"
    wh!(io, s.wh1, s.wh2)
    eof(io) && (r.code |= EOF)
    stripped && setfield!(r, 3, pos)
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
Sentinel(next, sentinels::Union{String, Vector{String}}) = Sentinel(next, Trie(sentinels, SENTINEL))
Sentinel(sentinels::Union{String, Vector{String}}) = Sentinel(defaultparser, Trie(sentinels, SENTINEL))

@inline function parse!(s::Sentinel, io::IO, r::Result{T}; kwargs...) where {T}
    # @debug "xparse Sentinel - $T"
    pos = position(io)
    if isempty(s.sentinels.leaves)
        parse!(s.next, io, r; kwargs...)
        if !ok(r.code)
            if position(io) == pos
                r.code &= ~INVALID
                r.code |= (SENTINEL | ifelse(eof(io), EOF, SUCCESS))
            end
        end
    else # non-empty sentinel value
        sent = match!(s.sentinels, io, r)
        sentpos = position(io)
        fastseek!(io, pos)
        parse!(s.next, io, r; kwargs...)
        if sent
            if !ok(r.code)
                r.code &= ~INVALID
                setfield!(r, 1, missing)
                fastseek!(io, sentpos)
            else
                # both sentinel value parsing matched & type parsing succeeded
                pos = position(io)
                if pos > sentpos
                    r.code &= ~SENTINEL
                else
                    r.code &= ~OK
                    setfield!(r, 1, missing)
                    fastseek!(io, sentpos)
                end
            end
        end
    end
    # @debug "Sentinel - $T: result.code=$(result.code), result.result=$(result.result)"
    return r
end

# Core integer parsing function
const MINUS   = UInt8('-')
const PLUS    = UInt8('+')
const NEG_ONE = UInt8('0')-UInt8(1)
const ZERO    = UInt8('0')
const TEN     = UInt8('9')+UInt8(1)

@inline function defaultparser(io::IO, r::Result{T}; kwargs...) where {T <: Integer}
    # @debug "xparse Int"
    setfield!(r, 1, missing)
    setfield!(r, 3, Int64(position(io)))
    # r.result = missing
    eof(io) && (r.code |= INVALID | EOF; return r)
    v = zero(T)
    b = peekbyte(io)
    negative = false
    if b === MINUS # check for leading '-' or '+'
        negative = true
        readbyte(io)
        eof(io) && (r.code |= INVALID | EOF; return r)
        b = peekbyte(io)
    elseif b === PLUS
        readbyte(io)
        eof(io) && (r.code |= INVALID | EOF; return r)
        b = peekbyte(io)
    end
    parseddigits = false
    while NEG_ONE < b < TEN
        parseddigits = true
        b = readbyte(io)
        v, ov_mul = Base.mul_with_overflow(v, T(10))
        v, ov_add = Base.add_with_overflow(v, T(b - ZERO))
        (ov_mul | ov_add) && (r.result = v; r.code |= OVERFLOW | ifelse(eof(io), EOF, SUCCESS); return r)
        eof(io) && break
        b = peekbyte(io)
    end
    if !parseddigits
        r.code |= INVALID
    else
        r.result = ifelse(negative, -v, v)
        r.code |= OK | ifelse(eof(io), EOF, SUCCESS)
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
    setfield!(r, 3, Int64(position(io)))
    if !match!(bools, io, r)
        r.code |= INVALID
    end
    return r
end

defaultparser(io::IO, r::Result{Missing}; kwargs...) = (setfield!(r, 3, Int64(position(io))); return r)
defaultparser(io::IO, r::Result{Union{}}; kwargs...) = (setfield!(r, 3, Int64(position(io))); return r)

end # module
