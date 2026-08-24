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

    months = ["Alfa", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot",
              "Golf", "Hotel", "India", "Juliett", "Kilo", "Lima"]
    months_abbr = ["Ab", "Bc", "Cd", "De", "Ef", "Fg",
                   "Gh", "Hi", "Ij", "Jk", "Kl", "Lm"]
    weekdays = ["Mondayx", "Tuesdayx", "Wednesdayx", "Thursdayx",
                "Fridayx", "Saturdayx", "Sundayx"]
    weekdays_abbr = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    locale = Dates.DateLocale(months, months_abbr, weekdays, weekdays_abbr)
    localized = DateFormat("U dd yyyy", locale)
    @test Dates.tryparse(Date, "Bravo 29 2024", localized) == expected
    @test Parsers.parse(Date, "Bravo 29 2024"; dateformat=localized) == expected
    @test Parsers.tryparse(Date, "February 29 2024"; dateformat=localized) === nothing

    function checklocalized(text, expected, format)
        pattern = Parsers.compilepattern(format)
        bytes = b(text)
        padded = [0xff; bytes; 0xfe]
        for source in (text, codeunits(text), bytes, @view(padded[2:end-1]))
            @test Parsers.tryparse(Date, source; dateformat=pattern) == expected
        end
        @test Parsers.tryparse(Date, padded, 2, length(bytes) + 1;
                               dateformat=pattern) == expected
    end

    # An abstract DateFormat token tuple can hold numeric and named formats.
    # Its runtime cache must therefore key every entry by locale, even when the
    # first cached value has numeric fields only.
    BroadDateFormat = Dates.DateFormat{nothing, Tuple}
    broad_numeric = BroadDateFormat(DateFormat("yyyy-mm-dd", locale).tokens, locale)
    broad_names_a = BroadDateFormat(localized.tokens, locale)
    beta_months = copy(months)
    beta_months[2] = "Beta"
    beta_locale = Dates.DateLocale(beta_months, months_abbr, weekdays, weekdays_abbr)
    broad_names_b = BroadDateFormat(DateFormat("U dd yyyy", beta_locale).tokens,
                                    beta_locale)
    @test Parsers.parse(Date, "2024-02-29"; dateformat=broad_numeric) == expected
    @test Parsers.parse(Date, "Bravo 29 2024"; dateformat=broad_names_a) == expected
    @test Parsers.parse(Date, "Beta 29 2024"; dateformat=broad_names_b) == expected
    @test Parsers.tryparse(Date, "Bravo 29 2024"; dateformat=broad_names_b) === nothing

    unicode_months = copy(months)
    unicode_months[2:4] = ["Février", "Σίγμα", "Москва"]
    unicode_locale = Dates.DateLocale(unicode_months, months_abbr, weekdays,
                                      weekdays_abbr)
    unicode_names = DateFormat("U dd yyyy", unicode_locale)
    for (month, value) in (("Février", 2), ("Σίγμα", 3), ("Москва", 4)),
        variant in (identity, lowercase, uppercase)
        checklocalized("$(variant(month)) 29 2024", Date(2024, value, 29),
                       unicode_names)
    end

    invalid_name = [UInt8[0xff]; b(" 29 2024")]
    @test Parsers.tryparse(Date, invalid_name; dateformat=unicode_names) === nothing
    invalid_span = [0x00; invalid_name; 0x00]
    @test Parsers.tryparse(Date, invalid_span, 2, length(invalid_name) + 1;
                           dateformat=unicode_names) === nothing

    # Dates consumes one Unicode letter word and then performs locale lookup.
    # Lowercase can change UTF-8 byte length or cross the ASCII boundary.
    for (localized_name, input_name) in (("İ", "i"), ("ẞ", "ß"), ("K", "K"))
        folded_months = copy(months)
        folded_months[2] = localized_name
        folded_locale = Dates.DateLocale(folded_months, months_abbr, weekdays,
                                         weekdays_abbr)
        folded_format = DateFormat("U dd yyyy", folded_locale)
        folded_pattern = Parsers.compilepattern(folded_format)
        text = "$input_name 29 2024"
        @test Dates.tryparse(Date, text, folded_format) == expected
        checklocalized(text, expected, folded_format)
        checklocalized(text, expected, folded_pattern)
    end

    collision_months = copy(months)
    collision_months[1] = "Foo"
    collision_months[2] = "foo"
    collision_locale = Dates.DateLocale(collision_months, months_abbr, weekdays,
                                        weekdays_abbr)
    collision_format = DateFormat("U dd yyyy", collision_locale)
    collision_pattern = Parsers.compilepattern(collision_format)
    for (collision_text, collision_expected) in
        (("Foo 01 2024", Date(2024, 1, 1)),
         ("foo 01 2024", Date(2024, 2, 1)),
         ("FOO 01 2024", Date(2024, 2, 1)))
        @test Dates.tryparse(Date, collision_text, collision_format) ==
              collision_expected
        checklocalized(collision_text, collision_expected, collision_format)
        checklocalized(collision_text, collision_expected, collision_pattern)
    end

    # Locale spelling length is not limited by the packed name accelerator.
    # Oversized keys use the immutable tuple fallback with exact-byte lookup
    # before its allocation-free lowercase retry.
    oversized_months = copy(months)
    oversized_months[1] = "K"^66_000
    oversized_months[2] = "k"^66_000
    oversized_locale = Dates.DateLocale(oversized_months, months_abbr, weekdays,
                                        weekdays_abbr)
    oversized_format = DateFormat("U dd yyyy", oversized_locale)
    oversized_pattern = Parsers.compilepattern(oversized_format)
    oversized_plan = getfield(getfield(oversized_pattern, :_storage), :plan)
    oversized_names = getfield(getfield(oversized_plan, :names), :names)
    oversized_table = getfield(oversized_names, :months_full)
    @test isempty(getfield(getfield(oversized_table, :trie), :nodes))
    for (name, month) in ((oversized_months[1], 1),
                          (oversized_months[2], 2),
                          ("K"^66_000, 2))
        text = "$name 01 2024"
        expected_oversized = Dates.tryparse(Date, text, oversized_format)
        @test expected_oversized == Date(2024, month, 1)
        checklocalized(text, expected_oversized, oversized_pattern)

        word = b(name * " ")
        expected_match = (month, ncodeunits(name) + 1, true)
        @test matchcivilname(word, oversized_table) == expected_match
        matchcivilname(word, oversized_table)
        @test civilnamealloc(word, oversized_table) == 0
    end

    # DateLocale freezes its lookup dictionaries when it is constructed. Its
    # public backing arrays remain mutable, but later mutations do not change
    # Dates parsing and must not change a newly compiled civil plan.
    frozen_months = copy(months)
    frozen_months[1] = "Alpha"
    frozen_locale = Dates.DateLocale(frozen_months, months_abbr, weekdays,
                                     weekdays_abbr)
    frozen_locale.months[1] = "Zulu"
    frozen_format = DateFormat("U dd yyyy", frozen_locale)
    frozen_pattern = Parsers.compilepattern(frozen_format)
    for (text, expected_frozen) in (("Alpha 01 2024", Date(2024, 1, 1)),
                                    ("Zulu 01 2024", nothing))
        @test Dates.tryparse(Date, text, frozen_format) === expected_frozen
        @test Parsers.tryparse(Date, text; dateformat=frozen_format) ===
              expected_frozen
        @test Parsers.tryparse(Date, text; dateformat=frozen_pattern) ===
              expected_frozen
    end

    for (first_name, second_name, input_name) in (("K", "K", "k"),
                                                   ("i", "İ", "i"))
        cross_width_months = copy(months)
        cross_width_months[1] = first_name
        cross_width_months[2] = second_name
        cross_width_locale = Dates.DateLocale(cross_width_months, months_abbr,
                                              weekdays, weekdays_abbr)
        cross_width_format = DateFormat("U dd yyyy", cross_width_locale)
        cross_width_pattern = Parsers.compilepattern(cross_width_format)
        text = "$input_name 01 2024"
        expected_cross_width = Dates.tryparse(Date, text, cross_width_format)
        @test expected_cross_width == Date(2024, 2, 1)
        @test Parsers.tryparse(Date, text; dateformat=cross_width_format) ==
              expected_cross_width
        @test Parsers.tryparse(Date, text; dateformat=cross_width_pattern) ==
              expected_cross_width
    end

    # The compiled name matcher is allocation-free and stops at the first
    # non-letter. A large record tail must not change that contract.
    unicode_table = Parsers.CivilNameTable(("A", "K"))
    short_unicode = b("K ")
    long_unicode = [short_unicode; fill(UInt8('x'), 1_000_000)]
    @test matchcivilname(short_unicode, unicode_table) == (2, 4, true)
    @test matchcivilname(long_unicode, unicode_table) == (2, 4, true)
    matchcivilname(short_unicode, unicode_table)
    matchcivilname(long_unicode, unicode_table)
    short_alloc = civilnamealloc(short_unicode, unicode_table)
    long_alloc = civilnamealloc(long_unicode, unicode_table)
    @test short_alloc == long_alloc == 0

    # An invalid unbounded ASCII word must stop when the compiled trie cannot
    # advance. It must not scan a record-sized word before locale lookup.
    counted_reads = Ref(0)
    counted_ascii = CountingRepeatedBytes(UInt8('A'), 1_000_000, counted_reads)
    @test matchcivilname(counted_ascii, unicode_table) == (0, 1, false)
    @test counted_reads[] == 2

    # The English abbreviation executor reads three bytes directly, then
    # validates the word end only when the field width does not own it.
    english_table = Parsers.CivilNameTable(Parsers.ENGLISH_MONTHS_ABBR)
    matchenglish(source, width=0) =
        Parsers._matchname(source, 1, length(source), english_table, width)
    @test matchenglish(b("Jan")) == (1, 4, true)
    @test matchenglish(b("Jan;")) == (1, 4, true)
    @test matchenglish(b("Jan💥")) == (1, 4, true)
    @test matchenglish(b("Janx")) == (0, 1, false)
    @test matchenglish(b("JanK")) == (0, 1, false)
    @test matchenglish(UInt8[codeunits("Jan")...; 0xff]) == (0, 1, false)
    @test matchenglish(b("Janx"), 3) == (1, 4, true)
    @test matchenglish(UInt8[codeunits("Jan")...; 0xff], 3) == (1, 4, true)
    @test matchenglish(b("Janx"), 4) == (0, 1, false)
    @test matchenglish(b("Jan"), 2) == (0, 1, false)

    for (format, text) in (("uyyyy", "Jan2024"),
                           ("UUUUyyyy", "January2024"),
                           ("UUUUyyyy", "Jan2024"))
        named_format = DateFormat(format)
        named_pattern = Parsers.compilepattern(named_format)
        @test Dates.tryparse(Date, text, named_format) === nothing
        @test Parsers.tryparse(Date, text; dateformat=named_format) === nothing
        @test Parsers.tryparse(Date, text; dateformat=named_pattern) === nothing
    end
    for text in ("May2024", "June2024", "July2024")
        named_format = DateFormat("UUUUyyyy")
        named_pattern = Parsers.compilepattern(named_format)
        expected_named = Dates.tryparse(Date, text, named_format)
        @test expected_named !== nothing
        @test Parsers.tryparse(Date, text; dateformat=named_format) == expected_named
        @test Parsers.tryparse(Date, text; dateformat=named_pattern) == expected_named
    end

    adjacent = DateFormat("yyyymmdd")
    @test Parsers.parse(Date, "20240229"; dateformat=adjacent) == expected
    repeated_delimiter = DateFormat("yyyy--mm--dd")
    @test Parsers.parse(Date, "2024--02--29"; dateformat=repeated_delimiter) == expected
    @test Parsers.parse(Date, "2024\\"; dateformat="yyyy\\") == Date(2024, 1, 1)

    opaque_pattern = Parsers.compilepattern("mm/dd/yyyy")
    @test repr(opaque_pattern) == "Parsers.DatePattern(<compiled>)"
    opaque_error = try
        Parsers.parse(Date, "invalid"; dateformat=opaque_pattern)
        nothing
    catch caught
        caught
    end
    @test opaque_error isa ArgumentError
    @test occursin("Parsers.DatePattern(<compiled>)", sprint(showerror, opaque_error))
    @test !occursin("CivilPlan", sprint(showerror, opaque_error))

    signed_year = DateFormat("yyyy-mm-dd")
    for (text, expected_year) in (("-0001-01-01", -1), ("-1-01-01", -1),
                                  ("+0001-01-01", 1))
        @test Parsers.parse(Date, text; dateformat=signed_year) ==
              Date(expected_year, 1, 1)
    end
    @test Parsers.parse(Date, "-0001-01-01") == Date(-1, 1, 1)
    @test Parsers.tryparse(Date, "-1-01-01") == Date(-1, 1, 1)

    # String compilation follows DateFormat's slash-run unescape semantics.
    # Every token letter remains literal when any slash immediately precedes
    # it, including an even slash run.
    for token in ('y', 'm', 'd', 'H', 'M', 'S', 's', 'u', 'U', 'I', 'p', 'e', 'E'),
        nslashes in 1:4
        source = repeat("\\", nslashes) * string(token)
        literal = repeat("\\", nslashes ÷ 2) * string(token)
        df = DateFormat(source)
        pattern = Parsers.compilepattern(source)
        @test Dates.tryparse(Date, literal, df) == Date(1)
        @test Parsers.tryparse(Date, literal; dateformat=pattern) == Date(1)
        @test Parsers.tryparse(Date, literal; dateformat=source) == Date(1)
    end
    slash_lf = "\\\n"
    @test Dates.tryparse(Date, slash_lf, DateFormat(slash_lf)) == Date(1)
    @test Parsers.tryparse(Date, slash_lf;
                           dateformat=Parsers.compilepattern(slash_lf)) == Date(1)
    @test Parsers.tryparse(Date, "\n"; dateformat=slash_lf) === nothing

    # The source type parameter is not authoritative when a hand-built
    # DateFormat carries a different runtime token tuple.
    other = DateFormat("dd/mm/yyyy")
    OtherFormat = Dates.DateFormat{Symbol("yyyy-mm-dd"), typeof(other.tokens)}
    mismatched = OtherFormat(other.tokens, Dates.ENGLISH)
    @test Date("29/02/2024", mismatched) == expected
    @test Parsers.parse(Date, "29/02/2024"; dateformat=mismatched) == expected

    # Delimiter values and field widths are not encoded in the token tuple
    # type. A hand-built DateFormat can therefore share the canonical type but
    # carry different runtime parsing rules.
    slash = DateFormat("yyyy/mm/dd")
    SlashFormat = Dates.DateFormat{Symbol("yyyy-mm-dd"), typeof(slash.tokens)}
    same_type_slash = SlashFormat(slash.tokens, Dates.ENGLISH)
    @test Date("2024/02/29", same_type_slash) == expected
    @test Parsers.parse(Date, "2024/02/29"; dateformat=same_type_slash) == expected

    shortyear = DateFormat("yymmdd")
    ShortYearFormat = Dates.DateFormat{:yyyymmdd, typeof(shortyear.tokens)}
    same_type_width = ShortYearFormat(shortyear.tokens, Dates.ENGLISH)
    @test Date("240229", same_type_width) == Date(24, 2, 29)
    @test Parsers.parse(Date, "240229"; dateformat=same_type_width) ==
          Date(24, 2, 29)

    NumericSourceFormat = Dates.DateFormat{42, typeof(DateFormat("yyyy-mm-dd").tokens)}
    numeric_source = NumericSourceFormat(DateFormat("yyyy-mm-dd").tokens,
                                         Dates.ENGLISH)
    @test Dates.tryparse(Date, "2024-02-29", numeric_source) == expected
    @test Parsers.tryparse(Date, "2024-02-29"; dateformat=numeric_source) ==
          expected

    # Dates groups unsupported letters into a delimiter token. Compile the
    # reconstructed DateFormat rather than interpreting its source string with
    # the civil token grammar.
    quarter_literal = DateFormat("yyyy-Q")
    @test Date("2024-Q", quarter_literal) == Date(2024, 1, 1)
    @test Parsers.parse(Date, "2024-Q"; dateformat=quarter_literal) ==
          Date(2024, 1, 1)
    @test Parsers.parse(Date, "2024-Q"; dateformat="yyyy-Q") == Date(2024, 1, 1)
    for source in ("yyyy/mm/dd", "yyyy年mm月dd日", "yyyy-Q")
        canonical = DateFormat(source)
        @test canonical.tokens === DateFormat(String(typeof(canonical).parameters[1])).tokens
    end

    # Large canonical token tuples embed one pointer-sized plan and cross the
    # bounded execution seam. This used to trigger recursively inferred code
    # that grew into GiB.
    long_source = join(fill("y-", 100)) * "y"
    long_format = DateFormat(long_source)
    long_text = join(fill("1-", 100)) * "1"
    @test Parsers.tryparse(Date, long_text; dateformat=long_format) == Date(1)
    @test getfield(Parsers._datepattern(long_format, Date), :_storage) ===
          getfield(Parsers._datepattern(long_format, Date), :_storage)
    parsedateformat(long_text, long_format)
    @test @allocated(parsedateformat(long_text, long_format)) <= 16

    wide_subsecond_source = "HH:MM:SS." * "s"^10
    wide_subsecond = DateFormat(wide_subsecond_source)
    wide_subsecond_value = "12:34:56.1234567890"
    @test_throws ArgumentError Parsers.compilepattern(wide_subsecond_source)
    @test_throws ArgumentError Parsers.compilepattern(wide_subsecond)
    for format in (wide_subsecond_source, wide_subsecond)
        @test_throws ArgumentError Parsers.parse(Time, wide_subsecond_value;
                                                 dateformat=format)
        @test_throws ArgumentError Parsers.tryparse(Time, wide_subsecond_value;
                                                    dateformat=format)
    end
    for parsefn in (Parsers.parse, Parsers.tryparse)
        @test_throws BoundsError parsefn(Time, UInt8['1'], 2, 2;
                                         dateformat=wide_subsecond)
    end

    # Non-fixed numeric fields are greedy. The bytecode's 0xff width is an
    # unbounded marker, so leading zeros do not create a 255-byte cutoff.
    greedy_format = DateFormat("yyyy-mm-dd")
    greedy_pattern = Parsers.compilepattern(greedy_format)
    for zeros in (250, 251, 255, 256, 300)
        for text in ("0"^zeros * "2024-01-02",
                     "2024-" * "0"^zeros * "01-02",
                     "2024-01-" * "0"^zeros * "02")
            @test Dates.tryparse(Date, text, greedy_format) == Date(2024, 1, 2)
            @test Parsers.tryparse(Date, text; dateformat=greedy_format) ==
                  Date(2024, 1, 2)
            @test Parsers.tryparse(Date, text; dateformat=greedy_pattern) ==
                  Date(2024, 1, 2)
        end
    end

    minimum_year_text = "-2147483648-01-01"
    minimum_year = Date(typemin(Int32), 1, 1)
    magnitude = b("2147483648")
    @test Parsers._readnum(magnitude, 1, length(magnitude), typemax(UInt8),
                           false) == (Int64(2147483648), 11, true)
    # Dates 1.10 narrows this signed year before construction. Parsers keeps
    # the Date constructor's full Int64 input range on every supported Julia.
    VERSION >= v"1.11" &&
        @test(Dates.tryparse(Date, minimum_year_text, greedy_format) == minimum_year)
    @test Parsers.tryparse(Date, minimum_year_text;
                           dateformat=greedy_format) == minimum_year
    @test Parsers.tryparse(Date, minimum_year_text;
                           dateformat=greedy_pattern) == minimum_year

    for year in (Int64(2147483648), Int64(-2147483649), Int64(10_000_000_000),
                 typemax(Int64), typemin(Int64))
        text = string(year, "-01-01")
        for T in (Date, DateTime)
            year_value = T(year, 1, 1)
            @test Parsers.tryparse(T, text; dateformat=greedy_format) == year_value
            @test Parsers.tryparse(T, text; dateformat=greedy_pattern) == year_value
        end
    end
    minyearbytes = b("-9223372036854775808")
    @test Parsers._readyear(minyearbytes, 1, length(minyearbytes),
                            typemax(UInt8), false) ==
          (typemin(Int64), length(minyearbytes) + 1, true)
    for text in ("9223372036854775808-01-01", "-9223372036854775809-01-01")
        @test Parsers.tryparse(Date, text; dateformat=greedy_format) === nothing
        @test Parsers.tryparse(DateTime, text; dateformat=greedy_pattern) === nothing
    end

    # Greedy and fixed String patterns match DateFormat beyond one-byte widths.
    for (source, text, expected_value) in (
        ("y"^256 * "-mm-dd", "2024-01-02", Date(2024, 1, 2)),
        ("U"^256 * "-dd-yyyy", "January-02-2024", Date(2024, 1, 2)),
        ("y"^256 * "m", "0"^255 * "11", Date(1, 1, 1)),
        ("U"^256 * "d", "January1", Date(1, 1, 1)),
    )
        format = DateFormat(source)
        @test Dates.tryparse(Date, text, format) == expected_value
        @test Parsers.tryparse(Date, text; dateformat=source) == expected_value
        @test Parsers.tryparse(Date, text; dateformat=format) == expected_value
        @test Parsers.tryparse(Date, text;
                               dateformat=Parsers.compilepattern(format)) == expected_value
    end

    @test Parsers.parse(Date, "2024-02-29") == expected
    @test Parsers.tryparse(Date, "2024-2-29") == Date(2024, 2, 29)
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

    # Only a wholly absent final delimiter + subsecond group is optional.
    for format in ("HH:MM:SS--s", "HH:MM:SSµs")
        df = DateFormat(format)
        pattern = Parsers.compilepattern(df)
        @test Parsers.tryparse(Time, "12:34:56"; dateformat=df) == Time(12, 34, 56)
        @test Parsers.tryparse(Time, "12:34:56"; dateformat=pattern) == Time(12, 34, 56)
    end
    @test Parsers.tryparse(Time, "12:34:56-";
                           dateformat=DateFormat("HH:MM:SS--s")) === nothing
    partial_mu = [codeunits("12:34:56"); UInt8(0xc2)]
    @test Parsers.tryparse(Time, partial_mu;
                           dateformat=DateFormat("HH:MM:SSµs")) === nothing

    # Dates parses every token but validates only fields used by the target.
    for (T, text, format, value) in (
        (Date, "99", "HH", Date(1, 1, 1)),
        (Date, "99 PM", "I p", Date(1, 1, 1)),
        (Date, "2024-02-29 99", "yyyy-mm-dd HH", Date(2024, 2, 29)),
        (Time, "99-99", "mm-dd", Time(0)),
        (Time, "99-99 12:00:00", "mm-dd HH:MM:SS", Time(12)),
    )
        df = DateFormat(format)
        pattern = Parsers.compilepattern(df)
        @test Dates.tryparse(T, text, df) == value
        @test Parsers.tryparse(T, text; dateformat=df) == value
        @test Parsers.tryparse(T, text; dateformat=pattern) == value
    end

    # Empty input is not a fieldless civil value. Nonempty literal-only formats
    # still produce the destination defaults, as Dates does.
    for T in (Date, DateTime, Time), format in ("", DateFormat(""),
                                                Parsers.compilepattern(""))
        @test Parsers.tryparse(T, ""; dateformat=format) === nothing
        @test_throws ArgumentError Parsers.parse(T, ""; dateformat=format)
    end
    for T in (Date, DateTime, Time), format in ("-", DateFormat("-"),
                                                Parsers.compilepattern("-"))
        default = T === Time ? Time(0) : T(1)
        @test Parsers.tryparse(T, "-"; dateformat=format) == default
    end
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

