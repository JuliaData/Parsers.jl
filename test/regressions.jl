using Dates, Random

const REGRESSION_FUZZ_SEED = 0x5041525345525333

@testset "public source forms and byte spans" begin
    for (T, text, expected) in (
        (Int64, "-123456789", Int64(-123456789)),
        (Float64, "-12.5e2", -1250.0),
        (Bool, "true", true),
        (BigInt, "123456789012345678901234567890", big"123456789012345678901234567890"),
    )
        padded = "xx" * text * "yy"
        sub = SubString(padded, 3, 2 + ncodeunits(text))
        sources = (text, Vector{UInt8}(codeunits(text)), codeunits(text), sub)
        for source in sources
            @test isequal(Parsers.parse(T, source), expected)
            @test isequal(Parsers.tryparse(T, source), expected)
        end

        first = 3
        last = first + ncodeunits(text) - 1
        for source in (Vector{UInt8}(codeunits(padded)), codeunits(padded))
            @test isequal(Parsers.parse(T, source, first, last), expected)
            @test isequal(Parsers.tryparse(T, source, first, last), expected)
        end
    end

    # A view is a whole source with its own 1-based indices. The span indices
    # belong to the view, not to its parent.
    source = view(Vector{UInt8}(codeunits("xx42yy")), 3:4)
    @test Parsers.parse(Int, source) == 42
    @test Parsers.parse(Int, source, 1, 2) == 42

    # Low-level kernels accept noncontiguous byte vectors. Their wide-load
    # fallback must gather logical bytes instead of reading parent storage.
    function stridedbytes(text)
        raw = UInt8[]
        for byte in codeunits(text)
            push!(raw, byte, 0xff)
        end
        return @view raw[1:2:end]
    end
    intview = stridedbytes("123456789012345")
    @test Parsers.parseint(Int64, intview, 1, length(intview)) ==
          (Int64(123456789012345), Parsers.RC_OK)
    floatview = stridedbytes("12345678.25")
    @test Parsers.parsefloat(Float64, floatview, 1, length(floatview)) ==
          (12345678.25, Parsers.RC_OK)

    # Invalid UTF-8 outside a selected byte span must not affect that span.
    source_with_invalid_edges = UInt8[0xff; codeunits("-17"); 0xfe]
    @test Parsers.parse(Int, source_with_invalid_edges, 2, 4) == -17
    @test Parsers.tryparse(Int, source_with_invalid_edges) === nothing
end

