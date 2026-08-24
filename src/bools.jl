# =============================================================================
# bool — exact true/false plus prefix matching for caller spellings
# =============================================================================

"""
    parsebool(buf, i, j) -> (Bool, code)

Parse exactly `true` or `false` from the byte span. The public Bool adapter
also accepts `1` and `0`, or caller-supplied replacement spelling lists.
"""
function parsebool(buf::AbstractVector{UInt8}, i::Int, j::Int)
    n = j - i + 1
    1 <= n <= 8 || return (false, RC_INVALID)
    # one clamped word, compared branch-free against both spellings
    w = _gather8(buf, i, j)
    istrue = (n == 4) & ((w & 0x00000000ffffffff) == 0x0000000065757274)
    isfalse = (n == 5) & ((w & 0x000000ffffffffff) == 0x00000065736c6166)
    return (istrue, ifelse(istrue | isfalse, RC_OK, RC_INVALID))
end

"""
    matchsentinel(buf, i, j, sentinels) -> Bool

Does the span exactly equal any sentinel string? (Empty spans are the caller's
missing fast path and never reach here.)
"""
@inline function matchsentinel(buf::AbstractVector{UInt8}, i::Int, j::Int,
                               sentinels::Vector{Vector{UInt8}})
    n = j - i + 1
    @inbounds for s in sentinels
        length(s) == n || continue
        k = 1
        while k <= n && buf[i + k - 1] == s[k]
            k += 1
        end
        k > n && return true
    end
    return false
end

# Prefix spelling helpers live with the Bool grammar. `api.jl` validates and
# normalizes public spelling lists before it calls the prefix kernel.
@inline function _boolsentinelprefix(buf::AbstractVector{UInt8}, i::Int, j::Int,
    s::AbstractVector{UInt8})
    n = length(s)
    (n > 0 && i <= j && n <= j - i + 1) || return false
    @inbounds for k in 1:n
        buf[i + k - 1] == s[k] || return false
    end
    return true
end

@inline function _boolsentinelprefix(buf::AbstractVector{UInt8}, i::Int, j::Int,
    s::AbstractString)
    n = ncodeunits(s)
    (n > 0 && i <= j && n <= j - i + 1) || return false
    @inbounds for k in 1:n
        buf[i + k - 1] == codeunit(s, k) || return false
    end
    return true
end

@inline _boolsentinellength(s::AbstractString) = ncodeunits(s)
@inline _boolsentinellength(s) = length(s)

@inline function _longestboolprefix(buf::AbstractVector{UInt8}, pos::Int, last::Int,
                                    spellings, value::Bool, bestlen::Int,
                                    bestvalue::Bool)
    spellings === nothing && return bestlen, bestvalue
    @inbounds for spelling in spellings
        n = _boolsentinellength(spelling)
        # True spellings are visited first. Do not replace an equal-length
        # match, so a spelling present in both lists keeps true-first behavior.
        if n > bestlen && _boolsentinelprefix(buf, pos, last, spelling)
            bestlen = n
            bestvalue = value
        end
    end
    return bestlen, bestvalue
end

"""
    _parseboolprefix(buf, pos, last, trues, falses) -> (Bool, nextpos, code)

Parse the longest Bool spelling at `pos` without scanning it again. `trues`
and `falses` must be `nothing` or collections of nonempty spellings already
normalized and validated by the public API's `_bytelist` helper. If both are
`nothing`, the accepted spellings are `1`, `0`, `true`, and `false`.
"""
@inline function _parseboolprefix(buf::AbstractVector{UInt8}, pos::Int, last::Int,
                                  trues, falses)
    pos > last && return false, pos, RC_INVALID
    if trues === nothing && falses === nothing
        @inbounds lead = buf[pos]
        lead == UInt8('1') && return true, pos + 1, RC_OK
        lead == UInt8('0') && return false, pos + 1, RC_OK
        if lead == UInt8('t') && last - pos >= 3
            @inbounds if buf[pos + 1] == UInt8('r') &&
                         buf[pos + 2] == UInt8('u') &&
                         buf[pos + 3] == UInt8('e')
                return true, pos + 4, RC_OK
            end
        elseif lead == UInt8('f') && last - pos >= 4
            @inbounds if buf[pos + 1] == UInt8('a') &&
                         buf[pos + 2] == UInt8('l') &&
                         buf[pos + 3] == UInt8('s') &&
                         buf[pos + 4] == UInt8('e')
                return false, pos + 5, RC_OK
            end
        end
        return false, pos, RC_INVALID
    end

    bestlen, value = _longestboolprefix(buf, pos, last, trues, true, 0, false)
    bestlen, value = _longestboolprefix(buf, pos, last, falses, false,
                                        bestlen, value)
    bestlen == 0 && return false, pos, RC_INVALID
    return value, pos + bestlen, RC_OK
end

@inline function matchsentinel(buf::AbstractVector{UInt8}, i::Int, j::Int,
                               sentinels::Union{AbstractVector{<:AbstractString},
                                                Tuple{Vararg{AbstractString}}})
    n = j - i + 1
    @inbounds for s in sentinels
        ncodeunits(s) == n || continue
        k = 1
        while k <= n && buf[i + k - 1] == codeunit(s, k)
            k += 1
        end
        k > n && return true
    end
    return false
end
