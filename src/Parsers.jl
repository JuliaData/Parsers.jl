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

@inline function readbyte(from::IOBuffer)
    @inbounds byte = from.data[from.ptr]
    from.ptr = from.ptr + 1
    return byte
end

@inline function peekbyte(from::IOBuffer)
    @inbounds byte = from.data[from.ptr]
    return byte
end

incr!(io::IOBuffer) = io.ptr += 1
incr!(io::IO) = readbyte(io)

iswh(b) = b == UInt8('\t') || b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\r')
@inline function wh!(io, b=peekbyte(io))
    while iswh(b)
        readbyte(io)
        b = peekbyte(io)
    end
    return
end

getio(io::IO) = io

# Result type which includes a ReturnCode
@enum ReturnCode OK EOF OVERFLOW INVALID INVALID_QUOTED_FIELD

struct Result{T}
    result::Union{T, Nothing}
    code::ReturnCode
    b::Union{UInt8, Nothing}
end

Result(x::T) where {T} = Result{T}(x, OK, nothing)
Result(::Type{T}, r::ReturnCode, b::Union{UInt8, Nothing}=nothing) where {T} = Result{T}(nothing, r, b)
Result(r::Result{T}, c::ReturnCode=r.code, b::Union{UInt8, Nothing}=r.b) where {T} = Result{T}(r.result, c, b)
Result(r::Result{T}, x::T, c::ReturnCode) where {T} = Result{T}(x, c, r.b)
Result(r::Result{T}, x::S, c::ReturnCode) where {T, S} = Result{S}(x, c, r.b)
Result(r::Result{Union{T, Missing}}, x::S, c::ReturnCode) where {T, S} = Result{Union{S, Missing}}(x, c, r.b)
Result(r::Result{T}, ::Type{S}) where {T, S} = Result{S}(nothing, r.code, r.b)
Result(r::Result{Union{T, Missing}}, ::Type{S}) where {T, S} = Result{Union{S, Missing}}(nothing, r.code, r.b)

struct ParserError <: Exception
    result::Result
end
#TODO: showerror for ParserError

# empty function for dispatching to default type parsers
function defaultparser end
# fallthrough for custom parser functions: user-provided function should be of the form: f(io::IO, ::Type{T}; kwargs...)::Result{T}
xparse(f::Base.Callable, io::IO, ::Type{T}; kwargs...) where {T} = f(io, T; kwargs...)

# For parsing delimited fields
# document that eof is always a valid delim
struct Delimited{I}
    next::I
    delims::Vector{UInt8}
end
Delimited(next, delims::Union{Char, UInt8}...=',') = Delimited(next, UInt8[d % UInt8 for d in delims])
getio(d::Delimited) = getio(d.next)

xparse(d::Delimited{I}, ::Type{T}; kwargs...) where {I, T} = xparse(defaultparser, d, T; kwargs...)

function xparse(f::Base.Callable, d::Delimited{I}, ::Type{T}; kwargs...) where {I, T}
    result = xparse(f, d.next, T; delims=d.delims, kwargs...)
    io = getio(d)
    eof(io) && return result
    b = peekbyte(io)
    for delim in d.delims
        if b === delim
            # found delimiter
            readbyte(io)
            return result
        end
    end
    # didn't find delimiter, result is invalid, consume until delimiter or eof
    c = b
    while true
        c = readbyte(io)
        eof(io) && @goto done
        b = peekbyte(io)
        for delim in d.delims
            if b === delim
                readbyte(io)
                @goto done
            end
        end
    end
@label done
    return Result(result, INVALID, c)
end

# For parsing quoted field
struct Quoted{I}
    next::I
    quotechar::UInt8
    escapechar::UInt8
end
Quoted(next, q::Union{Char, UInt8}='"', e::Union{Char, UInt8}='\\') = Quoted(next, UInt8(q), UInt8(e))

getio(q::Quoted) = getio(q.next)

xparse(q::Quoted{I}, ::Type{T}; kwargs...) where {I, T} = xparse(defaultparser, q, T; kwargs...)