@testset "DateFormat literals, locales, and strict defaults" begin
    expected = Date(2024, 2, 29)
    escaped = DateFormat("yyyy\\mdd")
    @test Parsers.parse(Date, "2024m02"; dateformat=escaped) == Date(2024, 1, 2)
    @test Parsers.parse(Date, "2024m02"; dateformat="yyyy\\mdd") == Date(2024, 1, 2)

    unicode_format = DateFormat("yyyy年mm月dd日")
    @test Parsers.parse(Date, "2024年02月29日"; dateformat=unicode_format) == expected

    months = ["Month$(lpad(string(i), 2, '0'))" for i in 1:12]
    months_abbr = ["M$(lpad(string(i), 2, '0'))" for i in 1:12]
    weekdays = ["Day$(lpad(string(i), 2, '0'))" for i in 1:7]
    weekdays_abbr = ["D$(lpad(string(i), 2, '0'))" for i in 1:7]
    locale = Dates.DateLocale(months, months_abbr, weekdays, weekdays_abbr)
    localized = DateFormat("U dd yyyy", locale)
    @test Parsers.parse(Date, "Month02 29 2024"; dateformat=localized) == expected
    @test Parsers.tryparse(Date, "February 29 2024"; dateformat=localized) === nothing

    unicode_months = copy(months)
    unicode_months[2] = "FÉVRIER"
    unicode_locale = Dates.DateLocale(unicode_months, months_abbr, weekdays,
                                      weekdays_abbr)
    unicode_names = DateFormat("U dd yyyy", unicode_locale)
    @test Parsers.parse(Date, "février 29 2024"; dateformat=unicode_names) == expected

    adjacent = DateFormat("yyyymmdd")
    @test Parsers.parse(Date, "20240229"; dateformat=adjacent) == expected
    repeated_delimiter = DateFormat("yyyy--mm--dd")
    @test Parsers.parse(Date, "2024--02--29"; dateformat=repeated_delimiter) == expected
    @test Parsers.parse(Date, "2024\\"; dateformat="yyyy\\") == Date(2024, 1, 1)

    signed_year = DateFormat("yyyy-mm-dd")
    for (text, expected_year) in (("-0001-01-01", -1), ("-1-01-01", -1),
                                  ("+0001-01-01", 1))
        @test Parsers.parse(Date, text; dateformat=signed_year) ==
              Date(expected_year, 1, 1)
    end
    @test Parsers.parse(Date, "-0001-01-01") == Date(-1, 1, 1)
    @test Parsers.tryparse(Date, "-1-01-01") === nothing

    @test Parsers.parse(Date, "2024-02-29") == expected
    @test Parsers.tryparse(Date, "2024-2-29") === nothing
    @test Parsers.tryparse(Date, "2024-02-29x") === nothing

    datetime = DateTime(2024, 2, 29, 23, 59, 59, 123)
    @test Parsers.parse(DateTime, "2024-02-29T23:59:59.123") == datetime
    @test Parsers.tryparse(DateTime, "2024-02-29T23:59") === nothing
    @test Parsers.tryparse(DateTime, "2024-02-29T24:00:00") === nothing

    time = Time(23, 59, 59) + Nanosecond(123456789)
    @test Parsers.parse(Time, "23:59:59.123456789") == time
    @test Parsers.parse(Time, "23:59:59.123456789";
                        dateformat="HH:MM:SS.s") == time
    @test Parsers.tryparse(Time, "23:59") === nothing
    @test Parsers.tryparse(Time, "24:00:00") === nothing
end

@testset "signed prefixed typemin for every width" begin
    for T in (Int8, Int16, Int32, Int64, Int128)
        magnitude = -big(typemin(T))
        for (base, prefix) in ((2, "0b"), (8, "0o"), (16, "0x"))
            digits = string(magnitude; base)
            text = "-" * prefix * digits
            @test Parsers.parse(T, text) == typemin(T)
            @test Parsers.tryparse(T, text) == typemin(T)
            @test Parsers.parse(T, text) == Base.parse(T, text)

            wrapped = Vector{UInt8}(codeunits("!" * text * ";"))
            @test Parsers.parse(T, wrapped, 2, ncodeunits(text) + 1) == typemin(T)

            explicit = "-" * digits
            @test Parsers.parse(T, explicit; base) == typemin(T)
            @test Parsers.tryparse(T, explicit; base) == typemin(T)
        end
    end
end

@testset "public byte inputs require one-based axes" begin
    source = OffsetBytes(b("123"))
    @test Base.has_offset_axes(source)
    @test_throws ArgumentError Parsers.parse(Int, source)
    @test_throws ArgumentError Parsers.tryparse(Int, source)
    @test_throws ArgumentError Parsers.parse(Int, source, 0, 2)
    @test_throws ArgumentError Parsers.tryparse(Int, source, 0, 2)
    @test_throws ArgumentError Parsers.parsenext(Int, source, 0, 2)

    # The low-level kernels still accept caller-managed axes and explicit spans.
    @test Parsers.parseint64(source, 0, 2) == (123, Parsers.RC_OK)
    negative_offset = OffsetBytes(b("1,234,567"), -90)
    @test Parsers.parsegroupedint64(negative_offset, -90, -82, UInt8(',')) ==
          (1_234_567, Parsers.RC_OK)
end

