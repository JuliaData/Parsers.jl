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

"""
    Trie(value::String, value_to_return::T) where {T}
    Trie(values::Vector{String}, value_to_return::T) where {T}
    Trie(values::Vector{Pair{String, T}}) where {T}

    A basic [trie](https://en.wikipedia.org/wiki/Trie) structure for use in parsing sentinel and other special values.
    The various constructors take either a single or set of strings to act as "sentinels" (i.e. special values to be parsed), plus an optional `value_to_return` argument, which will be the value returned if the sentinel is found while parsing.
    Note the last constructor `Trie(values::Vector{Pair{String, T}})` allows specifying different return values for different sentinel values. Bool parsing uses this like:
    ```
    const BOOLS = Trie(["true"=>true, "false"=>false])
    ```
    The only restriction is that each individual value must be of the same type (i.e. a single `Trie` can only ever return one type of value).
    
    See `?Parsers.match!` for more information on how a `Trie` can be used for special-value parsing.
"""
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

"""
    Parsers.match!(t::Parsers.Trie, io::IO, r::Parsers.Result, setvalue::Bool=true, ignorecase::Bool=false)

    Function that takes an `io::IO` argument, a prebuilt `r::Parsers.Result` argument, and a `t::Parsers.Trie` argument, and attempts to match/detect special values in `t` with the next bytes consumed from `io`.
    If special values are found, `r.result` will be set to the value that was associated with `t` when it was constructed.
    The return value of `Parsers.match!` is if a special value was indeed detected in `io` (`true` or `false`).
    Optionally, if the `setvalue` is `false`, `r.result` will be unaffected (i.e. not set) even if a special value is found.
    The optional argument `ignorecase` can be used if case-insensitive matching is desired.

    Note that `io` is reset to its original position if no special value is found.
"""
function match! end

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
