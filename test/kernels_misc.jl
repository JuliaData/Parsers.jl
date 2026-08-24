# Adapted from CSV.jl's kernel value-layer differentials (kernel/test_values.jl):
# Base.parse / Dates are the ORACLES here — every kernel must agree bit-for-bit
# with the oracle on the accept-set; deliberate deltas are pinned explicitly.
using Test, Random, Dates, Parsers

parseboolprefixdefault(source, pos=1, last=length(source)) =
    Parsers._parseboolprefix(source, pos, last, nothing, nothing)
parseboolprefixcustom(source, pos, last, trues, falses) =
    Parsers._parseboolprefix(source, pos, last, trues, falses)

@testset "parsebool + strictness pins" begin
    @test pbool("true") == (true, Parsers.RC_OK)
    @test pbool("false") == (false, Parsers.RC_OK)
    # strictness: parse-set ≡ detect-set — these are all INVALID by design
    for s in ("True", "TRUE", "1", "0", "t", "f", "yes", "no", "")
        @test pbool(s)[2] == Parsers.RC_INVALID
    end
end

@testset "bool: prefix kernel returns the longest spelling and its value once" begin
    for (source, expected) in (
        ("true;", (true, 5, Parsers.RC_OK)),
        ("false;", (false, 6, Parsers.RC_OK)),
        ("1;", (true, 2, Parsers.RC_OK)),
        ("0;", (false, 2, Parsers.RC_OK)),
        ("truth", (false, 1, Parsers.RC_INVALID)),
        ("", (false, 1, Parsers.RC_INVALID)),
    )
        bytes = b(source)
        @test parseboolprefixdefault(bytes) == expected
        @test parseboolprefixdefault(codeunits(source)) == expected
    end

    padded = b("<<false;>>")
    @test parseboolprefixdefault(padded, 3, 8) ==
          (false, 8, Parsers.RC_OK)
    @test parseboolprefixdefault(@view(padded[3:8])) ==
          (false, 6, Parsers.RC_OK)

    trues = ["y", "yes", "same"]
    falses = ["n", "no", "ye", "same"]
    @test parseboolprefixcustom(b("yes;"), 1, 4, trues, falses) ==
          (true, 4, Parsers.RC_OK)
    @test parseboolprefixcustom(b("ye;"), 1, 3, trues, falses) ==
          (false, 3, Parsers.RC_OK)
    @test parseboolprefixcustom(b("same;"), 1, 5, trues, falses) ==
          (true, 5, Parsers.RC_OK)
    @test parseboolprefixcustom(b("true;"), 1, 5, trues, falses) ==
          (false, 1, Parsers.RC_INVALID)

    tupletrues = ("on", "enabled")
    tuplefalses = ("off", "disabled")
    @test parseboolprefixcustom(b("enabled,"), 1, 8, tupletrues, tuplefalses) ==
          (true, 8, Parsers.RC_OK)
    bytetrues = [b("accept"), b("accepted")]
    bytefalses = [b("reject")]
    @test parseboolprefixcustom(b("accepted!"), 1, 9, bytetrues, bytefalses) ==
          (true, 9, Parsers.RC_OK)

    default_source = b("false;")
    custom_source = b("enabled;")
    parseboolprefixdefault(default_source)
    parseboolprefixcustom(custom_source, 1, length(custom_source),
                          tupletrues, tuplefalses)
    parseboolprefixcustom(b("yes;"), 1, 4, trues, falses)
    @test (@allocated parseboolprefixdefault(default_source)) == 0
    @test (@allocated parseboolprefixcustom(custom_source, 1,
                                             length(custom_source),
                                             tupletrues, tuplefalses)) == 0
    vector_source = b("yes;")
    @test (@allocated parseboolprefixcustom(vector_source, 1,
                                             length(vector_source),
                                             trues, falses)) == 0
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

@testset "bool: branch-free kernel accepts exactly true/false at any offset" begin
    for (s, expected) in (("true", (true, Parsers.RC_OK)), ("false", (false, Parsers.RC_OK)),
                          ("", (false, Parsers.RC_INVALID)), ("t", (false, Parsers.RC_INVALID)),
                          ("tru", (false, Parsers.RC_INVALID)), ("truee", (false, Parsers.RC_INVALID)),
                          ("fals", (false, Parsers.RC_INVALID)), ("falsee", (false, Parsers.RC_INVALID)),
                          ("TRUE", (false, Parsers.RC_INVALID)), ("True", (false, Parsers.RC_INVALID)),
                          ("1", (false, Parsers.RC_INVALID)), ("0", (false, Parsers.RC_INVALID)),
                          ("truefalse", (false, Parsers.RC_INVALID)), ("xtrue", (false, Parsers.RC_INVALID)))
        @test pbool(s) == expected
        padded = b("<<" * s * ">>>>>>>>")
        @test Parsers.parsebool(padded, 3, 2 + ncodeunits(s)) == expected
        @test Parsers.parsebool(@view(padded[3:end]), 1, ncodeunits(s)) == expected
    end
    for s in ("1", "0", "true", "false", " true ", "\ttrue\n")
        @test Parsers.parse(Bool, s) == Base.parse(Bool, s)
    end
    @test Parsers.tryparse(Bool, "2") === nothing
    @test Parsers.tryparse(Bool, "") === nothing
    @test Parsers.tryparse(Bool, " ") === nothing
end
