__precompile__(true)
module Parsers

import InternedStrings

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
Result(r::Result{T}, x::T, c::ReturnCode) where {T} = Result{T}(x, c, nothing)

struct ParserError <: Exception
    result::Result
end
#TODO: showerror for ParserError

# User-facing parse function
function parse(io::IO, ::Type{T}; kwargs...) where {T}
    result = xparse(io, T; kwargs...)
    return result.code === OK ? result.result : throw(ParserError(result))
end

function xparse(io::IO, ::Type{T};
                delim=',',
                quotechar='"',
                escapechar='\\',
                sentinel="",
                kwargs...) where {T}
    return xparse(Delimited(Quoted(Sentinel(io, sentinel), quotechar % UInt8, escapechar % UInt8), delim); kwargs...)
end

# For parsing delimited fields
# document that eof is always a valid delim
struct Delimited{I}
    next::I
    delims::Vector{UInt8}
end
Delimited(next, d::Union{Char, UInt8}=',') = Delimited(next, UInt8[d])
getio(d::Delimited) = getio(d.next)

function xparse(d::Delimited{I}, ::Type{T}; kwargs...) where {I, T}
    result = xparse(d.next, T; kwargs...)
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

function xparse(q::Quoted{I}, ::Type{T}; kwargs...) where {I, T}
    io = getio(q)
    b = peekbyte(io)
    quoted = false
    if b === q.quotechar
        readbyte(io)
        quoted = true
    end
    result = xparse(q.next, T; kwargs...)
    if quoted
        eof(io) && return Result(result, INVALID_QUOTED_FIELD, nothing)
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
Sentinel(next, sentinels::Vector{String}) = Sentinel(next, Tries.Trie(sentinels))
getio(s::Sentinel) = getio(s.next)

function xparse(s::Sentinel{I}, ::Type{T}; kwargs...)::Result{Union{T, Missing}} where {I, T}
    io = getio(s)
    pos = position(io)
    result = xparse(s.next, T; kwargs...)
    if result.code !== OK
        if isempty(s.sentinels) && position(io) == pos
            return Result{Union{T, Missing}}(missing, OK, nothing)
        else
            seek(io, pos)
            if haskey(s.sentinels, io)
                return Result{Union{T, Missing}}(missing, OK, nothing)
            end
        end
    end
    return Result{Union{T, Missing}}(result.result, result.code, result.b)
end

# Core integer parsing function
function xparse(io::IO, ::Type{T})::Result{T} where {T <: Integer}
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

end # module

#TODO
 #date/datetime parsing
 #custom parsing function
 #Trie tests
 #float parsing
 #showerror for ParserError
 #high-level functions
 #go thru csv issues
 #JSON2 can use?
 #performance benchmarks