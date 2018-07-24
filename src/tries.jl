mutable struct Node{T}
    label::UInt8
    leaf::Bool
    value::T
    leaves::Vector{Node{T}}
end
Node(label::UInt8, leaf::Bool=false, value::T=missing) where {T} = Node(label, leaf, value, Node{T}[])

function Base.show(io::IO, n::Node; indent::Int=0)
    print(io, "   "^indent)
    leafnode = n.leaf ? "leaf-node" : ""
    println(io, "Node: '$(escape_string(string(Char(n.label))))' $leafnode")
    for leaf in n.leaves
        show(io, leaf; indent=indent+1)
    end
end

struct Trie{T}
    leaves::Vector{Node{T}}
end

function Base.show(io::IO, t::Trie)
    println(io, "Parsers.Trie.Trie:")
    for leaf in t.leaves
        show(io, leaf; indent=1)
    end
    return
end
Trie(v::String, value::T=missing) where {T} = Trie([v], value)

function Trie(values::Vector{String}, value::T=missing) where {T}
    leaves = Node{T}[]
    for v in values
        if !isempty(v)
            append!(leaves, Tuple(codeunits(v)), value)
        end
    end
    return Trie(leaves)
end

function Trie(values::Vector{Pair{String, T}}) where {T}
    leaves = Node{T}[]
    for (k, v) in values
        if !isempty(k)
            append!(leaves, Tuple(codeunits(k)), v)
        end
    end
    return Trie(leaves)
end

function Base.append!(leaves, bytes, value)
    b = first(bytes)
    rest = Base.tail(bytes)
    for t in leaves
        if t.label === b
            if isempty(rest)
                t.leaf = true
                return
            else
                return append!(t.leaves, rest, value)
            end
        end
    end
    if isempty(rest)
        push!(leaves, Node(b, true, value))
        return
    else
        push!(leaves, Node(b, false, value))
        return append!(leaves[end].leaves, rest, value)
    end
end

lower(c::UInt8) = UInt8('A') <= c <= UInt8('Z') ? c | 0x20 : c 

function match!(node::Trie, io::IO, r::Result, setvalue::Bool=true, ignorecase::Bool=false)
    pos = position(io)
    if isempty(node.leaves)
        return true
    else
        for n in node.leaves
            match!(n, io, r, setvalue, ignorecase) && return true
        end
    end
    fastseek!(io, pos)
    return false    
end

function match!(node::Node, io::IO, r::Result, setvalue::Bool=true, ignorecase::Bool=false)
    eof(io) && return false
    b = peekbyte(io)
    # @debug "matching $(escape_string(string(Char(b)))) against $(escape_string(string(Char(node.label))))"
    if node.label === b || (ignorecase && lower(node.label) === lower(b))
        readbyte(io)
        if isempty(node.leaves)
            setvalue && (r.result = node.value)
            r.code = OK
            r.b = b
            return true
        else
            for n in node.leaves
                match!(n, io, r, setvalue, ignorecase) && return true
            end
        end
        # didn't match, if this is a leaf node, then we matched, otherwise, no match
        if node.leaf
            setvalue && (r.result = node.value)
            r.code = OK
            r.b = b
            return true
        end
    end
    return false
end

function matchleaf(node::Union{Trie, Node}, io::IO, b::UInt8)
    for n in node.leaves
        n.label === b && return n
    end
    return nothing
end
matchleaf(::Nothing, io, b) = nothing
