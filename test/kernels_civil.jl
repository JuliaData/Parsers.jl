# Adapted from CSV.jl's kernel value-layer differentials (kernel/test_values.jl):
# Base.parse / Dates are the ORACLES here — every kernel must agree bit-for-bit
# with the oracle on the accept-set; deliberate deltas are pinned explicitly.
using Test, Random, Dates, Parsers

const _ISO_DATE_ORACLE_FORMAT = DateFormat("yyyy-mm-dd")
const _ISO_DATETIME_ORACLE_FORMAT = DateFormat("yyyy-mm-ddTHH:MM:SS")
const _ISO_TIME_ORACLE_FORMAT = DateFormat("HH:MM:SS")

@testset "civil: daysfromcivil vs Dates oracle" begin
    for y in (-4000, -1900, -400, -100, -4, -1, 0,
              1, 100, 1583, 1600, 1900, 1970, 2000, 2020, 2024, 2100, 2400, 9999)
        for m in 1:12, d in (1, 15, 28)
            @test Parsers.daysfromcivil(y, m, d) == Dates.value(Date(y, m, d))
        end
    end
    # every day of four millennia (single aggregated assertion — 1.46M days)
    okall = true
    for y in -1000:3000, m in 1:12, d in 1:Dates.daysinmonth(y, m)
        okall &= Parsers.daysfromcivil(y, m, d) == Dates.value(Date(y, m, d))
    end
    @test okall
    # extremes and negative eras
    for (y, m, d) in ((-100_000, 1, 1), (275_760, 9, 13),
                      (typemax(Int64), 1, 1), (typemin(Int64), 1, 1))
        @test Parsers.daysfromcivil(y, m, d) == Dates.value(Date(y, m, d))
    end
end

@testset "civil: ISO patterns" begin
    c, rc = Parsers.parsecivil(b("2024-02-29"), 1, 10, Parsers.ISO_DATE)
    @test rc == Parsers.RC_OK && todate(c) == Date(2024, 2, 29)
    @test Parsers.parsecivil(b("2023-02-29"), 1, 10, Parsers.ISO_DATE)[2] == Parsers.RC_INVALID  # not a leap year
    @test Parsers.parsecivil(b("2024-13-01"), 1, 10, Parsers.ISO_DATE)[2] == Parsers.RC_INVALID
    @test Parsers.parsecivil(b("2024-00-01"), 1, 10, Parsers.ISO_DATE)[2] == Parsers.RC_INVALID
    c, rc = Parsers.parsecivil(b("24-01-01"), 1, 8, Parsers.ISO_DATE)          # greedy year, as Dates
    @test rc == Parsers.RC_OK && todate(c) == Date(24, 1, 1)
    s = "2024-01-02T03:04:05"
    c, rc = Parsers.parsecivil(b(s), 1, ncodeunits(s), Parsers.ISO_DATETIME)
    @test rc == Parsers.RC_OK && todatetime(c) == DateTime(2024, 1, 2, 3, 4, 5)
    s = "2024-01-02T03:04:05.125"
    c, rc = Parsers.parsecivil(b(s), 1, ncodeunits(s), Parsers.ISO_DATETIME)
    @test rc == Parsers.RC_OK && todatetime(c) == DateTime(2024, 1, 2, 3, 4, 5, 125)
    s = "10:30:00"
    c, rc = Parsers.parsecivil(b(s), 1, 8, Parsers.ISO_TIME)
    @test rc == Parsers.RC_OK && totime(c) == Time(10, 30)
    s = "10:30:00.000000001"
    c, rc = Parsers.parsecivil(b(s), 1, ncodeunits(s), Parsers.ISO_TIME)
    @test rc == Parsers.RC_OK && totime(c) == Time(10, 30, 0) + Nanosecond(1)
    @test Parsers.parsecivil(b("25:00:00"), 1, 8, Parsers.ISO_TIME)[2] == Parsers.RC_INVALID
    @test Parsers.parsecivil(b("23:60:00"), 1, 8, Parsers.ISO_TIME)[2] == Parsers.RC_INVALID
    @test Parsers.parsecivil(b("23:59:60"), 1, 8, Parsers.ISO_TIME)[2] == Parsers.RC_INVALID
    @test Parsers.parsecivil(b("23:59:59.1234567890"), 1, 19, Parsers.ISO_TIME)[2] == Parsers.RC_INVALID
    # whole-span rule
    @test Parsers.parsecivil(b("2024-01-02x"), 1, 11, Parsers.ISO_DATE)[2] == Parsers.RC_INVALID