@testset "groupmark for every documented numeric type" begin
    numeric_types = (
        Int8, Int16, Int32, Int64, Int128,
        UInt8, UInt16, UInt32, UInt64, UInt128,
        Float16, Float32, Float64, BigInt, BigFloat,
    )
    for T in numeric_types
        @test Parsers.parse(T, "1,0"; groupmark=',') == T(10)
        @test Parsers.tryparse(T, "1,0"; groupmark=',') == T(10)
        @test Parsers.tryparse(T, "1,,0"; groupmark=',') === nothing
    end
    @test Parsers.parse(Int16, "-0x80_00"; groupmark='_') == typemin(Int16)
    @test Parsers.parse(UInt16, "0xff_ff"; groupmark='_') == typemax(UInt16)
    @test Parsers.tryparse(Int16, "0x_ff"; groupmark='_') === nothing
    @test Parsers.tryparse(Int16, "12_"; groupmark='_') === nothing
    @test Parsers.parse(BigFloat, "1.234,5"; decimal=',', groupmark='.') == BigFloat(1234.5)

    # Leading zeros never consume the target's significant-digit budget.
    grouped_zeros = join(fill("000", 16), ',')
    for T in (Int8, Int16, Int32, Int64, Int128,
              UInt8, UInt16, UInt32, UInt64, UInt128)
        @test Parsers.parse(T, grouped_zeros; groupmark=',') == zero(T)
    end

    grouped = "1,234,567,890"
    parsegroupedint64(grouped)
    @test (@allocated parsegroupedint64(grouped)) == 0
end

@testset "custom Boolean String collections are reusable without allocation" begin
    for (trues, falses) in (
        (["y", "yes", "enabled"], ["n", "no", "disabled"]),
        (("y", "yes", "enabled"), ("n", "no", "disabled")),
    )
        @test parsecustombool("enabled", trues, falses)
        @test tryparsecustombool("disabled", trues, falses) === false
        @test tryparsecustombool("true", trues, falses) === nothing

        token = b("yes;")
        @test parsenextcustombool(token, trues, falses) ==
              (true, 4, Parsers.RC_OK)

        # Warm each specialization before measuring the reusable hot path.
        parsecustombool("enabled", trues, falses)
        tryparsecustombool("disabled", trues, falses)
        parsenextcustombool(token, trues, falses)
        @test (@allocated parsecustombool("enabled", trues, falses)) == 0
        @test (@allocated tryparsecustombool("disabled", trues, falses)) == 0
        @test (@allocated parsenextcustombool(token, trues, falses)) == 0
    end

    utf16trues = [UTF16TestString("yes")]
    utf16falses = [UTF16TestString("no")]
    @test Parsers.parse(Bool, "yes"; trues=utf16trues, falses=utf16falses)
    @test Parsers.parse(Bool, "no"; trues=utf16trues, falses=utf16falses) === false
    @test Parsers.parsenext(Bool, b("yes;"), 1, 4;
                            trues=utf16trues, falses=utf16falses) ==
          (true, 4, Parsers.RC_OK)

    for empty_spellings in ([""], ("",), [UInt8[]])
        @test_throws ArgumentError Parsers.parse(Bool, ""; trues=empty_spellings)
        @test_throws ArgumentError Parsers.tryparse(Bool, ""; trues=empty_spellings)
        @test_throws ArgumentError Parsers.parsenext(Bool, b("x"), 1, 1;
                                                     trues=empty_spellings)
    end
end

@testset "special floats ignore numeric group marks" begin
    for T in (Float16, Float32, Float64, BigFloat)
        @test isnan(Parsers.parse(T, "NaN"; groupmark='a'))
        value, nextpos, code = Parsers.parsenext(T, b("NaN;"), 1, 4; groupmark='a')
        @test isnan(value)
        @test nextpos == 4
        @test code == Parsers.RC_OK
    end
end

