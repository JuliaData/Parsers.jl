import Base: uinttype

const MANTISSA_MASK = 0x000fffffffffffff
const EXP_MASK = 0x00000000000007ff

sign_mask(::Type{Float64}) =        0x8000_0000_0000_0000
exponent_mask(::Type{Float64}) =    0x7ff0_0000_0000_0000
exponent_one(::Type{Float64}) =     0x3ff0_0000_0000_0000
exponent_half(::Type{Float64}) =    0x3fe0_0000_0000_0000
significand_mask(::Type{Float64}) = 0x000f_ffff_ffff_ffff

sign_mask(::Type{Float32}) =        0x8000_0000
exponent_mask(::Type{Float32}) =    0x7f80_0000
exponent_one(::Type{Float32}) =     0x3f80_0000
exponent_half(::Type{Float32}) =    0x3f00_0000
significand_mask(::Type{Float32}) = 0x007f_ffff

sign_mask(::Type{Float16}) =        0x8000
exponent_mask(::Type{Float16}) =    0x7c00
exponent_one(::Type{Float16}) =     0x3c00
exponent_half(::Type{Float16}) =    0x3800
significand_mask(::Type{Float16}) = 0x03ff

for T in (Float16, Float32, Float64)
    @eval significand_bits(::Type{$T}) = $(trailing_ones(significand_mask(T)))
    @eval exponent_bits(::Type{$T}) = $(sizeof(T)*8 - significand_bits(T) - 1)
    @eval exponent_bias(::Type{$T}) = $(Int(exponent_one(T) >> significand_bits(T)))
    # maximum float exponent
    @eval exponent_max(::Type{$T}) = $(Int(exponent_mask(T) >> significand_bits(T)) - exponent_bias(T))
    # maximum float exponent without bias
    @eval exponent_raw_max(::Type{$T}) = $(Int(exponent_mask(T) >> significand_bits(T)))
end

neededdigits(::Type{Float64}) = 309 + 17
neededdigits(::Type{Float32}) = 39 + 9 + 2
neededdigits(::Type{Float16}) = 9 + 5 + 9

function writeshortest(x::T,
        plus::Bool=false,
        space::Bool=false,
        hash::Bool=true,
        precision::Integer=-1,
        expchar::UInt8=UInt8('e'),
        padexp::Bool=false,
        decchar::UInt8=UInt8('.'),
        typed::Bool=false,
        compact::Bool=false) where {T <: Base.IEEEFloat}
    buf = Base.StringVector(neededdigits(T))
    pos = writeshortest(buf, 1, x, plus, space, hash, precision, expchar, padexp, decchar, typed, compact)
    return String(resize!(buf, pos - 1))
end

