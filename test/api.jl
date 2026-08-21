# The Base-parity surface. Where a behavior is claimed identical to Base, the
# test COMPUTES Base's answer (value, or error type + message) and compares —
# nothing is hardcoded that Base could disagree with. Deliberate deltas are
# listed explicitly at the bottom.
using Test, Random, Dates, Parsers

# (:ok, value) or (:err, ErrorType, message)
outcome(f) = try; (:ok, f()); catch e; (:err, typeof(e), sprint(showerror, e)); end
function sameasbase(T, s; kw...)
    ob = outcome(() -> Base.parse(T, s; kw...))
    op = outcome(() -> Parsers.parse(T, s; kw...))
    ob[1] == op[1] || return false
    ob[1] == :ok && return isequal(ob[2], op[2]) && typeof(ob[2]) == typeof(op[2])
    return ob[2] == op[2] && ob[3] == op[3]
end
function sametry(T, s; kw...)
    ob = outcome(() -> Base.tryparse(T, s; kw...))
    op = outcome(() -> Parsers.tryparse(T, s; kw...))
    ob[1] == op[1] || return false
    return ob[1] == :ok ? isequal(ob[2], op[2]) : (ob[2] == op[2] && ob[3] == op[3])
end

@testset "parse/tryparse Base parity outside documented deltas" begin
    ints = ["12", " 12 ", "\t-7\n", "+7", "-0", "0", "00042", "1_000", "0x1f", "-0x1f", "0b101", "0o17",
            "0X1F", "0x", "0b", "abc", "", "  ", "-", "+", "12abc", "1 2", "٣", "9223372036854775807",
            "-9223372036854775808", "9223372036854775808", "-9223372036854775809", "99999999999999999999",
            "0x7fffffffffffffff", "0x8000000000000000", "0xffffffffffffffff", "0x10000000000000000"]
    for s in ints, T in (Int8, Int16, Int32, Int64, Int128, UInt8, UInt16, UInt32, UInt64, UInt128)
        @test sameasbase(T, s)
        @test sametry(T, s)
    end
    for (s, base) in (("1f", 16), ("FF", 16), ("z", 36), ("Z", 36), ("Z", 62), ("z", 62), ("10", 1), ("10", 63),
                      ("0x1f", 16), ("-ff", 16), ("777", 8), ("1010", 2), ("12", 2), ("", 16), ("-", 2),
                      ("7fffffffffffffffffffffffffffffff", 16), ("80000000000000000000000000000000", 16),
                      ("-80000000000000000000000000000000", 16), ("zz", 36), (" ff ", 16))
        for T in (Int8, Int64, Int128, UInt8, UInt64, UInt128)
            @test sameasbase(T, s; base)
            @test sametry(T, s; base)
        end
    end
    floats = ["1.5", " 1.5 ", "-0.0", "1e400", "-1e400", "1e-400", "1e-320", "5e-324", "inf", "+Inf",
              "-Infinity", "NaN", "nan", "1.", ".5", "1_0.0", "0x1p3", "0x1.8", "-0x.8p1", "0x1p-1074",
              "0x1p-1075", "0x1p1024", "0x1.fffffffffffffp1023", "0X1P3", "0x", "0x.p1", "1e5f", "", "1e",
              "e5", "-", "1,5", "1.2.3", "3.141592653589793", "2.2250738585072014e-308",
              "1e", "1e+", "9007199254740993", "0.1", "123456789012345678901234567890"]
    for s in floats, T in (Float64, Float32, Float16)
        bytes = codeunits(s)
        first, last = Parsers._stripws(bytes, 1, length(bytes))
        _, rc = Parsers._parsefloatspan(T, bytes, first, last, UInt8('.'), nothing)
        if rc == Parsers.RC_OVERFLOW || rc == Parsers.RC_UNDERFLOW
            @test_throws ArgumentError Parsers.parse(T, s)
            @test Parsers.tryparse(T, s) === nothing
        else
            @test sameasbase(T, s)
            @test sametry(T, s)
        end
    end
    for s in ("true", " false ", "1", "0", "True", "2", "", "  ", "yes", "t", "TRUE")
        @test sameasbase(Bool, s)
        @test sametry(Bool, s)
    end
    for s in ("123456789012345678901234567890", " 1 ", "-0", "1e3", "+5", "12x")
        @test sameasbase(BigInt, s)
    end
    for s in ("1.5", " 1.5", "0.1", "1e400", "-2.5e-10", "x", "")
        @test sameasbase(BigFloat, s)
    end
    for s in ("123e4567-e89b-12d3-a456-426614174000", "123E4567-E89B-12D3-A456-426614174000", "nope", "")
        @test sameasbase(Base.UUID, s)
        @test sametry(Base.UUID, s)
    end
