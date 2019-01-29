const INTERNED_STRINGS_POOL = [WeakKeyDict{String, Nothing}()]

@inline function intern!(wkd::WeakKeyDict{K}, key)::K where {K}
    index = Base.ht_keyindex2!(wkd.ht, key)
    if index > 0
        @inbounds found_key = wkd.ht.keys[index]
        return (found_key.value)::K
    else
        kk::K = convert(K, key)
        finalizer(wkd.finalizer, kk)
        @inbounds Base._setindex!(wkd.ht, nothing, WeakRef(kk), -index)
        return kk
    end
end
@inline intern(::Type{S}, x::Tuple{Ptr{UInt8}, Int}) where {S <: AbstractString} = intern!(INTERNED_STRINGS_POOL[Threads.threadid()], x)
@inline intern(::Type{Tuple{Ptr{UInt8}, Int}}, x::Tuple{Ptr{UInt8}, Int}) = x
@inline intern(::Type{WeakRefString{UInt8}}, x::Tuple{Ptr{UInt8}, Int}) = WeakRefString(x)

# taken from Base.hash for String
function Base.hash(x::Tuple{Ptr{UInt8},Int}, h::UInt)
    h += Base.memhash_seed
    ccall(Base.memhash, UInt, (Ptr{UInt8}, Csize_t, UInt32), x[1], x[2], h % UInt32) + h
end
# taken from Base.:(==) for String
Base.isequal(x::Tuple{Ptr{UInt8}, Int}, y::String) =
    x[2] == sizeof(y) && 0 == ccall(:memcmp, Int32, (Ptr{UInt8}, Ptr{UInt8}, UInt), x[1], y, x[2])
Base.convert(::Type{String}, x::Tuple{Ptr{UInt8}, Int}) = unsafe_string(x[1], x[2])

const BUF = IOBuffer()
getptr(io::IO, pos, ptroff) = pointer(BUF.data, 1)
getptr(io::IOBuffer, pos, ptroff) = pointer(io.data, pos+1) + ptroff
incr(io::IO, b) = Base.write(BUF, b)
incr(io::IOBuffer, b) = 1

@inline parse!(d::Delimited{ignorerepeated, newline}, io::IO, r::Result{T}; kwargs...) where {ignorerepeated, newline, T <: Union{Tuple{Ptr{UInt8}, Int}, AbstractString}} =
    parse!(d.next, io, r, d.delims, ignorerepeated, newline; kwargs...)
@inline parse!(q::Quoted, io::IO, r::Result{T}, delims=nothing, ignorerepeated=false, newline=false; kwargs...) where {T <: Union{Tuple{Ptr{UInt8}, Int}, AbstractString}} =
    parse!(q.next, io, r, delims, ignorerepeated, newline, q.openquotechar, q.closequotechar, q.escapechar, q.ignore_quoted_whitespace; kwargs...)
@inline parse!(s::Strip, io::IO, r::Result{T}, delims=nothing, ignorerepeated=false, newline=false, openquotechar=nothing, closequotechar=nothing, escapechar=nothing, ignore_quoted_whitespace=false; kwargs...) where {T <: Union{Tuple{Ptr{UInt8}, Int}, AbstractString}} =
    parse!(s.next, io, r, delims, ignorerepeated, newline, openquotechar, closequotechar, escapechar, ignore_quoted_whitespace; kwargs...)
@inline parse!(s::Sentinel, io::IO, r::Result{T}, delims=nothing, ignorerepeated=false, newline=false, openquotechar=nothing, closequotechar=nothing, escapechar=nothing, ignore_quoted_whitespace=false; kwargs...) where {T <: Union{Tuple{Ptr{UInt8}, Int}, AbstractString}} =
    parse!(s.next, io, r, delims, ignorerepeated, newline, openquotechar, closequotechar, escapechar, ignore_quoted_whitespace, s.sentinels; kwargs...)
@inline parse!(::typeof(defaultparser), io::IO, r::Result{T}, delims=nothing, ignorerepeated=false, newline=false, openquotechar=nothing, closequotechar=nothing, escapechar=nothing, ignore_quoted_whitespace=false, node=nothing; kwargs...) where {T <: Union{Tuple{Ptr{UInt8}, Int}, AbstractString}} =
    defaultparser(io, r, delims, ignorerepeated, newline, openquotechar, closequotechar, escapechar, ignore_quoted_whitespace, node; kwargs...)

