__precompile__(true)
module Parsers

import InternedStrings, Dates

include("Tries.jl")
using .Tries

import Base.parse

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

fastseek!(io::IO, n::Integer) = seek(io, n)
function fastseek!(io::IOBuffer, n::Integer)
    io.ptr = n+1
    return
end

incr!(io::IOBuffer) = io.ptr += 1
incr!(io::IO) = readbyte(io)

getio(io::IO) = io

# Result type which includes a ReturnCode
@enum ReturnCode OK EOF OVERFLOW INVALID INVALID_QUOTED_FIELD

mutable struct Result{T}
    result::Union{T, Missing}
    code::ReturnCode
    b::UInt8
end

Result(x::T) where {T} = Result{T}(x, OK, 0x00)
Result(::Type{T}, r::ReturnCode, b::UInt8=0x00) where {T} = Result{T}(missing, r, b)
Result(r::Result{T}, c::ReturnCode=r.code, b::UInt8=r.b) where {T} = Result{T}(r.result, c, b)
Result(r::Result{T}, x::T, c::ReturnCode) where {T} = Result{T}(x, c, r.b)
Result(r::Result{T}, x::S, c::ReturnCode) where {T, S} = Result{S}(x, c, r.b)
Result(r::Result{T}, ::Type{S}) where {T, S} = Result{S}(missing, r.code, r.b)

struct Error <: Exception
    result::Result
end
#TODO: showerror for ParserError

# empty function for dispatching to default type parsers
function defaultparser end
# fallthrough for custom parser functions: user-provided function should be of the form: f(io::IO, ::Type{T}; kwargs...)::Result{T}
xparse(f::Base.Callable, io::IO, ::Type{T}; kwargs...) where {T} = f(io, T; kwargs...)
xparse(io::IO, ::Type{T}; kwargs...) where {T} = xparse(defaultparser, io, T; kwargs...)

# For parsing delimited fields
# document that eof is always a valid delim
struct Delimited{I}
    next::I
    delims::Tries.Trie
end
Delimited(next, delims::Union{Char, String}...=',') = Delimited(next, Tries.Trie(String[string(d) for d in delims]))
getio(d::Delimited) = getio(d.next)
Base.eof(io::Delimited) = eof(getio(io))

xparse(d::Delimited{I}, ::Type{T}; kwargs...) where {I, T} = xparse(defaultparser, d, T; kwargs...)

function xparse(f::Base.Callable, d::Delimited{I}, ::Type{T}) where {I, T}
    # @debug "xparse Delimited - $T"
    result = xparse(f, d.next, T)
    # @debug "Delimited - $T: result.code=$(result.code), result.result=$(result.result)"
    io = getio(d)
    eof(io) && return result
    ref = Ref{UInt8}()
    if Tries.match(d.delims, io; ref=ref)
        result.b = ref[]
        return result
    end
    # didn't find delimiter, result is invalid, consume until delimiter or eof
    # @debug "didn't find delimiters at expected location; result is invalid, parsing until delimiter is found"
    b = 0x00
    while true
        b = readbyte(io)
        (eof(io) || Tries.match(d.delims, io)) && break
    end
    result.code = INVALID
    result.b = b
    return result
end

# For parsing quoted field
struct Quoted{I}
    next::I
    quotechar::UInt8
    escapechar::UInt8
end
Quoted(next, q::Union{Char, UInt8}='"', e::Union{Char, UInt8}='\\') = Quoted(next, UInt8(q), UInt8(e))
getio(q::Quoted) = getio(q.next)
Base.eof(io::Quoted) = eof(getio(io))

xparse(q::Quoted{I}, ::Type{T}; kwargs...) where {I, T} = xparse(defaultparser, q, T; kwargs...)

function xparse(f::Base.Callable, q::Quoted{I}, ::Type{T};
    delims::Union{Nothing, Tries.Trie}=nothing,
    kwargs...) where {I, T}
    # @debug "xparse Quoted - $T"
    io = getio(q)
    if !eof(io) && peekbyte(io) === q.quotechar
        readbyte(io)
        quoted = true
        result = xparse(f, q.next, T; quotechar=q.quotechar, escapechar=q.escapechar, kwargs...)
    else
        result = xparse(f, q.next, T; kwargs...)
        quoted = false
    end
    # @debug "Quoted - $T: result.code=$(result.code), result.result=$(result.result)"
    if quoted
        if eof(io)
            result.code = INVALID_QUOTED_FIELD
            return result
        end
        b = peekbyte(io)
        if b !== q.quotechar
            # @debug "invalid quoted field"
            # result is invalid, parsing should have consumed until quotechar
            same = q.quotechar === q.escapechar
            c = b
            while true
                if same && b === q.escapechar
                    readbyte(io)
                    if (eof(io) || peekbyte(io) !== q.quotechar) 
                        result.code = INVALID
                        result.b = c
                        return result
                    end
                elseif b === q.escapechar
                    readbyte(io)
                    if eof(io)
                        result.code = INVALID_QUOTED_FIELD
                        result.b = b
                        return result
                    end
                elseif b === q.quotechar
                    readbyte(io)
                    result.code = INVALID
                    result.b = c
                    return result
                end
                c = readbyte(io)
                eof(io) && break
                b = peekbyte(io)
            end
            result.code = INVALID_QUOTED_FIELD
            result.b = c
            return result
        else
            readbyte(io)
        end
    end
    return result
