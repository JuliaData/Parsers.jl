# taken from Base.hash for String
function Base.hash(x::Tuple{Ptr{UInt8},Int}, h::UInt)
    h += Base.memhash_seed
    ccall(Base.memhash, UInt, (Ptr{UInt8}, Csize_t, UInt32), x[1], x[2], h % UInt32) + h
end
Base.isequal(x::Tuple{Ptr{UInt8}, Int}, y::String) = hash(x) === hash(y)
Base.convert(::Type{String}, x::Tuple{Ptr{UInt8}, Int}) = unsafe_string(x[1], x[2])

const BUF = IOBuffer()
getptr(io::IO) = pointer(BUF.data, BUF.ptr)
getptr(io::IOBuffer) = pointer(io.data, io.ptr)
incr(io::IO, b) = Base.write(BUF, b)
incr(io::IOBuffer, b) = 1

function xparse(d::Delimited{I}, ::Type{String}; kwargs...) where {I <: Union{Sentinel, IO}}
    io = getio(d)
    pos = position(io)
    result = xparse(d.next, String; kwargs...)
    eof(io) && return result
    b = peekbyte(io)
    for delim in d.delims
        if b === delim
            # found delimiter
            readbyte(io)
            return result
        end
    end
    # didn't find delimiter, no valid sentinel found, consume until delimiter or eof
    seek(io, pos)
    ptr = getptr(io)
    len = 0
    while true
        len += incr(io, b)
        readbyte(io)
        eof(io) && @goto done
        b = peekbyte(io)
        for delim in d.delims
            if b === delim
                # found delimiter
                readbyte(io)
                return @goto done
            end
        end
    end
@label done
    return Result(result, InternedStrings.intern(String, (ptr, len)), OK)
end

function xparse(d::Delimited{Quoted{I}}, ::Type{String}; kwargs...) where {I}
    q = d.next
    io = getio(q)
    b = peekbyte(io)
    quoted = false
    if b === q.quotechar
        readbyte(io)
        quoted = true
    end
    pos = position(io)
    result = xparse(q.next, String; kwargs...)
    if quoted
        eof(io) && return Result(result, INVALID_QUOTED_FIELD, nothing)
        b = peekbyte(io)
        if b !== q.quotechar
            # didn't parse a valid sentinel, parse string until quotechar
            seek(io, pos)
            same = q.quotechar === q.escapechar
            ptr = getptr(io)
            len = 0
            while true
                if same && b == q.escapechar
                    b = readbyte(io)
                    (eof(io) || peekbyte(io) !== q.quotechar) && return Result(result, InternedStrings.intern(String, (ptr, len)), OK)
                    len += incr(io, b)
                elseif b == q.escapechar
                    b = readbyte(io)
                    eof(io) && return Result(result, INVALID_QUOTED_FIELD, b)
                    len += incr(io, b)
                elseif b == q.quotechar
                    readbyte(io)
                    break
                end
                len += incr(io, b)
                b = readbyte(io)
                eof(io) && return Result(result, INVALID_QUOTED_FIELD, b)
                b = peekbyte(io)
            end
            return Result(result, InternedStrings.intern(String, (ptr, len)), OK)
        else
            readbyte(io)
        end
        return result
    else
        eof(io) && return result
        b = peekbyte(io)
        for delim in d.delims
            if b === delim
                # found delimiter
                readbyte(io)
                return result
            end
        end
        # didn't find delimiter, no valid sentinel found, consume until delimiter or eof
        seek(io, pos)
        ptr = getptr(io)
        len = 0
        while true
            len += incr(io, b)
            readbyte(io)
            eof(io) && @goto done
            b = peekbyte(io)
            for delim in d.delims
                if b === delim
                    # found delimiter
                    readbyte(io)
                    return @goto done
                end
            end
        end
    @label done
        return Result(result, InternedStrings.intern(String, (ptr, len)), OK)
    end
end

function xparse(q::Quoted{I}, ::Type{String}; kwargs...) where {I}
    io = getio(q)
    b = peekbyte(io)
    quoted = false
    if b === q.quotechar
        readbyte(io)
        quoted = true
    end
    pos = position(io)
    result = xparse(q.next, String; kwargs...)
    if quoted
        eof(io) && return Result(result, INVALID_QUOTED_FIELD, nothing)
        b = peekbyte(io)
        if b !== q.quotechar
            # didn't parse a valid sentinel, parse string until quotechar
            seek(io, pos)
            same = q.quotechar === q.escapechar
            ptr = getptr(io)
            len = 0
            while true
                if same && b == q.escapechar
                    b = readbyte(io)
                    (eof(io) || peekbyte(io) !== q.quotechar) && return Result(result, InternedStrings.intern(String, (ptr, len)), OK)
                    len += incr(io, b)
                elseif b == q.escapechar
                    b = readbyte(io)
                    eof(io) && return Result(result, INVALID_QUOTED_FIELD, b)
                    len += incr(io, b)
                elseif b == q.quotechar
                    readbyte(io)
                    break
                end
                len += incr(io, b)
                b = readbyte(io)
                eof(io) && return Result(result, INVALID_QUOTED_FIELD, b)
                b = peekbyte(io)
            end
            return Result(result, InternedStrings.intern(String, (ptr, len)), OK)
        else
            readbyte(io)
        end
    end
    return result
end

function xparse(s::Sentinel{I}, ::Type{String}; kwargs...)::Result{Union{String, Missing}} where {I}
    io = getio(s)
    if isempty(s.sentinels)
        return Result{Union{String, Missing}}(missing, OK, nothing)
    else
        if haskey(s.sentinels, io)
            return Result{Union{String, Missing}}(missing, OK, nothing)
        end
    end
    return Result{Union{String, Missing}}("", OK, nothing)
end

xparse(io::IO, ::Type{T}; kwargs...) where {T} = Result{String}("", OK, nothing)