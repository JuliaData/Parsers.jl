# Adapted from CSV.jl's kernel value-layer differentials (kernel/test_values.jl):
# Base.parse / Dates are the ORACLES here — every kernel must agree bit-for-bit
# with the oracle on the accept-set; deliberate deltas are pinned explicitly.
using Test, Random, Dates, Parsers

module DecomposeRef
using Parsers: DecParts, RC_OK, RC_INVALID
function _decompose_ref(buf::Vector{UInt8}, i::Int, j::Int, decimal::UInt8)
        neg = false
        @inbounds if i <= j
            b = buf[i]
            neg = b == UInt8('-')
            (neg | (b == UInt8('+'))) && (i += 1)
        end
        i > j && return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
        mant = zero(UInt64)
        ndig = 0
        exp10 = 0
        truncated = false
        sawdigit = false
        sawpoint = false
        digstart = 0
        @inbounds while i <= j
            b = buf[i]
            d = b - UInt8('0')
            if d <= 0x09
                sawdigit = true
                if !(ndig == 0 && d == 0x00)         # skip leading zeros entirely
                    digstart == 0 && (digstart = i)
                    if ndig < 19
                        mant = mant * 10 + d
                        ndig += 1
                    else
                        truncated |= d != 0x00
                        ndig += 1
                        sawpoint || (exp10 += 1)     # dropped integer digit
                        i += 1
                        continue
                    end
                end
                sawpoint && ndig <= 19 && (exp10 -= 1)
            elseif b == decimal && !sawpoint
                sawpoint = true
            elseif (b == UInt8('e')) | (b == UInt8('E'))
                sawdigit || return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
                i += 1
                eneg = false
                @inbounds if i <= j
                    eb = buf[i]
                    eneg = eb == UInt8('-')
                    (eneg | (eb == UInt8('+'))) && (i += 1)
                end
                i > j && return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
                e = 0
                @inbounds while i <= j
                    ed = buf[i] - UInt8('0')
                    ed > 0x09 && return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
                    e < 100_000 && (e = e * 10 + Int(ed))   # clamp: beyond ±99999 saturates
                    i += 1
                end
                exp10 += eneg ? -e : e
                return (DecParts(mant, Int32(exp10), Int32(ndig), truncated, neg, Int32(digstart)), RC_OK)
            else
                return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
            end
            i += 1
        end
        sawdigit || return (DecParts(0, 0, 0, false, neg, 0), RC_INVALID)
        return (DecParts(mant, Int32(exp10), Int32(ndig), truncated, neg, Int32(digstart)), RC_OK)
    end

end

