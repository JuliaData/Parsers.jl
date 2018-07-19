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
    quotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=quotechar,
    delims::Union{Nothing, Tries.Trie}=nothing,
    kwargs...)
    ptr = getptr(io)
    len = 0
    b = 0x00
    if quotechar !== nothing
        same = quotechar === escapechar
        eof(io) && return Result(EMPTY_STRING, INVALID_QUOTED_FIELD, 0x00)
        b = peekbyte(io)
        while true
            if same && b == escapechar
                pos = position(io)
                readbyte(io)
                if eof(io)
                    fastseek!(io, pos)
                    @goto done
                elseif peekbyte(io) !== quotechar
                    fastseek!(io, pos)
                    @goto done
                end
                # otherwise, next byte is escaped, so read it
                len += incr(io, b)
            elseif b == escapechar
                b = readbyte(io)
                eof(io) && return Result((ptr, len), INVALID_QUOTED_FIELD, b)
                # regular escaped byte
                len += incr(io, b)
            elseif b == quotechar
                @goto done
            end
            len += incr(io, b)
            b = readbyte(io)
            eof(io) && return Result((ptr, len), INVALID_QUOTED_FIELD, b)
            b = peekbyte(io)
        end
    elseif delims !== nothing
        eof(io) && @goto done
        # read until we find a delimiter
        b = peekbyte(io)
        ref = Ref{UInt8}() # so we can track which delimiter was found
        while true
            pos = position(io)
            if Tries.match(delims, io; ref=ref)
                fastseek!(io, pos)
                b = ref[]
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
    return Result((ptr, len), OK, b)
end

function xparse(::typeof(defaultparser), s::Sentinel, ::Type{Tuple{Ptr{UInt8}, Int}};
    quotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=quotechar,
    delims::Union{Nothing, Tries.Trie}=nothing,
    kwargs...)
    # @debug "xparse Sentinel, String: quotechar='$quotechar', delims='$delims'"
    io = getio(s)
    ptr = getptr(io)
    len = 0
    trie = s.sentinels
    node = nothing
    b = 0x00
    if quotechar !== nothing
        same = quotechar === escapechar
        eof(io) && return Result(EMPTY_STRING, INVALID_QUOTED_FIELD, 0x00)
        b = peekbyte(io)
        prevnode = node = Tries.matchleaf(trie, io, b)
        # @debug "b=$(Char(b)), node=$node"
        while true
            if same && b == escapechar
                pos = position(io)
                readbyte(io)
                if eof(io)
                    fastseek!(io, pos)
                    node = prevnode
                    @goto done
                elseif peekbyte(io) !== quotechar
                    fastseek!(io, pos)
                    node = prevnode
                    @goto done
                end
                # otherwise, next byte is escaped, so read it
                len += incr(io, b)
            elseif b == escapechar
                b = readbyte(io)
                eof(io) && return Result((ptr, len), INVALID_QUOTED_FIELD, b)
                len += incr(io, b)
            elseif b == quotechar
                node = prevnode
                @goto done
            end
            prevnode = node
            len += incr(io, b)
            readbyte(io)
            eof(io) && return Result((ptr, len), INVALID_QUOTED_FIELD, b)
            b = peekbyte(io)
            node = Tries.matchleaf(node, io, b)
            # @debug "b=$(Char(b)), node=$node"
        end
    elseif delims !== nothing
        eof(io) && @goto done
        # read until we find a delimiter
        b = peekbyte(io)
        ref = Ref{UInt8}() # so we can track which delimiter was found
        prevnode = node = Tries.matchleaf(trie, io, b)
        # @debug "b=$(Char(b)), node=$node"
        while true
            pos = position(io)
            if Tries.match(delims, io; ref=ref)
                fastseek!(io, pos)
                node = prevnode
                b = ref[]
                @goto done
            end
            prevnode = node
            len += incr(io, b)
            readbyte(io)
            eof(io) && @goto done
            b = peekbyte(io)
            node = Tries.matchleaf(node, io, b)
            @debug "b=$(Char(b)), node=$node"
        end
    else
        # just read until eof
        eof(io) && @goto done
        b = peekbyte(io)
        node = Tries.matchleaf(trie, io, b)
        while true
            len += incr(io, b)
            readbyte(io)
            eof(io) && @goto done
            b = peekbyte(io)
            node = Tries.matchleaf(node, io, b)
        end
    end
@label done
    # @debug "node=$node"
    if node !== nothing && node.leaf
        return Result{Tuple{Ptr{UInt8}, Int}}(missing, OK, b)
    elseif isempty(trie) && len == 0
        return Result{Tuple{Ptr{UInt8}, Int}}(missing, OK, b)
    else
        return Result{Tuple{Ptr{UInt8}, Int}}((ptr, len), OK, b)
    end
end

function xparse(::typeof(defaultparser), io::IO, ::Type{String}; kwargs...)
    res = xparse(io, Tuple{Ptr{UInt8}, Int}; kwargs...)
    return Result(res, make(String, res.result), res.code)
end
function xparse(::typeof(defaultparser), s::Sentinel, ::Type{String}; kwargs...)
    res = xparse(s, Tuple{Ptr{UInt8}, Int}; kwargs...)
    return Result(res, make(String, res.result), res.code)
end
