const MANTISSA_MASK = 0x000fffffffffffff
const EXP_MASK = 0x00000000000007ff

memcpy(d, doff, s, soff, n) = ccall(:memcpy, Cvoid, (Ptr{UInt8}, Ptr{UInt8}, Int), d + doff - 1, s + soff - 1, n)
memmove(d, doff, s, soff, n) = ccall(:memmove, Cvoid, (Ptr{UInt8}, Ptr{UInt8}, Int), d + doff - 1, s + soff - 1, n)

uint(x::Float16) = Core.bitcast(UInt16, x)
uint(x::Float32) = Core.bitcast(UInt32, x)
uint(x::Float64) = Core.bitcast(UInt64, x)

mantissabits(::Type{Float16}) = 10
mantissabits(::Type{Float32}) = 23
mantissabits(::Type{Float64}) = 52

exponentbits(::Type{Float16}) = 5
exponentbits(::Type{Float32}) = 8
exponentbits(::Type{Float64}) = 11

bias(::Type{Float16}) = 15
bias(::Type{Float32}) = 127
bias(::Type{Float64}) = 1023

pow5_bitcount(::Type{Float16}) = 30
pow5_bitcount(::Type{Float32}) = 61
pow5_bitcount(::Type{Float64}) = 121

pow5_inv_bitcount(::Type{Float16}) = 30
pow5_inv_bitcount(::Type{Float32}) = 59
pow5_inv_bitcount(::Type{Float64}) = 122

qinvbound(::Type{Float16}) = 4
qinvbound(::Type{Float32}) = 9
qinvbound(::Type{Float64}) = 21

qbound(::Type{Float16}) = 15
qbound(::Type{Float32}) = 31
qbound(::Type{Float64}) = 63

log10pow2(e) = (e * 78913) >> 18
log10pow5(e) = (e * 732923) >> 20
pow5bits(e) = ((e * 1217359) >> 19) + 1
@inline mulshift(m::UInt64, mula, mulb, j) = ((((UInt128(m) * mula) >> 64) + UInt128(m) * mulb) >> (j - 64)) % UInt64
@inline mulshift(m::UInt32, mul, j) = ((((UInt64(m) * (mul % UInt32)) >> 32) + (UInt64(m) * (mul >> 32))) >> (j - 32)) % UInt32
@inline mulshift(m::UInt16, mul, j) = ((((UInt32(m) * (mul % UInt16)) >> 16) + (UInt32(m) * (mul >> 16))) >> (j - 16))
indexforexp(e) = div(e + 15, 16)
pow10bitsforindex(idx) = 16 * idx + 120
lengthforindex(idx) = div(((Int64(16 * idx) * 1292913986) >> 32) + 1 + 16 + 8, 9)

@inline function pow5(x, p)
    count = 0
    while true
        q = div(x, 5)
        r = x - 5 * q
        r != 0 && return count >= p
        x = q
        count += 1
    end
end

pow2(x, p) = (x & ((Int64(1) << p) - 1)) == 0

@inline function decimallength(v)
    v >= 10000000000000000 && return 17
    v >= 1000000000000000 && return 16
    v >= 100000000000000 && return 15
    v >= 10000000000000 && return 14
    v >= 1000000000000 && return 13
    v >= 100000000000 && return 12
    v >= 10000000000 && return 11
    v >= 1000000000 && return 10
    v >= 100000000 && return 9
    v >= 10000000 && return 8
    v >= 1000000 && return 7
    v >= 100000 && return 6
    v >= 10000 && return 5
    v >= 1000 && return 4
    v >= 100 && return 3
    v >= 10 && return 2
    return 1
end

@inline function decimallength(v::UInt32)
    v >= 100000000 && return 9
    v >= 10000000 && return 8
    v >= 1000000 && return 7
    v >= 100000 && return 6
    v >= 10000 && return 5
    v >= 1000 && return 4
    v >= 100 && return 3
    v >= 10 && return 2
    return 1
end

@inline function decimallength(v::UInt16)
    v >= 10000 && return 5
    v >= 1000 && return 4
    v >= 100 && return 3
    v >= 10 && return 2
    return 1
end

@inline function mulshiftinvsplit(::Type{Float64}, mv, mp, mm, i, j)
    @inbounds mula, mulb = DOUBLE_POW5_INV_SPLIT[i + 1]
    vr = mulshift(mv, mula, mulb, j)
    vp = mulshift(mp, mula, mulb, j)
    vm = mulshift(mm, mula, mulb, j)
    return vr, vp, vm
end