@testset "BigInt base and prefix parity" begin
    for (text, base) in (
        ("101010", 2), ("777777", 8), ("deadBEEF", 16),
        ("zZ", 36), ("Zz", 62), ("-100000000000000000000000000000001", 2),
    )
        expected = Base.parse(BigInt, text; base)
        @test Parsers.parse(BigInt, text; base) == expected
        @test Parsers.tryparse(BigInt, text; base) == expected
    end
    for text in ("0b101010", "-0o777777", "+0xdeadBEEF", "0x123456789abcdef0123456789")
        expected = Base.parse(BigInt, text)
        @test Parsers.parse(BigInt, text) == expected
        @test Parsers.tryparse(BigInt, text) == expected
    end
    @test Parsers.parse(BigInt, "ff_ff"; base=16, groupmark='_') == big"65535"
    @test Parsers.parse(BigInt, "0xff_ff"; groupmark='_') == big"65535"
    @test Parsers.tryparse(BigInt, "0x") === nothing
    @test_throws ArgumentError Parsers.parse(BigInt, "0x")
    for base in (1, 63)
        @test_throws ArgumentError Parsers.parse(BigInt, "10"; base)
        @test_throws ArgumentError Parsers.tryparse(BigInt, "10"; base)
    end
    @test Parsers.tryparse(BigInt, "2"; base=2) === nothing
    @test_throws ArgumentError Parsers.parse(BigInt, "2"; base=2)
end

@testset "UInt64 long overflow and invalid-digit classification" begin
    for text in ("18446744073709551616", "1"^21, "9"^100)
        value, code = Parsers.parseint(UInt64, b(text), 1, ncodeunits(text))
        @test value == 0
        @test code == Parsers.RC_OVERFLOW
        @test Parsers.tryparse(UInt64, text) === nothing
        @test_throws OverflowError Parsers.parse(UInt64, text)
    end
    text = "1"^20 * "x"
    @test Parsers.parseint(UInt64, b(text), 1, ncodeunits(text))[2] == Parsers.RC_INVALID
end

@testset "BigFloat rounding and public Base parity" begin
    texts = (
        "0.1",
        "1.00000000000000011102230246251565404236316680908203125",
        "123456789012345678901234567890.123456789e-25",
        "1e10001",
        "-1e-10001",
    )
    for precision_bits in (24, 53, 113, 256)
        setprecision(BigFloat, precision_bits) do
            for text in texts
                expected = Base.parse(BigFloat, text)
                actual = Parsers.parse(BigFloat, text)
                @test isequal(actual, expected)
                @test precision(actual) == precision_bits
            end
        end
    end

    setprecision(BigFloat, 53) do
        for rounding_mode in (RoundNearest, RoundDown, RoundUp, RoundToZero)
            setrounding(BigFloat, rounding_mode) do
                for text in ("0.1", "-0.1")
                    expected = Base.parse(BigFloat, text)
                    @test isequal(Parsers.parse(BigFloat, text), expected)
                    @test isequal(Parsers.parse(BigFloat, text; rounding=rounding_mode), expected)
                end
            end
        end
    end

    @test Parsers.parse(BigFloat, "1,5"; decimal=',') == Base.parse(BigFloat, "1.5")
    @test Parsers.tryparse(BigFloat, "1.5"; decimal=',') === nothing
    @test isnan(Parsers.parse(BigFloat, "NaN"; decimal='a'))

    # Public parsing uses MPFR and is not limited by the low-level kernel's
    # decimal prove-out range.
    for precision_bits in (53, 256)
        setprecision(BigFloat, precision_bits) do
            # Values wider than Culong must fall back to the MPFR string path
            # on 32-bit systems instead of narrowing in the short-value path.
            for text in ("4294967296", "18,446,744,073")
                expected = Base.parse(BigFloat, replace(text, ',' => ""))
                actual = occursin(',', text) ?
                    Parsers.parse(BigFloat, text; groupmark=',') :
                    Parsers.parse(BigFloat, text)
                @test isequal(actual, expected)
            end
            @test Parsers.parse(BigFloat, "1,5"; decimal=',') == BigFloat(1.5)
            @test Parsers.tryparse(BigFloat, "1.5"; decimal=',') === nothing
            @test_throws ArgumentError Parsers.parse(BigFloat, "1.5"; decimal=',')
            @test Parsers.parse(BigFloat, "0x1.8p2"; decimal=',') == BigFloat(6)
            @test Parsers.tryparse(BigFloat, "0x1,8p2"; decimal=',') === nothing
            @test isinf(Parsers.parse(BigFloat, "Infinity"; decimal='i'))
            @test isnan(Parsers.parse(BigFloat, "NaN"; decimal='n'))
            for text in ("1e65536", "1e70000", "-1e-70000",
                         "1e100000", "-1e-100000")
                expected = Base.parse(BigFloat, text)
                @test isequal(Parsers.parse(BigFloat, text), expected)
                @test isequal(Parsers.tryparse(BigFloat, text), expected)
            end
        end
    end
