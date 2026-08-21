# Adapted from CSV.jl's kernel value-layer differentials (kernel/test_values.jl):
# Base.parse / Dates are the ORACLES here — every kernel must agree bit-for-bit
# with the oracle on the accept-set; deliberate deltas are pinned explicitly.
using Test, Random, Dates, Parsers

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
    for (y, m, d) in ((-100_000, 1, 1), (275_760, 9, 13), (typemax(Int32) ÷ 400 * 400 - 1, 12, 31))
        @test Parsers.daysfromcivil(y, m, d) == Dates.value(Date(y, m, d))
    end
end

@testset "civil: ISO patterns" begin
    c, rc = Parsers.parsecivil(b("2024-02-29"), 1, 10, Parsers.ISO_DATE)
    @test rc == Parsers.RC_OK && todate(c) == Date(2024, 2, 29)
    @test Parsers.parsecivil(b("2023-02-29"), 1, 10, Parsers.ISO_DATE)[2] == Parsers.RC_INVALID  # not a leap year
    @test Parsers.parsecivil(b("2024-13-01"), 1, 10, Parsers.ISO_DATE)[2] == Parsers.RC_INVALID
    @test Parsers.parsecivil(b("2024-00-01"), 1, 10, Parsers.ISO_DATE)[2] == Parsers.RC_INVALID
    @test Parsers.parsecivil(b("24-01-01"), 1, 8, Parsers.ISO_DATE)[2] == Parsers.RC_INVALID    # fixed-width year
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
    function checkfast(fast, pat, bytes)
        for pad in (0, 1, 7)
            buf = vcat(fill(UInt8(0xa5), pad), bytes, fill(UInt8(0x5a), 8))
            i = pad + 1
            @test fast(buf, i) == Parsers.parsecivil(buf, i, i + length(bytes) - 1, pat)
        end
    end

    for s in ("0000-01-01", "9999-12-31", "2000-02-29", "1900-02-29",
              "2400-02-29", "2020-1-01x", "2020/01-01", "2020-01/01")
        checkfast(Parsers.parseiso10, Parsers.ISO_DATE, b(s))
    end
    for s in ("2024-01-02T03:04:05", "2024-01-02 03:04:05",
              "2024-01-02t03:04:05", "1900-02-29T03:04:05")
        checkfast(Parsers.parseiso19, Parsers.ISO_DATETIME, b(s))
    end
    for s in ("00:00:00", "23:59:59", "24:00:00")
        checkfast(Parsers.parseiso8, Parsers.ISO_TIME, b(s))
    end
    c, rc = Parsers.parseiso8(b("03:04:05"), 1)
    @test (c, rc) == (Parsers.CivilParts(1, 1, 1, 3, 4, 5, 0), Parsers.RC_OK)

    # Every one-byte mutation checks separators and every possible byte at each
    # digit position. This includes the UInt8-underflow cases '/' and 0xff.
    for (fast, pat, base) in (
        (Parsers.parseiso10, Parsers.ISO_DATE, b("2024-02-29")),
        (Parsers.parseiso19, Parsers.ISO_DATETIME, b("2024-02-29T23:59:59")),
        (Parsers.parseiso8, Parsers.ISO_TIME, b("23:59:59")),
    )
        for pos in eachindex(base), byte in UInt8(0):UInt8(255)
            bytes = copy(base)
            bytes[pos] = byte
            checkfast(fast, pat, bytes)
        end
    end

    rng = MersenneTwister(0x15)
    for (fast, pat, n) in ((Parsers.parseiso10, Parsers.ISO_DATE, 10),
                           (Parsers.parseiso19, Parsers.ISO_DATETIME, 19),
                           (Parsers.parseiso8, Parsers.ISO_TIME, 8))
        for _ in 1:10_000
            checkfast(fast, pat, rand(rng, UInt8, n))
        end
    end
end

