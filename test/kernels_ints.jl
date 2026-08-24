# Adapted from CSV.jl's kernel value-layer differentials (kernel/test_values.jl):
# Base.parse / Dates are the ORACLES here — every kernel must agree bit-for-bit
# with the oracle on the accept-set; deliberate deltas are pinned explicitly.
using Test, Random, Dates, Parsers

function consumeintprefix!(out::Ref{T}, source) where {T <: Union{Int64, Int128}}
    value, nextpos, rc =
        Parsers._parseintprefix(T, source, 1, length(source), nothing, nothing)
    out[] = value + nextpos + rc
    return nothing
end

@testset "parseint64: oracle differential" begin
    for s in ("0", "-0", "+0", "1", "-1", "42", "123456789", "-123456789",
              "9223372036854775807", "-9223372036854775808", "00042", "-007",
              "1234567890123456789")
        v, rc = pint(s)
        @test rc == Parsers.RC_OK
        @test v == parse(Int64, s)
    end
    # overflow: well-formed digits, out of range → RC_OVERFLOW (lattice cue)
    for s in ("9223372036854775808", "-9223372036854775809",
              "99999999999999999999999999", "18446744073709551616")
        v, rc = pint(s)
        @test rc == Parsers.RC_OVERFLOW
        @test_throws OverflowError parse(Int64, s)
    end
    # invalid
    for s in ("", "-", "+", "abc", "1a", "1.5", " 1", "1 ", "--1", "1-", "0x10")
        @test pint(s)[2] == Parsers.RC_INVALID
    end
    rng = MersenneTwister(42)
    for _ in 1:200_000
        x = rand(rng, Int64)
        s = string(x)
        v, rc = pint(s)
        @test rc == Parsers.RC_OK && v == x
    end
    # random digit strings of every length 1..25
    for len in 1:25, _ in 1:2_000
        s = (rand(rng, Bool) ? "-" : "") * String(rand(rng, '0':'9', len))
        v, rc = pint(s)
        or = tryparse(Int64, s)
        if or === nothing
            @test rc == Parsers.RC_OVERFLOW
        else
            @test rc == Parsers.RC_OK && v == or
        end
    end
end

@testset "parseint128: oracle differential" begin
    for s in ("0", "-0", "+1", "9223372036854775808",
              string(typemax(Int128)), string(typemin(Int128)),
              "00099999999999999999999999")
        v, rc = pint128(s)
        @test rc == Parsers.RC_OK
        @test v == parse(Int128, s)
    end
    for s in (string(big(typemax(Int128)) + 1), string(big(typemin(Int128)) - 1),
              "9"^100)
        @test pint128(s)[2] == Parsers.RC_OVERFLOW
    end
    for s in ("", "-", "+", "1.0", "1x", " 1", "1 ")
        @test pint128(s)[2] == Parsers.RC_INVALID
    end
    rng = MersenneTwister(128)
    for _ in 1:100_000
        x = rand(rng, Int128)
        v, rc = pint128(string(x))
        @test rc == Parsers.RC_OK && v == x
    end
end


@testset "parsegroupedint64 ≡ degroup! + parseint64" begin
    # the word-gather grouped parser must agree with the reference composition
    # on every spelling, with spans both mid-buffer and flush against the end
    rng = MersenneTwister(5)
    alphabet = ['0':'9'; ','; ','; ','; '-'; '+'; 'x'; '.'; ' ']
    function refgrouped(buf, i, j)
        scratch = Vector{UInt8}(undef, 64)
        n = Parsers.degroup!(scratch, buf, i, j, UInt8(','), 0xff)
        n == -2 && return (Int64(0), Parsers.RC_INVALID)
        return n == -1 ? Parsers.parseint64(buf, i, j) : Parsers.parseint64(scratch, 1, n)
    end
    pinned = ("9,223,372,036,854,775,807", "-9,223,372,036,854,775,808",
              "9,223,372,036,854,775,808", "-9,223,372,036,854,775,809",
              "000,000,001", "0,0,0", "1,", ",1", "1,,2", "-,1", "+1,000",
              "12345678,9", "123456789,0", "1234567890,1", "0000000000000000000000,1",
              "1,234", "12,34,567", "-", "+", "", ",")
    okall = true
    for it in 1:60_000
        kind = rand(rng, 1:4)
        s = kind == 1 ? (rand(rng, Bool) ? "-" : "") *
                        join((String(rand(rng, '0':'9', rand(rng, 1:3))) for _ in 1:rand(rng, 1:7)), ",") :
            kind == 2 ? (rand(rng, Bool) ? "-" : "") *
                        join((String(rand(rng, '0':'9', 3)) for _ in 1:rand(rng, 6:9)), ",") :
            kind == 3 ? String(rand(rng, alphabet, rand(rng, 1:14))) :
                        rand(rng, pinned)
        for pad in (16, 0)
            buf = Vector{UInt8}(s * " "^pad)
            i, j = 1, ncodeunits(s)
            okall &= Parsers.parsegroupedint64(buf, i, j, UInt8(',')) == refgrouped(buf, i, j)
        end
    end
    @test okall
    for s in pinned, pad in (16, 0)
        buf = Vector{UInt8}(s * " "^pad)
        @test Parsers.parsegroupedint64(buf, 1, ncodeunits(s), UInt8(',')) == refgrouped(buf, 1, ncodeunits(s))
    end
    # and the through-the-kernel view: grouped column values equal ungrouped
    @test Parsers._hasbyte(b("1,234"), 1, 5, UInt8(','))
    @test !Parsers._hasbyte(b("1234567890123"), 1, 13, UInt8(','))
    @test Parsers._hasbyte(b("123456789012,"), 1, 13, UInt8(','))