end

@testset "BigFloat hexadecimal parity" begin
    for precision_bits in (53, 113, 256)
        setprecision(BigFloat, precision_bits) do
            for text in ("0x1p3", "-0x1.8p+2", "0x1.fffffffffffffp1023", "0x1p-1000",
                         "0x1.00000000000000000000000000000001p0")
                expected = Base.parse(BigFloat, text)
                @test isequal(Parsers.parse(BigFloat, text), expected)
                @test isequal(Parsers.tryparse(BigFloat, text), expected)
            end
        end
    end

    @test Parsers.parse(BigFloat, "0x1.8p2"; decimal=',') == BigFloat(6)
    @test Parsers.tryparse(BigFloat, "0x1,8p2"; decimal=',') === nothing

    huge_exponent = "9"^100
    for (text, expected_code) in (("0x1p" * huge_exponent, Parsers.RC_OVERFLOW),
                                  ("0x1p-" * huge_exponent, Parsers.RC_UNDERFLOW))
        value, code = Parsers.parsebigfloat(b(text), 1, ncodeunits(text))
        @test code == expected_code
        @test expected_code == Parsers.RC_OVERFLOW ? isinf(value) : iszero(value)
        expected = Base.parse(BigFloat, text)
        @test isequal(Parsers.parse(BigFloat, text), expected)
        @test isequal(Parsers.tryparse(BigFloat, text), expected)
    end
    zero_with_huge_exponent = "-0x0p" * huge_exponent
    value, code = Parsers.parsebigfloat(b(zero_with_huge_exponent), 1,
                                        ncodeunits(zero_with_huge_exponent))
    @test code == Parsers.RC_OK
    @test iszero(value) && signbit(value)
end