@inline function defaultparser(io::IO, r::Result{T},
    delims=nothing, ignorerepeated=false, newline=false, openquotechar=nothing, closequotechar=nothing,
    escapechar=nothing, ignore_quoted_whitespace=false, node=nothing;
    kwargs...) where {T <: Union{Tuple{Ptr{UInt8}, Int}, AbstractString}}
    # @debug "xparse Sentinel, String: quotechar='$quotechar', delims='$delims'"
    pos = position(io)
    setfield!(r, 3, Int64(pos))
    BUF.ptr = 1
    ptroff = 0
    len = 0
    b = eof(io) ? 0x00 : peekbyte(io)
    code = SUCCESS
    quoted = hasescapechars = false
    if b === openquotechar
        readbyte(io)
        ptroff += 1
        quoted = true
        code |= QUOTED
    elseif ignore_quoted_whitespace && (b === UInt8(' ') || b === UInt8('\t'))
        pos2 = position(io)
        off = 2
        while true
            readbyte(io)
            b = eof(io) ? 0x00 : peekbyte(io)
            if b === openquotechar
                readbyte(io)
                ptroff += off
                quoted = true
                code |= QUOTED
                break
            elseif b !== UInt8(' ') && b !== UInt8('\t')
                fastseek!(io, pos2)
                break
            end
            off += 1
        end
    end
    if quoted
        len, b, code, hasescapechars = handlequoted!(io, len, closequotechar, escapechar, code)
        if ignore_quoted_whitespace
            b = eof(io) ? 0x00 : peekbyte(io)
            while b === UInt8(' ') || b === UInt8('\t')
                readbyte(io)
                b = eof(io) ? 0x00 : peekbyte(io)
            end
        end
        if delims !== nothing
            if !eof(io)
                if ignorerepeated
                    matched = false
                    while match!(delims, io, r, false)
                        matched = true
                    end
                    if !matched && (newline && checknewline(io, r))
                        matched = true
                    end
                    if !matched
                        b = readbyte(io)
                        while !eof(io)
                            matched = false
                            while match!(delims, io, r, false)
                                matched = true
                            end
                            if !matched && (newline && checknewline(io, r))
                                matched = true
                            end
                            matched && break
                            b = readbyte(io)
                        end
                        code |= INVALID_DELIMITER
                    end
                else
                    if !(match!(delims, io, r, false) || (newline && checknewline(io, r)))
                        b = readbyte(io)
                        while !eof(io)
                            (match!(delims, io, r, false) || (newline && checknewline(io, r))) && break
                            b = readbyte(io)
                        end
                        code |= INVALID_DELIMITER
                    end
                end
            end
        end
    elseif delims !== nothing
        # read until we find a delimiter
        if ignorerepeated
            while !eof(io)
                matched = false
                while match!(delims, io, r, false)
                    matched = true
                end
                if !matched && (newline && checknewline(io, r))
                    matched = true
                end
                matched && break
                b = readbyte(io)
                len += incr(io, b)
            end
        else
            while !eof(io)
                (match!(delims, io, r, false) || (newline && checknewline(io, r))) && break
                b = readbyte(io)
                len += incr(io, b)
            end
        end
    else
        # just read until eof
        while !eof(io)
            b = readbyte(io)
            len += incr(io, b) 
        end
    end
    # @debug "node=$node"
    eof(io) && (code |= EOF)
    ptr = getptr(io, pos, ptroff)
    if match!(node, ptr, len)
        code |= SENTINEL
        setfield!(r, 1, missing)
    else
        code |= OK
        if hasescapechars
            setfield!(r, 1, unescape(T, intern(T, (ptr, len)), escapechar, closequotechar))
        else
            setfield!(r, 1, intern(T, (ptr, len)))
        end
    end
    r.code |= code
    return r
end

# unescaping not supported for Tuple{Ptr{UInt8}, Int}!!!
unescape(T, x::Tuple{Ptr{UInt8}, Int}, escapechar, closequotechar) = x

function unescape(T, s::AbstractString, escapechar, closequotechar)
    if length(BUF.data) < sizeof(s)
        resize!(BUF.data, sizeof(s))
    end
    len = 0
    str = codeunits(s)
    same = closequotechar === escapechar
    i = 1
    @inbounds while i <= length(str)
        b = str[i]
        if b !== escapechar
            len += 1
            BUF.data[len] = b
        elseif same
            len += 1
            BUF.data[len] = b
            i += 1
        end
        i += 1
    end
    return intern(T, (pointer(BUF.data), len))
end

function handlequoted!(io, len, closequotechar, escapechar, code)
    b = 0x00
    hasescapechars = false
    if eof(io)
        code |= INVALID_QUOTED_FIELD
    else
        same = closequotechar === escapechar
        while true
            b = peekbyte(io)
            if same && b === escapechar
                readbyte(io)
                if eof(io)
                    break
                elseif peekbyte(io) !== closequotechar
                    break
                end
                # otherwise, next byte is escaped, so read it
                hasescapechars = true
                len += incr(io, b)
                b = peekbyte(io)
            elseif b === escapechar
                readbyte(io)
                if eof(io)
                    code |= INVALID_QUOTED_FIELD
                    break
                end
                # regular escaped byte
                hasescapechars = true
                len += incr(io, b)
                b = peekbyte(io)
            elseif b === closequotechar
                readbyte(io)
                break
            end
            len += incr(io, b)
            readbyte(io)
            if eof(io)
                code |= INVALID_QUOTED_FIELD
                break
            end
        end
    end
    return len, b, code, hasescapechars
end
