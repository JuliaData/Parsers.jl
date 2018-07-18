module Tries

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

mutable struct Node
    label::UInt8
    leaf::Bool
    leaves::Vector{Node}
end
Node(label::UInt8, leaf::Bool=false) = Node(label, leaf, Node[])

function Base.show(io::IO, n::Node; indent::Int=0)
    print(io, "   "^indent)
    leafnode = n.leaf ? "leaf-node" : ""
    println(io, "Node: '$(escape_string(string(Char(n.label))))' $leafnode")
    for leaf in n.leaves
        show(io, leaf; indent=indent+1)
    end
end

struct Trie
    leaves::Vector{Node}
end

function Base.show(io::IO, t::Trie)
    println(io, "Parsers.Trie.Trie:")
    for leaf in t.leaves
        show(io, leaf; indent=1)
    end
    return
end
Trie() = Trie(Node[])
Trie(v::String) = Trie([v])

function Trie(values::Vector{String})
    t = Trie()
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

function match(node::Trie, io::IO; ref::Ref{UInt8}=Ref{UInt8}(), ignorecase::Bool=false)
    pos = position(io)
    if isempty(node.leaves)
        return true
    else
        for n in node.leaves
            if match(n, io; ignorecase=ignorecase)
                ref[] = n.label
                return true
            end
        end
    end
    fastseek!(io, pos)
    return false    
end
function match(node::Node, io::IO; ignorecase::Bool=false)
    eof(io) && return false
    b = peekbyte(io)
    # @debug "matching $(escape_string(string(Char(b)))) against $(escape_string(string(Char(node.label))))"
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