@testset "BigFloat default MPFR grammar and source parity" begin
    function source_forms(text)
        padded = "!" * text * ";"
        vector = Vector{UInt8}(codeunits(text))
        whole = (text, codeunits(text), vector,
                 SubString(padded, 2, ncodeunits(text) + 1),
                 view(vector, eachindex(vector)))
        spans = ((Vector{UInt8}(codeunits(padded)), 2, ncodeunits(text) + 1),
                 (codeunits(padded), 2, ncodeunits(text) + 1))
        return whole, spans
    end

    function check_bigfloat_sources(text, expected; rounding=nothing)
        whole, spans = source_forms(text)
        for source in whole
            actual = rounding === nothing ? Parsers.parse(BigFloat, source) :
                                             Parsers.parse(BigFloat, source; rounding)
            attempted = rounding === nothing ? Parsers.tryparse(BigFloat, source) :
                                                Parsers.tryparse(BigFloat, source; rounding)
            @test isequal(actual, expected)
            @test isequal(attempted, expected)
            @test precision(actual) == precision(expected)
        end
        for (source, first, last) in spans
            actual = rounding === nothing ? Parsers.parse(BigFloat, source, first, last) :
                                             Parsers.parse(BigFloat, source, first, last; rounding)
            attempted = rounding === nothing ? Parsers.tryparse(BigFloat, source, first, last) :
                                                Parsers.tryparse(BigFloat, source, first, last; rounding)
            @test isequal(actual, expected)
            @test isequal(attempted, expected)
            @test precision(actual) == precision(expected)
        end
    end

    # These short forms are valid in MPFR and Base but are outside the decimal
    # grammar used by the short-value optimization.
    base_forms = (
        "0.1", "-0.1", "1.5",
        "@NaN@", "@Inf@", "-@Inf@", "nan(payload)",
        "1@2", "0b1.1p2", "0b1.1@2",
        "0x1.8p2", "0x1.8@2",
        "123456789012345678901234567890",
        "3.1415926535897932384626433832795028841971e100",
        "-2.7182818284590452353602874713527e-100",
        "-0.0000000000000000000000000000000000000000",
        "-0e100000000000000000000",
        "1.2345678901234567890123456789e100000",
        "-1.2345678901234567890123456789e-100000",
        " \t3.141592653589793238462643e20",
        "3.141592653589793238462643e20 \n",
    )
    for precision_bits in (53, 256)
        setprecision(BigFloat, precision_bits) do
            for text in base_forms
                check_bigfloat_sources(text, Base.parse(BigFloat, text))
            end
        end
    end

    rounding_modes = RoundingMode[RoundNearest, RoundDown, RoundUp, RoundToZero]
    if isdefined(Base.Rounding, :RoundFromZero)
        push!(rounding_modes, getfield(Base.Rounding, :RoundFromZero))
    end
    midpoint = "1.00000000000000011102230246251565404236316680908203125"
    rounding_texts = ("0.1", "-0.1", midpoint, "-" * midpoint)
    setprecision(BigFloat, 53) do
        for rounding_mode in rounding_modes
            expected = setrounding(BigFloat, rounding_mode) do
                Base.parse.(BigFloat, rounding_texts)
            end
            setrounding(BigFloat, rounding_mode) do
                for (text, value) in zip(rounding_texts, expected)
                    check_bigfloat_sources(text, value)
                end
            end
            ambient_mode = rounding_mode == RoundDown ? RoundUp : RoundDown
            setrounding(BigFloat, ambient_mode) do
                for (text, value) in zip(rounding_texts, expected)
                    check_bigfloat_sources(text, value; rounding=rounding_mode)
                end
            end
        end
    end

    for text in ("1e", "0x1p", "1\0junk", "1@2x", "0b1.1p2x", "nan(payload)x",
                 "1.2345678901234567890123456789junk")
        whole, spans = source_forms(text)
        for source in whole
            @test Parsers.tryparse(BigFloat, source) === nothing
            @test_throws ArgumentError Parsers.parse(BigFloat, source)
        end
        for (source, first, last) in spans
            @test Parsers.tryparse(BigFloat, source, first, last) === nothing
            @test_throws ArgumentError Parsers.parse(BigFloat, source, first, last)
        end
    end

    # Configured separators retain Parsers' narrower grammar instead of
    # inheriting extra MPFR spellings from the default path.
    @test Parsers.tryparse(BigFloat, "1@2"; decimal=',') === nothing
    @test Parsers.tryparse(BigFloat, "1@2"; groupmark=',') === nothing
end

