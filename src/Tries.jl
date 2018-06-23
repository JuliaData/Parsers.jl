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

mutable struct Node
    label::UInt8
    leaf::Bool
    leaves::Vector{Node}
end
Node(label::UInt8, leaf::Bool=false) = Node(label, leaf, Node[])

struct Trie{T}
    value::T
    leaves::Vector{Node}
end
Trie(value=missing) = Trie(value, Node[])

Trie(v::String, value=missing) = Trie([v], value)

function Trie(values::Vector{String}, value=missing)
    t = Trie(value)
    for v in values
        if !isempty(v)
            append!(t, Tuple(codeunits(v)))
        end
    end
    return t
end

Base.isempty(t::Trie) = isempty(t.leaves)

function Base.append!(trie::Union{Trie, Node}, bytes)
    b = first(bytes)
    rest = Base.tail(bytes)
    for t in trie.leaves
        if t.label === b
            if isempty(rest)
                t.leaf = true
                return
            else
                return append!(t, rest)
            end
        end
    end
    if isempty(rest)
        push!(trie.leaves, Node(b, true))
        return
    else
        push!(trie.leaves, Node(b, false))
        return append!(trie.leaves[end], rest)
    end
end

lower(c::UInt8) = UInt8('A') <= c <= UInt8('Z') ? c | 0x20 : c 

function match(node::Trie, io::IO; ignorecase::Bool=false)
    pos = position(io)
    if isempty(node.leaves)
        return true
    else
        for n in node.leaves
            match(n, io; ignorecase=ignorecase) && return true
        end
    end
    seek(io, pos)
    return false    
end
function match(node::Node, io::IO; ignorecase::Bool=false)
    eof(io) && return false
    b = peekbyte(io)
    if node.label === b || (ignorecase && lower(node.label) === lower(b))
        readbyte(io)
        if isempty(node.leaves)
            return true
        else
            for n in node.leaves
                match(n, io; ignorecase=ignorecase) && return true
            end
        end
        # didn't match, if this is a leaf node, then we matched, otherwise, no match
        return node.leaf
    else
        return false
    end
end

function matchleaf(node::Union{Trie, Node}, io::IO, b::UInt8)
    for n in node.leaves
        n.label === b && return n
    end
    return nothing
end
matchleaf(::Nothing, io, b) = nothing

end # module