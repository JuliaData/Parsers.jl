using Parsers, Test, Dates

import Parsers: INVALID, OK, SENTINEL, QUOTED, DELIMITED, NEWLINE, EOF, INVALID_QUOTED_FIELD, INVALID_DELIMITER, OVERFLOW

@testset "Parsers" begin

@testset "Int" begin

r = Parsers.parse(Parsers.defaultparser, IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.defaultparser, IOBuffer("-"), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.defaultparser, IOBuffer("+"), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.defaultparser, IOBuffer("-1"), Int)
@test r.result === -1
@test r.code === OK | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.defaultparser, IOBuffer("0"), Int)
@test r.result === 0
@test r.code === OK | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.defaultparser, IOBuffer("+1"), Int)
@test r.result === 1
@test r.code === OK | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.defaultparser, IOBuffer("-a"), Int)
@test r.result === missing
@test r.code === INVALID
@test r.pos == 0
r = Parsers.parse(Parsers.defaultparser, IOBuffer("+a"), Int)
@test r.result === missing
@test r.code === INVALID
@test r.pos == 0
r = Parsers.parse(Parsers.defaultparser, IOBuffer("-1a"), Int)
@test r.result === -1
@test r.code === OK
@test r.pos == 0
r = Parsers.parse(Parsers.defaultparser, IOBuffer("+1a"), Int)
@test r.result === 1
@test r.code === OK
@test r.pos == 0
r = Parsers.parse(Parsers.defaultparser, IOBuffer("129"), Int8)
@test r.result === Int8(-127)
@test r.code === OVERFLOW | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.defaultparser, IOBuffer("abc"), Int)
@test r.result === missing
@test r.code === INVALID
@test r.pos == 0

end # @testset

@testset "Parsers.Sentinel" begin

r = Parsers.parse(Parsers.Sentinel(["NA"]), IOBuffer("NA"), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Sentinel(["\\N"]), IOBuffer("\\N"), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Sentinel(["NA"]), IOBuffer("NA2"), Int)
@test r.result === missing
@test r.code === SENTINEL
@test r.pos == 0
r = Parsers.parse(Parsers.Sentinel(["-", "NA", "\\N"]), IOBuffer("-"), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Sentinel(["£"]), IOBuffer("£"), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Sentinel(["NA"]), IOBuffer("null"), Int)
@test r.result === missing
@test r.code === INVALID
@test r.pos == 0
r = Parsers.parse(Parsers.Sentinel(String[]), IOBuffer("null"), Int)
@test r.result === missing
@test r.code === SENTINEL
@test r.pos == 0
r = Parsers.parse(Parsers.Sentinel(String[]), IOBuffer(""), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Sentinel(String["NA"]), IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Sentinel(String[]), IOBuffer(","), Int)
@test r.result === missing
@test r.code === SENTINEL
@test r.pos == 0
r = Parsers.parse(Parsers.Sentinel(String[]), IOBuffer("1,"), Int)
@test r.result === 1
@test r.code === OK
@test r.pos == 0

end # @testset

@testset "Parsers.Quoted" begin

r = Parsers.parse(Parsers.Quoted(), IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"\""), Int)
@test r.result === missing
@test r.code === INVALID | QUOTED | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(), IOBuffer("1"), Int)
@test r.result === 1
@test r.code === OK | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1\""), Int)
@test r.result === 1
@test r.code === OK | QUOTED | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1a\""), Int)
@test r.result === 1
@test r.code === INVALID | QUOTED | EOF | OK
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1abc\""), Int)
@test r.result === 1
@test r.code === INVALID | QUOTED | EOF | OK
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(), IOBuffer("1a"), Int)
@test r.result === 1
@test r.code === OK
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(), IOBuffer("1"), Int)
@test r.result === 1
@test r.code === OK | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1"), Int)
@test r.result == 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | OK
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1a"), Int)
@test r.result == 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | OK
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1abc"), Int)
@test r.result == 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | OK
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1\\"), Int)
@test r.result == 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | OK
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1\\\""), Int)
@test r.result == 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | OK
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1\\\"\""), Int)
@test r.result == 1
@test r.code === INVALID | QUOTED | EOF | OK
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted('"', '"'), IOBuffer("\"1ab\"\"c\""), Int)
@test r.result === 1
@test r.code === INVALID | QUOTED | EOF | OK
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted('"', '"'), IOBuffer("\"1ab\""), Int)
@test r.result === 1
@test r.code === INVALID | QUOTED | EOF | OK
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted('"', '"'), IOBuffer("\"1ab\"\""), Int)
@test r.result === 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | OK
@test r.pos == 0

