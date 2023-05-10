# All bytes that are not hex digits are 0x0000FFFF
const _HEX_LUT = UInt32[
    b in UInt8('0'):UInt8('9') ? UInt32(b - UInt8('0')) :
        b in UInt8('a'):UInt8('f') ? UInt32(b - UInt8('a') + 0x0a) :
        b in UInt8('A'):UInt8('F') ? UInt32(b - UInt8('A') + 0x0a) :
        0xFFFF
    for b
    in UInt8(0):UInt8(255)
]

### SHA1 ###

struct SHA1
    h::NTuple{5,UInt32}
end

supportedtype(::Type{SHA1}) = true

_set_tup5_at(t::NTuple{5,UInt32}, i, x::UInt32) = ntuple(j -> j == i ? x : t[j], 5)

function typeparser(::Type{SHA1}, source, pos, len, b, code, pl, options)
    if len - pos + 1 < 40
        @inbounds while pos <= len && _HEX_LUT[peekbyte(source, pos) + 0x01] != 0xFFFF
            pos += 1
            incr!(source)
        end
        eof(source, pos, len) && (code |= EOF)
        return (pos, code | INVALID, PosLen(pl.pos, pos - pl.pos), SHA1((0,0,0,0,0)))
    end

    check = UInt32(0)
    out = ntuple(j -> UInt32(0), 5)
    @inbounds for i in 1:5
        h = UInt32(0)
        for _ in 0:7 # Maybe unroll?
            b = peekbyte(source, pos)
            c = _HEX_LUT[b + 0x01]
            check |= c
            h = ((h << 4) | c)
            pos += 1
            incr!(source)
        end
        # Only check validity every 8 bytes to hopefully enable some vectorization
        if check == 0xFFFF
            pos -= 8 # Backtrack to the start of the invalid hex
            fastseek!(source, pos - 1)
            while _HEX_LUT[peekbyte(source, pos) + 0x01] != 0xFFFF
                pos += 1
                incr!(source)
            end
            return pos, code | INVALID, PosLen(pl.pos, pos - pl.pos), SHA1(out)
        end
        out = _set_tup5_at(out, i, h)
    end
    eof(source, pos, len) && (code |= EOF)
    return (pos, code | OK, PosLen(pl.pos, pos - pl.pos), SHA1(out))
end

### UUID ###

supportedtype(::Type{UUID}) = true

function typeparser(::Type{UUID}, source, pos, len, b, code, pl, options)
    check = UInt32(0)
    hi = UInt64(0)
    lo = UInt64(0)

    @inbounds begin
    if len - pos + 1 < 36
        while pos <= len && (_HEX_LUT[b + 0x01] != 0xFFFF || b == UInt8('-'))
            pos += 1
            incr!(source)
            b = peekbyte(source, pos)
        end
        eof(source, pos, len) && (code |= EOF)
        return (pos, code | INVALID, PosLen(pl.pos, pos - pl.pos), UUID((hi, lo)))
    end

    segment_len = 8
    for _ in 1:segment_len
        b = peekbyte(source, pos)
        c = _HEX_LUT[b + 0x01]
        check |= c
        hi = ((hi << 4) | UInt32(c))
        pos += 1
        incr!(source)
    end
    check != 0xFFFF || @goto backtrack_error
    peekbyte(source, pos) == UInt8('-') || @goto error

    pos += 1
    incr!(source)
    segment_len = 4
    for _ in 1:segment_len
        b = peekbyte(source, pos)
        c = _HEX_LUT[b + 0x01]
        check |= c
        hi = ((hi << 4) | UInt32(c))
        pos += 1
        incr!(source)
    end
    check != 0xFFFF || @goto backtrack_error
    peekbyte(source, pos) == UInt8('-') || @goto error

    pos += 1
    incr!(source)
    segment_len = 4
    for _ in 1:segment_len
        b = peekbyte(source, pos)
        c = _HEX_LUT[b + 0x01]
        check |= c
        hi = ((hi << 4) | UInt32(c))
        pos += 1
        incr!(source)
    end
    check != 0xFFFF || @goto backtrack_error
    peekbyte(source, pos) == UInt8('-') || @goto error

    pos += 1
    incr!(source)
    segment_len = 4
    for _ in 1:segment_len
        b = peekbyte(source, pos)
        c = _HEX_LUT[b + 0x01]
        check |= c
        lo = ((lo << 4) | UInt32(c))
        pos += 1
        incr!(source)
    end
    check != 0xFFFF || @goto backtrack_error
    peekbyte(source, pos) == UInt8('-') || @goto error

    pos += 1
    incr!(source)
    segment_len = 12
    for _ in 1:segment_len
        b = peekbyte(source, pos)
        c = _HEX_LUT[b + 0x01]
        check |= c
        lo = ((lo << 4) | UInt32(c))
        pos += 1
        incr!(source)
    end
    check != 0xFFFF || @goto backtrack_error
    end # @inbounds

    eof(source, pos, len) && (code |= EOF)
    return (pos, code | OK, PosLen(pl.pos, pos - pl.pos), UUID((hi, lo)))

    @label backtrack_error
    pos -= segment_len # Backtrack to the start of the invalid hex
    fastseek!(source, pos - 1)
    while _HEX_LUT[peekbyte(source, pos) + 0x01] != 0xFFFF
        pos += 1
        incr!(source)
    end
    @label error
    eof(source, pos, len) && (code |= EOF)
    return pos, code | INVALID, PosLen(pl.pos, pos - pl.pos), UUID((hi, lo))
end
