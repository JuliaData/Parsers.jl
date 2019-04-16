# tests from Base JuliaLang/julia

@testset "integer parsing" begin
    @test Parsers.parse(Int32, "0", base = 36) === Int32(0)
    @test Parsers.parse(Int32, "1", base = 36) === Int32(1)
    @test Parsers.parse(Int32, "9", base = 36) === Int32(9)
    @test Parsers.parse(Int32, "A", base = 36) === Int32(10)
    @test Parsers.parse(Int32, "a", base = 36) === Int32(10)
    @test Parsers.parse(Int32, "B", base = 36) === Int32(11)
    @test Parsers.parse(Int32, "b", base = 36) === Int32(11)
    @test Parsers.parse(Int32, "F", base = 36) === Int32(15)
    @test Parsers.parse(Int32, "f", base = 36) === Int32(15)
    @test Parsers.parse(Int32, "Z", base = 36) === Int32(35)
    @test Parsers.parse(Int32, "z", base = 36) === Int32(35)

    @test Parsers.parse(Int, "0") == 0
    @test Parsers.parse(Int, "-0") == 0
    @test Parsers.parse(Int, "1") == 1
    @test Parsers.parse(Int, "-1") == -1
    @test Parsers.parse(Int, "9") == 9
    @test Parsers.parse(Int, "-9") == -9
    @test Parsers.parse(Int, "10") == 10
    @test Parsers.parse(Int, "-10") == -10
    @test Parsers.parse(Int64, "3830974272") == 3830974272
    @test Parsers.parse(Int64, "-3830974272") == -3830974272

    @test Parsers.parse(Int, '3') == 3
    @test Parsers.parse(Int, '3', base = 8) == 3
    @test Parsers.parse(Int, 'a', base = 16) == 10
    @test_throws ArgumentError Parsers.parse(Int, 'a')
    @test_throws ArgumentError Parsers.parse(Int, typemax(Char))
end

# Issue 29451
struct Issue29451String <: AbstractString end
Base.ncodeunits(::Issue29451String) = 12345
Base.lastindex(::Issue29451String) = 1
Base.isvalid(::Issue29451String, i::Integer) = i == 1
Base.iterate(::Issue29451String, i::Integer=1) = i == 1 ? ('0', 2) : nothing

@test Issue29451String() == "0"
@test Parsers.parse(Int, Issue29451String()) == 0

@testset "Issue 20587" begin
    # Test that leading and trailing whitespace is ignored.
    for v in (1, 2, 3)
        @test Parsers.parse(Int, "    $v"    ) == v
        @test Parsers.parse(Int, "    $v\n"  ) == v
        @test Parsers.parse(Int, "$v    "    ) == v
        @test Parsers.parse(Int, "    $v    ") == v
    end
    for v in (true, false)
        @test Parsers.parse(Bool, "    $v"    ) == v
        @test Parsers.parse(Bool, "    $v\n"  ) == v
        @test Parsers.parse(Bool, "$v    "    ) == v
        @test Parsers.parse(Bool, "    $v    ") == v
    end
    for v in (0.05, -0.05, 2.5, -2.5)
        @test Parsers.parse(Float64, "    $v"    ) == v
        @test Parsers.parse(Float64, "    $v\n"  ) == v
        @test Parsers.parse(Float64, "$v    "    ) == v
        @test Parsers.parse(Float64, "    $v    ") == v
    end
    @test Parsers.parse(Float64, "    .5"    ) == 0.5
    @test Parsers.parse(Float64, "    .5\n"  ) == 0.5
    @test Parsers.parse(Float64, "    .5    ") == 0.5
    @test Parsers.parse(Float64, ".5    "    ) == 0.5
end