end

@testset "Float32 is parsed natively (Base's strtof is the oracle)" begin
    function float32oracle(text)
        bytes = codeunits(text)
        _, rc = Parsers._parsefloatspan(Float32, bytes, 1, length(bytes), UInt8('.'),
                                        nothing)
        return rc == Parsers.RC_OVERFLOW || rc == Parsers.RC_UNDERFLOW ? nothing :
               Base.tryparse(Float32, text)
    end
    rng = MersenneTwister(32)
    okall = true
    for _ in 1:300_000
        x = reinterpret(Float32, rand(rng, UInt32))
        (isnan(x) || isinf(x)) && continue
        s = string(x)                       # shortest repr must round-trip
        okall &= Parsers.parse(Float32, s) === x
        # decimal strings around every scale, incl. subnormals and halfway cases
        d = rand(rng, -50:40)
        s2 = string(rand(rng, 1:99999999)) * "e" * string(d)
        okall &= isequal(Parsers.tryparse(Float32, s2), float32oracle(s2))
    end
    @test okall
    for s in ("1.17549435e-38", "1.1754942e-38", "1.4e-45", "7e-46", "7.006492e-46", "3.4028235e38",
              "3.4028236e38", "16777217", "16777216.5", "0.1", "1e-46", "1e39", "0x1p-149", "0x1p-150",
              "0x1.fffffep127", "0x1p128", "0.000000000000000000000000000000000000011754944")
        @test isequal(Parsers.tryparse(Float32, s), float32oracle(s))
    end
end

@testset "keywords: decimal, groupmark, base prefixes, trues/falses, dateformat" begin
    @test Parsers.parse(Float64, "1,5"; decimal=',') == 1.5
    @test Parsers.parse(Float64, "1.234,5"; decimal=',', groupmark='.') == 1234.5
    @test Parsers.parse(Int, "1,234,567"; groupmark=',') == 1234567
    @test Parsers.parse(Float64, "1,234.5"; groupmark=',') == 1234.5
    @test Parsers.tryparse(Int, ",1"; groupmark=',') === nothing
    @test Parsers.parse(Bool, "yes"; trues=["yes"], falses=["no"]) === true
    @test Parsers.parse(Bool, "no"; trues=["yes"], falses=["no"]) === false
    @test Parsers.tryparse(Bool, "true"; trues=["yes"], falses=["no"]) === nothing   # lists replace defaults
    @test Parsers.parse(Date, "01/02/2024"; dateformat="mm/dd/yyyy") == Date(2024, 1, 2)
    @test Parsers.parse(Date, "01/02/2024"; dateformat=dateformat"mm/dd/yyyy") == Date(2024, 1, 2)
    @test Parsers.parse(DateTime, "2024-01-02 03:04"; dateformat="yyyy-mm-dd HH:MM") == DateTime(2024, 1, 2, 3, 4)
    @test Parsers.parse(Time, "1:05 PM"; dateformat="I:MM p") == Time(13, 5)
    @test Parsers.parse(Date, "Jan 02 2024"; dateformat="u dd yyyy") == Date(2024, 1, 2)
    @test Parsers.parse(Date, "Tue, 02 Jan 2024"; dateformat="e, dd u yyyy") == Date(2024, 1, 2)
    @test Parsers.parse(Date, "2024-01-02") == Date(2024, 1, 2)
    @test Parsers.parse(DateTime, "2024-01-02T03:04:05.125") == DateTime(2024, 1, 2, 3, 4, 5, 125)
    @test Parsers.parse(Time, "03:04:05.5") == Time(3, 4, 5, 500)
    @test Parsers.tryparse(Date, "2024-13-01") === nothing
    @test Parsers.tryparse(DateTime, "2024-01-02") === nothing         # strict: a date is not a datetime
    @test_throws ArgumentError Parsers.parse(Date, "nope")
    @test_throws ArgumentError Parsers.parse(Int, "10"; base=1)
    @test_throws ArgumentError Parsers.parse(Char, "a")                # unsupported T is a clear error
    # 0x/0o/0b are Base's rule: only when base is not given, lowercase only
    @test Parsers.parse(UInt8, "0xff") == 0xff
    @test_throws OverflowError Parsers.parse(UInt8, "0x100")
    @test_throws ArgumentError Parsers.parse(Int, "0x1f"; base=16)