@testset "whole float short-path decisions are final" begin
    invalid = ("1e", "1e+", "1x", "1.2.3", ".x", "+", "-")
    for T in (Float32, Float64), text in invalid
        bytes = b(text)
        value, code, handled = Parsers._float_fast(T, bytes, 1,
                                                    length(bytes), UInt8('.'))
        @test iszero(value)
        @test code == Parsers.RC_INVALID
        @test handled
        @test Parsers.tryparse(T, text) === nothing
    end

    for T in (Float16, Float32, Float64), text in
        ("Inf", "+Infinity", "-Inf", "NaN", "nan")
        actual = Parsers.parse(T, text; groupmark='i')
        expected = Base.parse(T, text)
        @test isequal(actual, expected) || (isnan(actual) && isnan(expected))
    end

    for T in (Float16, Float32, Float64), decimal in ('i', 'I', 'n', 'N')
        text = string(decimal, '5')
        bytes = b(text)
        @test Parsers.parsefloat(T, bytes, 1, length(bytes), UInt8(decimal)) ==
              (T(0.5), Parsers.RC_OK)
        @test Parsers.parse(T, text; decimal) == T(0.5)
        @test Parsers.parse(T, "-" * text; decimal) == T(-0.5)
    end

    grouped_cases = (
        ("1,234.5", '.', ',', 1234.5),
        ("1.234,5", ',', '.', 1234.5),
        ("1234.5", '.', ',', 1234.5),
        ("1234,5", ',', '.', 1234.5),
    )
    for T in (Float32, Float64), (text, decimal, groupmark, expected) in grouped_cases
        @test Parsers.parse(T, text; decimal, groupmark) == T(expected)
    end
    for T in (Float32, Float64), text in
        (",1", "1,", "1,,2", "1,2.3,4", "1,2.3.4")
        @test Parsers.tryparse(T, text; groupmark=',') === nothing
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