"""
    b, e10 = reduce_shortest(f[, maxsignif])

Reduce to shortest decimal representation where `abs(f) == b * 10^e10` and `b` is an
integer. If a `maxsignif` argument is provided, then `b < maxsignif`.
"""
@inline function reduce_shortest(f::T, maxsignif=nothing) where {T}
    U = uinttype(T)
    uf = reinterpret(U, f)
    m = uf & significand_mask(T)
    e = ((uf & exponent_mask(T)) >> significand_bits(T)) % Int

    ## Step 1
    #  mf * 2^ef == f
    mf = (one(U) << significand_bits(T)) | m
    ef = e - exponent_bias(T) - significand_bits(T)
    f_isinteger = mf & ((one(U) << -ef) - one(U)) == 0

    if ef > 0 || ef < -significand_bits(T) || !f_isinteger
        # fixup subnormals
        if e == 0
            ef = 1 - exponent_bias(T) - significand_bits(T)
            mf = m
        end

        ## Step 2
        #  u * 2^e2 == (f + prevfloat(f))/2
        #  v * 2^e2 == f
        #  w * 2^e2 == (f + nextfloat(f))/2
        e2 = ef - 2
        mf_iseven = iseven(mf) # trailing bit of significand is zero

        v = U(4) * mf
        w = v + U(2)
        u_shift_half = m == 0 && e > 1 # if first element of binade, other than first normal one
        u = v - U(2) + u_shift_half

        ## Step 3
        #  a == floor(u * 2^e2 / 10^e10), exact if a_allzero
        #  b == floor(v * 2^e2 / 10^e10), exact if b_allzero
        #  c == floor(w * 2^e2 / 10^e10)
        a_allzero = false
        b_allzero = false
        b_lastdigit = 0x00
        if e2 >= 0
            q = log10pow2(e2) - (T == Float64 ? (e2 > 3) : 0)
            e10 = q
            k = pow5_inv_bitcount(T) + pow5bits(q) - 1
            i = -e2 + q + k
            a, b, c = mulshiftinvsplit(T, u, v, w, q, i)
            if T == Float32 || T == Float16
                if q != 0 && div(c - 1, 10) <= div(a, 10)
                    l = pow5_inv_bitcount(T) + pow5bits(q - 1) - 1
                    mul = pow5invsplit_lookup(T, q-1)
                    b_lastdigit = (mulshift(v, mul, -e2 + q - 1 + l) % 10) % UInt8
                end
            end
            if q <= qinvbound(T)
                if ((v % UInt32) - 5 * div(v, 5)) == 0
                    b_allzero = pow5(v, q)
                elseif mf_iseven
                    a_allzero = pow5(u, q)
                else
                    c -= pow5(w, q)
                end
            end
        else
            q = log10pow5(-e2) - (T == Float64 ? (-e2 > 1) : 0)
            e10 = q + e2
            i = -e2 - q
            k = pow5bits(i) - pow5_bitcount(T)
            j = q - k
            a, b, c = mulshiftsplit(T, u, v, w, i, j)
            if T == Float32 || T == Float16
                if q != 0 && div(c - 1, 10) <= div(a, 10)
                    j = q - 1 - (pow5bits(i + 1) - pow5_bitcount(T))
                    mul = pow5split_lookup(T, i+1)
                    b_lastdigit = (mulshift(v, mul, j) % 10) % UInt8
                end
            end
            if q <= 1
                b_allzero = true
                if mf_iseven
                    a_allzero = !u_shift_half
                else
                    c -= 1
                end
            elseif q < qbound(T)
                b_allzero = pow2(v, q - (T != Float64))
            end
        end

        ## Step 4: reduction
        if a_allzero || b_allzero
            # a) slow loop
            while true
                c_div10 = div(c, 10)
                a_div10 = div(a, 10)
                if c_div10 <= a_div10
                    break
                end
                a_mod10 = (a % UInt32) - UInt32(10) * (a_div10 % UInt32)
                b_div10 = div(b, 10)
                b_mod10 = (b % UInt32) - UInt32(10) * (b_div10 % UInt32)
                a_allzero &= a_mod10 == 0
                b_allzero &= b_lastdigit == 0
                b_lastdigit = b_mod10 % UInt8
                b = b_div10
                c = c_div10
                a = a_div10
                e10 += 1
            end
            if a_allzero
                while true
                    a_div10 = div(a, 10)
                    a_mod10 = (a % UInt32) - UInt32(10) * (a_div10 % UInt32)
                    if a_mod10 != 0 && (maxsignif === nothing || b < maxsignif)
                        break
                    end
                    c_div10 = div(c, 10)
                    b_div10 = div(b, 10)
                    b_mod10 = (b % UInt32) - UInt32(10) * (b_div10 % UInt32)
                    b_allzero &= b_lastdigit == 0
                    b_lastdigit = b_mod10 % UInt8
                    b = b_div10
                    c = c_div10
                    a = a_div10
                    e10 += 1
                end
            end
            if b_allzero && b_lastdigit == 5 && iseven(b)
                b_lastdigit = UInt8(4)
            end
            roundup = (b == a && (!mf_iseven || !a_allzero)) || b_lastdigit >= 5
        else
            # b) specialized for common case (99% Float64, 96% Float32)
            roundup = b_lastdigit >= 5
            c_div100 = div(c, 100)
            a_div100 = div(a, 100)
            if c_div100 > a_div100
                b_div100 = div(b, 100)
                b_mod100 = (b % UInt32) - UInt32(100) * (b_div100 % UInt32)
                roundup = b_mod100 >= 50
                b = b_div100
                c = c_div100
                a = a_div100
                e10 += 2
            end
            while true
                c_div10 = div(c, 10)
                a_div10 = div(a, 10)
                if c_div10 <= a_div10
                    break
                end
                b_div10 = div(b, 10)
                b_mod10 = (b % UInt32) - UInt32(10) * (b_div10 % UInt32)
                roundup = b_mod10 >= 5
                b = b_div10
                c = c_div10
                a = a_div10
                e10 += 1
            end
            roundup = (b == a || roundup)
        end
        if maxsignif !== nothing && b > maxsignif
            # reduce to max significant digits
            while true
                b_div10 = div(b, 10)
                b_mod10 = (b % UInt32) - UInt32(10) * (b_div10 % UInt32)
                if b <= maxsignif
                    break
                end
                b = b_div10
                roundup = (b_allzero && iseven(b)) ? b_mod10 > 5 : b_mod10 >= 5
                b_allzero &= b_mod10 == 0
                e10 += 1
            end
            b = b + roundup

            # remove trailing zeros
            while true
                b_div10 = div(b, 10)
                b_mod10 = (b % UInt32) - UInt32(10) * (b_div10 % UInt32)
                if b_mod10 != 0
                    break
                end
                b = b_div10
                e10 += 1
            end
        else
            b = b + roundup
        end
    else
        # c) specialized f an integer < 2^53
        b = mf >> -ef
        e10 = 0

        if maxsignif !== nothing && b > maxsignif
            b_allzero = true
            # reduce to max significant digits
            while true
                b_div10 = div(b, 10)
                b_mod10 = (b % UInt32) - UInt32(10) * (b_div10 % UInt32)
                if b <= maxsignif
                    break
                end
                b = b_div10
                roundup = (b_allzero && iseven(b)) ? b_mod10 > 5 : b_mod10 >= 5
                b_allzero &= b_mod10 == 0
                e10 += 1
            end
            b = b + roundup
        end
        while true
            b_div10 = div(b, 10)
            b_mod10 = (b % UInt32) - UInt32(10) * (b_div10 % UInt32)
            if b_mod10 != 0
                break
            end
            b = b_div10
            e10 += 1
        end
    end
    return b, e10