@testset "parse as Bool, bin, hex, oct" begin
    @test Parsers.parse(Bool, "\u202f true") === true
    @test Parsers.parse(Bool, "\u202f false") === false

    parsebin(s) = Parsers.parse(Int, s, base = 2)
    parseoct(s) = Parsers.parse(Int, s, base = 8)
    parsehex(s) = Parsers.parse(Int, s, base = 16)

    @test parsebin("0") == 0
    @test parsebin("-0") == 0
    @test parsebin("1") == 1
    @test parsebin("-1") == -1
    @test parsebin("10") == 2
    @test parsebin("-10") == -2
    @test parsebin("11") == 3
    @test parsebin("-11") == -3
    @test parsebin("1111000011110000111100001111") == 252645135
    @test parsebin("-1111000011110000111100001111") == -252645135

    @test parseoct("0") == 0
    @test parseoct("-0") == 0
    @test parseoct("1") == 1
    @test parseoct("-1") == -1
    @test parseoct("7") == 7
    @test parseoct("-7") == -7
    @test parseoct("10") == 8
    @test parseoct("-10") == -8
    @test parseoct("11") == 9
    @test parseoct("-11") == -9
    @test parseoct("72") == 58
    @test parseoct("-72") == -58
    @test parseoct("3172207320") == 434704080
    @test parseoct("-3172207320") == -434704080

    @test parsehex("0") == 0
    @test parsehex("-0") == 0
    @test parsehex("1") == 1
    @test parsehex("-1") == -1
    @test parsehex("9") == 9
    @test parsehex("-9") == -9
    @test parsehex("a") == 10
    @test parsehex("-a") == -10
    @test parsehex("f") == 15
    @test parsehex("-f") == -15
    @test parsehex("10") == 16
    @test parsehex("-10") == -16
    @test parsehex("0BADF00D") == 195948557
    @test parsehex("-0BADF00D") == -195948557
    @test Parsers.parse(Int64, "BADCAB1E", base = 16) == 3135023902
    @test Parsers.parse(Int64, "-BADCAB1E", base = 16) == -3135023902
    @test Parsers.parse(Int64, "CafeBabe", base = 16) == 3405691582
    @test Parsers.parse(Int64, "-CafeBabe", base = 16) == -3405691582
    @test Parsers.parse(Int64, "DeadBeef", base = 16) == 3735928559
    @test Parsers.parse(Int64, "-DeadBeef", base = 16) == -3735928559
end

@testset "parse with delimiters" begin
    @test Parsers.parse(Int, "2\n") == 2
    @test Parsers.parse(Int, "   2 \n ") == 2
    @test Parsers.parse(Int, " 2 ") == 2
    @test Parsers.parse(Int, "2 ") == 2
    @test Parsers.parse(Int, " 2") == 2
    @test Parsers.parse(Int, "+2\n") == 2
    @test Parsers.parse(Int, "-2") == -2
    @test_throws ArgumentError Parsers.parse(Int, "   2 \n 0")
    @test_throws ArgumentError Parsers.parse(Int, "2x")
    @test_throws ArgumentError Parsers.parse(Int, "-")

    # multibyte spaces
    @test Parsers.parse(Int, "3\u2003\u202F") == 3
    @test_throws ArgumentError Parsers.parse(Int, "3\u2003\u202F,")
end

@testset "parse from bin/hex/oct" begin
    @test Parsers.parse(Int, "1234") == 1234
    @test Parsers.parse(Int, "0x1234") == 0x1234
    @test Parsers.parse(Int, "0o1234") == 0o1234
    @test Parsers.parse(Int, "0b1011") == 0b1011
    @test Parsers.parse(Int, "-1234") == -1234
    @test Parsers.parse(Int, "-0x1234") == -Int(0x1234)
    @test Parsers.parse(Int, "-0o1234") == -Int(0o1234)
    @test Parsers.parse(Int, "-0b1011") == -Int(0b1011)
end

@testset "parsing extrema of Integer types" begin
    for T in (Int8, Int16, Int32, Int64, Int128)
        @test Parsers.parse(T, string(typemin(T))) == typemin(T)
        @test Parsers.parse(T, string(typemax(T))) == typemax(T)
        @test_throws OverflowError Parsers.parse(T, string(big(typemin(T))-1))
        @test_throws OverflowError Parsers.parse(T, string(big(typemax(T))+1))
    end

    for T in (UInt8, UInt16, UInt32, UInt64, UInt128)
        @test Parsers.parse(T, string(typemin(T))) == typemin(T)
        @test Parsers.parse(T, string(typemax(T))) == typemax(T)
        @test_throws ArgumentError Parsers.parse(T, string(big(typemin(T))-1))
        @test_throws OverflowError Parsers.parse(T, string(big(typemax(T))+1))
    end
end

