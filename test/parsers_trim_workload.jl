# Trim-compile workload: exercises the float parse paths, in particular every
# rung of the overflow-widening ladder (UInt64 → UInt128 → BigInt) that the
# trim fix makes statically reachable — under the old Base.inferencebarrier
# form these calls were verifier errors AND the widened instances were absent
# from trimmed binaries (wide-mantissa parses would fail at runtime). It also
# compiles date formats at run time: `compilepattern`, format strings, and
# `DateFormat` values, including ones that reach the run-time format caches.
# Compiled by test/trim_compile_tests.jl with `juliac --trim=safe` (error
# budget zero), then executed so the value assertions prove runtime rounding too.
using Dates
using Parsers

function _assert_float_basics()::Nothing
    Parsers.parse(Float64, "1.5") === 1.5 || error("float basic")
    Parsers.parse(Float64, "-2.25e3") === -2250.0 || error("float exponent")
    Parsers.parse(Float64, "0.1") === 0.1 || error("float rounding")
    Parsers.parse(Float64, "0") === 0.0 || error("float zero")
    Parsers.parse(Float32, "1.5") === 1.5f0 || error("float32")
    Parsers.parse(Float16, "0.5") === Float16(0.5) || error("float16")
    return nothing
end

# the widening ladder itself: mantissas that overflow UInt64 (first rung) and
# UInt128 (second rung, into BigInt). Expected values are Base.parse results —
# Parsers must agree bit-for-bit.
function _assert_widening_ladder()::Nothing
    # 21 significant digits: overflows UInt64 accumulation -> UInt128
    Parsers.parse(Float64, "123456789012345678901.5") === 1.234567890123456789015e20 ||
        error("UInt128 rung")
    # 45 significant digits: overflows UInt128 -> BigInt
    Parsers.parse(Float64, "123456789012345678901234567890123456789012345.0") ===
        1.2345678901234567e44 || error("BigInt rung")
    # wide fractional digits take the _parsefrac widening path
    Parsers.parse(Float64, "0.123456789012345678901234567890123456789012345") ===
        0.12345678901234568 || error("frac widening")
    # widening in the presence of an exponent (_parseexp path)
    Parsers.parse(Float64, "123456789012345678901234567890e-10") ===
        1.2345678901234568e19 || error("exp widening")
    return nothing
end

function _assert_float_edges()::Nothing
    Parsers.tryparse(Float64, "1e310") === nothing || error("overflow tryparse")
    Parsers.tryparse(Float64, "-1e310") === nothing || error("negative overflow tryparse")
    try
        Parsers.parse(Float64, "1e310")
        error("overflow parse accepted")
    catch err
        err isa ArgumentError || rethrow()
    end
    try
        Parsers.parse(Float64, "-1e310")
        error("negative overflow parse accepted")
    catch err
        err isa ArgumentError || rethrow()
    end
    Parsers.parse(Float64, "5e-324") === 5.0e-324 || error("denormal")
    Parsers.parse(Float64, "1.7976931348623157e308") === floatmax(Float64) || error("floatmax")
    isnan(Parsers.parse(Float64, "NaN")) || error("nan")
    Parsers.parse(Float64, "Inf") === Inf || error("inf literal")
    return nothing
end

function _assert_non_floats()::Nothing
    Parsers.parse(Int, "12345") === 12345 || error("int")
    Parsers.parse(Int, "-7") === -7 || error("negative int")
    Parsers.tryparse(Float64, "abc") === nothing || error("tryparse miss")
    t = Parsers.tryparse(Float64, "2.5")
    (t isa Float64 && t === 2.5) || error("tryparse hit")
    Parsers.parse(Bool, "true") === true || error("bool")
    return nothing
end

# runtime-compiled formats through the fixed-width descriptor, the numeric
# delimited reader (variable widths), and the general interpreter (names)
function _assert_date_patterns()::Nothing
    p = Parsers.compilepattern("yyyy/mm/dd")
    Parsers.parse(Date, "2024/03/15"; dateformat=p) === Date(2024, 3, 15) ||
        error("fixed-width date pattern")
    Parsers.parse(Date, "2024/3/5"; dateformat=p) === Date(2024, 3, 5) ||
        error("numeric date pattern")
    p = Parsers.compilepattern("d u yyyy HH:MM")
    Parsers.parse(DateTime, "5 Mar 2024 13:45"; dateformat=p) ===
        DateTime(2024, 3, 5, 13, 45) || error("named date pattern")
    return nothing
end

# Building a DateFormat from a string at run time is not trim-safe inside
# Dates, so these formats are built while the program compiles. Behind a Ref,
# their values stay opaque to inference: a hand-built format whose tokens
# differ from its type's source string takes the run-time fallback, and a
# non-English named format takes the per-locale cache.
const _SLASH = dateformat"yyyy/mm/dd"
const _SAME_TYPE_SLASH = Ref(Dates.DateFormat{Symbol("yyyy-mm-dd"), typeof(_SLASH.tokens)}(
    _SLASH.tokens, Dates.ENGLISH))
const _LOCALIZED = Ref(Dates.DateFormat("U dd yyyy", Dates.DateLocale(
    ["Alfa", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot",
     "Golf", "Hotel", "India", "Juliett", "Kilo", "Lima"],
    ["Ab", "Bc", "Cd", "De", "Ef", "Fg", "Gh", "Hi", "Ij", "Jk", "Kl", "Lm"],
    ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
    ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"])))

function _assert_date_formats()::Nothing
    expected = Date(2024, 3, 15)
    # the first call compiles and caches the format; the second reuses it
    for _ in 1:2
        Parsers.parse(Date, "2024/03/15"; dateformat="yyyy/mm/dd") === expected ||
            error("format string")
    end
    Parsers.parse(Date, "2024/03/15"; dateformat=SubString("xyyyy/mm/dd", 2)) ===
        expected || error("format substring")
    Parsers.parse(Date, "2024/03/15"; dateformat=dateformat"yyyy/mm/dd") === expected ||
        error("DateFormat literal")
    p = Parsers.compilepattern(dateformat"yyyy/mm/dd")
    Parsers.parse(Date, "2024/03/15"; dateformat=p) === expected ||
        error("compiled DateFormat")
    Parsers.parse(Date, "2024/03/15"; dateformat=_SAME_TYPE_SLASH[]) === expected ||
        error("run-time DateFormat")
    Parsers.tryparse(Date, "2024-03-15"; dateformat=_SAME_TYPE_SLASH[]) === nothing ||
        error("run-time DateFormat mismatch")
    Parsers.parse(Date, "Charlie 15 2024"; dateformat=_LOCALIZED[]) === expected ||
        error("localized DateFormat")
    try
        Parsers.parse(Date, "2024-03-15"; dateformat=_SAME_TYPE_SLASH[])
        error("DateFormat mismatch accepted")
    catch err
        err isa ArgumentError || rethrow()
    end
    return nothing
end

function run_parsers_trim_workload()::Nothing
    _assert_float_basics()
    _assert_widening_ladder()
    _assert_float_edges()
    _assert_non_floats()
    _assert_date_patterns()
    _assert_date_formats()
    return nothing
end

function @main(args::Vector{String})::Cint
    _ = args
    run_parsers_trim_workload()
    return 0
end

Base.Experimental.entrypoint(main, (Vector{String},))