end

@testset "civil: fixed-width ISO fast-path differential" begin
    # An accepted accelerator input must agree with Dates, which is independent
    # of both the accelerator and the compiled-plan fallback. Copy before the
    # String conversion because String(::Vector{UInt8}) takes its input buffer.
    function checkdate(bytes)
        for pad in (0, 1, 7)
            buf = vcat(fill(UInt8(0xa5), pad), bytes, fill(UInt8(0x5a), 8))
            civil, code = Parsers.parseiso10(buf, pad + 1)
            if code == Parsers.RC_OK
                expected = tryparse(Date, String(copy(bytes)),
                                    _ISO_DATE_ORACLE_FORMAT)
                @test expected !== nothing
                @test todate(civil) == expected
            end
        end
    end
    function checkdatetime(bytes)
        for pad in (0, 1, 7)
            buf = vcat(fill(UInt8(0xa5), pad), bytes, fill(UInt8(0x5a), 8))
            civil, code = Parsers.parseiso19(buf, pad + 1)
            if code == Parsers.RC_OK
                expected = tryparse(DateTime, String(copy(bytes)),
                                    _ISO_DATETIME_ORACLE_FORMAT)
                @test expected !== nothing
                @test todatetime(civil) == expected
            end
        end
    end
    function checktime(bytes)
        for pad in (0, 1, 7)
            buf = vcat(fill(UInt8(0xa5), pad), bytes, fill(UInt8(0x5a), 8))
            civil, code = Parsers.parseiso8(buf, pad + 1)
            if code == Parsers.RC_OK
                expected = tryparse(Time, String(copy(bytes)),
                                    _ISO_TIME_ORACLE_FORMAT)
                @test expected !== nothing
                @test totime(civil) == expected
            end
        end
    end

    for s in ("0000-01-01", "9999-12-31", "2000-02-29", "1900-02-29",
              "2400-02-29", "2020-1-01x", "2020/01-01", "2020-01/01")
        checkdate(b(s))
    end
    for s in ("2024-01-02T03:04:05", "2024-01-02 03:04:05",
              "2024-01-02t03:04:05", "1900-02-29T03:04:05")
        checkdatetime(b(s))
    end
    for s in ("00:00:00", "23:59:59", "24:00:00")
        checktime(b(s))
    end
    c, rc = Parsers.parseiso8(b("03:04:05"), 1)
    @test (c, rc) == (Parsers.CivilParts(1, 1, 1, 3, 4, 5, 0), Parsers.RC_OK)

    # Every one-byte mutation checks separators and every possible byte at each
    # digit position. This includes the UInt8-underflow cases '/' and 0xff.
    datebytes = b("2024-02-29")
    for pos in eachindex(datebytes), byte in UInt8(0):UInt8(255)
        bytes = copy(datebytes)
        bytes[pos] = byte
        checkdate(bytes)
    end
    datetimebytes = b("2024-02-29T23:59:59")
    for pos in eachindex(datetimebytes), byte in UInt8(0):UInt8(255)
        bytes = copy(datetimebytes)
        bytes[pos] = byte
        checkdatetime(bytes)
    end
    timebytes = b("23:59:59")
    for pos in eachindex(timebytes), byte in UInt8(0):UInt8(255)
        bytes = copy(timebytes)
        bytes[pos] = byte
        checktime(bytes)
    end

    rng = MersenneTwister(0x15)
    for _ in 1:10_000
        checkdate(rand(rng, UInt8, 10))
    end
    for _ in 1:10_000
        checkdatetime(rand(rng, UInt8, 19))
    end
    for _ in 1:10_000
        checktime(rand(rng, UInt8, 8))
    end
end