@testset "parsefloat64: pinned adversaries" begin
    cases = [
        "0.0", "-0.0", "1.0", "0.1", "2.5", "1e0", "1e1", "1e-1", "1E5",
        "1.7976931348623157e308",      # maxfloat
        "1.7976931348623159e308",      # rounds to Inf
        "4.9406564584124654e-324",     # min subnormal
        "5e-324", "4.9e-324", "2.4703282292062327e-324",  # subnormal boundary (rounds to 0)
        "2.2250738585072014e-308",     # min normal
        "2.2250738585072011e-308",     # the notorious PHP hang value
        "9007199254740993",            # 2^53+1 (halfway)
        "9007199254740993.0",
        "1.00000000000000011102230246251565404236316680908203125",  # exactly representable long
        "0.500000000000000166533453693773481063544750213623046875",
        "1e308", "1e309", "1e-308", "1e-309", "1e-400", "1e400",
        "123456789012345678901234567890.123456789e-25",
        "3.141592653589793", "2.718281828459045",
        "0.000001", "1000000.0", "1e23", "8.98846567431158e307",
        "1" * "0"^100, "0." * "0"^100 * "1e103",
        # 768-digit halfway stress: forces the SDC tier
        "0." * "5"^400, "1." * "0"^300 * "1",
        "7.2057594037927933e16",
        "Inf", "-Inf", "+inf", "INFINITY", "-infinity", "NaN", "-nan", "+NAN",
    ]
    for s in cases
        v, rc = pflt(s)
        o = tryparse(Float64, s)
        if o === nothing
            # Base rejects ERANGE both directions; the kernel reports it as a
            # RANGE code and still hands back the ±Inf / ±0 it rounded to
            @test (rc == Parsers.RC_OVERFLOW && isinf(v)) || (rc == Parsers.RC_UNDERFLOW && v == 0.0)
        else
            @test rc == Parsers.RC_OK
            @test (isnan(v) && isnan(o)) || reinterpret(UInt64, v) == reinterpret(UInt64, o)
        end
    end
    # Compact subnormals are an Eisel-Lemire case, not an exact-decimal case.
    # This route pin prevents a few real tier-3 calls from dominating a corpus
    # benchmark and being mistaken for wrapper/compiler overhead.
    for s in ("5e-324", "4.9e-324", "2.4703282292062327e-324",
              "1e-320", "2.2250738585072011e-308")
        v, rc, done = Parsers._parsefloat_core(Float64, b(s), 1, ncodeunits(s), UInt8('.'))
        @test rc == (v == 0 ? Parsers.RC_UNDERFLOW : Parsers.RC_OK)   # the tie at 2^-1075 rounds to 0
        @test done
    end
    # Exact midpoint between zero and the minimum subnormal is 2^-1075.
    # Put the deciding ±1 decimal digit beyond HPD's 800 stored significant
    # digits. This pins both the 768-digit decision bound and sticky-tail use.
    decfrac(n, scale) = (d = string(n); "0." * "0"^(scale - length(d)) * d)
    midpoint = big(5)^1075 * big(10)^49
    for (n, bits) in ((midpoint - 1, UInt64(0)),
                      (midpoint, UInt64(0)),
                      (midpoint + 1, UInt64(1)))
        s = decfrac(n, 1124)
        buf = b(s)
        @test !Parsers._parsefloat_core(Float64, buf, 1, length(buf), UInt8('.'))[3]
        v, rc = Parsers.parsefloat64(buf, 1, length(buf))
        @test rc == (bits == 0 ? Parsers.RC_UNDERFLOW : Parsers.RC_OK)
        @test reinterpret(UInt64, v) == bits
    end
    for s in ("", ".", "-", "e5", "1e", "1e+", "1..2", "1.2.3", "1f5", " 1.0", "1.0 ", "nanx", "infs")
        @test pflt(s)[2] == Parsers.RC_INVALID
    end
end

@testset "parsefloat64: exact-halfway band stays in Eisel-Lemire (round-half-even in-line)" begin
    # odd 16-digit integers just above 2^53 are exact ties between doubles;
    # they used to trip to the 800-digit tier (2.4 µs each). Bit-exact vs Base
    # across the band, ties above 2^54, decimal .5 ties, and ties under the
    # exact-product exponent range -4..23.
    okall = true
    for x in (2^53 + 1):2:(2^53 + 40_001)
        s = string(x); v, rc = pflt(s)
        okall &= rc == Parsers.RC_OK && reinterpret(UInt64, v) == reinterpret(UInt64, parse(Float64, s))
    end
    for x in (2^54 + 2):4:(2^54 + 40_002)
        s = string(x); v, rc = pflt(s)
        okall &= rc == Parsers.RC_OK && reinterpret(UInt64, v) == reinterpret(UInt64, parse(Float64, s))
    end
    for x in (2^52):(2^52 + 20_000)
        s = string(x) * ".5"; v, rc = pflt(s)
        okall &= rc == Parsers.RC_OK && reinterpret(UInt64, v) == reinterpret(UInt64, parse(Float64, s))
    end
    rng = MersenneTwister(9)
    for _ in 1:40_000
        s = string((2^53 + 1) + 2 * rand(rng, 0:10^6)) * "e" * string(rand(rng, -4:23)); v, rc = pflt(s)
        okall &= rc == Parsers.RC_OK && reinterpret(UInt64, v) == reinterpret(UInt64, parse(Float64, s))
    end
    @test okall
    # and it must not touch tier 3: the tie resolves in the fast core
    @test Parsers._parsefloat_core(Float64, b("9007199254740993"), 1, 16, UInt8('.'))[3] == true
end

@testset "parsefloat64: round-trip (shortest repr) differential" begin
    rng = MersenneTwister(7)
    n = 0
    while n < 300_000
        bits = rand(rng, UInt64)
        x = reinterpret(Float64, bits)
        (isnan(x) || isinf(x)) && continue
        n += 1
        s = string(x)                       # Ryu shortest — must round-trip exactly
        v, rc = pflt(s)
        @test rc == Parsers.RC_OK
        @test reinterpret(UInt64, v) == reinterpret(UInt64, x)
    end
end