end


@inline function writeshortest(buf::Vector{UInt8}, pos, x::T,
                               plus=false, space=false, hash=true,
                               precision=-1, expchar=UInt8('e'), padexp=false, decchar=UInt8('.'),
                               typed=false, compact=false) where {T}
    @assert 0 < pos <= length(buf)
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
            pos += 1
            if typed && x isa Float32
                buf[pos] = UInt8('f')
                buf[pos + 1] = UInt8('0')
                pos += 2
            end
            return pos
        end
        while precision > 1
            buf[pos] = UInt8('0')
            pos += 1
            precision -= 1
        end
        if typed && x isa Float32
            buf[pos] = UInt8('f')
            buf[pos + 1] = UInt8('0')
            pos += 2
        end
        return pos
    elseif isnan(x)
        buf[pos] = UInt8('N')
        buf[pos + 1] = UInt8('a')
        buf[pos + 2] = UInt8('N')
        if typed
            if x isa Float32
                buf[pos + 3] = UInt8('3')
                buf[pos + 4] = UInt8('2')
            elseif x isa Float16
                buf[pos + 3] = UInt8('1')
                buf[pos + 4] = UInt8('6')
            end
        end
        return pos + 3 + (typed && x isa Union{Float32, Float16} ? 2 : 0)
    elseif !isfinite(x)
        if neg
            buf[pos] = UInt8('-')
        end
        buf[pos + neg] = UInt8('I')
        buf[pos + neg + 1] = UInt8('n')
        buf[pos + neg + 2] = UInt8('f')
        if typed
            if x isa Float32
                buf[pos + neg + 3] = UInt8('3')
                buf[pos + neg + 4] = UInt8('2')
            elseif x isa Float16
                buf[pos + neg + 3] = UInt8('1')
                buf[pos + neg + 4] = UInt8('6')
            end
        end
        return pos + neg + 3 + (typed && x isa Union{Float32, Float16} ? 2 : 0)
    end

    output, nexp = reduce_shortest(x, compact ? 999_999 : nothing)

    if typed && x isa Float16
        buf[pos] = UInt8('F')
        buf[pos + 1] = UInt8('l')
        buf[pos + 2] = UInt8('o')
        buf[pos + 3] = UInt8('a')
        buf[pos + 4] = UInt8('t')
        buf[pos + 5] = UInt8('1')
        buf[pos + 6] = UInt8('6')
        buf[pos + 7] = UInt8('(')
        pos += 8
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
    if -4 < pt <= (precision == -1 ? (T == Float16 ? 3 : 6) : precision)
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
        if typed && x isa Float32
            buf[pos] = UInt8('f')
            buf[pos + 1] = UInt8('0')
            pos += 2
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
    if typed && x isa Float16
        buf[pos] = UInt8(')')
        pos += 1
    end

    return pos
