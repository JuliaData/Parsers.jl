# Adapted from CSV.jl's kernel value-layer differentials (kernel/test_values.jl):
# Base.parse / Dates are the ORACLES here — every kernel must agree bit-for-bit
# with the oracle on the accept-set; deliberate deltas are pinned explicitly.
using Test, Random, Dates, Parsers

b(s) = Vector{UInt8}(codeunits(s))
pint(s) = Parsers.parseint64(b(s), 1, ncodeunits(s))
pint128(s) = Parsers.parseint128(b(s), 1, ncodeunits(s))
pflt(s) = Parsers.parsefloat64(b(s), 1, ncodeunits(s))
pbool(s) = Parsers.parsebool(b(s), 1, ncodeunits(s))
const todate = Parsers.todate
const todatetime = Parsers.todatetime
const totime = Parsers.totime

@testset "parsebool + strictness pins" begin
    @test pbool("true") == (true, Parsers.RC_OK)
    @test pbool("false") == (false, Parsers.RC_OK)
    # strictness: parse-set ≡ detect-set — these are all INVALID by design
    for s in ("True", "TRUE", "1", "0", "t", "f", "yes", "no", "")
        @test pbool(s)[2] == Parsers.RC_INVALID
    end
end



@testset "parseuuid: oracle differential" begin
    rng = MersenneTwister(31)
    for _ in 1:20_000
        u = rand(rng, UInt128)
        s = string(Base.UUID(u))
        s = rand(rng, Bool) ? uppercase(s) : s
        v, rc = Parsers.parseuuid(b(s), 1, 36)
        @test rc == Parsers.RC_OK
        @test Base.UUID(v) == Base.tryparse(Base.UUID, s)
    end
    # every single-byte corruption of a valid uuid, at every position, against
    # the oracle (exercises the SWAR range test's lane boundaries)
    s0 = "123e4567-e89b-12d3-a456-426614174000"
    okall = true
    for pos in 1:36, c in ('g', 'G', '`', '@', '/', ':', 'z', '\xff', '\x80', '\x00', ' ', '-', 'a', 'F', '0', '9')
        s = s0[1:pos-1] * c * s0[pos+1:end]
        v, rc = Parsers.parseuuid(b(s), 1, 36)
        o = Base.tryparse(Base.UUID, s)
        okall &= (o === nothing) == (rc != Parsers.RC_OK) && (o === nothing || o.value == v)
    end
    @test okall
    for s in ("123e4567-e89b-12d3-a456-42661417400",    # 35 chars
              "123e4567-e89b-12d3-a456-4266141740000",  # 37 chars
              "123e4567xe89b-12d3-a456-426614174000",   # bad dash
              "123e4567-e89b-12d3-a456-42661417400g",   # bad hex
              "{123e4567-e89b-12d3-a456-426614174000}", # braces
              "")
        @test Parsers.parseuuid(b(s), 1, ncodeunits(s))[2] == Parsers.RC_INVALID
        @test Base.tryparse(Base.UUID, s) === nothing
    end
end