end

@testset "byte-span forms and parsenext" begin
    buf = Vector{UInt8}("  12 ,3.5e2,true,-inf,x,0xff")
    @test Parsers.parse(Int, buf, 1, 5) == 12                          # whitespace inside the span is fine
    @test Parsers.parse(Float64, buf, 7, 11) == 350.0
    @test Parsers.parse(Bool, buf, 13, 16) === true
    @test Parsers.tryparse(Int, buf, 7, 11) === nothing
    @test Parsers.parse(Int, buf, 25, 28) == 255
    @test_throws BoundsError Parsers.parse(Int, buf, 1, 100)
    # views and codeunits are accepted without copying semantics changing
    s = "abc 42 def"
    @test Parsers.parse(Int, SubString(s, 5, 6)) == 42
    @test Parsers.parse(Int, codeunits(s), 5, 6) == 42
    @test Parsers.parse(Int, view(codeunits(s), 5:6)) == 42
    # parsenext: the token delimits itself
    n = length(buf)
    @test Parsers.parsenext(Int, buf, 3, n) == (12, 5, Parsers.RC_OK)
    @test Parsers.parsenext(Float64, buf, 7, n) == (350.0, 12, Parsers.RC_OK)
    @test Parsers.parsenext(Bool, buf, 13, n) == (true, 17, Parsers.RC_OK)
    @test Parsers.parsenext(Float64, buf, 18, n) == (-Inf, 22, Parsers.RC_OK)
    v, np, rc = Parsers.parsenext(Float64, buf, 23, n)
    @test rc == Parsers.RC_INVALID && np == 23
    @test Parsers.parsenext(Int, buf, 1, n)[3] == Parsers.RC_INVALID   # no skipping of whitespace
    j = Vector{UInt8}("[1.5e3,-2,true,null]")
    @test Parsers.parsenext(Float64, j, 2, length(j)) == (1500.0, 7, Parsers.RC_OK)
    @test Parsers.parsenext(Int, j, 8, length(j)) == (-2, 10, Parsers.RC_OK)
    @test Parsers.parsenext(Bool, j, 11, length(j)) == (true, 15, Parsers.RC_OK)
    @test Parsers.parsenext(Int, j, 16, length(j))[3] == Parsers.RC_INVALID
    # a huge number token still delimits itself and reports its range code
    big = Vector{UInt8}("1e999,")
    v, np, rc = Parsers.parsenext(Float64, big, 1, length(big))
    @test np == 6 && rc == Parsers.RC_OVERFLOW && isinf(v)
end

@testset "range codes retain the rounded values" begin
    v, rc = Parsers.parsefloat(Float64, b("1e400"), 1, 5)
    @test rc == Parsers.RC_OVERFLOW && v == Inf
    v, rc = Parsers.parsefloat(Float64, b("-1e-400"), 1, 7)
    @test rc == Parsers.RC_UNDERFLOW && v === -0.0
    v, rc = Parsers.parsefloat(Float32, b("1e40"), 1, 4)
    @test rc == Parsers.RC_OVERFLOW && v == Inf32
    v, rc = Parsers.parsefloat(Float64, b("0.0"), 1, 3)
    @test rc == Parsers.RC_OK && v == 0.0                              # a true zero is not an underflow
    @test Parsers.parseint(Int8, b("200"), 1, 3)[2] == Parsers.RC_OVERFLOW
    @test Parsers.parseint(UInt8, b("-1"), 1, 2)[2] == Parsers.RC_INVALID