@testset "civil: fixed numeric DatePattern valid and invalid inputs" begin
    pattern = Parsers.compilepattern("yyyymmddHHMMSS")
    @test pattern.fixed.nbytes == 14

    source = b("xx20240229235958yy")
    civil, code = Parsers.parsecivil(source, 3, 16, pattern)
    expected = DateTime(2024, 2, 29, 23, 59, 58)
    @test code == Parsers.RC_OK
    @test todatetime(civil) == expected
    @test Parsers.parse(DateTime, "20240229235958"; dateformat=pattern) == expected

    # Dates treats fractional fields as variable-width, so compilepattern does
    # not normally select this internal fixed-subsecond path. Construct the
    # fixed program directly to keep that optimized branch covered.
    fractional_ops = copy(Parsers.compilepattern(DateFormat("yyyymmddHHMMSSsss")).ops)
    fractional_ops[end] = Parsers.PatternOp(0x07, 0x03, true)
    fractional_pattern = Parsers.DatePattern(fractional_ops, true, true)
    @test fractional_pattern.fixed.nbytes == 17
    fractional, code = Parsers.parsecivil(b("20240229235958123"), 1, 17,
                                           fractional_pattern)
    @test code == Parsers.RC_OK
    @test fractional.nanosecond == 123_000_000
    @test Parsers.parse(DateTime, "20240229235958123";
                        dateformat=fractional_pattern) == expected + Millisecond(123)
    @test Parsers.parsecivil(b("2024022923595812x"), 1, 17,
                              fractional_pattern)[2] == Parsers.RC_INVALID
    @test Parsers.parsecivil(b("2024022923595812"), 1, 16,
                              fractional_pattern)[2] == Parsers.RC_INVALID
    @test Parsers.parsecivil(b("202402292359581234"), 1, 18,
                              fractional_pattern)[2] == Parsers.RC_INVALID

    for text in (
        "20230229235958", # invalid leap day
        "20241301235958", # month
        "20240230235958", # day
        "20240229245958", # hour
        "20240229236058", # minute
        "20240229235960", # second
        "2024022x235958", # non-digit in a numeric field
        "2024022923595",  # short span
        "202402292359580", # long span
    )
        @test Parsers.parsecivil(b(text), 1, ncodeunits(text), pattern)[2] ==
              Parsers.RC_INVALID
        @test Parsers.tryparse(DateTime, text; dateformat=pattern) === nothing
    end
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
    @test_throws ArgumentError Parsers.compilepattern("yyyy-Qq")
    # 12-hour clock, AM/PM, and day names — Dates parity (adjusthour + the
    # 1..12 rule when AM/PM is present; day names validated, value ignored)
    let rng = MersenneTwister(4), okall = true
        for f in ("yyyy-mm-dd I:MM p", "I:MM:SS p", "e, dd u yyyy", "E dd U yyyy HH:MM", "II:MM p", "e yyyy-mm-dd", "I p")
            p = Parsers.compilepattern(f); df = DateFormat(f)
            T = p.hasdate && p.hastime ? DateTime : p.hasdate ? Date : Time
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
        # a lone 'e' pattern is neither a date nor a time
        pe = Parsers.compilepattern("e"); @test !pe.hasdate && !pe.hastime
    end
    @test_throws ArgumentError Parsers.compilepattern("y"^256)
    # Large year fields are invalid data, not conversion exceptions.
    pwide = Parsers.compilepattern("yyyyyyyyyy")
    @test Parsers.parsecivil(b("9999999999"), 1, 10, pwide)[2] == Parsers.RC_INVALID
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

@testset "civil: ISO fraction fast paths agree with parsecivil" begin
    function checkfrac(fast, pat, bytes)
        for pad in (0, 1, 7)
            buf = vcat(fill(UInt8(0xa5), pad), bytes, fill(UInt8(0x5a), 8))
            i = pad + 1
            j = i + length(bytes) - 1
            @test fast(buf, i, j) == Parsers.parsecivil(buf, i, j, pat)
        end
    end
    for s in ("2024-02-29T23:59:59.1", "2024-02-29T23:59:59.12", "2024-02-29T23:59:59.123",
              "2024-02-29T23:59:59.123456789", "2024-02-29T23:59:59.", "2024-02-29T23:59:59.x",
              "2024-02-29T23:59:59:123", "2024-02-29 23:59:59.123", "2023-02-29T23:59:59.123",
              "2024-02-29T24:00:00.123", "2024-02-29T23:59:59.1234567890")
        checkfrac(Parsers.parseiso19frac, Parsers.ISO_DATETIME, b(s))
    end
    for s in ("23:59:59.7", "23:59:59.789", "23:59:59.789012345", "23:59:59.", "24:00:00.1",
              "23:59:59x1", "23:59:59.1234567890")
        checkfrac(Parsers.parseiso8frac, Parsers.ISO_TIME, b(s))
    end
    for (fast, pat, base) in ((Parsers.parseiso19frac, Parsers.ISO_DATETIME, b("2024-02-29T23:59:59.125")),
                              (Parsers.parseiso8frac, Parsers.ISO_TIME, b("23:59:59.125")))
        for pos in eachindex(base), byte in UInt8(0):UInt8(255)
            bytes = copy(base)
            bytes[pos] = byte
            checkfrac(fast, pat, bytes)
        end
    end
    @test Parsers.parse(DateTime, "2024-02-29T23:59:59.125") == DateTime(2024, 2, 29, 23, 59, 59, 125)
    @test Parsers.parse(DateTime, "2024-02-29T23:59:59.1") == DateTime(2024, 2, 29, 23, 59, 59, 100)
    @test Parsers.tryparse(DateTime, "2024-02-29T23:59:59.") === nothing
    @test Parsers.parse(Time, "23:59:59.125") == Time(23, 59, 59, 125)
    @test Parsers.parse(Time, "23:59:59.000000001") == Time(23, 59, 59) + Nanosecond(1)