end

memcpy(d, doff, s, soff, n) = (ccall(:memcpy, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t), d + doff - 1, s + soff - 1, n); nothing)
memmove(d, doff, s, soff, n) = (ccall(:memmove, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t), d + doff - 1, s + soff - 1, n); nothing)

# Note: these are smaller than the values given in Figure 4 from the paper
# see https://github.com/ulfjack/ryu/issues/119
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

@inline function mulshift(m::U, mul, j) where {U<:Unsigned}
    W = widen(U)
    nbits = 8*sizeof(U)
    return ((((W(m) * (mul % U)) >> nbits) + W(m) * (mul >> nbits)) >> (j - nbits)) % promote_type(U,UInt32)
end

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

@inline function mulshiftinvsplit(::Type{T}, mv, mp, mm, i, j) where {T}
    mul = pow5invsplit_lookup(T, i)
    vr = mulshift(mv, mul, j)
    vp = mulshift(mp, mul, j)
    vm = mulshift(mm, mul, j)
    return vr, vp, vm
end

@inline function mulshiftsplit(::Type{T}, mv, mp, mm, i, j) where {T}
    mul = pow5split_lookup(T, i)
    vr = mulshift(mv, mul, j)
    vp = mulshift(mp, mul, j)
    vm = mulshift(mm, mul, j)
    return vr, vp, vm
end

function pow5invsplit(::Type{T}, i) where {T<:AbstractFloat}
    W = widen(uinttype(T))
    pow = big(5)^i
    inv = div(big(1) << (ndigits(pow, base=2) - 1 + pow5_inv_bitcount(T)), pow) + 1
    return W(inv)
end

function pow5invsplit_lookup end
for T in (Float64, Float32, Float16)
    e2_max = exponent_max(T) - precision(T) - 2
    i_max = log10pow2(e2_max)
    table = [pow5invsplit(T, i) for i = 0:i_max]
    @eval pow5invsplit_lookup(::Type{$T}, i) = @inbounds($table[i+1])
end

function pow5split(::Type{T}, i) where {T<:AbstractFloat}
    W = widen(uinttype(T))
    pow = big(5)^i
    return W(pow >> (ndigits(pow, base=2) - pow5_bitcount(T)))
end

function pow5split_lookup end
for T in (Float64, Float32, Float16)
    e2_min = 1 - exponent_bias(T) - significand_bits(T) - 2
    i_max = 1 - e2_min - log10pow5(-e2_min)
    table = [pow5split(T, i) for i = 0:i_max]
    @eval pow5split_lookup(::Type{$T}, i) = @inbounds($table[i+1])
end

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