end

@testset "package-owned exact fixed-float fallback" begin
    rawbits(::Type{Float64}, value) = reinterpret(UInt64, value)
    rawbits(::Type{Float32}, value) = UInt64(reinterpret(UInt32, value))
    rawbits(::Type{Float16}, value) = UInt64(reinterpret(UInt16, value))
    signmask(::Type{Float64}) = UInt64(1) << 63
    signmask(::Type{Float32}) = UInt64(1) << 31
    signmask(::Type{Float16}) = UInt64(1) << 15

    function sources(text)
        vector = b(text)
        wrapped = "xx" * text * "yy"
        substring = SubString(wrapped, 3, 2 + ncodeunits(text))
        contiguous = view(copy(vector), eachindex(vector))
        interleaved = UInt8[]
        for byte in vector
            push!(interleaved, byte, 0xff)
        end
        strided = view(interleaved, 1:2:length(interleaved))
        return (text, vector, codeunits(text), substring, contiguous, strided)
    end

    function check_public_value(T, text, expected)
        for source in sources(text)
            @test isequal(Parsers.parse(T, source), expected)
            @test isequal(Parsers.tryparse(T, source), expected)
        end
        padded = b("xx" * text * "yy")
        first = 3
        last = first + ncodeunits(text) - 1
        @test isequal(Parsers.parse(T, padded, first, last), expected)
        @test isequal(Parsers.tryparse(T, codeunits(String(padded)), first, last), expected)
    end

    function check_public_range(T, text)
        for source in sources(text)
            @test_throws ArgumentError Parsers.parse(T, source)
            @test Parsers.tryparse(T, source) === nothing
        end
        padded = b("xx" * text * "yy")
        first = 3
        last = first + ncodeunits(text) - 1
        @test_throws ArgumentError Parsers.parse(T, padded, first, last)
        @test Parsers.tryparse(T, padded, first, last) === nothing
    end

    normal = (
        (Float64, UInt64,
         ("1.00000000000000011102230246251565404236316680908203124",
          "1.00000000000000011102230246251565404236316680908203125",
          "1.00000000000000011102230246251565404236316680908203126"),
         UInt64(0x3ff0000000000000)),
        (Float32, UInt32,
         ("1.000000059604644775390624",
          "1.000000059604644775390625",
          "1.000000059604644775390626"),
         UInt64(0x3f800000)),
    )
    for (T, U, spellings, lowerbits) in normal, neg in (false, true), delta in -1:1
        unsigned = spellings[delta + 2]
        text = neg ? "-" * unsigned : unsigned
        bytes = b(text)
        @test !Parsers._parsefloat_core(T, bytes, 1, length(bytes), UInt8('.'))[3]

        parts, rc = Parsers._decompose(bytes, 1, length(bytes), UInt8('.'))
        @test rc == Parsers.RC_OK && parts.truncated
        lower = Parsers._eisel_lemire(T, parts.mant, Int(parts.exp10))
        upper = Parsers._eisel_lemire(T, parts.mant + 1, Int(parts.exp10))
        @test lower == lowerbits && upper == lower + 1
        cmp, resolved = Parsers._u256midpointcmp(T, bytes, 1, length(bytes), UInt8('.'),
                                                 UInt64(lower))
        @test resolved && cmp == delta

        magnitude = delta <= 0 ? lowerbits : lowerbits + 1
        expectedbits = magnitude | (neg ? signmask(T) : 0)
        value, rc = Parsers.parsefloat(T, bytes, 1, length(bytes))
        @test rc == Parsers.RC_OK
        @test rawbits(T, value) == expectedbits
        expected = reinterpret(T, U(expectedbits))
        check_public_value(T, text, expected)

        comma = replace(text, '.' => ',')
        @test isequal(Parsers.parse(T, comma; decimal=','), expected)
        grouped = neg ? "-0," * unsigned : "0," * unsigned
        @test isequal(Parsers.parse(T, grouped; groupmark=','), expected)
        token = b(text * ";")
        @test Parsers.parsenext(T, token, 1, length(token)) ==
              (expected, ncodeunits(text) + 1, Parsers.RC_OK)
    end

    # Arithmetic limits must fail closed into SDC instead of truncating.
    one256 = Parsers._u256(UInt64(1))
    power110, ok = Parsers._u256pow5(one256, 110)
    @test ok
    @test power110[4] != 0
    @test !Parsers._u256pow5(one256, 111)[2]
    shifted255, ok = Parsers._u256shl(one256, 255)
    @test ok && shifted255 == (UInt64(0), UInt64(0), UInt64(0), UInt64(1) << 63)
    @test !Parsers._u256shl(one256, 256)[2]
    @test !Parsers._u256shl(one256, -1)[2]
    @test !Parsers._u256pow5(one256, -1)[2]
    max256 = ntuple(_ -> typemax(UInt64), 4)
    @test Parsers._u256mul(max256, UInt64(1)) == (max256, true)
    @test !Parsers._u256mul(max256, UInt64(2))[2]

    # Generate exact decimal midpoints around three binades. This covers even
    # and odd lower mantissas plus transitions to the next binary exponent.
    function midpointtext(T, lowerbits, delta)
        midpoint, exponent = Parsers._floatmidpoint(T, lowerbits)
        if exponent >= 0
            return string((BigInt(midpoint) << exponent) + delta)
        end
        scale = -exponent
        digits = string(BigInt(midpoint) * big(5)^scale + delta)
        if length(digits) <= scale
            return "0." * "0"^(scale - length(digits)) * digits
        end
        cut = length(digits) - scale
        return digits[1:cut] * "." * digits[cut + 1:end]
    end

    # Exhaust every positive Float16 boundary at the exact tie. Build the
    # decimal from the IEEE binary16 layout, independently of parser helpers.
    exhaustive16 = true
    for lowerbits in UInt64(0):UInt64(0x7bff)
        biased = lowerbits >> 10
        fraction = lowerbits & UInt64(0x03ff)
        mantissa = biased == 0 ? fraction : UInt64(0x0400) | fraction
        exponent = biased == 0 ? -25 : Int(biased) - 26
        midpoint = 2mantissa + 1
        if exponent >= 0
            text = string(BigInt(midpoint) << exponent)
        else
            scale = -exponent
            digits = string(BigInt(midpoint) * big(5)^scale)
            if length(digits) <= scale
                text = "0." * "0"^(scale - length(digits)) * digits
            else
                cut = length(digits) - scale
                text = digits[1:cut] * "." * digits[cut + 1:end]
            end
        end
        expected = iseven(lowerbits) ? lowerbits : lowerbits + 1
        expectedrc = expected == 0 ? Parsers.RC_UNDERFLOW :
                     expected == Parsers._infbits(Float16) ? Parsers.RC_OVERFLOW :
                     Parsers.RC_OK
        for neg in (false, true)
            source = codeunits(neg ? "-" * text : text)
            value, rc = Parsers.parsefloat(Float16, source, 1, length(source))
            expectedbits = expected | (neg ? signmask(Float16) : 0)
            exhaustive16 &= rc == expectedrc && rawbits(Float16, value) == expectedbits
        end
    end
    @test exhaustive16

    # Sample Float16 midpoints at zero, subnormal, normal, binade-transition,
    # and overflow boundaries. Values inside the Float32 midpoint cell exercise
    # direct Float16 disambiguation; wider ±1 steps validate the normal stage.
    float16lowerbits = (UInt64(0), UInt64(1), UInt64(2), UInt64(0x03ff),
                        UInt64(0x0400), UInt64(0x3bff), UInt64(0x3c00),
                        UInt64(0x3c01), UInt64(0x3fff), UInt64(0x4000),
                        UInt64(0x7bfe), UInt64(0x7bff))
    for lowerbits in float16lowerbits, delta in -1:1, neg in (false, true)
        unsigned = midpointtext(Float16, lowerbits, delta)
        text = neg ? "-" * unsigned : unsigned
        bytes = b(text)
        value32, rc32 = Parsers.parsefloat(Float32, bytes, 1, length(bytes))
        _, _, exact, stagedlower = Parsers._float16stage(value32, rc32)
        @test !exact || stagedlower == lowerbits
        cmp, resolved = Parsers._u256midpointcmp(Float16, bytes, 1, length(bytes),
                                                 UInt8('.'), lowerbits)
        @test resolved && cmp == delta
        magnitude = delta < 0 ? lowerbits : delta > 0 ? lowerbits + 1 :
                    iseven(lowerbits) ? lowerbits : lowerbits + 1
        expectedbits = magnitude | (neg ? signmask(Float16) : 0)
        value, rc = Parsers.parsefloat(Float16, bytes, 1, length(bytes))
        expectedrc = magnitude == 0 ? Parsers.RC_UNDERFLOW :
                     magnitude == Parsers._infbits(Float16) ? Parsers.RC_OVERFLOW :
                     Parsers.RC_OK
        @test rc == expectedrc && rawbits(Float16, value) == expectedbits
        if expectedrc == Parsers.RC_OK
            @test isequal(Parsers.parse(Float16, text),
                          reinterpret(Float16, UInt16(expectedbits)))
        else
            @test Parsers.tryparse(Float16, text) === nothing
        end
    end

    for (T, U) in ((Float64, UInt64), (Float32, UInt32))
        MB = Parsers._mantbits(T)
        mask = (UInt64(1) << MB) - 1
        fractions = (UInt64(0), UInt64(1), UInt64(2), mask >> 1,
                     mask - 2, mask - 1, mask)
        bias = Parsers._bias(T)
        for biased in (bias - 1):(bias + 1),
            fraction in fractions, delta in -1:1, neg in (false, true)
            lowerbits = (UInt64(biased) << MB) | fraction
            unsigned = midpointtext(T, lowerbits, delta)
            text = neg ? "-" * unsigned : unsigned
            bytes = b(text)
            @test !Parsers._parsefloat_core(T, bytes, 1, length(bytes), UInt8('.'))[3]
            parts, rc = Parsers._decompose(bytes, 1, length(bytes), UInt8('.'))
            @test rc == Parsers.RC_OK
            lower = Parsers._eisel_lemire(T, parts.mant, Int(parts.exp10))
            upper = Parsers._eisel_lemire(T, parts.mant + 1, Int(parts.exp10))
            @test lower == lowerbits && upper == lower + 1
            cmp, resolved = Parsers._u256midpointcmp(T, bytes, 1, length(bytes),
                                                     UInt8('.'), UInt64(lower))
            @test resolved && cmp == delta
            magnitude = delta < 0 ? lowerbits : delta > 0 ? lowerbits + 1 :
                        iseven(lowerbits) ? lowerbits : lowerbits + 1
            expectedbits = magnitude | (neg ? signmask(T) : 0)
            value, rc = Parsers.parsefloat(T, bytes, 1, length(bytes))
            @test rc == Parsers.RC_OK && rawbits(T, value) == expectedbits
            @test isequal(Parsers.parse(T, text), reinterpret(T, U(expectedbits)))
        end
    end

    # Leading zeros and a stripped trailing zero with a compensating exponent
    # must keep the same exact midpoint decision.
    for (T, _, spellings, _) in normal
        tie = spellings[2]
        point = findfirst(==('.'), tie)
        fractiondigits = ncodeunits(tie) - point
        text = "000" * replace(tie, "." => "") * "0e-" * string(fractiondigits + 1)
        @test isequal(Parsers.parse(T, text), one(T))
    end
    @test Parsers._parsefloat_core(Float32, b(normal[2][3][2]), 1,
                                   ncodeunits(normal[2][3][2]), UInt8('.'))[3] == false
    @test Parsers.parse(Float16, normal[2][3][2]) === Float16(1)

    # These values expose both sides of Float32-to-Float16 double rounding.
    maxfinite16 = reinterpret(Float16, UInt16(0x7bff))
    minsubnormal16 = reinterpret(Float16, UInt16(0x0001))
    for (text, expected) in (("65519.999", maxfinite16),
                             ("-65519.999", -maxfinite16),
                             ("2.9802323e-8", minsubnormal16),
                             ("-2.9802323e-8", -minsubnormal16))
        value32, rc32 = Parsers.parsefloat(Float32, b(text), 1, ncodeunits(text))
        _, _, exact, _ = Parsers._float16stage(value32, rc32)
        @test exact
        check_public_value(Float16, text, expected)
    end
    @test Parsers.parse(Float16, "65,519.999"; groupmark=',') == maxfinite16
    @test Parsers.parse(Float16, "65519,999"; decimal=',') == maxfinite16
    @test Parsers.parse(Float16, "0x1.ffdp15") == maxfinite16
    @test Parsers.tryparse(Float16, "0x1p-25") === nothing

    # Force the total SDC fallback with coefficients wider than UInt256.
    lower16 = reinterpret(Float16, UInt16(0x3c00))
    upper16 = reinterpret(Float16, UInt16(0x3c01))
    longbelow = "1.00048828124" * "9"^91
    longabove = "1.00048828125" * "0"^90 * "1"
    for (text, expected) in ((longbelow, lower16), (longabove, upper16))
        bytes = b(text)
        parts, rc = Parsers._decompose(bytes, 1, length(bytes), UInt8('.'))
        @test rc == Parsers.RC_OK && parts.truncated
        @test !Parsers._u128midpointcmp(parts, UInt64(0x3c00))[2]
        @test !Parsers._u256midpointcmp(Float16, bytes, 1, length(bytes), UInt8('.'),
                                       UInt64(0x3c00))[2]
        check_public_value(Float16, text, expected)
        check_public_value(Float16, "-" * text, -expected)
    end

    # Exact midpoint between zero and the least subnormal, with ±1 in the last
    # decimal place. These exceed the four-limb tier and exercise total SDC.
    for (T, U, power, exponent) in ((Float64, UInt64, 1075, -1083),
                                    (Float32, UInt32, 150, -158))
        midpoint = big(5)^power * big(10)^8
        for delta in -1:1, neg in (false, true)
            text = (neg ? "-" : "") * string(midpoint + delta) * "e" * string(exponent)
            bytes = b(text)
            @test !Parsers._parsefloat_core(T, bytes, 1, length(bytes), UInt8('.'))[3]
            magnitude = delta <= 0 ? UInt64(0) : UInt64(1)
            expectedbits = magnitude | (neg ? signmask(T) : 0)
            value, rc = Parsers.parsefloat(T, bytes, 1, length(bytes))
            @test rawbits(T, value) == expectedbits
            @test rc == (magnitude == 0 ? Parsers.RC_UNDERFLOW : Parsers.RC_OK)
            expected = reinterpret(T, U(expectedbits))
            if rc == Parsers.RC_OK
                check_public_value(T, text, expected)
            else
                check_public_range(T, text)
            end
            token = b(text * ";")
            @test Parsers.parsenext(T, token, 1, length(token)) ==
                  (expected, ncodeunits(text) + 1, rc)
        end
    end

    # Exact midpoint between the maximum finite value and infinity.
    for (T, U, threshold) in ((Float64, UInt64, big(2)^1024 - big(2)^970),
                              (Float32, UInt32, big(2)^128 - big(2)^103))
        for delta in -1:1, neg in (false, true)
            text = (neg ? "-" : "") * string(threshold + delta)
            bytes = b(text)
            @test !Parsers._parsefloat_core(T, bytes, 1, length(bytes), UInt8('.'))[3]
            magnitude = delta < 0 ? Parsers._infbits(T) - 1 : Parsers._infbits(T)
            expectedbits = magnitude | (neg ? signmask(T) : 0)
            value, rc = Parsers.parsefloat(T, bytes, 1, length(bytes))
            @test rawbits(T, value) == expectedbits
            @test rc == (delta < 0 ? Parsers.RC_OK : Parsers.RC_OVERFLOW)
            expected = reinterpret(T, U(expectedbits))
            if rc == Parsers.RC_OK
                check_public_value(T, text, expected)
            else
                check_public_range(T, text)
            end
            token = b(text * ";")
            @test Parsers.parsenext(T, token, 1, length(token)) ==
                  (expected, ncodeunits(text) + 1, rc)
        end
    end