@testset "parsefloat64: random decimal-string differential vs Base" begin
    rng = MersenneTwister(11)
    for _ in 1:150_000
        mant = String(rand(rng, '0':'9', rand(rng, 1:24)))
        frac = rand(rng, Bool) ? "." * String(rand(rng, '0':'9', rand(rng, 1:24))) : ""
        ex = rand(rng, Bool) ? "e" * string(rand(rng, -330:330)) : ""
        s = (rand(rng, Bool) ? "-" : "") * mant * frac * ex
        v, rc = pflt(s)
        o = tryparse(Float64, s)
        if o === nothing
            @test (rc == Parsers.RC_OVERFLOW && isinf(v)) || (rc == Parsers.RC_UNDERFLOW && v == 0.0)
        else
            @test rc == Parsers.RC_OK
            @test (isnan(v) && isnan(o)) || reinterpret(UInt64, v) == reinterpret(UInt64, o)
        end
    end
    # long-mantissa SDC pressure
    for _ in 1:2_000
        # Cross the 800-digit storage cap in the general differential corpus.
        s = "0." * String(rand(rng, '0':'9', rand(rng, 100:1_200))) * "e" * string(rand(rng, -300:300))
        v, rc = pflt(s)
        o = tryparse(Float64, s)
        if o === nothing
            @test (rc == Parsers.RC_OVERFLOW && isinf(v)) || (rc == Parsers.RC_UNDERFLOW && v == 0.0)
        else
            @test rc == Parsers.RC_OK
            @test (isnan(v) && isnan(o)) || reinterpret(UInt64, v) == reinterpret(UInt64, o)
        end
    end
end

@testset "_decompose: phase-structured ≡ byte-loop reference (DecParts field-exact)" begin
    rng = MersenneTwister(0x16f10a7)
    alphabet = ['0':'9'; '0'; '0'; '.'; 'e'; 'E'; '-'; '+'; 'x'; ' ']
    okall = true
    for it in 1:150_000
        kind = rand(rng, 1:5)
        s = kind == 1 ? String(rand(rng, '0':'9', rand(rng, 1:25))) *
                        (rand(rng, Bool) ? "." * String(rand(rng, '0':'9', rand(rng, 0:25))) : "") *
                        (rand(rng, Bool) ? "e" * string(rand(rng, -40:40)) : "") :
            kind == 2 ? "0" ^ rand(rng, 0:12) * "." * "0" ^ rand(rng, 0:12) * String(rand(rng, '0':'9', rand(rng, 0:30))) :
            kind == 3 ? String(rand(rng, alphabet, rand(rng, 1:20))) :
            kind == 4 ? (rand(rng, Bool) ? "-" : "+") * String(rand(rng, '0':'9', rand(rng, 1:40))) * "." *
                        String(rand(rng, '0':'9', rand(rng, 1:40))) * "e" * string(rand(rng, -400:400)) :
                        String(rand(rng, '0':'9', rand(rng, 18:22)))
        # the span sits mid-buffer (digits after it must not be consumed) and
        # flush against the end (no word may read past the buffer)
        for (pre, post) in ((0, 16), (3, 0), (0, 0))
            prefix = rand(rng, UInt8, pre)
            suffix = UInt8[rand(rng, ['0':'9'; 'a']) for _ in 1:post]
            buf = [prefix; Vector{UInt8}(codeunits(s)); suffix]
            i = pre + 1; j = i + ncodeunits(s) - 1
            okall &= Parsers._decompose(buf, i, j, UInt8('.')) == DecomposeRef._decompose_ref(buf, i, j, UInt8('.'))
        end
    end
    @test okall
    # long-mantissa shapes the SWAR tail exists for
    for s in ("1" * "0"^400, "0." * "9"^400, "1234567890123456789" * "0"^100 * "1", "1" * "0"^30 * "e-30",
              "0." * "0"^25 * "1" * "0"^25)
        buf = Vector{UInt8}(codeunits(s))
        @test Parsers._decompose(buf, 1, length(buf), UInt8('.')) == DecomposeRef._decompose_ref(buf, 1, length(buf), UInt8('.'))
    end
end

