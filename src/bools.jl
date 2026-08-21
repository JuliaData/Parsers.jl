# =============================================================================
# bool — exactly true/false (or the caller's explicit lists, matched above)
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
