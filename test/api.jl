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

@testset "parse/tryparse ≡ Base.parse/tryparse (computed, not hardcoded)" begin
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
        @test sameasbase(T, s)
        @test sametry(T, s)
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
        okall &= isequal(Parsers.tryparse(Float32, s2), Base.tryparse(Float32, s2))
    end
    @test okall
    for s in ("1.17549435e-38", "1.1754942e-38", "1.4e-45", "7e-46", "7.006492e-46", "3.4028235e38",
              "3.4028236e38", "16777217", "16777216.5", "0.1", "1e-46", "1e39", "0x1p-149", "0x1p-150",
              "0x1.fffffep127", "0x1p128", "0.000000000000000000000000000000000000011754944")
        @test isequal(Parsers.tryparse(Float32, s), Base.tryparse(Float32, s))
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

@testset "range codes on the kernels; Base rejects, the values are still there" begin
    b(s) = Vector{UInt8}(codeunits(s))
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