@inline function mulshiftinvsplit(::Type{Float32}, mv, mp, mm, i, j)
    @inbounds mul = FLOAT_POW5_INV_SPLIT[i + 1]
    vr = mulshift(mv, mul, j)
    vp = mulshift(mp, mul, j)
    vm = mulshift(mm, mul, j)
    return vr, vp, vm
end

@inline function mulshiftinvsplit(::Type{Float16}, mv, mp, mm, i, j)
    @inbounds mul = HALF_POW5_INV_SPLIT[i + 1]
    vr = mulshift(mv, mul, j)
    vp = mulshift(mp, mul, j)
    vm = mulshift(mm, mul, j)
    return vr, vp, vm
end

@inline function mulshiftsplit(::Type{Float64}, mv, mp, mm, i, j)
    @inbounds mula, mulb = DOUBLE_POW5_SPLIT[i + 1]
    vr = mulshift(mv, mula, mulb, j)
    vp = mulshift(mp, mula, mulb, j)
    vm = mulshift(mm, mula, mulb, j)
    return vr, vp, vm
end

@inline function mulshiftsplit(::Type{Float32}, mv, mp, mm, i, j)
    @inbounds mul = FLOAT_POW5_SPLIT[i + 1]
    vr = mulshift(mv, mul, j)
    vp = mulshift(mp, mul, j)
    vm = mulshift(mm, mul, j)
    return vr, vp, vm
end

@inline function mulshiftsplit(::Type{Float16}, mv, mp, mm, i, j)
    @inbounds mul = HALF_POW5_SPLIT[i + 1]
    vr = mulshift(mv, mul, j)
    vp = mulshift(mp, mul, j)
    vm = mulshift(mm, mul, j)
    return vr, vp, vm
end

@inline function pow5invsplit(::Type{Float64}, i)
    pow = big(5)^i
    inv = div(big(1) << (bitlength(pow) - 1 + pow5_inv_bitcount(Float64)), pow) + 1
    return (UInt64(inv & ((big(1) << 64) - 1)), UInt64(inv >> 64))
end

@inline function pow5invsplit(::Type{Float32}, i)
    pow = big(5)^i
    inv = div(big(1) << (bitlength(pow) - 1 + pow5_inv_bitcount(Float32)), pow) + 1
    return UInt64(inv)
end

@inline function pow5invsplit(::Type{Float16}, i)
    pow = big(5)^i
    inv = div(big(1) << (bitlength(pow) - 1 + pow5_inv_bitcount(Float16)), pow) + 1
    return UInt32(inv)
end

@inline function pow5split(::Type{Float64}, i)
    pow = big(5)^i
    j = bitlength(pow) - pow5_bitcount(Float64)
    return (UInt64((pow >> j) & ((big(1) << 64) - 1)), UInt64(pow >> (j + 64)))
end

@inline function pow5split(::Type{Float32}, i)
    pow = big(5)^i
    return UInt64(pow >> (bitlength(pow) - pow5_bitcount(Float32)))
end

@inline function pow5split(::Type{Float16}, i)
    pow = big(5)^i
    return UInt32(pow >> (bitlength(pow) - pow5_bitcount(Float16)))
end

const DOUBLE_POW5_INV_SPLIT = map(i->pow5invsplit(Float64, i), 0:291)
const FLOAT_POW5_INV_SPLIT = map(i->pow5invsplit(Float32, i), 0:30)
const HALF_POW5_INV_SPLIT = map(i->pow5invsplit(Float16, i), 0:17)

const DOUBLE_POW5_SPLIT = map(i->pow5split(Float64, i), 0:325)
const FLOAT_POW5_SPLIT = map(i->pow5split(Float32, i), 0:46)
const HALF_POW5_SPLIT = map(i->pow5split(Float16, i), 0:23)

const DIGIT_TABLE = UInt8[
  '0','0','0','1','0','2','0','3','0','4','0','5','0','6','0','7','0','8','0','9',
  '1','0','1','1','1','2','1','3','1','4','1','5','1','6','1','7','1','8','1','9',
  '2','0','2','1','2','2','2','3','2','4','2','5','2','6','2','7','2','8','2','9',
  '3','0','3','1','3','2','3','3','3','4','3','5','3','6','3','7','3','8','3','9',
  '4','0','4','1','4','2','4','3','4','4','4','5','4','6','4','7','4','8','4','9',
  '5','0','5','1','5','2','5','3','5','4','5','5','5','6','5','7','5','8','5','9',
  '6','0','6','1','6','2','6','3','6','4','6','5','6','6','6','7','6','8','6','9',
  '7','0','7','1','7','2','7','3','7','4','7','5','7','6','7','7','7','8','7','9',
  '8','0','8','1','8','2','8','3','8','4','8','5','8','6','8','7','8','8','8','9',
  '9','0','9','1','9','2','9','3','9','4','9','5','9','6','9','7','9','8','9','9'
]