end

@testset "civil: DateFormat patterns take a fixed fast path, compiled once" begin
    for (f, T) in (("mm/dd/yyyy", Date), ("yyyy-mm-dd HH:MM:SS", DateTime), ("dd.mm.yy", Date),
                   ("HH:MM", Time), ("yyyymmdd", Date), ("yyyy-mm-ddTHH:MM:SS.sss", DateTime))
        df = DateFormat(f)
        pat = Parsers.compilepattern(df)
        @test pat.fixed.nbytes == ncodeunits(f)
        @test Parsers._datepattern(df, T) === Parsers._datepattern(df, T)
        @test Parsers._datepattern(f, T) === Parsers._datepattern(f, T)
        interp = Parsers.DatePattern(pat.ops, pat.hasdate, pat.hastime, pat.months_abbr,
                                     pat.months_full, pat.days_abbr, pat.days_full,
                                     Parsers.FixedDatePattern())
        rng = MersenneTwister(7)
        okall = true
        for _ in 1:2_000
            dt = DateTime(rand(rng, 1:2100), rand(rng, 1:12), rand(rng, 1:28),
                          rand(rng, 0:23), rand(rng, 0:59), rand(rng, 0:59), rand(rng, 0:999))
            x = T === Date ? Date(dt) : T === Time ? Time(dt) : dt
            s = Dates.format(x, df)
            bytes = b(s)
            okall &= Parsers.parsecivil(bytes, 1, length(bytes), pat) ==
                     Parsers.parsecivil(bytes, 1, length(bytes), interp)
            okall &= Parsers.parse(T, s; dateformat=df) == T(s, df)
            # a mutated byte must never let the fixed attempt disagree with the interpreter
            m = copy(bytes)
            m[rand(rng, eachindex(m))] = rand(rng, UInt8)
            okall &= Parsers.parsecivil(m, 1, length(m), pat) == Parsers.parsecivil(m, 1, length(m), interp)
        end
        @test okall
    end
    @test Parsers.compilepattern(DateFormat("U dd yyyy")).fixed.nbytes == 0
    @test Parsers.compilepattern(DateFormat("I:MM p")).fixed.nbytes == 0
    # Dates' variable widths still apply through the interpreter fallback
    df = DateFormat("mm/dd/yyyy")
    @test Parsers.parse(Date, "3/14/2021"; dateformat=df) == Date(2021, 3, 14)
    @test Parsers.parse(Date, "03/14/02021"; dateformat=df) == Date(2021, 3, 14)
    @test Parsers.parse(Date, "03/14/2021"; dateformat=df) == Date(2021, 3, 14)
    parsedateformat("03/14/2021", df)
    @test @allocated(parsedateformat("03/14/2021", df)) == 0
    parsedateformat("03/14/2021", "mm/dd/yyyy")
    @test @allocated(parsedateformat("03/14/2021", "mm/dd/yyyy")) == 0
    # other locales compile through the cache and keep their names
    months = ["Month$(lpad(string(i), 2, '0'))" for i in 1:12]
    locale = Dates.DateLocale(months, ["M$i" for i in 1:12], ["Day$i" for i in 1:7], ["D$i" for i in 1:7])
    localized = DateFormat("U dd yyyy", locale)
    @test Parsers._datepattern(localized, Date) === Parsers._datepattern(localized, Date)
    @test Parsers.parse(Date, "Month02 29 2024"; dateformat=localized) == Date(2024, 2, 29)
end
