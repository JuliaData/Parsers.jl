# Parsers.jl test suite
#
#   kernels_ints.jl    Int64/Int128/UInt/grouped/BigInt span kernels vs Base oracles
#   kernels_floats.jl  Float64 tiers (Ryu round-trips, random decimals, SDC pressure,
#                      pinned adversaries), decompose oracle, BigFloat vs MPFR
#   kernels_civil.jl   CivilParts, Rata Die, format programs, ISO fast paths, tokens
#   kernels_misc.jl    Bool, UUID
#   api.jl             the Base-parity surface: parse/tryparse/parsenext, every T,
#                      whitespace, bases/prefixes, hex floats, Float32 native,
#                      Float16, keywords, error messages identical to Base
using Test, Parsers, Aqua
include("helpers.jl")
@testset "Parsers" begin
    @testset "Aqua" begin
        Aqua.test_all(Parsers)
    end
    include("kernels_ints.jl")
    include("kernels_floats.jl")
    include("kernels_civil.jl")
    include("kernels_misc.jl")
    include("api.jl")
    include("regressions.jl")
end

include("trim_compile_tests.jl")