@testset "GMP chunks follow the C long ABI" begin
    # GMP's `mpn_set_str` returns mp_size_t, which its ABI defines as C long.
    # BigInt's stored signed limb count remains C int and is narrowed only
    # after the returned size is checked.
    @test Parsers._GMP_SIZE_T === Clong

    # Keep the wide digit-to-bit estimate wide until after limb rounding, then
    # reject capacities that cannot fit GMP's Cint size field before narrowing.
    for L in (UInt32, UInt64)
        bits = (widemul(typemax(Int), 3402) >> 10) + 1
        expected = Int(cld(bits, 8 * sizeof(L)))
        @test Parsers._limbsfordigits(L, typemax(Int)) == expected
    end
    maxlimbs = Int(typemax(Cint))
    @test Parsers._gmpbitsforlimbs(maxlimbs, 1) == maxlimbs
    @test Parsers._gmpsize(maxlimbs) == typemax(Cint)
    @test Parsers._gmpsize(-maxlimbs) == -typemax(Cint)
    @test_throws OverflowError Parsers._gmpgrowcapacity(maxlimbs, maxlimbs)
    @test Parsers._gmpcheckedaddbits(0, 4) == 4
    maxvaluebits = Parsers._gmpmaxvaluebits()
    if maxvaluebits < UInt128(typemax(Int))
        maxbits = Int(maxvaluebits)
        @test Parsers._gmpcheckedaddbits(maxbits, 0) == maxbits
        @test_throws OverflowError Parsers._gmpcheckedaddbits(maxbits, 1)
    else
        @test_throws OverflowError Parsers._gmpcheckedaddbits(typemax(Int), 1)
    end
    if sizeof(Culong) < sizeof(Int)
        @test_throws OverflowError Parsers._gmpbitsforlimbs(maxlimbs, 3)
    end
    if sizeof(Int) > sizeof(Cint)
        @test_throws OverflowError Parsers._gmpbitsforlimbs(maxlimbs + 1, 1)
        @test_throws OverflowError Parsers._gmpsize(maxlimbs + 1)
    end

    for text in ("123456789012345678", "-57607098681222696")
        bytes = b(text)
        expected_int = Base.parse(BigInt, text)
        value, code = Parsers.parsebigint(bytes, 1, length(bytes))
        @test code == Parsers.RC_OK
        @test value == expected_int
        @test Parsers.parse(BigInt, text) == expected_int

        padded = b("xx" * text * "yy")
        first = 3
        last = first + ncodeunits(text) - 1
        @test Parsers.parse(BigInt, padded, first, last) == expected_int

        expected_float = Base.parse(BigFloat, text)
        float_value, float_code = Parsers.parsebigfloat(bytes, 1, length(bytes))
        @test float_code == Parsers.RC_OK
        @test isequal(float_value, expected_float)
        @test isequal(Parsers.parse(BigFloat, text), expected_float)
    end
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

    # `mpfr_mul_2si` accepts C long, which is narrower than Julia Int on
    # 64-bit Windows. Check the ABI guard everywhere and the full exact/prefix
    # behavior on platforms where the widths differ. The final case crosses
    # the boundary only after `_roundbig!` adds its discarded-bit shift.
    @test Parsers._cexponent(Int32, Int128(typemax(Int32))) == typemax(Int32)
    @test_throws Parsers._MPFRScaleRange Parsers._cexponent(
        Int32, Int128(typemax(Int32)) + 1)
    @test_throws Parsers._MPFRScaleRange Parsers._cexponent(
        Int32, Int128(typemin(Int32)) - 1)
    if sizeof(Clong) < sizeof(Int)
        positive = string(Int128(typemax(Clong)) + 2)
        negative = string(Int128(typemin(Clong)) - 1)
        for (text, expectedcode) in (("0x1p" * positive, Parsers.RC_OVERFLOW),
                                     ("0x1p" * negative, Parsers.RC_UNDERFLOW))
            token = b(text)
            _, code = Parsers.parsebigfloat(token, 1, length(token))
            @test code == expectedcode
            source = [token; UInt8(';')]
            _, nextpos, code = Parsers.parsenext(BigFloat, source, 1,
                                                 length(source))
            @test nextpos == length(token) + 1
            @test code == expectedcode
        end
        setprecision(BigFloat, 128) do
            text = "0x1" * repeat("0", 32) * "p$(typemax(Clong))"
            token = b(text)
            @test Parsers.parsebigfloat(token, 1, length(token))[2] ==
                  Parsers.RC_OVERFLOW
            source = [token; UInt8(';')]
            @test Parsers.parsenext(BigFloat, source, 1, length(source))[3] ==
                  Parsers.RC_OVERFLOW
        end
    end
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

    # The default public router sends only MPFR-specific leading forms and
    # nonzero 20-digit integers around the short decimal kernel. Exact whole
    # Strings and their CodeUnits view use the zero-copy MPFR seam.
    for text in ("@NaN@", "nan(payload)", "0b1.1p2")
        bytes = codeunits(text)
        @test Parsers._obviousmpfrdefault(bytes, 1, length(bytes))
    end
    @test !Parsers._obviousmpfrdefault(codeunits("1@2"), 1, 3)
    integer20 = "11111111111111111111"
    @test Parsers._prefermpfrdefault(codeunits(integer20), 1,
                                     ncodeunits(integer20))
    @test !Parsers._prefermpfrdefault(codeunits("01111111111111111111"), 1, 20)
    @test !Parsers._prefermpfrdefault(codeunits("1.111111111111111111"), 1, 20)
    for precision_bits in (53, 256, 1024)
        setprecision(BigFloat, precision_bits) do
            for text in (integer20, "-" * integer20)
                expected = Base.parse(BigFloat, text)
                for source in (text, codeunits(text))
                    @test isequal(Parsers.parse(BigFloat, source), expected)
                    @test isequal(Parsers.tryparse(BigFloat, source), expected)
                end
            end
        end
    end

    rounding_modes = RoundingMode[RoundNearest, RoundDown, RoundUp, RoundToZero]
    if isdefined(Base.Rounding, :RoundFromZero)
        push!(rounding_modes, getfield(Base.Rounding, :RoundFromZero))
    end
    # q == 0 has one MPFR rounding operation. A UInt64 coefficient wider than
    # the active precision is therefore safe on the short path, including
    # directed rounding of negative values.
    setprecision(BigFloat, 53) do
        integer19 = "1111111111111111111"
        texts = (integer19, "-" * integer19)
        for rounding_mode in rounding_modes
            expected = setrounding(BigFloat, rounding_mode) do
                Base.parse.(BigFloat, texts)
            end
            for (text, value) in zip(texts, expected)
                check_bigfloat_sources(text, value; rounding=rounding_mode)
            end
        end
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

    for text in ("x", "+x", "?1", "1e", "0x1p", "1\0junk", "1@2x",
                 "0b1.1p2x", "nan(payload)x",
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
    for text in ("@NaN@", "nan(payload)", "0b1.1p2", "1@2")
        @test Parsers.tryparse(BigFloat, text; decimal=',') === nothing
        @test Parsers.tryparse(BigFloat, text; groupmark='_') === nothing
        @test_throws ArgumentError Parsers.parse(BigFloat, text; decimal=',')
        @test_throws ArgumentError Parsers.parse(BigFloat, text; groupmark='_')
    end

    # Configured grammar is independent of the rounding mode. MPFR faithful
    # rounding has no limb-kernel equivalent, but it must not enable MPFR-only
    # exponents, NaN payloads, or a decimal byte that the caller did not select.
    faithful = Base.MPFR.MPFRRoundFaithful
    invalid_faithful = (
        ("1.25", (; decimal=',')),
        ("1@2", (; decimal=',')),
        ("nan(123)", (; decimal=',')),
        ("1@2", (; groupmark='_')),
        ("nan(123)", (; groupmark='_')),
        ("1_2@3", (; groupmark='_')),
        ("1_234.5", (; decimal=',', groupmark='_')),
        ("1__234,5", (; decimal=',', groupmark='_')),
    )
    for (text, options) in invalid_faithful
        whole, spans = source_forms(text)
        for source in whole
            @test Parsers.tryparse(BigFloat, source; rounding=faithful,
                                   options...) === nothing
            @test_throws ArgumentError Parsers.parse(
                BigFloat, source; rounding=faithful, options...)
        end
        for (source, first, last) in spans
            @test Parsers.tryparse(BigFloat, source, first, last;
                                   rounding=faithful, options...) === nothing
            @test_throws ArgumentError Parsers.parse(
                BigFloat, source, first, last; rounding=faithful, options...)
        end
    end
    @test Parsers.parse(BigFloat, "1,25"; decimal=',', rounding=faithful) ==
          BigFloat(1.25)
    @test Parsers.parse(BigFloat, "1_234.5"; groupmark='_',
                        rounding=faithful) == BigFloat(1234.5)
    @test Parsers.parse(BigFloat, "1_234,5"; decimal=',', groupmark='_',
                        rounding=faithful) == BigFloat(1234.5)
    @test Parsers.parse(BigFloat, "x5"; decimal='x') == BigFloat(0.5)
    @test Parsers.parse(BigFloat, "-@Inf@") == -BigFloat(Inf)
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

    # Decomposition stores the significant-digit position relative to the
    # token. Large valid source indices must not narrow to Int32. A 32-bit
    # process cannot represent an index above typemax(Int32).
    if sizeof(Int) > 4
        highpos = Int(typemax(Int32)) + 1
        highsource = HugeIndexedBytes(highpos + 1, highpos)
        @test Parsers.parsenext(Float64, highsource, highpos, highpos + 1) ==
              (1.0, highpos + 1, Parsers.RC_OK)
        @test Parsers.parsenext(BigFloat, highsource, highpos, highpos + 1) ==
              (BigFloat(1), highpos + 1, Parsers.RC_OK)
    end

    # Prefix kernels reserve internal cursor headroom above very high public
    # indices. The lazy source performs an unconditional bounds check so an
    # `@inbounds` caller cannot hide a wrapped lookahead.
    threshold = typemax(Int) ÷ 2 + 1
    for n in (threshold, typemax(Int) - 1)
        delimited = CheckedTailBytes(n, "1;")
        for (T, expected) in ((Int64, Int64(1)), (BigInt, BigInt(1)),
                              (Float64, 1.0), (BigFloat, BigFloat(1)),
                              (Bool, true))
            value, nextpos, code = Parsers.parsenext(T, delimited, n - 1, n)
            @test isequal(value, expected)
            @test nextpos == n
            @test code == Parsers.RC_OK
        end

        terminal = CheckedTailBytes(n, "1")
        for (T, expected) in ((Int64, Int64(1)), (BigInt, BigInt(1)),
                              (Float64, 1.0), (BigFloat, BigFloat(1)),
                              (Bool, true))
            value, nextpos, code = Parsers.parsenext(T, terminal, n, n)
            @test isequal(value, expected)
            @test nextpos == n + 1
            @test code == Parsers.RC_OK
        end
    end

    maxsource = CheckedTailBytes(typemax(Int), "1;")
    for (T, expected) in ((Int64, Int64(1)), (BigInt, BigInt(1)),
                          (Float64, 1.0), (BigFloat, BigFloat(1)),
                          (Bool, true))
        value, nextpos, code =
            Parsers.parsenext(T, maxsource, typemax(Int) - 1, typemax(Int))
        @test isequal(value, expected)
        @test nextpos == typemax(Int)
        @test code == Parsers.RC_OK
        @test_throws OverflowError Parsers.parsenext(
            T, CheckedTailBytes(typemax(Int), "1"), typemax(Int), typemax(Int))
    end

    # Multi-byte lookahead, grouping, and a leading decimal point use the same
    # translated boundary without colliding with internal position sentinels.
    maxinthex = CheckedTailBytes(typemax(Int), "0x1;")
    @test Parsers.parsenext(Int64, maxinthex, typemax(Int) - 3,
                            typemax(Int)) ==
          (Int64(1), typemax(Int), Parsers.RC_OK)
    @test Parsers.parsenext(Float64, maxinthex, typemax(Int) - 3,
                            typemax(Int)) ==
          (1.0, typemax(Int), Parsers.RC_OK)
    @test Parsers.parsenext(BigFloat,
                            CheckedTailBytes(typemax(Int), ".5;"),
                            typemax(Int) - 2, typemax(Int)) ==
          (BigFloat(0.5), typemax(Int), Parsers.RC_OK)
    @test Parsers.parsenext(Bool, CheckedTailBytes(typemax(Int), "true;"),
                            typemax(Int) - 4, typemax(Int)) ==
          (true, typemax(Int), Parsers.RC_OK)
    for T in (Int64, BigInt, Float64, BigFloat)
        value, nextpos, code = Parsers.parsenext(
            T, CheckedTailBytes(typemax(Int), "1_2;"),
            typemax(Int) - 3, typemax(Int); groupmark='_')
        @test isequal(value, T(12))
        @test nextpos == typemax(Int)
        @test code == Parsers.RC_OK
    end

    # Exact-span kernels share the same checked index window. They consume a
    # terminal token without forming `last + 1`, and explicit-base errors map
    # their local byte position back to the caller's index space.
    civilpattern = Parsers.compilepattern("yyyy-mm-dd/")
    uuidtext = "123e4567-e89b-12d3-a456-426614174000"
    expecteduuid = Base.UUID(uuidtext).value
    threshold = typemax(Int) ÷ 2 + 1
    for n in (threshold, typemax(Int) - 1, typemax(Int))
        onebyte = CheckedTailBytes(n, "1")
        @test Parsers.parseint64(onebyte, n, n) == (Int64(1), Parsers.RC_OK)
        @test Parsers.parseint128(onebyte, n, n) == (Int128(1), Parsers.RC_OK)
        @test Parsers.parseint(UInt64, onebyte, n, n) ==
              (UInt64(1), Parsers.RC_OK)
        @test Parsers.parseint(UInt128, onebyte, n, n) ==
              (UInt128(1), Parsers.RC_OK)
        @test Parsers.parsebigint(onebyte, n, n) == (BigInt(1), Parsers.RC_OK)
        @test Parsers.parsefloat(Float16, onebyte, n, n) ==
              (Float16(1), Parsers.RC_OK)
        @test Parsers.parsefloat(Float32, onebyte, n, n) ==
              (Float32(1), Parsers.RC_OK)
        @test Parsers.parsefloat(Float64, onebyte, n, n) ==
              (Float64(1), Parsers.RC_OK)
        bigvalue, bigcode = Parsers.parsebigfloat(onebyte, n, n)
        @test isequal(bigvalue, BigFloat(1))
        @test bigcode == Parsers.RC_OK
        @test Parsers.parsebool(CheckedTailBytes(n, "true"), n - 3, n) ==
              (true, Parsers.RC_OK)

        # The public explicit-span boundary rebases before whitespace stripping,
        # group scans, DateFormat selection, or BigFloat grammar dispatch.
        @test Parsers.parse(Int64, onebyte, n, n; groupmark='_') == 1
        @test Parsers.parse(Float64, onebyte, n, n; groupmark='_') == 1.0
        @test Parsers.parse(BigInt, onebyte, n, n; groupmark='_') == BigInt(1)
        @test Parsers.parse(BigFloat, onebyte, n, n) == BigFloat(1)
        @test Parsers.parse(BigFloat, onebyte, n, n; groupmark='_') == BigFloat(1)
        @test Parsers.parse(Bool, onebyte, n, n)
        publicdate = CheckedTailBytes(n, "2024-01-02/")
        @test Parsers.parse(Date, publicdate, n - 10, n;
                            dateformat=civilpattern) == Date(2024, 1, 2)
        whitespace = CheckedTailBytes(n, " ")
        for T in (Int64, Float64, BigInt, BigFloat, Bool)
            @test Parsers.tryparse(T, whitespace, n, n) === nothing
        end

        invalidpublic = CheckedTailBytes(n, "x")
        for T in (Int64, Float64, Bool, BigInt, BigFloat, Base.UUID, Date)
            err = try
                Parsers.parse(T, invalidpublic, n, n)
                nothing
            catch caught
                caught
            end
            @test err isa ArgumentError
            @test occursin("x", sprint(showerror, err))
            @test Parsers.tryparse(T, invalidpublic, n, n) === nothing
        end
        mpfrfallback = CheckedTailBytes(n, "1@2")
        @test Parsers.parse(BigFloat, mpfrfallback, n - 2, n) == BigFloat(100)
        @test Parsers.tryparse(BigFloat, mpfrfallback, n - 2, n) == BigFloat(100)

        radix = CheckedTailBytes(n, "ff")
        @test Parsers.parseint(Int64, radix, n - 1, n, 16) ==
              (Int64(255), Parsers.RC_OK, 0)
        @test Parsers.parsebigint(radix, n - 1, n, 16) ==
              (BigInt(255), Parsers.RC_OK, 0)
        invalidradix = CheckedTailBytes(n, "fg")
        @test Parsers.parseint(Int64, invalidradix, n - 1, n, 16) ==
              (Int64(0), Parsers.RC_INVALID, n)
        @test Parsers.parsebigint(invalidradix, n - 1, n, 16) ==
              (BigInt(0), Parsers.RC_INVALID, n)
        signonly = CheckedTailBytes(n, "+")
        @test Parsers.parseint(Int64, signonly, n, n, 16) ==
              (Int64(0), Parsers.RC_INVALID, n)
        @test Parsers.parsebigint(signonly, n, n, 16) ==
              (BigInt(0), Parsers.RC_INVALID, n)
        @test Parsers.tryparse(Int64, signonly, n, n; base=16) === nothing
        @test_throws ArgumentError Parsers.parse(Int64, signonly, n, n; base=16)

        groupedint = CheckedTailBytes(n, "1_2")
        @test Parsers.parsegroupedint64(groupedint, n - 2, n, UInt8('_')) ==
              (Int64(12), Parsers.RC_OK)
        @test Parsers.parsegroupedint(Int64, groupedint, n - 2, n,
                                     UInt8('_'), 10) ==
              (Int64(12), Parsers.RC_OK, 0)
        invalidgroup = CheckedTailBytes(n, "1__2")
        @test Parsers.parsegroupedint(Int64, invalidgroup, n - 3, n,
                                     UInt8('_'), 10) ==
              (Int64(0), Parsers.RC_INVALID, n - 2)

        decimal = CheckedTailBytes(n, "1.5")
        for T in (Float16, Float32, Float64)
            @test Parsers.parsefloat(T, decimal, n - 2, n) ==
                  (T(1.5), Parsers.RC_OK)
        end
        special = CheckedTailBytes(n, "Infinity")
        @test Parsers.parsefloat(Float64, special, n - 7, n) ==
              (Inf, Parsers.RC_OK)
        hexfloat = CheckedTailBytes(n, "0x1.8p1")
        @test Parsers._parsehexfloat(Float64, hexfloat, n - 6, n) ==
              (3.0, Parsers.RC_OK)
        groupedfloat = CheckedTailBytes(n, "1_2.5")
        @test Parsers.parsegroupedfloatpublic(Float64, groupedfloat, n - 4, n,
                                              UInt8('.'), UInt8('_')) ==
              (12.5, Parsers.RC_OK)
        bighex = CheckedTailBytes(n, "0x1.8p1")
        bighexvalue, bighexcode = Parsers.parsebigfloat(bighex, n - 6, n)
        @test isequal(bighexvalue, BigFloat(3))
        @test bighexcode == Parsers.RC_OK

        civil = CheckedTailBytes(n, "2024-01-02/")
        parts, civilcode = Parsers.parsecivil(civil, n - 10, n, civilpattern)
        @test parts == Parsers.CivilParts(2024, 1, 2, 0, 0, 0, 0)
        @test civilcode == Parsers.RC_OK
        uuid = CheckedTailBytes(n, uuidtext)
        @test Parsers.parseuuid(uuid, n - 35, n) ==
              (expecteduuid, Parsers.RC_OK)
    end

    # DecParts keeps its hot 24-byte layout. Values at or outside its 32-bit
    # state saturate, and an unrepresentable relative digit offset uses one
    # negative marker instead of throwing during a valid parse. Exponents can
    # exceed machine Int, while digit counts and source positions cannot.
    wideexp = Int128(typemax(Int32)) + 42
    bounded = Parsers._decparts(UInt64(1), wideexp, typemax(Int), true, false,
                                typemax(Int), Parsers._INDEX_WINDOW_FIRST)
    @test sizeof(Parsers.DecParts) == 24
    @test Parsers._decparts(UInt64(1), 0, 19, false, false, 1, 1).ndig == 19
    @test Parsers._decparts(UInt64(1), 0, Int(typemax(Int32)), false,
                            false, 1, 1).ndig == typemax(Int32)
    @test bounded.exp10 == typemax(Int32)
    @test bounded.ndig == typemax(Int32)
    @test bounded.digoffset == Parsers._DECPARTS_OFFSET_SENTINEL
    @test Parsers._decpartsint32(typemin(Int)) == typemin(Int32)
    @test Parsers._decpartsexp32(typemax(Int32)) == typemax(Int32)
    @test Parsers._decpartsexp32(-typemax(Int32)) == -typemax(Int32)
    @test Parsers._decpartsexp32(Int128(typemax(Int32)) + 1) == typemax(Int32)
    @test Parsers._decpartsexp32(-Int128(typemax(Int32)) - 1) ==
          -typemax(Int32)
    @test Parsers._decpartsexp32(-wideexp) == -typemax(Int32)
    @test Parsers._decpartsdigoffset(0, 1) == 0
    @test Parsers._decpartsdigoffset(1, 1) == 1
    @test Parsers._decpartsdigoffset(Int(typemax(Int32)), 1) == typemax(Int32)

    # Force the sentinel for signed, leading-fraction-zero, exponent, and
    # grouped tokens. The BigFloat prepass locates the coefficient and decimal
    # position together without parsing the validated grammar again.
    sentinelcases = (
        ("-000001.25", BigFloat(-1.25), nothing),
        ("0.00000125", Base.parse(BigFloat, "0.00000125"), nothing),
        ("000001.25e2", BigFloat(125), nothing),
        ("0,000,001.25", BigFloat(1.25), UInt8(',')),
    )
    for (text, expected, groupmark) in sentinelcases
        source = [b(text); UInt8(';')]
        parts, nextpos, code = Parsers._decomposeprefix(
            source, 1, length(source), UInt8('.'), groupmark)
        @test code == Parsers.RC_OK
        @test nextpos == length(source)
        marked = Parsers.DecParts(parts.mant, parts.exp10, parts.ndig,
                                  parts.truncated, parts.neg,
                                  Parsers._DECPARTS_OFFSET_SENTINEL)
        value, code = Parsers._leasedbigfloatfromparts(
            source, 1, nextpos - 1, UInt8('.'), marked, precision(BigFloat),
            Base.Rounding.rounding(BigFloat), groupmark)
        @test isequal(value, expected)
        @test code == Parsers.RC_OK
    end

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

@testset "radix prefixes commit only after a digit" begin
    prefix_types = (Int8, Int64, UInt64, BigInt, Float16, Float32, Float64,
                    BigFloat)
    for T in prefix_types, text in ("0x,", "0xg", "0x.p1", "0b2", "0o8")
        value, nextpos, code = Parsers.parsenext(T, b(text), 1,
                                                 ncodeunits(text))
        @test isequal(value, zero(T))
        @test nextpos == 2
        @test code == Parsers.RC_OK
        @test Parsers.tryparse(T, text) === nothing
    end
    for T in prefix_types
        value, nextpos, code = Parsers.parsenext(T, b("0x1;"), 1, 4)
        @test isequal(value, one(T))
        @test nextpos == 4
        @test code == Parsers.RC_OK
    end

    # Whole-value parsing still commits the introducer before it diagnoses the
    # missing or invalid radix digit, matching Base's error classification.
    for T in (Int, BigInt), text in ("0x", "0xg", "0x.p1")
        base_error = try
            Base.parse(T, text)
            nothing
        catch err
            err
        end
        parsers_error = try
            Parsers.parse(T, text)
            nothing
        catch err
            err
        end
        @test typeof(parsers_error) === typeof(base_error)
        @test sprint(showerror, parsers_error) == sprint(showerror, base_error)
    end
end

@testset "unsupported parsenext targets are configuration errors" begin
    for T in (Date, Base.UUID, String, Char), source in (UInt8[], b("x"))
        first, last = isempty(source) ? (1, 0) : (1, 1)
        @test_throws ArgumentError Parsers.parsenext(T, source, first, last)
    end
end

@testset "float prefixes commit only complete grammar" begin
    cases = (
        ("1e,", 1.0, 2, Parsers.RC_OK),
        ("1e+,", 1.0, 2, Parsers.RC_OK),
        ("1e-2;", 0.01, 5, Parsers.RC_OK),
        ("0x1p,", 1.0, 4, Parsers.RC_OK),
        ("0x1p+,", 1.0, 4, Parsers.RC_OK),
        ("0x1.fp2;", 7.75, 8, Parsers.RC_OK),
        ("Inf;", Inf, 4, Parsers.RC_OK),
        ("Infinity;", Inf, 9, Parsers.RC_OK),
        ("Infi;", Inf, 4, Parsers.RC_OK),
    )
    for T in (Float16, Float32, Float64), (text, expected, nextpos, code) in cases
        value, actualnext, actualcode = Parsers.parsenext(T, b(text), 1,
                                                          ncodeunits(text))
        @test isequal(value, T(expected))
        @test actualnext == nextpos
        @test actualcode == code
    end

    for T in (Float16, Float32, Float64)
        @test Parsers.parsenext(T, b("1,234.5;"), 1, 8; groupmark=',') ==
              (T(1234.5), 8, Parsers.RC_OK)
        @test Parsers.parsenext(T, b("1,,2"), 1, 4; groupmark=',') ==
              (one(T), 2, Parsers.RC_OK)
        @test Parsers.parsenext(T, b("1,25;"), 1, 5; decimal=',') ==
              (T(1.25), 5, Parsers.RC_OK)
        for decimal in ('i', 'I', 'n', 'N')
            source = b(string(decimal, "5;"))
            @test Parsers.parsenext(T, source, 1, length(source); decimal) ==
                  (T(0.5), 3, Parsers.RC_OK)
        end
    end

    padded = b("xx12.5;yy")
    @test Parsers.parsenext(Float64, padded, 3, 7) ==
          (12.5, 7, Parsers.RC_OK)
    @test Parsers.parsenext(Float64, codeunits("12.5;"), 1, 5) ==
          (12.5, 5, Parsers.RC_OK)
    @test Parsers.parsenext(Float64, @view(padded[3:7]), 1, 5) ==
          (12.5, 5, Parsers.RC_OK)
    interleaved = UInt8['1', 'x', '2', 'x', '.', 'x', '5', 'x', ';']
    @test Parsers.parsenext(Float64, @view(interleaved[1:2:end]), 1, 5) ==
          (12.5, 5, Parsers.RC_OK)

    # These shapes exercise the short fused coefficient path, the wide digit
    # gatherer, and the exact midpoint tail without scanning the grammar twice.
    hard32 = "1.000000059604644775390626"
    hard64 = "1.00000000000000011102230246251565404236316680908203126"
    for (T, text) in ((Float16, "1.5"), (Float16, "65519.999"),
                      (Float32, hard32), (Float64, hard64))
        token = b(text)
        expected, expectedcode = Parsers.parsefloat(T, token, 1, length(token))
        source = [token; UInt8(';')]
        actual, nextpos, code = Parsers.parsenext(T, source, 1, length(source))
        @test isequal(actual, expected)
        @test nextpos == length(token) + 1
        @test code == expectedcode
    end

    # The twentieth coefficient byte returns an explicit continuation result.
    # Resuming it must produce the same conversion fields and token boundary as
    # the general decomposer, including leading zeros and exponent commit.
    carrytexts = (
        "12345678901234567890;",
        "1234567890123456789.0;",
        "000000000000000000001.5;",
        "0.000000000000000000001;",
        "1." * repeat("2345678901", 6) * "e-17;",
        "12345678901234567890e+;",
    )
    for text in carrytexts
        source = b(text)
        scan = Parsers._shortdecimalparts(source, 1, length(source), UInt8('.'))
        @test Parsers._shortcarry(scan)
        parts, continuednext, continuedcode =
            Parsers._continuelongdecimalparts(source, 1, scan.nextpos,
                                              length(source), UInt8('.'), scan)
        general, generalnext, generalcode =
            Parsers._decomposeplainprefix(source, 1, length(source), UInt8('.'))
        @test (parts.mant, parts.exp10, parts.ndig, parts.truncated, parts.neg,
               continuednext, continuedcode) ==
              (general.mant, general.exp10, general.ndig, general.truncated,
               general.neg, generalnext, generalcode)
    end

    # A complete short coefficient with an enormous exponent is not a carry.
    # Both that path and the carried twentieth-digit path must consume the
    # exponent and report the target range without reading absent carry state.
    hugeexp = repeat("9", 80)
    for T in (Float16, Float32, Float64),
        coefficient in ("1234567890123456789", "12345678901234567890"),
        (esign, expectedcode) in (("+", Parsers.RC_OVERFLOW),
                                  ("-", Parsers.RC_UNDERFLOW))
        text = coefficient * "e" * esign * hugeexp * ";x"
        source = codeunits(text)
        _, nextpos, code = Parsers.parsenext(T, source, 1, length(source))
        @test nextpos == ncodeunits(text) - 1
        @test code == expectedcode
    end

    # Exercise each requested carry length through all public byte source
    # shapes. The exact span kernel supplies the independent expected value.
    for T in (Float16, Float32, Float64), digits in (20, 21, 39, 55)
        tail = repeat("2345678901", cld(digits - 1, 10))[1:(digits - 1)]
        token = b("1." * tail)
        expected, expectedcode = Parsers.parsefloat(T, token, 1, length(token))
        delimited = [token; UInt8(';'); UInt8('x')]
        padded = [UInt8('!'); UInt8('!'); delimited]
        sources = ((delimited, 1, length(delimited)),
                   (codeunits(String(copy(delimited))), 1, length(delimited)),
                   (@view(padded[3:end]), 1, length(delimited)),
                   (padded, 3, length(padded)))
        for (source, first, last) in sources
            actual, nextpos, code = Parsers.parsenext(T, source, first, last)
            @test isequal(actual, expected)
            @test nextpos == first + length(token)
            @test code == expectedcode
        end
    end
    @test Parsers.parsenext(Float64, b("x,"), 1, 2) ==
          (0.0, 1, Parsers.RC_INVALID)

    hardbytes = b(hard64)
    prefixedhard = [hardbytes; UInt8(';')]
    parts, nextpos, code = Parsers._decomposeprefix(prefixedhard, 1,
                                                    length(prefixedhard),
                                                    UInt8('.'), nothing)
    exactparts, exactcode = Parsers._decompose(hardbytes, 1, length(hardbytes),
                                               UInt8('.'))
    @test (parts, code) == (exactparts, exactcode)
    @test nextpos == length(hardbytes) + 1

    for text in ("1.5", "1." * repeat("2345678901", 8), "0x1.8p200")
        token = b(text)
        expected, expectedcode = Parsers.parsebigfloat(token, 1, length(token))
        source = [token; UInt8(';')]
        actual, nextpos, code = Parsers.parsenext(BigFloat, source, 1,
                                                  length(source))
        @test isequal(actual, expected)
        @test nextpos == length(token) + 1
        @test code == expectedcode
    end

    # Long decimal prefixes use a bounded leading interval. Equal rounded
    # endpoints prove the result for every omitted suffix; a disagreement
    # falls back to the exact full coefficient. Exercise both outcomes and all
    # rounding directions against MPFR's native BigFloat conversion.
    setprecision(BigFloat, 53) do
        coefficient = repeat("1234567890", 200)
        midpoint = "1.00000000000000011102230246251565404236316680908203125" *
                   repeat("0", 200)
        grouped = join(fill("123", 700), ",")
        for mode in (RoundNearest, RoundToZero, RoundUp, RoundDown, RoundFromZero)
            for (text, source, groupmark) in (
                (coefficient, coefficient * ";", nothing),
                ("0." * coefficient, "0." * coefficient * ";", nothing),
                (coefficient * "e-1999", coefficient * "e-1999;", nothing),
                (midpoint, midpoint * ";", nothing),
                (replace(grouped, "," => ""), grouped * ";", ','),
            )
                expected = setrounding(BigFloat, mode) do
                    Base.parse(BigFloat, text)
                end
                bytes = b(text)
                exact, exactcode = Parsers.parsebigfloat(
                    bytes, 1, length(bytes); prec=53, rounding=mode)
                @test exactcode == Parsers.RC_OK
                @test isequal(exact, expected)
                prefix, nextpos, prefixcode = Parsers.parsenext(
                    BigFloat, b(source), 1, ncodeunits(source);
                    rounding=mode, groupmark)
                @test prefixcode == Parsers.RC_OK
                @test nextpos == ncodeunits(source)
                @test isequal(prefix, expected)
            end
        end
    end

    reusable_long = b("0." * repeat("1234567890", 200) * ";")
    parsenextbigfloat(reusable_long)
    @test @allocated(parsenextbigfloat(reusable_long)) <= 256

    rounding_source = b("1.0000000000000000000000000000000000000001;")
    for mode in (RoundNearest, RoundToZero, RoundUp, RoundDown, RoundFromZero)
        scoped = setrounding(BigFloat, mode) do
            Parsers.parsenext(BigFloat, rounding_source, 1,
                              length(rounding_source))
        end
        explicit = Parsers.parsenext(BigFloat, rounding_source, 1,
                                     length(rounding_source); rounding=mode)
        @test isequal(scoped, explicit)
    end

    # Eighteen exponent digits fit UInt64 but not 32-bit Int. These values
    # previously wrapped to ±1 during the BigFloat digit reread on x86.
    for exponent in ("4294967297", "-4294967295")
        exact = b("1e" * exponent)
        @test Parsers.parsebigfloat(exact, 1, length(exact))[2] ==
              Parsers.RC_OVERFLOW
        for (text, groupmark) in (("1e" * exponent, nothing),
                                  ("1,0e" * exponent, ','))
            token = b(text)
            source = [token; UInt8(';')]
            _, nextpos, code = Parsers.parsenext(
                BigFloat, source, 1, length(source); groupmark)
            @test nextpos == length(token) + 1
            @test code == Parsers.RC_OVERFLOW
        end
    end

    # Exponents just outside Int can still cancel a wide coefficient offset.
    # The final decimal scale is representable and must not be rejected while
    # the UInt64 exponent accumulator is still reading digits.
    aboveint = string(Int128(typemax(Int)) + 1)
    positive = b("e" * aboveint)
    positivefrac = typemax(Int) - 30
    @test Parsers._bigfloatexponent(positive, 1, length(positive),
                                    1 - positivefrac, positivefrac) ==
          (31, true)
    negative = b("e-" * aboveint)
    @test Parsers._bigfloatexponent(negative, 1, length(negative),
                                    typemax(Int) - 30, 0) ==
          (typemin(Int), true)

    # A long coefficient and a large explicit exponent can cancel exactly.
    # The bounded exponent accumulator must retain that cancellation, while
    # adjacent magnitudes still return the correct range status.
    million = 1_000_000
    millionzeros = repeat("0", million)
    longcases = (
        ("1" * millionzeros * "e-$million", 1.0, Parsers.RC_OK),
        ("0." * millionzeros * "1e$(million + 1)", 1.0, Parsers.RC_OK),
        ("1" * millionzeros * "e-$(million - 309)", Inf,
         Parsers.RC_OVERFLOW),
        ("0." * millionzeros * "1e$(million - 324)", 0.0,
         Parsers.RC_UNDERFLOW),
    )
    for (text, expected, expectedcode) in longcases
        token = b(text)
        actual, code = Parsers.parsefloat(Float64, token, 1, length(token))
        @test isequal(actual, expected)
        @test code == expectedcode
        source = [token; UInt8(';')]
        actual, nextpos, code = Parsers.parsenext(Float64, source, 1,
                                                  length(source))
        @test isequal(actual, expected)
        @test nextpos == length(token) + 1
        @test code == expectedcode
    end

    harddigits = replace(hard64, "." => "")
    hardfraction = length(hard64) - findfirst(==('.'), hard64)
    scaledhard = harddigits * millionzeros *
                 "e-$(million + hardfraction)"
    hardexpected, hardcode = Parsers.parsefloat(Float64, hardbytes, 1,
                                                length(hardbytes))
    scaledbytes = b(scaledhard)
    @test Parsers.parsefloat(Float64, scaledbytes, 1, length(scaledbytes)) ==
          (hardexpected, hardcode)
    scaledsource = [scaledbytes; UInt8(';')]
    @test Parsers.parsenext(Float64, scaledsource, 1, length(scaledsource)) ==
          (hardexpected, length(scaledbytes) + 1, hardcode)

    # Hexadecimal coefficient shifts can cancel a large binary exponent too.
    # Cover both signs of `p` beyond the old six-digit accumulator, plus the
    # Float64 overflow and underflow neighbours.
    hexinteger = "0x1" * millionzeros * "p-$(4million)"
    hexfraction = "0x0." * millionzeros * "1p$(4 * (million + 1))"
    for text in (hexinteger, hexfraction), T in (Float16, Float32, Float64)
        token = b(text)
        @test Parsers._parsehexfloat(T, token, 1, length(token)) ==
              (one(T), Parsers.RC_OK)
        source = [token; UInt8(';')]
        @test Parsers.parsenext(T, source, 1, length(source)) ==
              (one(T), length(token) + 1, Parsers.RC_OK)
    end

    hexoverflow = b("0x1" * millionzeros * "p-$(4million - 1024)")
    overflowvalue, overflowcode = Parsers._parsehexfloat(
        Float64, hexoverflow, 1, length(hexoverflow))
    @test isinf(overflowvalue)
    @test overflowcode == Parsers.RC_OVERFLOW
    hexunderflow = b("0x1" * millionzeros * "p-$(4million + 1075)")
    @test Parsers._parsehexfloat(Float64, hexunderflow, 1,
                                length(hexunderflow)) ==
          (0.0, Parsers.RC_UNDERFLOW)

    # BigFloat owns the same wide exponent syntax. The fractional case keeps
    # its GMP coefficient small while still crossing the old exponent bound.
    bighex = b(hexfraction)
    bighexvalue, bighexcode = Parsers.parsebigfloat(bighex, 1, length(bighex))
    @test bighexvalue == BigFloat(1)
    @test bighexcode == Parsers.RC_OK
    bighexsource = [bighex; UInt8(';')]
    @test Parsers.parsenext(BigFloat, bighexsource, 1,
                            length(bighexsource)) ==
          (BigFloat(1), length(bighex) + 1, Parsers.RC_OK)

    for T in (Float16, Float32, Float64)
        source = b("123.5;")
        parsenextdefault(T, source)
        # Julia 1.10 boxes this isbits float tuple return. Later Julia releases
        # keep it on the stack.
        allocation_limit = VERSION < v"1.11" ? 32 : 0
        @test (@allocated parsenextdefault(T, source)) <= allocation_limit
    end
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
            bytes = codeunits(text)
            _, rc = Parsers._parsefloatspan(T, bytes, 1, length(bytes), UInt8('.'), nothing)
            expected = rc == Parsers.RC_OVERFLOW || rc == Parsers.RC_UNDERFLOW ? nothing :
                       Base.tryparse(T, text)
            record(isequal(Parsers.tryparse(T, text), expected),
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