neededdigits(::Type{Float64}) = 309 + 17
neededdigits(::Type{Float32}) = 39 + 9
neededdigits(::Type{Float16}) = 9 + 5

@inline function writeshortest(buf::Vector{UInt8}, pos, x::T,
    plus=false, space=false, hash=true,
    precision=-1, expchar=UInt8('e'), padexp=false, decchar=UInt8('.')) where {T}
    neg = signbit(x)
    # special cases
    if x == 0
        if neg
            buf[pos] = UInt8('-')
            pos += 1
        elseif plus
            buf[pos] = UInt8('+')
            pos += 1
        elseif space
            buf[pos] = UInt8(' ')
            pos += 1
        end
        buf[pos] = UInt8('0')
        pos += 1
        if hash
            buf[pos] = decchar
            pos += 1
        end
        if precision == -1
            buf[pos] = UInt8('0')
            return pos + 1
        end
        while precision > 1
            buf[pos] = UInt8('0')
            pos += 1
            precision -= 1
        end
        return pos
    elseif isnan(x)
        buf[pos] = UInt8('N')
        buf[pos + 1] = UInt8('a')
        buf[pos + 2] = UInt8('N')
        return pos + 3
    elseif !isfinite(x)
        if neg
            buf[pos] = UInt8('-')
        end
        buf[pos + neg] = UInt8('I')
        buf[pos + neg + 1] = UInt8('n')
        buf[pos + neg + 2] = UInt8('f')
        return pos + neg + 3
    end

    bits = uint(x)
    mant = bits & (oftype(bits, 1) << mantissabits(T) - oftype(bits, 1))
    exp = Int((bits >> mantissabits(T)) & ((Int64(1) << exponentbits(T)) - 1))
    m2 = oftype(bits, Int64(1) << mantissabits(T)) | mant
    e2 = exp - bias(T) - mantissabits(T)
    fraction = m2 & ((oftype(bits, 1) << -e2) - 1)
    if e2 > 0 || e2 < -52 || fraction != 0
        if exp == 0
            e2 = 1 - bias(T) - mantissabits(T) - 2
            m2 = mant
        else
            e2 -= 2
        end
        even = (m2 & 1) == 0
        mv = oftype(m2, 4 * m2)
        mp = oftype(m2, mv + 2)
        mmShift = mant != 0 || exp <= 1
        mm = oftype(m2, mv - 1 - mmShift)
        vmIsTrailingZeros = false
        vrIsTrailingZeros = false
        lastRemovedDigit = 0x00
        if e2 >= 0
            q = log10pow2(e2) - (T == Float64 ? (e2 > 3) : 0)
            e10 = q
            k = pow5_inv_bitcount(T) + pow5bits(q) - 1
            i = -e2 + q + k
            vr, vp, vm = mulshiftinvsplit(T, mv, mp, mm, q, i)
            if T == Float32 || T == Float16
                if q != 0 && div(vp - 1, 10) <= div(vm, 10)
                    l = pow5_inv_bitcount(T) + pow5bits(q - 1) - 1
                    mul = T == Float32 ? FLOAT_POW5_INV_SPLIT[q] : HALF_POW5_INV_SPLIT[q]
                    lastRemovedDigit = (mulshift(mv, mul, -e2 + q - 1 + l) % 10) % UInt8
                end
            end
            if q <= qinvbound(T)
                if ((mv % UInt32) - 5 * div(mv, 5)) == 0
                    vrIsTrailingZeros = pow5(mv, q)
                elseif even
                    vmIsTrailingZeros = pow5(mm, q)
                else
                    vp -= pow5(mp, q)
                end
            end
        else
            q = log10pow5(-e2) - (T == Float64 ? (-e2 > 1) : 0)
            e10 = q + e2
            i = -e2 - q
            k = pow5bits(i) - pow5_bitcount(T)
            j = q - k
            vr, vp, vm = mulshiftsplit(T, mv, mp, mm, i, j)
            if T == Float32 || T == Float16
                if q != 0 && div(vp - 1, 10) <= div(vm, 10)
                    j = q - 1 - (pow5bits(i + 1) - pow5_bitcount(T))
                    mul = T == Float32 ? FLOAT_POW5_SPLIT[i + 2] : HALF_POW5_SPLIT[i + 2]
                    lastRemovedDigit = (mulshift(mv, mul, j) % 10) % UInt8
                end
            end
            if q <= 1
                vrIsTrailingZeros = true
                if even
                    vmIsTrailingZeros = mmShift
                else
                    vp -= 1
                end
            elseif q < qbound(T)
                vrIsTrailingZeros = pow2(mv, q - (T != Float64))
            end
        end
        removed = 0
        if vmIsTrailingZeros || vrIsTrailingZeros
            while true
                vpDiv10 = div(vp, 10)
                vmDiv10 = div(vm, 10)
                vpDiv10 <= vmDiv10 && break
                vmMod10 = (vm % UInt32) - UInt32(10) * (vmDiv10 % UInt32)
                vrDiv10 = div(vr, 10)
                vrMod10 = (vr % UInt32) - UInt32(10) * (vrDiv10 % UInt32)
                vmIsTrailingZeros &= vmMod10 == 0
                vrIsTrailingZeros &= lastRemovedDigit == 0
                lastRemovedDigit = vrMod10 % UInt8
                vr = vrDiv10
                vp = vpDiv10
                vm = vmDiv10
                removed += 1
            end
            if vmIsTrailingZeros
                while true
                    vmDiv10 = div(vm, 10)
                    vmMod10 = (vm % UInt32) - UInt32(10) * (vmDiv10 % UInt32)
                    vmMod10 != 0 && break
                    vpDiv10 = div(vp, 10)
                    vrDiv10 = div(vr, 10)
                    vrMod10 = (vr % UInt32) - UInt32(10) * (vrDiv10 % UInt32)
                    vrIsTrailingZeros &= lastRemovedDigit == 0
                    lastRemovedDigit = vrMod10 % UInt8
                    vr = vrDiv10
                    vp = vpDiv10
                    vm = vmDiv10
                    removed += 1
                end
            end
            if vrIsTrailingZeros && lastRemovedDigit == 5 && vr % 2 == 0
                lastRemovedDigit = UInt8(4)
            end
            output = vr + ((vr == vm && (!even || !vmIsTrailingZeros)) || lastRemovedDigit >= 5)
        else
            roundUp = false
            vpDiv100 = div(vp, 100)
            vmDiv100 = div(vm, 100)
            if vpDiv100 > vmDiv100
                vrDiv100 = div(vr, 100)
                vrMod100 = (vr % UInt32) - UInt32(100) * (vrDiv100 % UInt32)
                roundUp = vrMod100 >= 50
                vr = vrDiv100
                vp = vpDiv100
                vm = vmDiv100
                removed += 2
            end
            while true
                vpDiv10 = div(vp, 10)
                vmDiv10 = div(vm, 10)
                vpDiv10 <= vmDiv10 && break
                vrDiv10 = div(vr, 10)
                vrMod10 = (vr % UInt32) - UInt32(10) * (vrDiv10 % UInt32)
                roundUp = vrMod10 >= 5
                vr = vrDiv10
                vp = vpDiv10
                vm = vmDiv10
                removed += 1
            end
            output = vr + (vr == vm || roundUp || lastRemovedDigit >= 5)
        end
        nexp = e10 + removed
    else
        output = m2 >> -e2
        nexp = 0
        while true
            q = div(output, 10)
            r = (output % UInt32) - UInt32(10) * (q % UInt32)
            r != 0 && break
            output = q
            nexp += 1
        end
    end

    if neg
        buf[pos] = UInt8('-')
        pos += 1
    elseif plus
        buf[pos] = UInt8('+')
        pos += 1
    elseif space
        buf[pos] = UInt8(' ')
        pos += 1
    end

    olength = decimallength(output)
    exp_form = true
    pt = nexp + olength
    if -4 < pt <= (precision == -1 ? (T == Float16 ? 5 : 6) : precision) #&& !(pt >= olength && abs(mod(x + 0.05, 10^(pt - olength)) - 0.05) > 0.05)
        exp_form = false
        if pt <= 0
            buf[pos] = UInt8('0')
            pos += 1
            buf[pos] = decchar
            pos += 1
            for _ = 1:abs(pt)
                buf[pos] = UInt8('0')
                pos += 1
            end
        # elseif pt >= olength
            # nothing to do at this point
        # else
            # nothing to do at this point
        end
    else
        pos += 1
    end
    i = 0
    ptr = pointer(buf)
    ptr2 = pointer(DIGIT_TABLE)
    if (output >> 32) != 0
        q = output ÷ 100000000
        output2 = (output % UInt32) - UInt32(100000000) * (q % UInt32)
        output = q

        c = output2 % UInt32(10000)
        output2 = div(output2, UInt32(10000))
        d = output2 % UInt32(10000)
        c0 = (c % 100) << 1
        c1 = (c ÷ 100) << 1
        d0 = (d % 100) << 1
        d1 = (d ÷ 100) << 1
        memcpy(ptr, pos + olength - 2, ptr2, c0 + 1, 2)
        memcpy(ptr, pos + olength - 4, ptr2, c1 + 1, 2)
        memcpy(ptr, pos + olength - 6, ptr2, d0 + 1, 2)
        memcpy(ptr, pos + olength - 8, ptr2, d1 + 1, 2)
        i += 8
    end
    output2 = output % UInt32
    while output2 >= 10000
        c = output2 % UInt32(10000)
        output2 = div(output2, UInt32(10000))
        c0 = (c % 100) << 1
        c1 = (c ÷ 100) << 1
        memcpy(ptr, pos + olength - i - 2, ptr2, c0 + 1, 2)
        memcpy(ptr, pos + olength - i - 4, ptr2, c1 + 1, 2)
        i += 4
    end
    if output2 >= 100
        c = (output2 % UInt32(100)) << 1
        output2 = div(output2, UInt32(100))
        memcpy(ptr, pos + olength - i - 2, ptr2, c + 1, 2)
        i += 2
    end
    if output2 >= 10
        c = output2 << 1
        buf[pos + 1] = DIGIT_TABLE[c + 2]
        buf[pos - exp_form] = DIGIT_TABLE[c + 1]
    else
        buf[pos - exp_form] = UInt8('0') + (output2 % UInt8)
    end

    if !exp_form
        if pt <= 0
            pos += olength
            precision -= olength
            while hash && precision > 0
                buf[pos] = UInt8('0')
                pos += 1
                precision -= 1
            end
        elseif pt >= olength
            pos += olength
            precision -= olength
            for _ = 1:nexp
                buf[pos] = UInt8('0')
                pos += 1
                precision -= 1
            end
            if hash
                buf[pos] = decchar
                pos += 1
                if precision < 0
                    buf[pos] = UInt8('0')
                    pos += 1
                end
                while precision > 0
                    buf[pos] = UInt8('0')
                    pos += 1
                    precision -= 1
                end
            end
        else
            pointoff = olength - abs(nexp)
            memmove(ptr, pos + pointoff + 1, ptr, pos + pointoff, olength - pointoff + 1)
            buf[pos + pointoff] = decchar
            pos += olength + 1
            precision -= olength
            while hash && precision > 0
                buf[pos] = UInt8('0')
                pos += 1
                precision -= 1
            end
        end
    else
        if olength > 1 || hash
            buf[pos] = decchar
            pos += olength
            precision -= olength
        end
        if hash && olength == 1
            buf[pos] = UInt8('0')
            pos += 1
        end
        while hash && precision > 0
            buf[pos] = UInt8('0')
            pos += 1
            precision -= 1
        end

        buf[pos] = expchar
        pos += 1
        exp2 = nexp + olength - 1
        if exp2 < 0
            buf[pos] = UInt8('-')
            pos += 1
            exp2 = -exp2
        elseif padexp
            buf[pos] = UInt8('+')
            pos += 1
        end

        if exp2 >= 100
            c = exp2 % 10
            memcpy(ptr, pos, ptr2, 2 * div(exp2, 10) + 1, 2)
            buf[pos + 2] = UInt8('0') + (c % UInt8)
            pos += 3
        elseif exp2 >= 10
            memcpy(ptr, pos, ptr2, 2 * exp2 + 1, 2)
            pos += 2
        else
            if padexp
                buf[pos] = UInt8('0')
                pos += 1
            end
            buf[pos] = UInt8('0') + (exp2 % UInt8)
            pos += 1
        end
    end

    return pos
end

function writeshortest(x::T,
        plus::Bool=false,
        space::Bool=false,
        hash::Bool=true,
        precision::Integer=-1,
        expchar::UInt8=UInt8('e'),
        padexp::Bool=false,
        decchar::UInt8=UInt8('.')) where {T <: Base.IEEEFloat}
    buf = Base.StringVector(neededdigits(T))
    pos = writeshortest(buf, 1, x)
    @assert pos - 1 <= length(buf)
    return String(resize!(buf, pos - 1))
end