# taken from Base.hash for String
function Base.hash(x::Tuple{Ptr{UInt8},Int}, h::UInt)
    h += Base.memhash_seed
    ccall(Base.memhash, UInt, (Ptr{UInt8}, Csize_t, UInt32), x[1], x[2], h % UInt32) + h
end
Base.isequal(x::Tuple{Ptr{UInt8}, Int}, y::String) = hash(x) === hash(y)
Base.convert(::Type{String}, x::Tuple{Ptr{UInt8}, Int}) = unsafe_string(x[1], x[2])
const EMPTY_STRING = (Ptr{UInt8}(0), 0)

const BUF = IOBuffer()
getptr(io::IO) = pointer(BUF.data, BUF.ptr)
getptr(io::IOBuffer) = pointer(io.data, io.ptr)
incr(io::IO, b) = Base.write(BUF, b)
incr(io::IOBuffer, b) = 1

make(::Type{String}, x::Tuple{Ptr{UInt8}, Int}) = InternedStrings.intern(String, x)
make(::Type{String}, ::Missing) = missing

function xparse(::typeof(defaultparser), io::IO, ::Type{Tuple{Ptr{UInt8}, Int}};
    openquotechar::Union{UInt8, Nothing}=nothing,
    closequotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=openquotechar,
    delims::Union{Nothing, Trie}=nothing,
    kwargs...)
    ptr = getptr(io)
    len = 0
    b = 0x00
    code = OK
    r = Result((ptr, len), OK, b)
    if openquotechar !== nothing
        same = closequotechar === escapechar
        if eof(io)
            code = INVALID_QUOTED_FIELD
            @goto done
        end
        b = peekbyte(io)
        while true
            if same && b == escapechar
                pos = position(io)
                readbyte(io)
                if eof(io)
                    fastseek!(io, pos)
                    @goto done
                elseif peekbyte(io) !== closequotechar
                    fastseek!(io, pos)
                    @goto done
                end
                # otherwise, next byte is escaped, so read it
                len += incr(io, b)
            elseif b == escapechar
                b = readbyte(io)
                if eof(io)
                    code = INVALID_QUOTED_FIELD
                    @goto done
                end
                # regular escaped byte
                len += incr(io, b)
            elseif b == closequotechar
                @goto done
            end
            len += incr(io, b)
            b = readbyte(io)
            if eof(io)
                code = INVALID_QUOTED_FIELD
                @goto done
            end
            b = peekbyte(io)
        end
    elseif delims !== nothing
        eof(io) && @goto done
        # read until we find a delimiter
        b = peekbyte(io)
        while true
            pos = position(io)
            if match!(delims, io, r, false)
                fastseek!(io, pos)
                b = r.b
                @goto done
            end
            len += incr(io, b)
            readbyte(io)
            eof(io) && @goto done
            b = peekbyte(io)
        end
    else
        # just read until eof
        while !eof(io)
            b = readbyte(io)
            len += incr(io, b) 
        end
    end
@label done
    r.result = (ptr, len)
    r.code = code
    r.b = b
    return r
end

function xparse(::typeof(defaultparser), s::Sentinel, ::Type{Tuple{Ptr{UInt8}, Int}};
    openquotechar::Union{UInt8, Nothing}=nothing,
    closequotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=openquotechar,
    delims::Union{Nothing, Trie}=nothing,
    kwargs...)
    # @debug "xparse Sentinel, String: quotechar='$quotechar', delims='$delims'"
    io = getio(s)
    ptr = getptr(io)
    len = 0
    trie = s.sentinels
    node = nothing
    b = 0x00
    code = OK
    r = Result((ptr, len), OK, b)
    if openquotechar !== nothing
        same = closequotechar === escapechar
        if eof(io)
            code = INVALID_QUOTED_FIELD
            @goto done
        end
        b = peekbyte(io)
        prevnode = node = matchleaf(trie, io, b)
        # @debug "b=$(Char(b)), node=$node"
        while true
            if same && b == escapechar
                pos = position(io)
                readbyte(io)
                if eof(io)
                    fastseek!(io, pos)
                    node = prevnode
                    @goto done
                elseif peekbyte(io) !== closequotechar
                    fastseek!(io, pos)
                    node = prevnode
                    @goto done
                end
                # otherwise, next byte is escaped, so read it
                len += incr(io, b)
            elseif b == escapechar
                b = readbyte(io)
                if eof(io)
                    code = INVALID_QUOTED_FIELD
                    @goto done
                end
                len += incr(io, b)
            elseif b == closequotechar
                node = prevnode
                @goto done
            end
            prevnode = node
            len += incr(io, b)
            readbyte(io)
            if eof(io)
                code = INVALID_QUOTED_FIELD
                @goto done
            end
            b = peekbyte(io)
            node = matchleaf(node, io, b)
            # @debug "b=$(Char(b)), node=$node"
        end
    elseif delims !== nothing
        eof(io) && @goto done
        # read until we find a delimiter
        b = peekbyte(io)
        prevnode = node = matchleaf(trie, io, b)
        # @debug "b=$(Char(b)), node=$node"
        while true
            pos = position(io)
            if match!(delims, io, r, false)
                fastseek!(io, pos)
                node = prevnode
                b = r.b
                @goto done
            end
            prevnode = node
            len += incr(io, b)
            readbyte(io)
            eof(io) && @goto done
            b = peekbyte(io)
            node = matchleaf(node, io, b)
            # @debug "b=$(Char(b)), node=$node"
        end
    else
        # just read until eof
        eof(io) && @goto done
        b = peekbyte(io)
        node = matchleaf(trie, io, b)
        while true
            len += incr(io, b)
            readbyte(io)
            eof(io) && @goto done
            b = peekbyte(io)
            node = matchleaf(node, io, b)
        end
    end
@label done
    # @debug "node=$node"
    r.b = b
    if (node !== nothing && node.leaf) || (isempty(trie.leaves) && len == 0)
        r.result = missing
        return r
    else
        r.result = (ptr, len)
        r.code = code
        return r
    end
end

function xparse(::typeof(defaultparser), io::IO, ::Type{String};
    openquotechar::Union{UInt8, Nothing}=nothing,
    closequotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=openquotechar,
    delims::Union{Nothing, Trie}=nothing,
    kwargs...)
    res = xparse(io, Tuple{Ptr{UInt8}, Int}; openquotechar=openquotechar, closequotechar=closequotechar, escapechar=escapechar, delims=delims, kwargs...)
    return Result(res, make(String, res.result), res.code)
end
function xparse(::typeof(defaultparser), s::Sentinel, ::Type{String};
    openquotechar::Union{UInt8, Nothing}=nothing,
    closequotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=openquotechar,
    delims::Union{Nothing, Trie}=nothing,
    kwargs...)
    res = xparse(s, Tuple{Ptr{UInt8}, Int}; openquotechar=openquotechar, closequotechar=closequotechar, escapechar=escapechar, delims=delims, kwargs...)
    return Result(res, make(String, res.result), res.code)
end