end # @testset

@testset "Parsers.Quoted + Parsers.Sentinel" begin

r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"\""), Int)
@test r.result === missing
@test r.code === INVALID | EOF | QUOTED
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(String[])), IOBuffer("\"\""), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF | QUOTED
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("NA"), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"NA\""), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF | QUOTED
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"NA"), Int)
@test r.result === missing
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | SENTINEL
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"NA2"), Int)
@test r.result === missing
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | SENTINEL
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"NA2\""), Int)
@test r.result === missing
@test r.code === INVALID | QUOTED | EOF | SENTINEL
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"+1\""), Int)
@test r.result === 1
@test r.code === OK | QUOTED | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"+1"), Int)
@test r.result === 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | OK
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"NAabc\""), Int)
@test r.result === missing
@test r.code === INVALID | QUOTED | SENTINEL | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"NA\\\"abc\""), Int)
@test r.result === missing
@test r.code === INVALID | QUOTED | SENTINEL | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(String[]), '"', '"'), IOBuffer("\"1ab\"\"c\""), Int)
@test r.result === 1
@test r.code === INVALID | QUOTED | OK | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(String[]), '"', '"'), IOBuffer("\"1ab\""), Int)
@test r.result === 1
@test r.code === INVALID | QUOTED | OK | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(String[]), '"', '"'), IOBuffer("\"1ab\"\""), Int)
@test r.result === 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | OK | EOF
@test r.pos == 0

r = Parsers.parse(Parsers.Quoted('"', '"'), IOBuffer("\"1\"\"abc,"), Int)
@test r.result === 1
@test r.code === OK | QUOTED | EOF | INVALID_QUOTED_FIELD
@test r.pos == 0

end # @testset

@testset "Parsers.Delimited" begin

r = Parsers.parse(Parsers.Delimited(), IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(), IOBuffer("1"), Int)
@test r.result === 1
@test r.code === OK | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(), IOBuffer("1,"), Int)
@test r.result === 1
@test r.code === OK | DELIMITED | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(), IOBuffer("1;"), Int)
@test r.result === 1
@test r.code === INVALID | EOF | OK | INVALID_DELIMITER
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(','; newline=true), IOBuffer("1\n"), Int)
@test r.result === 1
@test r.code === OK | EOF | NEWLINE
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(','; newline=true), IOBuffer("1abc\n"), Int)
@test r.result === 1
@test r.code === INVALID | OK | NEWLINE | EOF | INVALID_DELIMITER
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(','; newline=true), IOBuffer("1abc"), Int)
@test r.result === 1
@test r.code === INVALID | OK | EOF | INVALID_DELIMITER
@test r.pos == 0

r = Parsers.parse(Parsers.Delimited(','; newline=true), IOBuffer("1\r2"), Int)
@test r.result === 1
@test r.code === OK | NEWLINE
@test r.pos == 0

end # @testset

@testset "Parsers.Delimited + Parsers.Sentinel" begin

r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(["NA"])), IOBuffer("NA"), Int)
@test r.result === missing
@test r.code === EOF | SENTINEL
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(["\\N"])), IOBuffer("\\N"), Int)
@test r.result === missing
@test r.code === EOF | SENTINEL
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(["NA"])), IOBuffer("NA2"), Int)
@test r.result === missing
@test r.code === INVALID | SENTINEL | EOF | INVALID_DELIMITER
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(["-", "NA", "\\N"])), IOBuffer("-"), Int)
@test r.result === missing
@test r.code === EOF | SENTINEL
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(["£"])), IOBuffer("£"), Int)
@test r.result === missing
@test r.code === EOF | SENTINEL
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(["NA"])), IOBuffer("null"), Int)
@test r.result === missing
@test r.code === EOF | INVALID_DELIMITER
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(String[])), IOBuffer("null"), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF | INVALID_DELIMITER
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(String[])), IOBuffer(""), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(String["NA"])), IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(String[])), IOBuffer(","), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF | DELIMITED
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(String[])), IOBuffer("1,"), Int)
@test r.result === 1
@test r.code === OK | DELIMITED | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(String[])), IOBuffer("1abc,"), Int)
@test r.result === 1
@test r.code === OK | EOF | INVALID_DELIMITER | DELIMITED
@test r.pos == 0

end # @testset

@testset "Parsers.Delimited + Parsers.Quoted" begin