@testset "parsenext full grammar, range codes, and bounds" begin
    decimal = b("1,5;")
    @test Parsers.parsenext(Float64, decimal, 1, length(decimal); decimal=',') ==
          (1.5, 4, Parsers.RC_OK)

    grouped_int = b("1,234;")
    @test Parsers.parsenext(Int, grouped_int, 1, length(grouped_int); groupmark=',') ==
          (1234, 6, Parsers.RC_OK)
    grouped_float = b("1,234.5;")
    @test Parsers.parsenext(Float64, grouped_float, 1, length(grouped_float); groupmark=',') ==
          (1234.5, 8, Parsers.RC_OK)

    explicit_base = b("ff;")
    @test Parsers.parsenext(Int, explicit_base, 1, length(explicit_base); base=16) ==
          (255, 3, Parsers.RC_OK)
    prefixed = b("0xff;")
    @test Parsers.parsenext(Int, prefixed, 1, length(prefixed)) ==
          (255, 5, Parsers.RC_OK)
    big_prefixed = b("0x123456789abcdef0123456789;")
    @test Parsers.parsenext(BigInt, big_prefixed, 1, length(big_prefixed)) ==
          (Base.parse(BigInt, "0x123456789abcdef0123456789"), length(big_prefixed), Parsers.RC_OK)
    big_grouped = b("1,000;")
    @test Parsers.parsenext(BigInt, big_grouped, 1, length(big_grouped); groupmark=',') ==
          (BigInt(1000), 6, Parsers.RC_OK)

    custom_true = b("yes;")
    @test Parsers.parsenext(Bool, custom_true, 1, length(custom_true); trues=["yes"], falses=["no"]) ==
          (true, 4, Parsers.RC_OK)
    custom_false = b("no;")
    @test Parsers.parsenext(Bool, custom_false, 1, length(custom_false); trues=["yes"], falses=["no"]) ==
          (false, 3, Parsers.RC_OK)

    hexfloat = b("0x1.8p2,")
    @test Parsers.parsenext(Float64, hexfloat, 1, length(hexfloat)) ==
          (6.0, 8, Parsers.RC_OK)
    @test Parsers.parsenext(BigFloat, hexfloat, 1, length(hexfloat)) ==
          (BigFloat(6), 8, Parsers.RC_OK)
    bigfloat_grouped = b("1.234,5;")
    @test Parsers.parsenext(BigFloat, bigfloat_grouped, 1, length(bigfloat_grouped);
                            decimal=',', groupmark='.') ==
          (BigFloat(1234.5), 8, Parsers.RC_OK)

    int_overflow = b("128,")
    @test Parsers.parsenext(Int8, int_overflow, 1, length(int_overflow)) ==
          (Int8(0), 4, Parsers.RC_OVERFLOW)
    @test Parsers.parsenext(UInt8, b("-1"), 1, 2) ==
          (UInt8(0), 1, Parsers.RC_INVALID)
    @test Parsers.parsenext(Float64, b("ix"), 1, 2) ==
          (0.0, 1, Parsers.RC_INVALID)
    @test Parsers.parsenext(Bool, b("xyz"), 1, 3) ==
          (false, 1, Parsers.RC_INVALID)
    uint_overflow = b("18446744073709551616,")
    @test Parsers.parsenext(UInt64, uint_overflow, 1, length(uint_overflow)) ==
          (UInt64(0), 21, Parsers.RC_OVERFLOW)

    float16_overflow = b("1e5,")
    value, nextpos, code = Parsers.parsenext(Float16, float16_overflow, 1, length(float16_overflow))
    @test isinf(value) && value > 0
    @test nextpos == 4
    @test code == Parsers.RC_OVERFLOW
    float16_underflow = b("1e-20,")
    value, nextpos, code = Parsers.parsenext(Float16, float16_underflow, 1, length(float16_underflow))
    @test value === Float16(0.0)
    @test nextpos == 6
    @test code == Parsers.RC_UNDERFLOW

    bigfloat_range = b("1e70000,")
    kernel_value, kernel_code = Parsers.parsebigfloat(bigfloat_range, 1, 7)
    @test kernel_code == Parsers.RC_OVERFLOW
    value, nextpos, code = Parsers.parsenext(BigFloat, bigfloat_range, 1, length(bigfloat_range))
    @test isequal(value, kernel_value)
    @test nextpos == 8
    @test code == kernel_code

    bounds_source = b("123")
    for (pos, last) in ((0, 3), (-1, 3), (1, 4), (4, 4), (1, 0), (1, -1))
        @test_throws BoundsError Parsers.parsenext(Int, bounds_source, pos, last)
    end
    huge = big(typemax(Int)) + 1
    @test_throws BoundsError Parsers.parsenext(Int, bounds_source, huge, huge)
    @test_throws BoundsError Parsers.parsenext(Int, bounds_source, -huge, 3)
    @test Parsers.parsenext(Int, bounds_source, 4, 3) ==
          (0, 4, Parsers.RC_INVALID)
    @test Parsers.parsenext(Int, UInt8[], 1, 0) ==
          (0, 1, Parsers.RC_INVALID)

    # Run the same invalid ranges with compiler-inserted bounds checks disabled.
    # This catches an unsafe @inbounds scan if the public guard is removed.
    no_bounds_code = """
    using Parsers
    source = UInt8[0x31, 0x32, 0x33]
    for (pos, last) in ((0, 3), (-1, 3), (1, 4), (4, 4), (1, 0), (1, -1))
        threw = false
        try
            Parsers.parsenext(Int, source, pos, last)
        catch err
            err isa BoundsError || rethrow()
            threw = true
        end
        threw || error("parsenext accepted out-of-bounds range (\$pos, \$last)")
    end
    Parsers.parsenext(Int, source, 4, 3) == (0, 4, Parsers.RC_INVALID) ||
        error("valid empty end range changed")
    Parsers.parsenext(Int, UInt8[], 1, 0) == (0, 1, Parsers.RC_INVALID) ||
        error("empty source range changed")
    """
    cmd = `$(Base.julia_cmd()) --startup-file=no --check-bounds=no -e $no_bounds_code`
    @test success(cmd)
