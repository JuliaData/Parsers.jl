module Tries

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

struct Trie
    value::UInt8
    leaves::Vector{Trie}
end
Trie(b::UInt8) = Trie(b, Trie[])

function Trie(values::Vector{String})
    t = Trie(0x00)
    for value in values
        append!(t, Tuple(codeunits(value)))
    end
    return t
end

Base.isempty(t::Trie) = isempty(t.leaves)

function Base.append!(trie::Trie, bytes)
    b = first(bytes)
    rest = Base.tail(bytes)
    for t in trie.leaves
        if t.value === b
            return isempty(rest) ? nothing : append!(t, rest)
        end
    end
    t = Trie(b)
    push!(trie.leaves, t)
    return isempty(rest) ? nothing : append!(t, rest)
end

function Base.haskey(trie::Trie, io::IO)
    eof(io) && return false
    pos = position(io)
    b = peekbyte(io)
    for t in trie.leaves
        if t.value === b
            readbyte(io)
            return isempty(t.leaves) ? true : haskey(t, io)
        end
    end
    seek(io, pos)
    return false
end

end # module