@testset "civil: fixed numeric DatePattern valid and invalid inputs" begin
    pattern = Parsers.compilepattern("yyyymmddHHMMSS")
    @test !ismutable(pattern)

    source = b("xx20240229235958yy")
    civil, code = Parsers.parsecivil(source, 3, 16, pattern)
    expected = DateTime(2024, 2, 29, 23, 59, 58)
    @test code == Parsers.RC_OK
    @test todatetime(civil) == expected
    @test Parsers.parse(DateTime, "20240229235958"; dateformat=pattern) == expected

    # The natural three-digit spelling takes the fixed executor. Other valid
    # widths fall through to the same plan's interpreter, as Dates requires.
    fractional_pattern = Parsers.compilepattern(DateFormat("yyyymmddHHMMSSsss"))
    fractional, code = Parsers.parsecivil(b("20240229235958123"), 1, 17,
                                           fractional_pattern)
    @test code == Parsers.RC_OK
    @test fractional.nanosecond == 123_000_000
    @test Parsers.parse(DateTime, "20240229235958123";
                        dateformat=fractional_pattern) == expected + Millisecond(123)
    @test Parsers.parsecivil(b("2024022923595812x"), 1, 17,
                              fractional_pattern)[2] == Parsers.RC_INVALID
    fractional, code = Parsers.parsecivil(b("2024022923595812"), 1, 16,
                                           fractional_pattern)
    @test code == Parsers.RC_OK && fractional.nanosecond == 120_000_000
    fractional, code = Parsers.parsecivil(b("202402292359581234"), 1, 18,
                                           fractional_pattern)
    @test code == Parsers.RC_OK && fractional.nanosecond == 123_400_000

    for text in (
        "20230229235958", # invalid leap day
        "20241301235958", # month
        "20240230235958", # day
        "20240229245958", # hour
        "20240229236058", # minute
        "20240229235960", # second
        "2024022x235958", # non-digit in a numeric field
        "202402292359580", # long span: the trailing greedy field reads 580 seconds
    )
        @test Parsers.parsecivil(b(text), 1, ncodeunits(text), pattern)[2] ==
              Parsers.RC_INVALID
        @test Parsers.tryparse(DateTime, text; dateformat=pattern) === nothing
    end
    # the last field is greedy, as in Dates: a short span reads five seconds
    @test Parsers.parse(DateTime, "2024022923595"; dateformat=pattern) ==
          DateTime("2024022923595", DateFormat("yyyymmddHHMMSS")) == DateTime(2024, 2, 29, 23, 59, 5)
end