end

@testset "small deterministic public differential fuzz" begin
    rng = MersenneTwister(REGRESSION_FUZZ_SEED)
    checks = Ref(0)
    failures = String[]
    function record(condition::Bool, description::String)
        checks[] += 1
        if !condition && length(failures) < 10
            push!(failures, description)
        end
        return nothing
    end

    integer_types = (Int8, Int16, Int32, Int64, Int128,
                     UInt8, UInt16, UInt32, UInt64, UInt128)
    for T in integer_types, _ in 1:64
        value = rand(rng, T)
        text = string(value)
        padded = "!" * text * ";"
        substring = SubString(padded, 2, ncodeunits(text) + 1)
        vector = Vector{UInt8}(codeunits(text))
        sources = (text, vector, codeunits(text), substring, view(vector, eachindex(vector)))
        for source in sources
            record(Parsers.parse(T, source) == value,
                   "parse source mismatch for $T and $(repr(text))")
            record(Parsers.tryparse(T, source) == value,
                   "tryparse source mismatch for $T and $(repr(text))")
        end

        wrapped = UInt8[0xff; codeunits(text); 0xfe]
        record(Parsers.parse(T, wrapped, 2, ncodeunits(text) + 1) == value,
               "offset mismatch for $T and $(repr(text))")
        record(Parsers.tryparse(T, wrapped) === nothing,
               "invalid UTF-8 whole source accepted for $T and $(repr(text))")
    end

    for (T, U) in ((Float16, UInt16), (Float32, UInt32), (Float64, UInt64)), _ in 1:256
        value = reinterpret(T, rand(rng, U))
        isfinite(value) || continue
        text = string(value)
        vector = Vector{UInt8}(codeunits(text))
        padded = "!" * text * ";"
        sources = (text, vector, codeunits(text),
                   SubString(padded, 2, ncodeunits(text) + 1),
                   view(vector, eachindex(vector)))
        for source in sources
            record(isequal(Parsers.parse(T, source), value),
                   "float parse source mismatch for $T and $(repr(text))")
            record(isequal(Parsers.tryparse(T, source), value),
                   "float tryparse source mismatch for $T and $(repr(text))")
        end
    end

    for _ in 1:500
        sign = rand(rng, Bool) ? "-" : ""
        text = sign * string(rand(rng, 0:999_999)) * "." *
               lpad(string(rand(rng, 0:999_999)), 6, '0') * "e" * string(rand(rng, -40:40))
        for T in (Float16, Float32, Float64)
            record(isequal(Parsers.tryparse(T, text), Base.tryparse(T, text)),
                   "decimal differential mismatch for $T and $(repr(text))")
        end
    end

    for _ in 1:256
        value = rand(rng, Int64)
        text = string(value)
        source = Vector{UInt8}(codeunits(text * ","))
        record(Parsers.parsenext(Int64, source, 1, length(source)) ==
               (value, ncodeunits(text) + 1, Parsers.RC_OK),
               "parsenext mismatch for $(repr(text))")
    end

    isempty(failures) || @info "deterministic fuzz failures" failures
    @info "deterministic regression fuzz" seed=string(REGRESSION_FUZZ_SEED) checks=checks[]
    @test isempty(failures)
end