@testset "parsefloat64: bounded fast-path equivalence" begin
    rng = MersenneTwister(0x16f10a7)
    function checkvalid(s::String, decimal::UInt8)
        raw = Vector{UInt8}(codeunits(s))
        prefix = rand(rng, UInt8, rand(rng, 0:3))
        buf = [prefix; raw; rand(rng, UInt8, 16)]
        i = length(prefix) + 1
        j = i + length(raw) - 1
        oracle = parse(Float64, decimal == UInt8('.') ? s : replace(s, ',' => '.'))
        v, rc = Parsers.parsefloat64(buf, i, j, decimal)
        @test rc == Parsers.RC_OK && reinterpret(UInt64, v) == reinterpret(UInt64, oracle)
        fast, handled = Parsers._float_fast(buf, i, j, decimal)
        @test !handled || reinterpret(UInt64, fast) == reinterpret(UInt64, oracle)
        return nothing
    end
    for decimal in (UInt8('.'), UInt8(',')), len in 1:17, _ in 1:50
        digits = String(rand(rng, '0':'9', len))
        for p in 0:len, sign in ("", "+", "-")
            checkvalid(sign * digits[1:p] * Char(decimal) * digits[p + 1:end], decimal)
        end
        checkvalid("0"^rand(rng, 1:8) * digits, decimal)
    end
    for decimal in (UInt8('.'), UInt8(','))
        for s in ("0", "-0", "+0", ".5", "5.", "000.000", "00000000.000000",
                  "9007199254740991", "9007199254740992", "9007199254740993",
                  "4.9406564584124654e-324", "5e-324", "2.2250738585072014e-308")
            checkvalid(decimal == UInt8('.') ? s : replace(s, '.' => ','), decimal)
        end
        for len in 1:17, _ in 1:1_000
            raw = rand(rng, UInt8, len)
            buf = [raw; rand(rng, UInt8, 16)]
            fast, handled = Parsers._float_fast(buf, 1, len, decimal)
            if handled
                text = String(raw)
                oracle = tryparse(Float64, decimal == UInt8('.') ? text : replace(text, ',' => '.'))
                @test oracle !== nothing
                @test reinterpret(UInt64, fast) == reinterpret(UInt64, oracle::Float64)
            end
        end
    end
    # The bounded short-span path needs no readable suffix beyond its
    # inclusive end.
    raw = Vector{UInt8}(codeunits("1.25"))
    for suffixlen in 0:16
        buf = [UInt8[0xaa, 0xbb]; raw; fill(UInt8('x'), suffixlen)]
        @test Parsers._float_fast(buf, 3, 6, UInt8('.')) == (1.25, true)
    end
    for s in ("1", "12345678", "1234.5678", "12345678.123456")
        raw = Vector{UInt8}(codeunits(s))
        @test Parsers._float_fast([raw; fill(UInt8('x'), 16)], 1, length(raw), UInt8('.'))[2]
    end
    for s in ("1..2", "9007199254740991", "9007199254740992", "9007199254740993")
        raw = Vector{UInt8}(codeunits(s))
        @test !Parsers._float_fast([raw; fill(UInt8('x'), 16)], 1, length(raw), UInt8('.'))[2]
    end
    # A decimal in the readable suffix is outside the requested span.
    padded = Vector{UInt8}(codeunits("12.3456789012345"))
    @test Parsers._float_fast(padded, 1, 2, UInt8('.')) == (12.0, true)
    w = Parsers._load8(Vector{UInt8}(codeunits("12345678")), 1)
    @test Parsers._rundigits(w, 0) == (UInt64(0), true)
    @test Parsers._rundigits(w, 8) == (UInt64(12_345_678), true)
end