@testset "civil: custom patterns (the kernel's test formats)" begin
    p = Parsers.compilepattern("yyyymmdd")
    c, rc = Parsers.parsecivil(b("20240102"), 1, 8, p)
    @test rc == Parsers.RC_OK && todate(c) == Date(2024, 1, 2)
    p = Parsers.compilepattern("dd/mm/yyyy")
    c, rc = Parsers.parsecivil(b("15/01/2023"), 1, 10, p)
    @test rc == Parsers.RC_OK && todate(c) == Date(2023, 1, 15)
    expected = Date(2023, 1, 15)
    text = "15/01/2023"
    padded = b("<$text>")
    for source in (text, codeunits(text), b(text), SubString("<$text>", 2, 11),
                   @view(padded[2:11]))
        @test Parsers.parse(Date, source; dateformat=p) == expected
        @test Parsers.tryparse(Date, source; dateformat=p) == expected
    end
    @test Parsers.parse(Date, padded, 2, 11; dateformat=p) == expected
    @test Parsers.tryparse(Date, padded, 2, 11; dateformat=p) == expected
    p = Parsers.compilepattern("u dd yyyy")
    c, rc = Parsers.parsecivil(b("Jan 02 2024"), 1, 11, p)
    @test rc == Parsers.RC_OK && todate(c) == Date(2024, 1, 2)
    c, rc = Parsers.parsecivil(b("jul 04 1776"), 1, 11, p)
    @test rc == Parsers.RC_OK && todate(c) == Date(1776, 7, 4)
    for (month, name) in enumerate(Parsers.ENGLISH_MONTHS_ABBR)
        text = string(uppercase(name), " 02 2024")
        c, rc = Parsers.parsecivil(b(text), 1, ncodeunits(text), p)
        @test rc == Parsers.RC_OK && todate(c) == Date(2024, month, 2)
    end
    @test Parsers.parsecivil(b("Foo 02 2024"), 1, 11, p)[2] == Parsers.RC_INVALID
    literal_pattern = Parsers.compilepattern("yyyy-Qq")
    c, rc = Parsers.parsecivil(b("2024-Qq"), 1, 7, literal_pattern)
    @test rc == Parsers.RC_OK && todate(c) == Date(2024, 1, 1)
    # 12-hour clock, AM/PM, and day names — Dates parity (adjusthour + the
    # 1..12 rule when AM/PM is present; day names validated, value ignored)
    let rng = MersenneTwister(4), okall = true
        for (f, T) in (("yyyy-mm-dd I:MM p", DateTime), ("I:MM:SS p", Time),
                       ("e, dd u yyyy", Date), ("E dd U yyyy HH:MM", DateTime),
                       ("II:MM p", Time), ("e yyyy-mm-dd", Date), ("I p", Time))
            p = Parsers.compilepattern(f); df = DateFormat(f)
            for _ in 1:3_000
                dt = DateTime(rand(rng, 1900:2100), rand(rng, 1:12), rand(rng, 1:28),
                              rand(rng, 0:23), rand(rng, 0:59), rand(rng, 0:59))
                x = T === Date ? Date(dt) : T === Time ? Time(dt) : dt
                s = Dates.format(x, df)
                s = rand(rng, Bool) ? s : replace(replace(s, "AM" => "am"), "PM" => "pm")
                c, rc = Parsers.parsecivil(b(s), 1, ncodeunits(s), p)
                v = rc == Parsers.RC_OK ? (T === Date ? todate(c) : T === Time ? totime(c) : todatetime(c)) : nothing
                okall &= v == T(s, df)
            end
        end
        @test okall
        for (f, s, ok) in (("I p", "12 AM", true), ("I p", "12 PM", true), ("I p", "13 PM", false),
                           ("I p", "0 am", false), ("HH p", "23 pm", false), ("e", "Mon", true),
                           ("e", "mon", true), ("E", "Monday", true), ("E", "Mon", false),
                           ("e", "Foo", false), ("I p", "1 xm", false), ("I p", "1 a", false))
            p = Parsers.compilepattern(f)
            @test (Parsers.parsecivil(b(s), 1, ncodeunits(s), p)[2] == Parsers.RC_OK) == ok
        end
        c, _ = Parsers.parsecivil(b("12 AM"), 1, 5, Parsers.compilepattern("I p")); @test c.hour == 0
        c, _ = Parsers.parsecivil(b("12 PM"), 1, 5, Parsers.compilepattern("I p")); @test c.hour == 12
        c, _ = Parsers.parsecivil(b("7 pm"), 1, 4, Parsers.compilepattern("I p")); @test c.hour == 19
        # A day name is validated but does not alter the default civil value.
        c, rc = Parsers.parsecivil(b("Mon"), 1, 3, Parsers.compilepattern("e"))
        @test rc == Parsers.RC_OK && c == Parsers.CivilParts()
    end
    # Greedy fields use a width sentinel. Extended bytecode widths preserve
    # fixed DateFormat runs above 255 characters.
    @test Parsers.compilepattern("y"^256 * "-mm-dd") isa Parsers.DatePattern
    widefixed = Parsers.compilepattern("y"^256 * "m")
    widevalue = b("0"^255 * "11")
    cfixed, rcfixed = Parsers.parsecivil(widevalue, 1, length(widevalue), widefixed)
    @test rcfixed == Parsers.RC_OK && cfixed == Parsers.CivilParts()
    # Large year fields keep the full Int64 Dates input range.
    pwide = Parsers.compilepattern("yyyyyyyyyy")
    cwide, rcwide = Parsers.parsecivil(b("9999999999"), 1, 10, pwide)
    @test rcwide == Parsers.RC_OK && cwide.year == 9_999_999_999
    phuge = Parsers.compilepattern("y"^19)
    @test Parsers.parsecivil(b("9999999999999999999"), 1, 19, phuge)[2] == Parsers.RC_INVALID
    # differential against Dates for a spread of dates and formats
    for (fmt, dfmt) in (("yyyy-mm-dd", dateformat"yyyy-mm-dd"),
                        ("dd/mm/yyyy", dateformat"dd/mm/yyyy"),
                        ("yyyymmdd", dateformat"yyyymmdd"))
        p = Parsers.compilepattern(fmt)
        dt = Date(1980, 1, 1)
        while dt < Date(2040, 1, 1)
            s = Dates.format(dt, dfmt)
            c, rc = Parsers.parsecivil(b(s), 1, ncodeunits(s), p)
            @test rc == Parsers.RC_OK && todate(c) == dt
            dt += Day(97)
        end
    end
end