# make sure base can be any Integer
@testset "issue #15597, T=$T" for T in (Int, BigInt)
    let n = Parsers.parse(T, "123", base = Int8(10))
        @test n == 123
        @test isa(n, T)
    end
end

@testset "issue #17065" begin
    @test Parsers.parse(Int, "2") === 2
    @test Parsers.parse(Bool, "true") === true
    @test Parsers.parse(Bool, "false") === false
    @test Parsers.tryparse(Bool, "true") === true
    @test Parsers.tryparse(Bool, "false") === false
    @test_throws ArgumentError Parsers.parse(Int, "2", base = 1)
    @test_throws ArgumentError Parsers.parse(Int, "2", base = 63)
end

# issue #17333: tryparse should still throw on invalid base
for T in (Int32, BigInt), base in (0, 1, 100)
    @test_throws ArgumentError Parsers.tryparse(T, "0", base = base)
end

@test Parsers.tryparse(Float64, "1.23") === 1.23
@test Parsers.tryparse(Float32, "1.23") === 1.23f0
@test Parsers.tryparse(Float16, "1.23") === Float16(1.23)

# parsing complex numbers (#22250)
@testset "complex parsing" begin
    for r in (1, 0, -1), i in (1, 0, -1), sign in ('-', '+'), Im in ("i", "j", "im")
        for s1 in ("", " "), s2 in ("", " "), s3 in ("", " "), s4 in ("", " ")
            n = Complex(r, sign == '+' ? i : -i)
            s = string(s1, r, s2, sign, s3, i, Im, s4)
            @test n === Parsers.parse(Complex{Int}, s)
            @test Complex(r) === Parsers.parse(Complex{Int}, string(s1, r, s2))
            @test Complex(0, i) === Parsers.parse(Complex{Int}, string(s3, i, Im, s4))
            for T in (Float64, BigFloat)
                nT = Parsers.parse(Complex{T}, s)
                @test nT isa Complex{T}
                @test nT == n
                @test n == Parsers.parse(Complex{T}, string(s1, r, ".0", s2, sign, s3, i, ".0", Im, s4))
                @test n*Parsers.parse(T,"1e-3") == Parsers.parse(Complex{T}, string(s1, r, "e-3", s2, sign, s3, i, "e-3", Im, s4))
            end
        end
    end
    @test Parsers.parse(Complex{Float16}, "3.3+4i") === Complex{Float16}(3.3+4im)
    @test Parsers.parse(Complex{Int}, SubString("xxxxxx1+2imxxxx", 7, 10)) === 1+2im
    for T in (Int, Float64), bad in ("3 + 4*im", "3 + 4", "1+2ij", "1im-3im", "++4im")
        @test_throws ArgumentError Parsers.parse(Complex{T}, bad)
    end
    @test_throws ArgumentError Parsers.parse(Complex{Int}, "3 + 4.2im")
end

@testset "parse and tryparse type inference" begin
    @inferred Parsers.parse(Int, "12")
    @inferred Parsers.parse(Float64, "12")
    @inferred Parsers.parse(Complex{Int}, "12")
    @test eltype([Parsers.parse(Int, s, base=16) for s in String[]]) == Int
    @test eltype([Parsers.parse(Float64, s) for s in String[]]) == Float64
    @test eltype([Parsers.parse(Complex{Int}, s) for s in String[]]) == Complex{Int}
    @test eltype([Parsers.tryparse(Int, s, base=16) for s in String[]]) == Union{Nothing, Int}
    @test eltype([Parsers.tryparse(Float64, s) for s in String[]]) == Union{Nothing, Float64}
    @test eltype([Parsers.tryparse(Complex{Int}, s) for s in String[]]) == Union{Nothing, Complex{Int}}
end

@testset "isssue #29980" begin
    @test Parsers.parse(Bool, "1") === true
    @test Parsers.parse(Bool, "01") === true
    @test Parsers.parse(Bool, "0") === false
    @test Parsers.parse(Bool, "000000000000000000000000000000000000000000000000001") === true
    @test Parsers.parse(Bool, "000000000000000000000000000000000000000000000000000") === false
    @test_throws ArgumentError Parsers.parse(Bool, "1000000000000000000000000000000000000000000000000000")
    @test_throws ArgumentError Parsers.parse(Bool, "2")
    @test_throws ArgumentError Parsers.parse(Bool, "02")
end
