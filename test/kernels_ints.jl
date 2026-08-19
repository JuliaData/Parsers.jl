# Adapted from CSV.jl's kernel value-layer differentials (kernel/test_values.jl):
# Base.parse / Dates are the ORACLES here — every kernel must agree bit-for-bit
# with the oracle on the accept-set; deliberate deltas are pinned explicitly.
using Test, Random, Dates, Parsers

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