@testset "civil: compiled numeric-delimited date executor" begin
    cases = (("y/m/d", "24/2/9"), ("y/d/m", "24/9/2"),
             ("m/y/d", "2/24/9"), ("m/d/y", "2/9/24"),
             ("d/y/m", "9/24/2"), ("d/m/y", "9/2/24"))
    for (format, text) in cases
        pattern = Parsers.compilepattern(format)
        @test pattern._storage.plan.executor == Parsers._EXECUTE_NUMERIC_DATE
        bytes = b(text)
        padded = [0xff; bytes; 0xfe]
        for source in (text, codeunits(text), bytes, @view(padded[2:end-1]))
            @test Parsers.parse(Date, source; dateformat=pattern) == Date(24, 2, 9)
        end
        @test Parsers.parse(Date, padded, 2, length(bytes) + 1;
                            dateformat=pattern) == Date(24, 2, 9)
        fast = Parsers.parsecivil(bytes, 1, length(bytes), pattern)
        interpreted = Parsers._interpretcivil(bytes, 1, length(bytes), pattern._storage,
                                               pattern._storage.plan.flags)
        @test fast == interpreted
    end

    pattern = Parsers.compilepattern("y/m/d")
    for text in ("2024/02/29", "+24/2/9", "-24/2/9",
                 "000000000000000000000024/0002/0009",
                 "-9223372036854775808/1/1", "9223372036854775807/1/1",
                 "", "24-2-9", "24/2/9x", "24/13/1", "2023/2/29",
                 "9223372036854775808/1/1")
        bytes = b(text)
        fast = Parsers.parsecivil(bytes, 1, length(bytes), pattern)
        interpreted = Parsers._interpretcivil(bytes, 1, length(bytes), pattern._storage,
                                               pattern._storage.plan.flags)
        @test fast == interpreted
    end
    wide_natural = Parsers.compilepattern("y"^33 * "/m/d")
    @test Parsers.parsecivil(UInt8[], 1, 0, wide_natural)[2] == Parsers.RC_INVALID
end

@testset "civil: ISO fraction fast paths agree with Dates" begin
    datetimewhole = DateFormat("yyyy-mm-ddTHH:MM:SS")
    timewhole = DateFormat("HH:MM:SS")

    function fractionoracle(::Type{T}, bytes) where {T}
        datetime = T === DateTime
        wholeend = datetime ? 19 : 8
        point = wholeend + 1
        point < length(bytes) && bytes[point] == UInt8('.') || return nothing
        whole = tryparse(T, String(bytes[1:wholeend]),
                         datetime ? datetimewhole : timewhole)
        whole === nothing && return nothing
        fraction = tryparse(Int, String(bytes[point + 1:end]))
        fraction === nothing && return nothing
        ndigits = length(bytes) - point
        1 <= ndigits <= 9 || return nothing
        nanoseconds = fraction * Int(10)^(9 - ndigits)
        return datetime ? whole + Millisecond(nanoseconds ÷ 1_000_000) :
                          whole + Nanosecond(nanoseconds)
    end

    function checkfrac(fast::F, convert::C, ::Type{T},
                       bytes::B) where {F, C, T, B}
        for pad in (0, 1, 7)
            buf = vcat(fill(UInt8(0xa5), pad), bytes, fill(UInt8(0x5a), 8))
            i = pad + 1
            j = i + length(bytes) - 1
            civil, code = fast(buf, i, j)
            if code == Parsers.RC_OK
                expected = fractionoracle(T, bytes)
                @test expected !== nothing
                @test convert(civil) == expected
            end
        end
    end
    for s in ("2024-02-29T23:59:59.1", "2024-02-29T23:59:59.12", "2024-02-29T23:59:59.123",
              "2024-02-29T23:59:59.123456789", "2024-02-29T23:59:59.", "2024-02-29T23:59:59.x",
              "2024-02-29T23:59:59:123", "2024-02-29 23:59:59.123", "2023-02-29T23:59:59.123",
              "2024-02-29T24:00:00.123", "2024-02-29T23:59:59.1234567890")
        checkfrac(Parsers.parseiso19frac, todatetime, DateTime, b(s))
    end
    for s in ("23:59:59.7", "23:59:59.789", "23:59:59.789012345", "23:59:59.", "24:00:00.1",
              "23:59:59x1", "23:59:59.1234567890")
        checkfrac(Parsers.parseiso8frac, totime, Time, b(s))
    end
    for (fast, convert, T, base) in (
        (Parsers.parseiso19frac, todatetime, DateTime,
         b("2024-02-29T23:59:59.125")),
        (Parsers.parseiso8frac, totime, Time, b("23:59:59.125")),
    )
        for pos in eachindex(base), byte in UInt8(0):UInt8(255)
            bytes = copy(base)
            bytes[pos] = byte
            checkfrac(fast, convert, T, bytes)
        end
    end
    @test Parsers.parse(DateTime, "2024-02-29T23:59:59.125") == DateTime(2024, 2, 29, 23, 59, 59, 125)
    @test Parsers.parse(DateTime, "2024-02-29T23:59:59.1") == DateTime(2024, 2, 29, 23, 59, 59, 100)
    @test Parsers.tryparse(DateTime, "2024-02-29T23:59:59.") === nothing
    @test Parsers.parse(Time, "23:59:59.125") == Time(23, 59, 59, 125)
    @test Parsers.parse(Time, "23:59:59.000000001") == Time(23, 59, 59) + Nanosecond(1)
