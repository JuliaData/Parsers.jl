using Parsers, Test, Dates

import Parsers: INVALID, OK, SENTINEL, QUOTED, DELIMITED, NEWLINE, EOF, INVALID_EOF, INVALID_QUOTED_FIELD, INVALID_DELIMITER, OVERFLOW

@testset "Parsers" begin

@testset "Int" begin

r = Parsers.parse(Parsers.defaultparser, IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.b === 0x00
r = Parsers.parse(Parsers.defaultparser, IOBuffer("-"), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.b === UInt8('-')
r = Parsers.parse(Parsers.defaultparser, IOBuffer("+"), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.b === UInt8('+')
r = Parsers.parse(Parsers.defaultparser, IOBuffer("-1"), Int)
@test r.result === -1
@test r.code === OK | EOF
@test r.b === 0x31
r = Parsers.parse(Parsers.defaultparser, IOBuffer("0"), Int)
@test r.result === 0
@test r.code === OK | EOF
@test r.b === 0x30
r = Parsers.parse(Parsers.defaultparser, IOBuffer("+1"), Int)
@test r.result === 1
@test r.code === OK | EOF
@test r.b === 0x31
r = Parsers.parse(Parsers.defaultparser, IOBuffer("-a"), Int)
@test r.result === missing
@test r.code === INVALID
@test r.b === UInt8('a')
r = Parsers.parse(Parsers.defaultparser, IOBuffer("+a"), Int)
@test r.result === missing
@test r.code === INVALID
@test r.b === UInt8('a')
r = Parsers.parse(Parsers.defaultparser, IOBuffer("-1a"), Int)
@test r.result === -1
@test r.code === OK
@test r.b === 0x61
r = Parsers.parse(Parsers.defaultparser, IOBuffer("+1a"), Int)
@test r.result === 1
@test r.code === OK
@test r.b === 0x61
r = Parsers.parse(Parsers.defaultparser, IOBuffer("129"), Int8)
@test r.result === Int8(-127)
@test r.code === OVERFLOW | EOF
@test r.b === UInt8('9')
r = Parsers.parse(Parsers.defaultparser, IOBuffer("abc"), Int)
@test r.result === missing
@test r.code === INVALID
@test r.b === UInt8('a')

end # @testset

@testset "Parsers.Sentinel" begin

r = Parsers.parse(Parsers.Sentinel(["NA"]), IOBuffer("NA"), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF
@test r.b === UInt8('A')
r = Parsers.parse(Parsers.Sentinel(["\\N"]), IOBuffer("\\N"), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF
@test r.b === UInt8('N')
r = Parsers.parse(Parsers.Sentinel(["NA"]), IOBuffer("NA2"), Int)
@test r.result === missing
@test r.code === SENTINEL
@test r.b === UInt8('A')
r = Parsers.parse(Parsers.Sentinel(["-", "NA", "\\N"]), IOBuffer("-"), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF
@test r.b === UInt8('-')
r = Parsers.parse(Parsers.Sentinel(["£"]), IOBuffer("£"), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF
@test r.b === 0xa3
r = Parsers.parse(Parsers.Sentinel(["NA"]), IOBuffer("null"), Int)
@test r.result === missing
@test r.code === INVALID
@test r.b === UInt8('n')
r = Parsers.parse(Parsers.Sentinel(String[]), IOBuffer("null"), Int)
@test r.result === missing
@test r.code === SENTINEL
@test r.b === UInt8('n')
r = Parsers.parse(Parsers.Sentinel(String[]), IOBuffer(""), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF
@test r.b === 0x00
r = Parsers.parse(Parsers.Sentinel(String["NA"]), IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.b === 0x00
r = Parsers.parse(Parsers.Sentinel(String[]), IOBuffer(","), Int)
@test r.result === missing
@test r.code === SENTINEL
@test r.b === UInt8(',')
r = Parsers.parse(Parsers.Sentinel(String[]), IOBuffer("1,"), Int)
@test r.result === 1
@test r.code === OK
@test r.b === UInt8(',')

end # @testset

@testset "Parsers.Quoted" begin

r = Parsers.parse(Parsers.Quoted(), IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.b === 0x00
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"\""), Int)
@test r.result === missing
@test r.code === INVALID | QUOTED | EOF
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("1"), Int)
@test r.result === 1
@test r.code === OK | EOF
@test r.b === UInt8('1')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1\""), Int)
@test r.result === 1
@test r.code === OK | QUOTED | EOF
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1a\""), Int)
@test r.result === 1
@test r.code === INVALID | QUOTED | EOF | OK
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1abc\""), Int)
@test r.result === 1
@test r.code === INVALID | QUOTED | EOF | OK
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("1a"), Int)
@test r.result === 1
@test r.code === OK
@test r.b === UInt8('a')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("1"), Int)
@test r.result === 1
@test r.code === OK | EOF
@test r.b === UInt8('1')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1"), Int)
@test r.result == 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | OK
@test r.b === UInt8('1')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1a"), Int)
@test r.result == 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | OK
@test r.b === UInt8('a')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1abc"), Int)
@test r.result == 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | OK
@test r.b === UInt8('c')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1\\"), Int)
@test r.result == 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | OK
@test r.b === UInt8('\\')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1\\\""), Int)
@test r.result == 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | OK
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"1\\\"\""), Int)
@test r.result == 1
@test r.code === INVALID | QUOTED | EOF | OK
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted('"', '"'), IOBuffer("\"1ab\"\"c\""), Int)
@test r.result === 1
@test r.code === INVALID | QUOTED | EOF | OK
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted('"', '"'), IOBuffer("\"1ab\""), Int)
@test r.result === 1
@test r.code === INVALID | QUOTED | EOF | OK
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted('"', '"'), IOBuffer("\"1ab\"\""), Int)
@test r.result === 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | OK
@test r.b === UInt8('"')