function xparse(f::Base.Callable, q::Quoted{I}, ::Type{T}; kwargs...) where {I, T}
    io = getio(q)
    b = peekbyte(io)
    quoted = false
    if b === q.quotechar
        readbyte(io)
        quoted = true
        result = xparse(f, q.next, T; quotechar=q.quotechar, escapechar=q.escapechar, kwargs...)
    else
        result = xparse(f, q.next, T; kwargs...)
    end
    if quoted
        eof(io) && return Result(result, INVALID_QUOTED_FIELD, result.b)
        b = peekbyte(io)
        if b !== q.quotechar
            # result is invalid, parsing should have consumed until quotechar
            same = q.quotechar === q.escapechar
            c = b
            while true
                if same && b === q.escapechar
                    readbyte(io)
                    (eof(io) || peekbyte(io) !== q.quotechar) && return Result(result, INVALID, c)
                elseif b === q.escapechar
                    readbyte(io)
                    eof(io) && return Result(result, INVALID_QUOTED_FIELD, b)
                elseif b === q.quotechar
                    readbyte(io)
                    return Result(result, INVALID, c)
                end
                c = readbyte(io)
                eof(io) && break
                b = peekbyte(io)
            end
            return Result(result, INVALID_QUOTED_FIELD, c)
        else
            readbyte(io)
        end
    end
    return result
end

# For parsing sentinel values
struct Sentinel{I}
    next::I
    sentinels::Tries.Trie
end
Sentinel(next, sentinels::Union{String, Vector{String}}) = Sentinel(next, Tries.Trie(sentinels))
getio(s::Sentinel) = getio(s.next)

xparse(s::Sentinel{I}, ::Type{T}; kwargs...)::Result{Union{T, Missing}} where {I, T} = xparse(defaultparser, s, T; kwargs...)

function xparse(f::Base.Callable, s::Sentinel{I}, ::Type{T}; kwargs...)::Result{Union{T, Missing}} where {I, T}
    io = getio(s)
    pos = position(io)
    result = xparse(f, s.next, T; kwargs...)
    if result.code !== OK
        if isempty(s.sentinels) && position(io) == pos
            return Result{Union{T, Missing}}(missing, OK, nothing)
        else
            seek(io, pos)
            if Tries.match(s.sentinels, io)
                return Result{Union{T, Missing}}(missing, OK, nothing)
            end
        end
    end
    return Result{Union{T, Missing}}(result.result, result.code, result.b)
end

# Core integer parsing function
function xparse(::typeof(defaultparser), io::IO, ::Type{T}; kwargs...)::Result{T} where {T <: Integer}
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
        return Result(ifelse(negative, -v, v))
    end
end

include("strings.jl")
include("floats.jl")

# Bool parsing
const TRUE = Tries.Trie(["true"], true)
const FALSE = Tries.Trie(["false"], false)

function xparse(::typeof(defaultparser), io::IO, ::Type{Bool}; kwargs...)::Result{Bool}
    Tries.match(TRUE, io) && return Result(true, OK, nothing)
    Tries.match(FALSE, io) && return Result(false, OK, nothing)
    return Result(Bool, INVALID, nothing)
end

# Dates.TimeType parsing
function xparse(::typeof(defaultparser), io::IO, ::Type{T};
            dateformat::Dates.DateFormat=Dates.default_format(T),
            kwargs...)::Result{T} where {T <: Dates.TimeType}
    res = xparse(io, String; kwargs...)
    if res.code === OK && !isempty(res.result)
        dt = tryparse(T, res.result, dateformat)
        return dt === nothing ? Result(T, INVALID, res.b) : Result(T(res.result, dateformat), OK, nothing)
    else
        return Result(T, INVALID, res.b)
    end
end


end # module

#TODO
 #custom parsing function
 #Trie tests
 #showerror for ParserError
 #high-level functions
 #whole row parsing functionality
 #go thru csv issues
 #JSON2 can use?
 #performance benchmarks
 #docs