end

@testset "civil: compiled plans own execution and caching" begin
    invariant_pattern = Parsers.compilepattern("mm/dd/yyyy")
    invariant_plan = getfield(getfield(invariant_pattern, :_storage), :plan)
    @test !ismutable(invariant_pattern)
    @test !ismutable(invariant_plan)
    @test !ismutable(getfield(invariant_plan, :ops))
    @test sizeof(typeof(invariant_pattern)) == sizeof(Ptr{Cvoid})
    cached_string = Parsers._datepattern("mm/dd/yyyy", Date)
    cached_substring = Parsers._datepattern(SubString("xmm/dd/yyyy", 2), Date)
    @test getfield(cached_string, :_storage) ===
          getfield(Parsers._datepattern("mm/dd/yyyy", Date), :_storage) ===
          getfield(cached_substring, :_storage)
    cached_format = DateFormat("mm/dd/yyyy")
    @test getfield(Parsers._datepattern(cached_format, Date), :_storage) ===
          getfield(Parsers._datepattern(cached_format, Date), :_storage)
    threaded_patterns = Vector{typeof(invariant_pattern)}(undef, 64)
    Threads.@threads for i in eachindex(threaded_patterns)
        threaded_patterns[i] =
            Parsers._datepattern("yyyy/mm/dd HH:MM:SS.s", DateTime)
    end
    threaded_storage = getfield(first(threaded_patterns), :_storage)
    @test all(pattern -> getfield(pattern, :_storage) === threaded_storage,
              threaded_patterns)

    longformat = "yyyy" * repeat("-", 20) * "mm-dd"
    longtext = "24" * repeat("-", 20) * "2-29"
    longpattern = Parsers.compilepattern(longformat)
    longplan = getfield(getfield(longpattern, :_storage), :plan)
    @test ncodeunits(getfield(getfield(longplan, :ops), :code)) > 32
    @test Parsers.parse(Date, longtext; dateformat=longpattern) ==
          Date(longtext, DateFormat(longformat)) == Date(24, 2, 29)

    for (f, T) in (("mm/dd/yyyy", Date), ("yyyy-mm-dd HH:MM:SS", DateTime), ("dd.mm.yy", Date),
                   ("HH:MM", Time), ("yyyymmdd", Date), ("yyyy-mm-ddTHH:MM:SS.sss", DateTime))
        df = DateFormat(f)
        pat = Parsers.compilepattern(df)
        @test !ismutable(pat)
        rng = MersenneTwister(7)
        okall = true
        for _ in 1:2_000
            dt = DateTime(rand(rng, 1:2100), rand(rng, 1:12), rand(rng, 1:28),
                          rand(rng, 0:23), rand(rng, 0:59), rand(rng, 0:59), rand(rng, 0:999))
            x = T === Date ? Date(dt) : T === Time ? Time(dt) : dt
            s = Dates.format(x, df)
            bytes = b(s)
            civil, rc = Parsers.parsecivil(bytes, 1, length(bytes), pat)
            value = rc == Parsers.RC_OK ?
                    (T === Date ? todate(civil) : T === Time ? totime(civil) : todatetime(civil)) :
                    nothing
            okall &= value == T(s, df)
            okall &= Parsers.parse(T, s; dateformat=df) == T(s, df)
        end
        @test okall
    end
    # Dates' variable widths still apply through the compiled numeric executor.
    df = DateFormat("mm/dd/yyyy")
    @test Parsers.parse(Date, "3/14/2021"; dateformat=df) == Date(2021, 3, 14)
    @test Parsers.parse(Date, "03/14/02021"; dateformat=df) == Date(2021, 3, 14)
    @test Parsers.parse(Date, "03/14/2021"; dateformat=df) == Date(2021, 3, 14)
    # at most a boxed return on Julia 1.10; a per-call compile allocates over a KiB
    parsedateformat("03/14/2021", df)
    @test @allocated(parsedateformat("03/14/2021", df)) <= 16
    parsedateformat("03/14/2021", "mm/dd/yyyy")
    @test @allocated(parsedateformat("03/14/2021", "mm/dd/yyyy")) <= 16
    # other locales compile through the cache and keep their names
    months = ["Alfa", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot",
              "Golf", "Hotel", "India", "Juliett", "Kilo", "Lima"]
    months_abbr = ["Ab", "Bc", "Cd", "De", "Ef", "Fg",
                   "Gh", "Hi", "Ij", "Jk", "Kl", "Lm"]
    weekdays = ["Mondayx", "Tuesdayx", "Wednesdayx", "Thursdayx",
                "Fridayx", "Saturdayx", "Sundayx"]
    weekdays_abbr = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    locale = Dates.DateLocale(months, months_abbr, weekdays, weekdays_abbr)
    localized = DateFormat("U dd yyyy", locale)
    @test Dates.tryparse(Date, "Bravo 29 2024", localized) == Date(2024, 2, 29)
    @test Parsers.parse(Date, "Bravo 29 2024"; dateformat=localized) == Date(2024, 2, 29)
    @test getfield(Parsers._datepattern(localized, Date), :_storage) ===
          getfield(Parsers._datepattern(localized, Date), :_storage)
    parsedateformat("Bravo 29 2024", localized)
    @test @allocated(parsedateformat("Bravo 29 2024", localized)) <= 16
    localized_pattern = Parsers.compilepattern(localized)
    parsedateformat("Bravo 29 2024", localized_pattern)
    @test @allocated(parsedateformat("Bravo 29 2024", localized_pattern)) <= 16

    unicode_months = copy(months)
    unicode_months[2] = "Février"
    unicode_locale = Dates.DateLocale(unicode_months, months_abbr, weekdays,
                                      weekdays_abbr)
    unicode_format = DateFormat("U dd yyyy", unicode_locale)
    @test Parsers.parse(Date, "FÉVRIER 29 2024"; dateformat=unicode_format) ==
          Date(2024, 2, 29)
    unicode_pattern = Parsers.compilepattern(unicode_format)
    parsedateformat("février 29 2024", unicode_pattern)
    @test @allocated(parsedateformat("février 29 2024", unicode_pattern)) <= 16

    # Numeric formats do not retain or key on unused locale name tables.
    numeric_a = DateFormat("yyyy/mm/dd", locale)
    numeric_b = DateFormat("yyyy/mm/dd", unicode_locale)
    numeric_plan_a = Parsers._datepattern(numeric_a, Date)
    numeric_plan_b = Parsers._datepattern(numeric_b, Date)
    @test getfield(numeric_plan_a, :_storage) ===
          getfield(numeric_plan_b, :_storage)

    # A full locale-sensitive bucket replaces an old entry. The active value
    # therefore reaches a stable cached plan instead of recompiling forever.
    newest_localized = localized
    for index in 1:10
        variant_months = copy(months)
        variant_months[2] = "Bravo$index"
        variant_locale = Dates.DateLocale(variant_months, months_abbr, weekdays,
                                          weekdays_abbr)
        newest_localized = DateFormat("U dd yyyy", variant_locale)
        Parsers._datepattern(newest_localized, Date)
    end
    newest_plan_a = Parsers._datepattern(newest_localized, Date)
    newest_plan_b = Parsers._datepattern(newest_localized, Date)
    @test getfield(newest_plan_a, :_storage) === getfield(newest_plan_b, :_storage)

    # The bounded String cache also replaces an old entry after saturation.
    for index in 1:(Parsers._PATTERNCACHEMAX + 2)
        Parsers._cachedpattern(repeat("!", index) * string(index))
    end
    active_format = "!987654321!"
    active_plan_a = Parsers._cachedpattern(active_format)
    active_plan_b = Parsers._cachedpattern(active_format)
    @test getfield(active_plan_a, :_storage) === getfield(active_plan_b, :_storage)
