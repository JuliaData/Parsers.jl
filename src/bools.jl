# =============================================================================
# bool — exactly true/false (or the caller's explicit lists, matched above)
# =============================================================================

function parsebool(buf::Vector{UInt8}, i::Int, j::Int)
    n = j - i + 1
    @inbounds if n == 4 && buf[i] == UInt8('t') && buf[i+1] == UInt8('r') &&
                 buf[i+2] == UInt8('u') && buf[i+3] == UInt8('e')
        return (true, RC_OK)
    elseif n == 5 && buf[i] == UInt8('f') && buf[i+1] == UInt8('a') &&
           buf[i+2] == UInt8('l') && buf[i+3] == UInt8('s') && buf[i+4] == UInt8('e')
        return (false, RC_OK)
    end
    return (false, RC_INVALID)
end

"""
    matchsentinel(buf, i, j, sentinels) -> Bool

Does the span exactly equal any sentinel string? (Empty spans are the caller's
missing fast path and never reach here.)
"""
function matchsentinel(buf::Vector{UInt8}, i::Int, j::Int, sentinels::Vector{Vector{UInt8}})
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

