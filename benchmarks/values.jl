# Dependency-free microbenchmarks for Parsers kernels and public whole-string
# calls. Keep the full environment header with any published result.
#
# Run from the repository root:
#
#     julia --project=. benchmarks/values.jl

using Dates
using Parsers
using Random

const CORPUS_SIZE = 100_000
const SAMPLE_COUNT = 9
const SEED = 0x0000_0000_5eed_1234

function gitcommit()
    try
        return readchomp(`git rev-parse --verify HEAD`)
    catch
        return "unknown"
    end
end

function print_environment()
    println("Parsers value benchmark")
    println("  Parsers:   ", Base.pkgversion(Parsers))
    println("  Julia:     ", VERSION)
    println("  commit:    ", gitcommit())
    println("  machine:   ", Sys.MACHINE)
    println("  CPU:       ", Sys.CPU_NAME)
    println("  word size: ", Sys.WORD_SIZE)
    println("  threads:   ", Threads.nthreads())
    println("  corpus:    ", CORPUS_SIZE, " values per shape")
    println("  seed:      0x", string(SEED; base=16))
    println("  statistic: minimum of ", SAMPLE_COUNT, " samples after one warmup")
    println("  note:      Base span cases materialize each String slice")
    println()
end

function makecorpus(generate, n, seed)
    rng = MersenneTwister(seed)
    values = [generate(rng, i) for i in 1:n]
    # The slack permits the kernels' guarded word loads at the end of the last
    # value. It is outside every measured span.
    buffer = Vector{UInt8}(join(values, '\n') * "\n" * " "^16)
    spans = Tuple{Int, Int}[]
    sizehint!(spans, n)
    first = 1
    for value in values
        last = first + ncodeunits(value) - 1
        push!(spans, (first, last))
        first = last + 2
    end
    return buffer, spans
end

function benchmark(f, input...; samples=SAMPLE_COUNT)
    result = f(input...)
    times = Float64[]
    sizehint!(times, samples)
    for _ in 1:samples
        GC.gc()
        elapsed = @elapsed result = f(input...)
        push!(times, elapsed)
    end
    return minimum(times), result
end

format_ns(seconds, n) = lpad(string(round(seconds / n * 1e9; digits=1)), 12)

integer_kernel(::Type{T}) where {T <: Integer} = function (buffer, spans)
    checksum = zero(T)
    for (first, last) in spans
        value, _ = Parsers.parseint(T, buffer, first, last)
        checksum += value
    end
    return checksum
end

float_kernel(::Type{T}) where {T <: Union{Float64, Float32}} = function (buffer, spans)
    checksum = zero(T)
    for (first, last) in spans
        value, _ = Parsers.parsefloat(T, buffer, first, last)
        checksum += value
    end
    return checksum
end

base_parser(::Type{T}) where {T} = function (buffer, spans)
    checksum = zero(T)
    for (first, last) in spans
        checksum += Base.parse(T, String(buffer[first:last]))
    end
    return checksum
end

function report(name, parser_time, base_time, n)
    println(
        rpad(name, 28),
        format_ns(parser_time, n),
        format_ns(base_time, n),
        "   ns/value",
    )
end