r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"\""), Int)
@test r.result === missing
@test r.code === INVALID | QUOTED | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("1"), Int)
@test r.result === 1
@test r.code === OK | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1\""), Int)
@test r.result === 1
@test r.code === OK | QUOTED | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1a\""), Int)
@test r.result === 1
@test r.code === INVALID | OK | QUOTED | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1abc\""), Int)
@test r.result === 1
@test r.code === INVALID | OK | QUOTED | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("1a"), Int)
@test r.result === 1
@test r.code === INVALID | OK | EOF | INVALID_DELIMITER
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("1"), Int)
@test r.result === 1
@test r.code === OK | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1"), Int)
@test r.result == 1
@test r.code === OK | EOF | QUOTED | INVALID_QUOTED_FIELD
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1a"), Int)
@test r.result == 1
@test r.code === OK | EOF | QUOTED | INVALID_QUOTED_FIELD
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1abc"), Int)
@test r.result == 1
@test r.code === OK | EOF | QUOTED | INVALID_QUOTED_FIELD
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1\\"), Int)
@test r.result == 1
@test r.code === OK | EOF | QUOTED | INVALID_QUOTED_FIELD
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1\\\""), Int)
@test r.result == 1
@test r.code === OK | EOF | QUOTED | INVALID_QUOTED_FIELD
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1\\\"\""), Int)
@test r.result == 1
@test r.code === QUOTED | OK | EOF | INVALID
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1\"abc,"), Int)
@test r.result === 1
@test r.code === QUOTED | OK | INVALID | DELIMITED | EOF | INVALID_DELIMITER
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted('"', '"')), IOBuffer("\"1ab\"\"c\""), Int)
@test r.result === 1
@test r.code === QUOTED | OK | INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted('"', '"')), IOBuffer("\"1ab\""), Int)
@test r.result === 1
@test r.code === QUOTED | OK | INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted('"', '"')), IOBuffer("\"1ab\"\""), Int)
@test r.result === 1
@test r.code === OK | EOF | QUOTED | INVALID_QUOTED_FIELD
@test r.pos == 0

end # @testset

@testset "Parsers.Delimited + Parsers.Quoted + Parsers.Sentinel" begin

r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"\""), Int)
@test r.result === missing
@test r.code === INVALID | EOF | QUOTED
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(String[]))), IOBuffer("\"\""), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF | QUOTED
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("NA"), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"NA\""), Int)
@test r.result === missing
@test r.code === SENTINEL | QUOTED | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"NA"), Int)
@test r.result === missing
@test r.code === QUOTED | SENTINEL | INVALID_QUOTED_FIELD | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"NA2"), Int)
@test r.result === missing
@test r.code === QUOTED | SENTINEL | INVALID_QUOTED_FIELD | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"NA2\""), Int)
@test r.result === missing
@test r.code === QUOTED | SENTINEL | INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"+1\""), Int)
@test r.result === 1
@test r.code === OK | QUOTED | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"+1"), Int)
@test r.result === 1
@test r.code === QUOTED | OK | EOF | INVALID_QUOTED_FIELD
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"NAabc\""), Int)
@test r.result === missing
@test r.code === QUOTED | SENTINEL | INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"NA\\\"abc\""), Int)
@test r.result === missing
@test r.code === QUOTED | SENTINEL | INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(String[]), '"', '"')), IOBuffer("\"1ab\"\"c\""), Int)
@test r.result === 1
@test r.code === QUOTED | OK | INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(String[]), '"', '"')), IOBuffer("\"1ab\""), Int)
@test r.result === 1
@test r.code === QUOTED | OK | INVALID | EOF
@test r.pos == 0
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(String[]), '"', '"')), IOBuffer("\"1ab\"\""), Int)
@test r.result === 1
@test r.code === QUOTED | OK | INVALID_QUOTED_FIELD | EOF
@test r.pos == 0

r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"quoted field 1\","), Int)
@test r.result === missing
@test r.code === QUOTED | INVALID | DELIMITED | EOF
@test r.pos == 0

end # @testset

@testset "Parsers.Strip" begin

r = Parsers.parse(Parsers.Strip(), IOBuffer("      64.348\t  "), Float64)
@test r.result === 64.348
@test r.code === OK | EOF
@test r.pos == 0

end

include("strings.jl")
include("floats.jl")
include("dates.jl")
include("bools.jl")

@testset "ignore repeated delimiters" begin

let io=IOBuffer("1,,,2,null,4"), layers=Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["null"])); ignorerepeated=true)
    r = Parsers.parse(layers, io, Int)
    @test r.result === 1
    @test r.code === OK | DELIMITED
    @test r.pos == 0
    r = Parsers.parse(layers, io, Int)
    @test r.result === 2
    @test r.code === OK | DELIMITED
    @test r.pos == 4
    r = Parsers.parse(layers, io, Int)
    @test r.result === missing
    @test r.code === SENTINEL | DELIMITED
    @test r.pos == 6
    r = Parsers.parse(layers, io, Int)
    @test r.result === 4
    @test r.code === OK | EOF
    @test r.pos == 11