@testset "parsebigfloat: oracle differential (mpfr_strtofr)" begin
    rng = MersenneTwister(29)
    check(s) = begin
        v, rc = Parsers.parsebigfloat(b(s), 1, ncodeunits(s))
        @test rc == Parsers.RC_OK
        o = parse(BigFloat, s)
        @test (isnan(v) && isnan(o)) || (v == o && signbit(v) == signbit(o))
    end
    for prec in (2, 24, 53, 65, 113, 256, 1000)
        setprecision(BigFloat, prec) do
            # pinned adversaries (halfway cases matter at every precision)
            for s in ("0.1", "-0.1", "1.5", "1.75", "1.7500000000000000000001",
                      "2.5", "1e0", "9007199254740993",
                      "0." * "5"^400, "1." * "0"^300 * "1",
                      "3.14159265358979323846264338327950288419716939937510582097",
                      "1e300", "1e-300", "123456789.123456789e-45",
                      "2.2250738585072011e-308", "2.2250738585072014e-308",
                      "4.9406564584124654e-324", "1.7976931348623157e308",
                      "Inf", "-inf", "NaN", "0.0", "-0.0")
                check(s)
            end
            # random decimal strings
            for _ in 1:4_000
                mant = String(rand(rng, '0':'9', rand(rng, 1:60)))
                frac = rand(rng, Bool) ? "." * String(rand(rng, '0':'9', rand(rng, 1:60))) : ""
                ex = rand(rng, Bool) ? "e" * string(rand(rng, -320:320)) : ""
                check((rand(rng, Bool) ? "-" : "") * mant * frac * ex)
            end
            # round-trips of random values at this precision
            for _ in 1:1_000
                x = ldexp(BigFloat(rand(rng, UInt64)) + rand(rng), rand(rng, -200:200))
                rand(rng, Bool) && (x = -x)
                check(string(x))
            end
        end
    end
    # Float64 consistency: at 53 bits the two independent pipelines must agree
    # bit-for-bit on normal-range values (BigFloat has no subnormals)
    setprecision(BigFloat, 53) do
        for _ in 1:20_000
            bits = rand(rng, UInt64)
            x = reinterpret(Float64, bits)
            (isnan(x) || isinf(x) || issubnormal(x) || x == 0) && continue
            s = string(x)
            vb, _ = Parsers.parsebigfloat(b(s), 1, ncodeunits(s))
            vf, _ = Parsers.parsefloat64(b(s), 1, ncodeunits(s))
            @test Float64(vb) === vf
        end
    end
    # a reused workspace must be stateless across values: interleave shapes
    # (positive/negative q, short/long mantissas, specials, invalids) and
    # compare against fresh-workspace parses
    ws = Parsers.BigWork()
    seq = ["0.1", "1e300", "-2.5", "123456789012345678901234567890.5e-40",
           "Inf", "9" ^ 40, "bad", "1e-300", "0.0", "-0.0", "3.14"]
    for _ in 1:3, s in seq
        vw, rcw = Parsers.parsebigfloat(b(s), 1, ncodeunits(s), UInt8('.'), ws)
        vf, rcf = Parsers.parsebigfloat(b(s), 1, ncodeunits(s))
        @test rcw == rcf
        rcw == Parsers.RC_OK && @test (isnan(vw) && isnan(vf)) ||
                                (vw == vf && signbit(vw) == signbit(vf))
    end

    # prove-out range bound is explicit, not silent
    for s in ("1e65535", "1e-65537")
        v, rc = Parsers.parsebigfloat(b(s), 1, ncodeunits(s); prec=65)
        o = setprecision(BigFloat, 65) do
            parse(BigFloat, s)
        end
        @test rc == Parsers.RC_OK && v == o
    end
    @test Parsers.parsebigfloat(b("1e65536"), 1, 7)[2] == Parsers.RC_OVERFLOW
    @test Parsers.parsebigfloat(b("1e-65538"), 1, 8)[2] == Parsers.RC_OVERFLOW
    @test Parsers.parsebigfloat(b("1e100000"), 1, 8)[2] == Parsers.RC_OVERFLOW
    @test Parsers.parsebigfloat(b("1e-100000"), 1, 9)[2] == Parsers.RC_OVERFLOW
    # The gate is based on the full M * 10^q representation. DecParts.exp10
    # only describes its first 19 digits and used to reject this in-range value.
    longfraction = "0." * "1"^65_556
    setprecision(BigFloat, 24) do
        v, rc = Parsers.parsebigfloat(b(longfraction), 1, ncodeunits(longfraction))
        @test rc == Parsers.RC_OK && v == parse(BigFloat, longfraction)
    end
    # A fixed exponent clamp could be cancelled by a long mantissa at the gate,
    # after which _bigmantissa reconstructed an enormous q for pow_ui.
    clamptrap = "1"^50_000 * "e-100000000000000000000"
    @test Parsers.parsebigfloat(b(clamptrap), 1, ncodeunits(clamptrap); prec=24)[2] == Parsers.RC_OVERFLOW
    # Zero bypasses scaling and preserves its sign even with a huge exponent.
    negzero = "-0e100000000000000000000"
    nz, rc = Parsers.parsebigfloat(b(negzero), 1, ncodeunits(negzero); prec=65)
    @test rc == Parsers.RC_OK && iszero(nz) && signbit(nz)
    for s in ("", ".", "1..2", "1e", "x")
        @test Parsers.parsebigfloat(b(s), 1, ncodeunits(s))[2] == Parsers.RC_INVALID
    end
end