function main()
    print_environment()
    println(rpad("shape", 28), lpad("Parsers", 12), lpad("Base", 12))
    println("─"^63)

    cases = [
        ("int 1-4 digits", Int64, integer_kernel,
         (rng, _) -> string(rand(rng, -9999:9999))),
        ("int 5-9 digits", Int64, integer_kernel,
         (rng, _) -> string(rand(rng, 10_000:999_999_999))),
        ("int 10-18 digits", Int64, integer_kernel,
         (rng, _) -> string(rand(rng, Int64(10)^10:Int64(10)^17))),
        ("uint64", UInt64, integer_kernel,
         (rng, _) -> string(rand(rng, UInt64))),
        ("int128", Int128, integer_kernel,
         (rng, _) -> string(rand(rng, Int128))),
        ("float short (x.y)", Float64, float_kernel,
         (rng, _) -> string(round(rand(rng) * 1000; digits=3))),
        ("float64 shortest", Float64, float_kernel,
         (rng, _) -> string(reinterpret(Float64, rand(rng, UInt64) & 0x7fefffffffffffff))),
        ("float exponent", Float64, float_kernel,
         (rng, _) -> string(rand(rng, 1:999), '.', rand(rng, 0:99), 'e', rand(rng, -30:30))),
        ("float32 shortest", Float32, float_kernel,
         (rng, _) -> string(reinterpret(Float32, rand(rng, UInt32) & 0x7f7fffff))),
    ]

    for (case_index, (name, type, kernel, generate)) in enumerate(cases)
        buffer, spans = makecorpus(generate, CORPUS_SIZE, SEED + UInt(case_index))
        parser_time, parser_checksum = benchmark(kernel(type), buffer, spans)
        base_time, base_checksum = benchmark(base_parser(type), buffer, spans)
        isequal(parser_checksum, base_checksum) ||
            error("checksum mismatch for $name: $parser_checksum != $base_checksum")
        report(name, parser_time, base_time, length(spans))
    end

    buffer, spans = makecorpus(
        (rng, _) -> string(Date(2020, 1, 1) + Day(rand(rng, 0:2000))),
        CORPUS_SIZE,
        SEED + 100,
    )
    parser_time, parser_checksum = benchmark(buffer, spans) do bytes, ranges
        checksum = 0
        for (first, _) in ranges
            value, _ = Parsers.parseiso10(bytes, first)
            checksum += value.day
        end
        checksum
    end
    base_time, base_checksum = benchmark(buffer, spans) do bytes, ranges
        checksum = 0
        for (first, last) in ranges
            checksum += Dates.day(Date(String(bytes[first:last])))
        end
        checksum
    end
    parser_checksum == base_checksum || error("checksum mismatch for date ISO")
    report("date ISO", parser_time, base_time, length(spans))

    buffer, spans = makecorpus(
        (rng, _) -> string(Base.UUID(rand(rng, UInt128))),
        CORPUS_SIZE,
        SEED + 101,
    )
    parser_time, parser_checksum = benchmark(buffer, spans) do bytes, ranges
        checksum = UInt128(0)
        for (first, last) in ranges
            value, _ = Parsers.parseuuid(bytes, first, last)
            checksum ⊻= value
        end
        checksum
    end
    base_time, base_checksum = benchmark(buffer, spans) do bytes, ranges
        checksum = UInt128(0)
        for (first, last) in ranges
            checksum ⊻= Base.parse(Base.UUID, String(bytes[first:last])).value
        end
        checksum
    end
    parser_checksum == base_checksum || error("checksum mismatch for UUID")
    report("UUID", parser_time, base_time, length(spans))

    buffer, spans = makecorpus(
        (rng, _) -> rand(rng, ("true", "false")),
        CORPUS_SIZE,
        SEED + 102,
    )
    parser_time, parser_checksum = benchmark(buffer, spans) do bytes, ranges
        checksum = 0
        for (first, last) in ranges
            value, _ = Parsers.parsebool(bytes, first, last)
            checksum += value
        end
        checksum
    end
    base_time, base_checksum = benchmark(buffer, spans) do bytes, ranges
        checksum = 0
        for (first, last) in ranges
            checksum += Base.parse(Bool, String(bytes[first:last]))
        end
        checksum
    end
    parser_checksum == base_checksum || error("checksum mismatch for Bool")
    report("Bool", parser_time, base_time, length(spans))

    rng = MersenneTwister(SEED + 103)
    strings = [string(rand(rng, Int64)) for _ in 1:CORPUS_SIZE]
    parser_time, parser_checksum = benchmark(strings) do values
        checksum = 0
        for value in values
            checksum += Parsers.parse(Int64, value)
        end
        checksum
    end
    base_time, base_checksum = benchmark(strings) do values
        checksum = 0
        for value in values
            checksum += Base.parse(Int64, value)
        end
        checksum
    end
    parser_checksum == base_checksum || error("checksum mismatch for public Int64")
    report("parse(Int64, String)", parser_time, base_time, length(strings))
end

main()