end

let io=IOBuffer("1,,,2,null,4"), layers=Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["null"])); ignorerepeated=true)
    r = Parsers.parse(layers, io, String)
    @test r.result === "1"
    @test r.code === OK | DELIMITED
    @test r.pos == 0
    r = Parsers.parse(layers, io, String)
    @test r.result === "2"
    @test r.code === OK | DELIMITED
    @test r.pos == 4
    r = Parsers.parse(layers, io, String)
    @test r.result === missing
    @test r.code === SENTINEL | DELIMITED
    @test r.pos == 6
    r = Parsers.parse(layers, io, String)
    @test r.result === "4"
    @test r.code === OK | EOF
    @test r.pos == 11
end

end

@testset "ignore quoted whitespace" begin

r = Parsers.parse(Parsers.Quoted('"', '"', true), IOBuffer(" \"1\""), Int)
@test r.result === 1
@test r.code === QUOTED | OK | EOF

r = Parsers.parse(Parsers.Quoted('"', '"', true), IOBuffer(" \t \"1\"\t "), Int)
@test r.result === 1
@test r.code === QUOTED | OK

r = Parsers.parse(Parsers.Quoted('"', '"', true), IOBuffer(" \"1\""), String)
@test r.result === "1"
@test r.code === QUOTED | OK | EOF

r = Parsers.parse(Parsers.Quoted('"', '"', true), IOBuffer(" \t \"1\"\t "), String)
@test r.result === "1"
@test r.code === QUOTED | OK | EOF

let io=IOBuffer("1, \"2\"\t, \"null\"  ,4"), layers=Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["null"]), '"', '"', true))
    r = Parsers.parse(layers, io, Int)
    @test r.result === 1
    @test r.code === OK | DELIMITED
    r = Parsers.parse(layers, io, Int)
    @test r.result === 2
    @test r.code === OK | QUOTED | DELIMITED
    r = Parsers.parse(layers, io, Int)
    @test r.result === missing
    @test r.code === SENTINEL | QUOTED | DELIMITED
    r = Parsers.parse(layers, io, Int)
    @test r.result === 4
    @test r.code === OK | EOF
end

let io=IOBuffer("1, \"2\"\t, \"null\"  ,4"), layers=Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["null"]), '"', '"', true))
    r = Parsers.parse(layers, io, String)
    @test r.result === "1"
    @test r.code === OK | DELIMITED
    r = Parsers.parse(layers, io, String)
    @test r.result === "2"
    @test r.code === OK | QUOTED | DELIMITED
    r = Parsers.parse(layers, io, String)
    @test r.result === missing
    @test r.code === SENTINEL | QUOTED | DELIMITED
    r = Parsers.parse(layers, io, String)
    @test r.result === "4"
    @test r.code === OK | EOF
end

end # @testset

# custom parser
function int2str(io::IO, r::Parsers.Result{Int}, args...)
    v = 0
    while !eof(io) && (UInt8('0') <= Parsers.peekbyte(io) <= UInt8('9'))
        v *= 10
        v += Int(Parsers.readbyte(io) - UInt8('0'))
    end
    r.result = v
    r.code = OK
    return r
end

@testset "Misc" begin

@test Parsers.parse(Int, "101") === 101
@test Parsers.parse(Float64, "101,101"; decimal=',') === 101.101
@test Parsers.parse(IOBuffer("true"), Bool) === true
@test_throws Parsers.Error Parsers.parse(Int, "abc")

@test Parsers.tryparse(Int, "abc") === nothing
@test Parsers.tryparse(IOBuffer("101,101"), Float32; decimal=',') === Float32(101.101)

@test Parsers.parse(int2str, Int, "101") === 101
@test Parsers.parse(int2str, IOBuffer("101"), Int) === 101
@test Parsers.tryparse(int2str, Int, "101") === 101
@test Parsers.tryparse(int2str, IOBuffer("101"), Int) === 101

@test Parsers.parse(Date, "01/20/2018"; dateformat="mm/dd/yyyy") === Date(2018, 1, 20)

@test_throws Parsers.Error Parsers.parse(Missing, "")
@test Parsers.tryparse(Missing, "") === nothing

r = Parsers.parse(Parsers.Quoted('{', '}', '\\'), IOBuffer("{1}"), Int)
@test r.result === 1
@test r.code === OK | QUOTED | EOF
@test r.pos == 0