end

# strip whitespace
struct Strip{I}
    next::I
    wh1::UInt8
    wh2::UInt8
end
Strip(io::I, wh1=' ', wh2='\t') where {I} = Strip{I}(io, wh1 % UInt8, wh2 % UInt8)
getio(s::Strip) = getio(s.next)
Base.eof(io::Strip) = eof(getio(io))

xparse(s::Strip, ::Type{T}; kwargs...) where {T} = xparse(defaultparser, s, T; kwargs...)

@inline function wh!(io, wh1, wh2)
    if !eof(io)
        b = peekbyte(io)
        while b == wh1 || b == wh2
            readbyte(io)
            eof(io) && break
            b = peekbyte(io)
        end
    end
end

function xparse(f::Base.Callable, s::Strip, ::Type{T};
    quotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=quotechar,
    delims::Union{Nothing, Tries.Trie}=nothing,
    kwargs...) where {T}
    # @debug "xparse Strip - $T"
    io = getio(s)
    wh!(io, s.wh1, s.wh2)
    result = xparse(f, s.next, T; kwargs...)
    # @debug "Strip - $T: result.code=$(result.code), result.result=$(result.result), result.b=$(result.b)"
    wh!(io, s.wh1, s.wh2)
    return result
end
# don't strip whitespace for Strings
xparse(f::Base.Callable, s::Strip, ::Type{String}; kwargs...) = xparse(f, s.next, String; kwargs...)

# For parsing sentinel values
struct Sentinel{I}
    next::I
    sentinels::Tries.Trie
end
Sentinel(next, sentinels::Union{String, Vector{String}}) = Sentinel(next, Tries.Trie(sentinels))
getio(s::Sentinel) = getio(s.next)
Base.eof(io::Sentinel) = eof(getio(io))

xparse(s::Sentinel{I}, ::Type{T}; kwargs...) where {I, T} = xparse(defaultparser, s, T; kwargs...)

function xparse(f::Base.Callable, s::Sentinel{I}, ::Type{T})::Result{T} where {I, T}
    # @debug "xparse Sentinel - $T"
    io = getio(s)
    pos = position(io)
    result = xparse(f, s.next, T)
    # @debug "Sentinel - $T: result.code=$(result.code), result.result=$(result.result)"
    c = result.code
    if c !== OK
        if isempty(s.sentinels) && position(io) == pos
            result.code = OK
            return result
        else
            fastseek!(io, pos)
            ref = Ref{UInt8}()
            if Tries.match(s.sentinels, io; ref=ref)
                result.code = OK
                result.b = ref[]
                return result
            end
        end
    end
    return result
end

# Core integer parsing function
function xparse(::typeof(defaultparser), io::IO, ::Type{T};
    quotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=quotechar,
    delims::Union{Nothing, Tries.Trie}=nothing,
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
const TRUE = Tries.Trie(["true"])
const FALSE = Tries.Trie(["false"])

function xparse(::typeof(defaultparser), io::IO, ::Type{Bool}; trues::Tries.Trie=TRUE, falses::Tries.Trie=FALSE, kwargs...)::Result{Bool}
    ref = Ref{UInt8}(0x00)
    Tries.match(trues, io; ref=ref) && return Result(true, OK, ref[])
    Tries.match(falses, io; ref=ref) && return Result(false, OK, ref[])
    return Result(Bool, INVALID, ref[])
end

# Dates.TimeType parsing
function xparse(::typeof(defaultparser), io::IO, ::Type{T};
            dateformat::Dates.DateFormat=Dates.default_format(T),
            kwargs...)::Result{T} where {T <: Dates.TimeType}
    res = xparse(io, String; kwargs...)
    if res.code === OK && !isempty(res.result)
        dt = tryparse(T, res.result, dateformat)
        return dt === nothing ? Result(T, INVALID, res.b) : Result(T(res.result, dateformat), OK, 0x00)
    else
        return Result(T, INVALID, res.b)
    end
end

xparse(::typeof(defaultparser), io::IO, ::Type{Missing}; kwargs...) = Result(Missing, INVALID, 0x00)
xparse(::typeof(defaultparser), io::IO, ::Type{Union{}}; kwargs...) = Result(Missing, INVALID, 0x00)

end # module

#TODO
 #open/close quotechar
 #Trie tests
 #showerror for ParserError
 #high-level functions: parse, tryparse
 #whole row parsing functionality
 #go thru csv issues
 #JSON2 can use?
 #performance benchmarks
 #docs