end

@testset "public fixed-float ranges are platform-independent" begin
    cases = (
        (Float64, "1e400", Inf),
        (Float64, "-1e-400", -0.0),
        (Float32, "1e40", Inf32),
        (Float32, "-1e-46", -0.0f0),
        (Float16, "1e40", Inf16),
        (Float16, "-1e-46", -Float16(0)),
        (Float16, "1e5", Inf16),
        (Float16, "-1e-20", -Float16(0)),
    )
    for (T, text, rounded) in cases
        bytes = b(text)
        wrapped = "xx" * text * "yy"
        substring = SubString(wrapped, 3, 2 + ncodeunits(text))
        padded = b("xx" * text * "yy")
        first = 3
        last = first + ncodeunits(text) - 1
        for source in (text, bytes, codeunits(text), substring)
            @test_throws ArgumentError Parsers.parse(T, source)
            @test Parsers.tryparse(T, source) === nothing
        end
        @test_throws ArgumentError Parsers.parse(T, padded, first, last)
        @test Parsers.tryparse(T, padded, first, last) === nothing

        value, rc = Parsers._parsefloatspan(T, bytes, 1, length(bytes), UInt8('.'), nothing)
        @test isequal(value, rounded)
        @test rc == (isinf(value) ? Parsers.RC_OVERFLOW : Parsers.RC_UNDERFLOW)
    end

    # These are deliberate Base deltas. Parsers does not ask Base to parse a
    # fixed float, even on Base's Windows-specific Float32 range path.
    @test isequal(Base.tryparse(Float16, "1e5"), Inf16)
    @test isequal(Base.tryparse(Float16, "-1e-20"), -Float16(0))
    if Sys.iswindows()
        @test Base.tryparse(Float64, "1e400") === nothing
        @test Base.tryparse(Float64, "-1e-400") === nothing
        @test isequal(Base.tryparse(Float32, "1e40"), Inf32)
        @test isequal(Base.tryparse(Float32, "-1e-46"), -0.0f0)
    else
        @test Base.tryparse(Float64, "1e400") === nothing
        @test Base.tryparse(Float64, "-1e-400") === nothing
        @test Base.tryparse(Float32, "1e40") === nothing
        @test Base.tryparse(Float32, "-1e-46") === nothing
    end

    @test !isdefined(Parsers, :_trycfloat)
    @test !isdefined(Parsers, :_basefloatrange)

    # Custom grammars use the same deterministic range policy.
    @test Parsers.tryparse(Float32, "1e40"; decimal=',') === nothing
    @test Parsers.tryparse(Float32, "1e40"; groupmark=',') === nothing
    @test_throws ArgumentError Parsers.parse(Float32, "1e40"; decimal=',')
    @test_throws ArgumentError Parsers.parse(Float32, "1e40"; groupmark=',')
end

@testset "deliberate deltas from Base (documented in the README)" begin
    # Base.parse(BigInt, "") reports a nonsensical base error; ours names the type
    @test_throws ArgumentError Parsers.parse(BigInt, "")
    @test Parsers.tryparse(BigInt, "") === nothing
    # whitespace tolerance is ASCII whitespace (Base's isspace also strips
    # Unicode spaces around integers)
    @test Parsers.tryparse(Int, " 12") === nothing
    # dates: field widths as written are exact and the whole input must be
    # consumed (Dates is lenient on both); a bare date is not a DateTime
    @test Parsers.tryparse(Date, "24-01-01") === nothing
    @test Dates.Date("24-01-01", dateformat"yyyy-mm-dd") == Date(24, 1, 1)
end