end


@testset "parsebigint: oracle differential" begin
    rng = MersenneTwister(23)
    for len in (1, 5, 17, 18, 19, 20, 37, 100, 300), _ in 1:500
        s = (rand(rng, Bool) ? "-" : "") * String(rand(rng, '0':'9', len))
        v, rc = Parsers.parsebigint(b(s), 1, ncodeunits(s))
        @test rc == Parsers.RC_OK
        @test v == parse(BigInt, s)
    end
    for s in ("0", "-0", "+7", "00042", "9" ^ 1000)
        v, rc = Parsers.parsebigint(b(s), 1, ncodeunits(s))
        @test rc == Parsers.RC_OK && v == parse(BigInt, s)
    end
    for s in ("", "-", "+", "1.5", "1e5", " 1", "1 ", "0x10", "--1")
        @test Parsers.parsebigint(b(s), 1, ncodeunits(s))[2] == Parsers.RC_INVALID
    end
end

using Random
@testset "bigint: limb construction differential vs Base" begin
    rng = MersenneTwister(19)
    okall = true
    for n in vcat(1:40, [57, 76, 95, 114, 133, 152, 171, 190, 209, 228, 300, 500, 1000])
        for _ in 1:(n <= 40 ? 50 : 5)
            s = rand(rng, ("", "-", "+")) * String(rand(rng, '0':'9', n))
            v, rc = Parsers.parsebigint(b(s), 1, ncodeunits(s))
            okall &= rc == Parsers.RC_OK && v == parse(BigInt, s)
            okall &= Parsers.parse(BigInt, s) == parse(BigInt, s)
        end
        for s in ("1" * "0"^(n - 1), "0"^n, "0"^n * "1", "9"^n, "-" * "9"^n)
            v, rc = Parsers.parsebigint(b(s), 1, ncodeunits(s))
            okall &= rc == Parsers.RC_OK && v == parse(BigInt, s)
        end
    end
    @test okall
    # a non-digit anywhere in a long span is invalid
    for k in (1, 8, 9, 19, 20, 38, 39, 60)
        s = "1"^60
        s = s[1:k - 1] * "x" * s[k + 1:end]
        @test Parsers.parsebigint(b(s), 1, 60)[2] == Parsers.RC_INVALID
        @test Parsers.tryparse(BigInt, s) === nothing
    end
    # the span end is respected: bytes beyond j never leak into the value
    padded = b("12345678901234567890123xyz")
    @test Parsers.parsebigint(padded, 1, 23)[1] == parse(BigInt, "12345678901234567890123")
    @test Parsers.parsebigint(padded, 3, 10)[1] == parse(BigInt, "34567890")
end