end

@testset "civil: the fixed fast path accepts every valid field value" begin
    # a bitwise OR of digits can exceed 9 (2 | 9 == 11), so each digit is range-checked alone
    for (f, T) in (("mm/dd/yyyy", Date), ("yyyy-mm-dd HH:MM:SS", DateTime), ("HH:MM:SS", Time))
        pat = Parsers.compilepattern(DateFormat(f))
        okall = true
        dt = DateTime(2023, 1, 1)
        while dt < DateTime(2025, 1, 1)
            x = T === Date ? Date(dt) : T === Time ? Time(dt) : dt
            s = Dates.format(x, f)
            c, rc = Parsers.parsecivil(b(s), 1, ncodeunits(s), pat)
            okall &= rc == Parsers.RC_OK && (T === Date ? todate(c) == x : T === Time ? totime(c) == x : todatetime(c) == x)
            dt += T === Time ? Second(7919) : Hour(13) + Minute(29) + Second(49)
        end
        @test okall
    end
    # Every digit is checked independently. Bitwise combinations such as
    # 2 | 9 must not make an invalid field look numeric.
    for s in ("29/01/2024", "49/01/2024", "58/01/2024", "69/01/2024", "99/01/2024",
              "01/49/2024", "01/58/2024", "01/69/2024", "01/99/2024")
        @test Parsers.tryparse(Date, s; dateformat="mm/dd/yyyy") === nothing
    end
    @test Parsers.tryparse(Date, "2x/01/2024"; dateformat="mm/dd/yyyy") === nothing
    @test Parsers.tryparse(Date, "/9/01/2024"; dateformat="mm/dd/yyyy") === nothing