end # @testset

@testset "Parsers.Quoted + Parsers.Sentinel" begin

r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF
@test r.b === 0x00
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"\""), Int)
@test r.result === missing
@test r.code === INVALID | EOF | QUOTED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(String[])), IOBuffer("\"\""), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF | QUOTED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("NA"), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF
@test r.b === UInt8('A')
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"NA\""), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF | QUOTED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"NA"), Int)
@test r.result === missing
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | SENTINEL
@test r.b === UInt8('A')
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"NA2"), Int)
@test r.result === missing
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | SENTINEL
@test r.b === UInt8('2')
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"NA2\""), Int)
@test r.result === missing
@test r.code === INVALID | QUOTED | EOF | SENTINEL
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"+1\""), Int)
@test r.result === 1
@test r.code === OK | QUOTED | EOF
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"+1"), Int)
@test r.result === 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | EOF | OK
@test r.b === UInt8('1')
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"NAabc\""), Int)
@test r.result === missing
@test r.code === INVALID | QUOTED | SENTINEL | EOF
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(["NA"])), IOBuffer("\"NA\\\"abc\""), Int)
@test r.result === missing
@test r.code === INVALID | QUOTED | SENTINEL | EOF
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(String[]), '"', '"'), IOBuffer("\"1ab\"\"c\""), Int)
@test r.result === 1
@test r.code === INVALID | QUOTED | OK | EOF
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(String[]), '"', '"'), IOBuffer("\"1ab\""), Int)
@test r.result === 1
@test r.code === INVALID | QUOTED | OK | EOF
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(Parsers.Sentinel(String[]), '"', '"'), IOBuffer("\"1ab\"\""), Int)
@test r.result === 1
@test r.code === INVALID_QUOTED_FIELD | QUOTED | OK | EOF
@test r.b === UInt8('"')

end # @testset

@testset "Parsers.Delimited" begin

