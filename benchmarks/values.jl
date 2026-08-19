# ns/value for the kernels vs Base.parse across a value-shape grid.
#
# Run:  julia --project=. benchmarks/values.jl        (Base only — no extra deps)
#
# Each case: many same-shape values concatenated; we time parsing all of them
# through precomputed spans so the measurement is pure value-parse cost.
using Parsers, Dates, Random

function makecorpus(gen, n)
    rng = MersenneTwister(1234)
    vals = [gen(rng, i) for i in 1:n]
    buf = Vector{UInt8}(join(vals, '\n') * "\n" * " "^16)   # slack for word loads
    spans = Tuple{Int, Int}[]
    s = 1
    for v in vals
        push!(spans, (s, s + ncodeunits(v) - 1))
        s += ncodeunits(v) + 1
    end
    return buf, spans
end

function bench(f, buf, spans; reps=7)
    f(buf, spans)
    best = Inf
    for _ in 1:reps
        best = min(best, @elapsed f(buf, spans))
    end
    return best / length(spans) * 1e9
end
fmt(x) = lpad(isnan(x) ? "—" : string(round(x, digits=1)), 9)

kern(::Type{T}) where {T <: Integer} = (b, ss) -> (a = 0; for (i, j) in ss; v, rc = Parsers.parseint(T, b, i, j); a += v; end; a)
kern(::Type{T}) where {T <: Union{Float64, Float32}} = (b, ss) -> (a = 0.0; for (i, j) in ss; v, rc = Parsers.parsefloat(T, b, i, j); a += v; end; a)
base(::Type{T}) where {T} = (b, ss) -> (a = zero(T); for (i, j) in ss; a += Base.parse(T, String(b[i:j])); end; a)

function main()
    n = 100_000
    println(rpad("shape", 24), lpad("kernel", 9), lpad("Base", 9), "   (ns/value)")
    println("─"^52)
    cases = [
        ("int 1-4 digits",     Int64,   (rng, i) -> string(rand(rng, -9999:9999))),
        ("int 5-9 digits",     Int64,   (rng, i) -> string(rand(rng, 10_000:999_999_999))),
        ("int 10-18 digits",   Int64,   (rng, i) -> string(rand(rng, Int64(10)^10:Int64(10)^17))),
        ("uint64",             UInt64,  (rng, i) -> string(rand(rng, UInt64))),
        ("int128",             Int128,  (rng, i) -> string(rand(rng, Int128))),
        ("float short (x.y)",  Float64, (rng, i) -> string(round(rand(rng) * 1000, digits=3))),
        ("float shortest",     Float64, (rng, i) -> string(reinterpret(Float64, rand(rng, UInt64) & 0x7fefffffffffffff))),
        ("float exp form",     Float64, (rng, i) -> string(rand(rng, 1:999)) * "." * string(rand(rng, 0:99)) * "e" * string(rand(rng, -30:30))),
        ("float32 shortest",   Float32, (rng, i) -> string(reinterpret(Float32, rand(rng, UInt32) & 0x7f7fffff))),
    ]
    for (name, T, gen) in cases
        buf, spans = makecorpus(gen, n)
        println(rpad(name, 24), fmt(bench(kern(T), buf, spans)), fmt(bench(base(T), buf, spans)))
    end
    # dates, bools, uuids through the public API's kernels
    buf, spans = makecorpus((rng, i) -> string(Date(2020, 1, 1) + Day(rand(rng, 0:2000))), n)
    tk = bench((b, ss) -> (a = 0; for (i, j) in ss; c, rc = Parsers.parseiso10(b, i); a += c.day; end; a), buf, spans)
    tb = bench((b, ss) -> (a = 0; for (i, j) in ss; a += Dates.day(Date(String(b[i:j]))); end; a), buf, spans)
    println(rpad("date ISO", 24), fmt(tk), fmt(tb))
    buf, spans = makecorpus((rng, i) -> string(DateTime(2020, 1, 1) + Second(rand(rng, 0:10^7))), n)
    tk = bench((b, ss) -> (a = 0; for (i, j) in ss; c, rc = Parsers.parseiso19(b, i); a += c.second; end; a), buf, spans)
    tb = bench((b, ss) -> (a = 0; for (i, j) in ss; a += Dates.second(DateTime(String(b[i:j]))); end; a), buf, spans)
    println(rpad("datetime ISO", 24), fmt(tk), fmt(tb))
    buf, spans = makecorpus((rng, i) -> string(Base.UUID(rand(rng, UInt128))), n)
    tk = bench((b, ss) -> (a = UInt128(0); for (i, j) in ss; v, rc = Parsers.parseuuid(b, i, j); a ⊻= v; end; a), buf, spans)
    tb = bench((b, ss) -> (a = UInt128(0); for (i, j) in ss; a ⊻= Base.parse(Base.UUID, String(b[i:j])).value; end; a), buf, spans)
    println(rpad("uuid", 24), fmt(tk), fmt(tb))
    buf, spans = makecorpus((rng, i) -> rand(rng, ("true", "false")), n)
    tk = bench((b, ss) -> (a = 0; for (i, j) in ss; v, rc = Parsers.parsebool(b, i, j); a += v; end; a), buf, spans)
    tb = bench((b, ss) -> (a = 0; for (i, j) in ss; a += Base.parse(Bool, String(b[i:j])); end; a), buf, spans)
    println(rpad("bool", 24), fmt(tk), fmt(tb))
    # the public whole-string API (what most callers use), incl. its overhead
    strs = [string(rand(MersenneTwister(9), Int64)) for _ in 1:n]
    tk = (f = () -> (a = 0; for s in strs; a += Parsers.parse(Int64, s); end; a); f(); minimum(@elapsed(f()) for _ in 1:7) / n * 1e9)
    tb = (f = () -> (a = 0; for s in strs; a += Base.parse(Int64, s); end; a); f(); minimum(@elapsed(f()) for _ in 1:7) / n * 1e9)
    println(rpad("parse(Int64, ::String)", 24), fmt(tk), fmt(tb))
end

main()