let io=IOBuffer("1,2,null,4"), layers=Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["null"])))
    r = Parsers.parse(layers, io, Int)
    @test r.result === 1
    @test r.code === OK | DELIMITED
    @test r.pos == 0
    r = Parsers.parse(layers, io, Int)
    @test r.result === 2
    @test r.code === OK | DELIMITED
    @test r.pos == 2
    r = Parsers.parse(layers, io, Int)
    @test r.result === missing
    @test r.code === SENTINEL | DELIMITED
    @test r.pos == 4
    r = Parsers.parse(layers, io, Int)
    @test r.result === 4
    @test r.code === OK | EOF
    @test r.pos == 9
end

# https://github.com/JuliaData/CSV.jl/issues/345
open("temp", "w+") do io
    write(io, "\"DALLAS BLACK DANCE THEATRE\",")
end

let layers=Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["null"])))
    open("temp") do io
        r = Parsers.parse(layers, io, String)
        @test r.result == "DALLAS BLACK DANCE THEATRE"
        @test r.code === OK | QUOTED | DELIMITED | EOF
    end
end
rm("temp")

# https://github.com/JuliaData/CSV.jl/issues/344
open("temp", "w+") do io
    write(io, "1,2,null,4")
end

let layers=Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["null"])))
    open("temp") do io
        r = Parsers.parse(layers, io, Int)
        @test r.result === 1
        @test r.code === OK | DELIMITED
        @test r.pos == 0
        r = Parsers.parse(layers, io, Int)
        @test r.result === 2
        @test r.code === OK | DELIMITED
        @test r.pos == 2
        r = Parsers.parse(layers, io, Int)
        @test r.result === missing
        @test r.code === SENTINEL | DELIMITED
        @test r.pos == 4
        r = Parsers.parse(layers, io, Int)
        @test r.result === 4
        @test r.code === OK | EOF
        @test r.pos == 9
    end
end
rm("temp")

# 6: AbstractString input
@test Parsers.parse(Int, SubString("101")) === 101
@test Parsers.parse(Float64, SubString("101,101"); decimal=',') === 101.101
@test Parsers.parse(IOBuffer("true"), Bool) === true
@test_throws Parsers.Error Parsers.parse(Int, "abc")

@test Parsers.tryparse(Int, "abc") === nothing
@test Parsers.tryparse(IOBuffer(SubString("101,101")), Float32; decimal=',') === Float32(101.101)

@test Parsers.parse(int2str, Int, SubString("101")) === 101
@test Parsers.parse(int2str, IOBuffer(SubString("101")), Int) === 101
@test Parsers.tryparse(int2str, Int, SubString("101")) === 101
@test Parsers.tryparse(int2str, IOBuffer(SubString("101")), Int) === 101

# https://github.com/JuliaData/CSV.jl/issues/306
# ensure sentinels are matched before trying to parse type values
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["1"]))), IOBuffer("1"), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["1"]))), IOBuffer("1"), String)
@test r.result === missing
@test r.code === SENTINEL | EOF
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["-"]))), IOBuffer("1"), Int)
@test r.result === 1
@test r.code === OK | EOF
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["-"]))), IOBuffer("-1"), Int)
@test r.result === -1
@test r.code === OK | EOF
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["-"]))), IOBuffer("-"), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF

end # @testset

@testset "BufferedIO" begin

io = IOBuffer("hey there sally")
b = Parsers.BufferedIO(io)
@test !eof(b)
@test Parsers.peekbyte(b) === UInt8('h')
@test position(b) == 0
@test Parsers.readbyte(b) === UInt8('h')
@test position(b) == 1
Parsers.fastseek!(b, 4)
@test Parsers.readbyte(b) === UInt8('t')
Parsers.fastseek!(b, 2)
@test Parsers.readbyte(b) === UInt8('y')

open("test", "w+") do io
    write(io, "hey there sally")
end

b = Parsers.BufferedIO(open("test"))
@test !eof(b)
@test Parsers.peekbyte(b) === UInt8('h')
@test position(b) == 0
@test Parsers.readbyte(b) === UInt8('h')
@test position(b) == 1
Parsers.fastseek!(b, 4)
@test Parsers.readbyte(b) === UInt8('t')
Parsers.fastseek!(b, 2)
@test Parsers.readbyte(b) === UInt8('y')
close(b.io)
rm("test")

end

@testset "deprecations" begin

@test Parsers.parse("101", Int) === 101
@test Parsers.tryparse("101", Int) === 101
@test Parsers.parse(int2str, "101", Int) === 101
@test Parsers.tryparse(int2str, "101", Int) === 101

end

end # @testset