@testset "single-pass integer prefix kernels" begin
    prefix_digits = codeunits("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    function basedigits(value::BigInt, base::Int)
        value == 0 && return "0"
        bytes = UInt8[]
        while value != 0
            value, digit = divrem(value, base)
            push!(bytes, prefix_digits[Int(digit) + 1])
        end
        reverse!(bytes)
        return String(bytes)
    end

    function prefixsources(token::String)
        text = "!!" * token * ";tail"
        vector = Vector{UInt8}(codeunits(text))
        substring = SubString("?" * text * "?", 2, ncodeunits(text) + 1)
        strided_storage = fill(UInt8('?'), 2length(vector))
        strided_storage[1:2:end] = vector
        return ((codeunits(text), 3, ncodeunits(text)),
                (vector, 3, length(vector)),
                (view(vector, eachindex(vector)), 3, length(vector)),
                (codeunits(substring), 3, ncodeunits(substring)),
                (view(strided_storage, 1:2:length(strided_storage)), 3,
                 length(vector)))
    end

    function checkfixed(T, token, base, groupmark, expected, code)
        for (source, pos, last) in prefixsources(token)
            value, nextpos, rc = Parsers._parseintprefix(T, source, pos, last,
                                                         base, groupmark)
            @test value == expected
            @test nextpos == pos + ncodeunits(token)
            @test rc == code
        end
    end

    # Every fixed width and every supported explicit base exercises the same
    # checked accumulator. Both signed bounds and overflow must retain the
    # complete token end, including valid group marks after overflow.
    for T in (Int8, Int16, Int32, Int64, Int128,
              UInt8, UInt16, UInt32, UInt64, UInt128), base in 2:62
        maximum = BigInt(typemax(T))
        digits = basedigits(maximum, base)
        checkfixed(T, digits, base, nothing, typemax(T), Parsers.RC_OK)
        grouped = join(collect(digits), '_')
        checkfixed(T, grouped, base, '_', typemax(T), Parsers.RC_OK)
        checkfixed(T, basedigits(maximum + 1, base), base, nothing, zero(T),
                   Parsers.RC_OVERFLOW)
        if T <: Signed
            magnitude = -BigInt(typemin(T))
            checkfixed(T, "-" * basedigits(magnitude, base), base, nothing,
                       typemin(T), Parsers.RC_OK)
        end
    end

    # Prefixes are lowercase, atomic, and recognized only when `base` is
    # omitted. An unsigned sign and every no-digit shape fail at the original
    # position. A malformed group mark remains outside a valid shorter token.
    checkfixed(Int8, "-0x80", nothing, nothing, typemin(Int8), Parsers.RC_OK)
    checkfixed(Int, "+0o17", nothing, nothing, 15, Parsers.RC_OK)
    checkfixed(Int, "0b101", nothing, nothing, 5, Parsers.RC_OK)
    for (token, base) in (("0Xf", nothing), ("0xff", 16))
        for (source, pos, last) in prefixsources(token)
            @test Parsers._parseintprefix(Int, source, pos, last, base, nothing) ==
                  (0, pos + 1, Parsers.RC_OK)
        end
    end
    checkfixed(Int, "1_2_3", 10, '_', 123, Parsers.RC_OK)
    for token in ("0x", "-0b", "+0o", "_1", "+")
        source = codeunits("!!" * token * ";")
        expected = first(token) in ('0', '-', '+') && token != "+" ?
                   (0, 3 + ncodeunits(token) - 1, Parsers.RC_OK) :
                   (0, 3, Parsers.RC_INVALID)
        @test Parsers._parseintprefix(Int, source, 3, length(source), nothing,
                                     token == "_1" ? '_' : nothing) == expected
    end
    @test Parsers._parseintprefix(UInt8, codeunits("!!-1;"), 3, 5, nothing,
                                 nothing) == (UInt8(0), 3, Parsers.RC_INVALID)
    @test Parsers._parseintprefix(Int, codeunits("!!1__2;"), 3, 7, 10, '_') ==
          (1, 4, Parsers.RC_OK)
    @test Parsers._parseintprefix(Int8, codeunits("!!128_9;"), 3, 8, 10, '_') ==
          (Int8(0), 8, Parsers.RC_OVERFLOW)

    # The wide decimal paths gather complete eight-digit words while they
    # discover the token end. Exercise every possible terminator lane,
    # overflow, long leading-zero values, and signed boundaries.
    for T in (Int64, UInt64, Int128, UInt128)
        maxdigits = ncodeunits(string(typemax(T)))
        for n in 1:(maxdigits + 1)
            token = "1"^n
            expected = tryparse(T, token)
            code = expected === nothing ? Parsers.RC_OVERFLOW : Parsers.RC_OK
            value = expected === nothing ? zero(T) : expected
            checkfixed(T, token, nothing, nothing, value, code)
        end
    end
    checkfixed(Int64, "0"^80 * string(typemax(Int64)), nothing, nothing,
               typemax(Int64), Parsers.RC_OK)
    checkfixed(Int128, "0"^80 * string(typemax(Int128)), nothing, nothing,
               typemax(Int128), Parsers.RC_OK)
    checkfixed(Int64, string(typemin(Int64)), 10, nothing, typemin(Int64),
               Parsers.RC_OK)
    checkfixed(Int128, string(typemin(Int128)), 10, nothing, typemin(Int128),
               Parsers.RC_OK)

    # Grouped 64-bit prefixes defer their bound check while consuming the
    # grammar once. Leading zeros do not count, and overflow still consumes
    # every valid mark and digit before the terminator.
    checkfixed(Int64, "0_000_009_223_372_036_854_775_807", 10, '_',
               typemax(Int64), Parsers.RC_OK)
    checkfixed(Int64, "9_223_372_036_854_775_808_0", 10, '_', zero(Int64),
               Parsers.RC_OVERFLOW)
    checkfixed(UInt64, "18_446_744_073_709_551_615", 10, '_',
               typemax(UInt64), Parsers.RC_OK)
    checkfixed(UInt64, "18_446_744_073_709_551_616_0", 10, '_', zero(UInt64),
               Parsers.RC_OVERFLOW)

    allocated_source = codeunits("12345;")
    consumed = Ref{Int64}(0)
    consumeintprefix!(consumed, allocated_source)
    @test consumed[] == 12345 + 6
    @test (@allocated consumeintprefix!(consumed, allocated_source)) == 0

    allocated128 = codeunits(string(typemax(Int128), ";"))
    consumed128 = Ref{Int128}(0)
    consumeintprefix!(consumed128, allocated128)
    @test consumed128[] == typemax(Int128) + 40
    @test (@allocated consumeintprefix!(consumed128, allocated128)) == 0

    # BigInt uses the same grammar but writes radix chunks directly into its
    # allocated limbs. Cover every radix, grouping, offsets, and both signs.
    magnitude = (BigInt(1) << 521) + (BigInt(1) << 257) + 0x123456789abcdef
    for base in 2:62
        digits = basedigits(magnitude, base)
        for (token, groupmark, expected) in
            ((digits, nothing, magnitude),
             (join(collect(digits), '_'), '_', magnitude),
             ("-" * digits, nothing, -magnitude),
             ("+" * digits, nothing, magnitude))
            for (source, pos, last) in prefixsources(token)
                value, nextpos, rc = Parsers._parsebigintprefix(source, pos, last,
                                                                base, groupmark)
                @test value == expected
                @test nextpos == pos + ncodeunits(token)
                @test rc == Parsers.RC_OK
            end
        end
    end
    for (token, expected) in (("0x123456789abcdef", parse(BigInt, "123456789abcdef";
                                                          base=16)),
                              ("-0b10000000000000001", -BigInt(65537)),
                              ("+0o10000000000000001", parse(BigInt, "10000000000000001";
                                                               base=8)))
        for (source, pos, last) in prefixsources(token)
            value, nextpos, rc = Parsers._parsebigintprefix(source, pos, last,
                                                            nothing, nothing)
            @test value == expected
            @test nextpos == pos + ncodeunits(token)
            @test rc == Parsers.RC_OK
        end
    end
    for token in ("0x", "-0b", "+0o", "_1", "+")
        source = codeunits("!!" * token * ";")
        value, nextpos, rc = Parsers._parsebigintprefix(source, 3, length(source),
                                                        nothing,
                                                        token == "_1" ? '_' : nothing)
        @test value == 0
        committed_zero = first(token) in ('0', '-', '+') && token != "+"
        @test nextpos == (committed_zero ? 3 + ncodeunits(token) - 1 : 3)
        @test rc == (committed_zero ? Parsers.RC_OK : Parsers.RC_INVALID)
    end
    @test Parsers._parsebigintprefix(codeunits("!!1__2;"), 3, 7, 10, '_') ==
          (BigInt(1), 4, Parsers.RC_OK)

    # Result capacity follows the token, not the caller's remaining buffer.
    # This pins geometric growth and prevents a short prefix from reserving
    # storage for an unrelated large suffix.
    short_source = codeunits("7;")
    long_source = vcat(UInt8('7'), UInt8(';'), fill(UInt8('9'), 1_000_000))
    short_value, short_next, short_rc =
        Parsers._parsebigintprefix(short_source, 1, length(short_source), nothing,
                                   nothing)
    long_value, long_next, long_rc =
        Parsers._parsebigintprefix(long_source, 1, length(long_source), nothing,
                                   nothing)
    @test (short_value, short_next, short_rc) == (BigInt(7), 2, Parsers.RC_OK)
    @test (long_value, long_next, long_rc) == (BigInt(7), 2, Parsers.RC_OK)
    @test long_value.alloc == short_value.alloc == 1
end

@testset "bigint: limb construction is limb-width generic (32-bit limbs simulated)" begin
    rng = MersenneTwister(23)
    for L in (UInt32, UInt64), n in (1, 8, 9, 10, 18, 19, 20, 37, 38, 57, 100, 333)
        for _ in 1:20
            s = String(rand(rng, '0':'9', n))
            nlimbs = Parsers._limbsfordigits(L, n)
            limbs = zeros(L, nlimbs + 1)
            bytes = b(s)
            size = GC.@preserve limbs begin
                p = pointer(limbs)
                sz, acc, nacc, ok = Parsers._feeddigits!(p, 0, zero(UInt64), 0, bytes, 1, n + 1)
                @test ok
                Parsers._flushdigits!(p, sz, acc, nacc)
            end
            @test size <= nlimbs
            @test size == 0 || limbs[size] != 0
            value = sum((BigInt(limbs[l]) << (8 * sizeof(L) * (l - 1)) for l in 1:size); init=BigInt(0))
            @test value == parse(BigInt, s)
        end
    end
end