r = Parsers.parse(Parsers.Delimited(), IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF | DELIMITED
@test r.b === 0x00
r = Parsers.parse(Parsers.Delimited(), IOBuffer("1"), Int)
@test r.result === 1
@test r.code === OK | EOF | DELIMITED
@test r.b === UInt8('1')
r = Parsers.parse(Parsers.Delimited(), IOBuffer("1,"), Int)
@test r.result === 1
@test r.code === OK | DELIMITED | EOF
@test r.b === UInt8(',')
r = Parsers.parse(Parsers.Delimited(), IOBuffer("1;"), Int)
@test r.result === 1
@test r.code === INVALID | EOF | OK | INVALID_DELIMITER
@test r.b === UInt8(';')
r = Parsers.parse(Parsers.Delimited(',', '\n'), IOBuffer("1\n"), Int)
@test r.result === 1
@test r.code === OK | DELIMITED | EOF | NEWLINE
@test r.b === UInt8('\n')
r = Parsers.parse(Parsers.Delimited(',', '\n'), IOBuffer("1abc\n"), Int)
@test r.result === 1
@test r.code === INVALID | OK | NEWLINE | EOF | INVALID_DELIMITER | DELIMITED
@test r.b === UInt8('\n')
r = Parsers.parse(Parsers.Delimited(',', '\n'), IOBuffer("1abc"), Int)
@test r.result === 1
@test r.code === INVALID | OK | EOF | INVALID_DELIMITER
@test r.b === UInt8('c')

r = Parsers.parse(Parsers.Delimited(',', '\n', '\r', "\r\n"), IOBuffer("1\r2"), Int)
@test r.result === 1
@test r.code === OK | DELIMITED | NEWLINE
@test r.b === UInt8('\r')

end # @testset

@testset "Parsers.Delimited + Parsers.Sentinel" begin

r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(["NA"])), IOBuffer("NA"), Int)
@test r.result === missing
@test r.code === EOF | SENTINEL | DELIMITED
@test r.b === UInt8('A')
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(["\\N"])), IOBuffer("\\N"), Int)
@test r.result === missing
@test r.code === EOF | SENTINEL | DELIMITED
@test r.b === UInt8('N')
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(["NA"])), IOBuffer("NA2"), Int)
@test r.result === missing
@test r.code === INVALID | SENTINEL | EOF | INVALID_DELIMITER
@test r.b === UInt8('2')
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(["-", "NA", "\\N"])), IOBuffer("-"), Int)
@test r.result === missing
@test r.code === EOF | SENTINEL | DELIMITED
@test r.b === UInt8('-')
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(["£"])), IOBuffer("£"), Int)
@test r.result === missing
@test r.code === EOF | SENTINEL | DELIMITED
@test r.b === 0xa3
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(["NA"])), IOBuffer("null"), Int)
@test r.result === missing
@test r.code === INVALID | EOF | INVALID_DELIMITER
@test r.b === UInt8('l')
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(String[])), IOBuffer("null"), Int)
@test r.result === missing
@test r.code === INVALID | SENTINEL | EOF | INVALID_DELIMITER
@test r.b === UInt8('l')
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(String[])), IOBuffer(""), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF | DELIMITED
@test r.b === 0x00
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(String["NA"])), IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF | DELIMITED
@test r.b === 0x00
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(String[])), IOBuffer(","), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF | DELIMITED
@test r.b === UInt8(',')
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(String[])), IOBuffer("1,"), Int)
@test r.result === 1
@test r.code === OK | DELIMITED | EOF
@test r.b === UInt8(',')
r = Parsers.parse(Parsers.Delimited(Parsers.Sentinel(String[])), IOBuffer("1abc,"), Int)
@test r.result === 1
@test r.code === INVALID | OK | EOF | INVALID_DELIMITER | DELIMITED
@test r.b === UInt8(',')

end # @testset

@testset "Parsers.Delimited + Parsers.Quoted" begin

r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF | DELIMITED
@test r.b === 0x00
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"\""), Int)
@test r.result === missing
@test r.code === INVALID | QUOTED | EOF | DELIMITED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("1"), Int)
@test r.result === 1
@test r.code === OK | EOF | DELIMITED
@test r.b === UInt8('1')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1\""), Int)
@test r.result === 1
@test r.code === OK | QUOTED | EOF | DELIMITED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1a\""), Int)
@test r.result === 1
@test r.code === INVALID | OK | QUOTED | EOF | DELIMITED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1abc\""), Int)
@test r.result === 1
@test r.code === INVALID | OK | QUOTED | EOF | DELIMITED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("1a"), Int)
@test r.result === 1
@test r.code === INVALID | OK | EOF | INVALID_DELIMITER
@test r.b === UInt8('a')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("1"), Int)
@test r.result === 1
@test r.code === OK | EOF | DELIMITED
@test r.b === UInt8('1')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1"), Int)
@test r.result == 1
@test r.code === OK | EOF | QUOTED | INVALID_QUOTED_FIELD | DELIMITED
@test r.b === UInt8('1')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1a"), Int)
@test r.result == 1
@test r.code === OK | EOF | QUOTED | INVALID_QUOTED_FIELD | DELIMITED
@test r.b === UInt8('a')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1abc"), Int)
@test r.result == 1
@test r.code === OK | EOF | QUOTED | INVALID_QUOTED_FIELD | DELIMITED
@test r.b === UInt8('c')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1\\"), Int)
@test r.result == 1
@test r.code === OK | EOF | QUOTED | INVALID_QUOTED_FIELD | DELIMITED
@test r.b === UInt8('\\')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1\\\""), Int)
@test r.result == 1
@test r.code === OK | EOF | QUOTED | INVALID_QUOTED_FIELD | DELIMITED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1\\\"\""), Int)
@test r.result == 1
@test r.code === QUOTED | OK | EOF | INVALID | DELIMITED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted()), IOBuffer("\"1\"abc,"), Int)
@test r.result === 1
@test r.code === QUOTED | OK | INVALID | DELIMITED | EOF | INVALID_DELIMITER
@test r.b === UInt8(',')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted('"', '"')), IOBuffer("\"1ab\"\"c\""), Int)
@test r.result === 1
@test r.code === QUOTED | OK | INVALID | EOF | DELIMITED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted('"', '"')), IOBuffer("\"1ab\""), Int)
@test r.result === 1
@test r.code === QUOTED | OK | INVALID | EOF | DELIMITED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted('"', '"')), IOBuffer("\"1ab\"\""), Int)
@test r.result === 1
@test r.code === OK | EOF | QUOTED | INVALID_QUOTED_FIELD | DELIMITED
@test r.b === UInt8('"')