end

@testset "civil: format-string and DateFormat adapters have the same behavior" begin
    cases = (("mm/dd/yyyy", Date, Date(2024, 2, 29)),
             ("yyyymmdd", Date, Date(2024, 2, 29)),
             ("yyyy-mm-dd HH:MM:SS", DateTime, DateTime(2024, 2, 29, 13, 14, 15)),
             ("HH:MM:SS.s", Time, Time(13, 14, 15, 123)),
             ("yyyy\\mdd", Date, Date(2024, 2, 29)),
             ("u dd yyyy", Date, Date(2024, 2, 29)),
             ("I:MM p", Time, Time(13, 14)),
             ("dd.mm.yy", Date, Date(24, 2, 29)),
             ("y/m/d", Date, Date(2024, 2, 29)),
             ("yyyy-mm-ddTHH:MM:SS.sss", DateTime, DateTime(2024, 2, 29, 13, 14, 15, 123)),
             ("yyyyyymmdd", Date, Date(2024, 2, 29)),
             ("e, dd u yyyy", Date, Date(2024, 2, 29)),
             ("yyyy年mm月dd日", Date, Date(2024, 2, 29)),
             ("yyyy--mm--dd", Date, Date(2024, 2, 29)))
    for (f, T, value) in cases
        df = DateFormat(f)
        s = Dates.format(value, df)
        expected = T(s, df)
        a = Parsers.compilepattern(f)
        d = Parsers.compilepattern(df)
        @test Parsers.parse(T, s; dateformat=a) == expected
        @test Parsers.parse(T, s; dateformat=d) == expected
    end
    # variable widths and greedy trailing fields, as Dates
    for (s, f, T) in (("3/14/2021", "mm/dd/yyyy", Date), ("03/14/02021", "mm/dd/yyyy", Date),
                      ("2024-2-29", "yyyy-mm-dd", Date), ("24-01-01", "yyyy-mm-dd", Date),
                      ("20240229", "yyyymmdd", Date), ("2024022923595", "yyyymmddHHMMSS", DateTime),
                      ("1/2/3", "y/m/d", Date), ("2024-1-2 3:4:5", "yyyy-mm-dd HH:MM:SS", DateTime),
                      ("12:5:7.5", "HH:MM:SS.s", Time))
        base = T(s, DateFormat(f))
        @test Parsers.parse(T, s; dateformat=f) == base
        @test Parsers.parse(T, s; dateformat=DateFormat(f)) == base
    end
    # adjacent fields stay exact-width, as Dates
    @test Parsers.tryparse(Date, "2024229"; dateformat="yyyymmdd") === nothing
    @test tryparse(Date, "2024229", DateFormat("yyyymmdd")) === nothing
    # the default ISO patterns follow the same rule
    @test Parsers.parse(Date, "2024-2-29") == Date(2024, 2, 29)
    @test Parsers.parse(DateTime, "2024-2-29T3:4:5") == DateTime(2024, 2, 29, 3, 4, 5)
    @test Parsers.parse(Time, "3:4:5") == Time(3, 4, 5)
    # ISO plans produced through either adapter use the same deep execution
    # behavior as the precompiled defaults.
    for (T, s, source, default) in ((Date, "2024-02-29", Dates.ISODateFormat, Parsers.ISO_DATE),
                                    (DateTime, "2024-02-29T13:14:15.123", Dates.ISODateTimeFormat, Parsers.ISO_DATETIME),
                                    (Time, "13:14:15.123", Dates.ISOTimeFormat, Parsers.ISO_TIME))
        bytes = b(s)
        @test Parsers.parsecivil(bytes, 1, length(bytes), Parsers.compilepattern(source)) ==
              Parsers.parsecivil(bytes, 1, length(bytes), default)
        @test Parsers.parse(T, s; dateformat=source) == T(s, source)
    end
end