r = Parsers.parse(Parsers.Quoted('"', '"'), IOBuffer("\"1\"\"abc,"), Int)
@test r.result === 1
@test r.code === OK | QUOTED | EOF | INVALID_QUOTED_FIELD
@test r.b === UInt8(',')

end # @testset

@testset "Parsers.Delimited + Parsers.Quoted + Parsers.Sentinel" begin

r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer(""), Int)
@test r.result === missing
@test r.code === INVALID | EOF | DELIMITED
@test r.b === 0x00
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"\""), Int)
@test r.result === missing
@test r.code === INVALID | EOF | QUOTED | DELIMITED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(String[]))), IOBuffer("\"\""), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF | QUOTED | DELIMITED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("NA"), Int)
@test r.result === missing
@test r.code === SENTINEL | EOF | DELIMITED
@test r.b === UInt8('A')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"NA\""), Int)
@test r.result === missing
@test r.code === SENTINEL | QUOTED | EOF | DELIMITED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"NA"), Int)
@test r.result === missing
@test r.code === QUOTED | SENTINEL | INVALID_QUOTED_FIELD | DELIMITED | EOF
@test r.b === UInt8('A')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"NA2"), Int)
@test r.result === missing
@test r.code === QUOTED | SENTINEL | INVALID_QUOTED_FIELD | DELIMITED | EOF
@test r.b === UInt8('2')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"NA2\""), Int)
@test r.result === missing
@test r.code === QUOTED | SENTINEL | INVALID | DELIMITED | EOF
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"+1\""), Int)
@test r.result === 1
@test r.code === OK | QUOTED | EOF | DELIMITED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"+1"), Int)
@test r.result === 1
@test r.code === QUOTED | OK | EOF | INVALID_QUOTED_FIELD | DELIMITED
@test r.b === UInt8('1')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"NAabc\""), Int)
@test r.result === missing
@test r.code === QUOTED | SENTINEL | INVALID | DELIMITED | EOF
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"NA\\\"abc\""), Int)
@test r.result === missing
@test r.code === QUOTED | SENTINEL | INVALID | DELIMITED | EOF
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(String[]), '"', '"')), IOBuffer("\"1ab\"\"c\""), Int)
@test r.result === 1
@test r.code === QUOTED | OK | INVALID | DELIMITED | EOF
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(String[]), '"', '"')), IOBuffer("\"1ab\""), Int)
@test r.result === 1
@test r.code === QUOTED | OK | INVALID | DELIMITED | EOF
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(String[]), '"', '"')), IOBuffer("\"1ab\"\""), Int)
@test r.result === 1
@test r.code === QUOTED | OK | INVALID_QUOTED_FIELD | EOF | DELIMITED
@test r.b === UInt8('"')

r = Parsers.parse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(["NA"]))), IOBuffer("\"quoted field 1\","), Int)
@test r.result === missing
@test r.code === QUOTED | INVALID | DELIMITED | EOF
@test r.b === UInt8(',')

end # @testset

@testset "Parsers.Strip" begin

r = Parsers.parse(Parsers.Strip(), IOBuffer("      64.348\t  "), Float64)
@test r.result === 64.348
@test r.code === OK | EOF
@test r.b === UInt8('\t')

end

include("strings.jl")
include("floats.jl")
include("dates.jl")
include("bools.jl")

@testset "Misc" begin

@test Parsers.parse("101", Int) === 101
@test Parsers.parse("101,101", Float64; decimal=',') === 101.101
@test Parsers.parse(IOBuffer("true"), Bool) === true
@test_throws Parsers.Error Parsers.parse("abc", Int)

@test Parsers.tryparse("abc", Int) === nothing
@test Parsers.tryparse(IOBuffer("101,101"), Float32; decimal=',') === Float32(101.101)

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

@test Parsers.parse(int2str, "101", Int) === 101
@test Parsers.parse(int2str, IOBuffer("101"), Int) === 101
@test Parsers.tryparse(int2str, "101", Int) === 101
@test Parsers.tryparse(int2str, IOBuffer("101"), Int) === 101

@test Parsers.parse("01/20/2018", Date; dateformat="mm/dd/yyyy") === Date(2018, 1, 20)

@test_throws Parsers.Error Parsers.parse("", Missing)
@test Parsers.tryparse("", Missing) === nothing

r = Parsers.parse(Parsers.Quoted('{', '}', '\\'), IOBuffer("{1}"), Int)
@test r.result === 1
@test r.code === OK | QUOTED | EOF
@test r.b === UInt8('}')

end # @testset

end # @testset
