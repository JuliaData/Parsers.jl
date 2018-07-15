include("/Users/jacobquinn/.julia/dev/Parsers/src/Parsers.jl")
using .Parsers, Test, Dates

@testset "Parsers" begin

@testset "Int" begin

r = Parsers.xparse(IOBuffer(""), Int)
@test r.result === nothing
@test r.code === Parsers.EOF
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-"), Int)
@test r.result === nothing
@test r.code === Parsers.EOF
@test r.b === UInt8('-')
r = Parsers.xparse(IOBuffer("+"), Int)
@test r.result === nothing
@test r.code === Parsers.EOF
@test r.b === UInt8('+')
r = Parsers.xparse(IOBuffer("-1"), Int)
@test r.result === -1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("0"), Int)
@test r.result === 0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("+1"), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-a"), Int)
@test r.result === nothing
@test r.code === Parsers.INVALID
@test r.b === UInt8('a')
r = Parsers.xparse(IOBuffer("+a"), Int)
@test r.result === nothing
@test r.code === Parsers.INVALID
@test r.b === UInt8('a')
r = Parsers.xparse(IOBuffer("-1a"), Int)
@test r.result === -1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("+1a"), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-1_000"), Int)
@test r.result === -1000
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1_000"), Int)
@test r.result === 1000
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("129"), Int8)
@test r.result === Int8(-127)
@test r.code === Parsers.OVERFLOW
@test r.b === UInt8('9')
r = Parsers.xparse(IOBuffer("abc"), Int)
@test r.result === nothing
@test r.code === Parsers.INVALID
@test r.b === UInt8('a')

end # @testset

@testset "Parsers.Sentinel" begin

r = Parsers.xparse(Parsers.Sentinel(IOBuffer("NA"), ["NA"]), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("\\N"), ["\\N"]), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("NA2"), ["NA"]), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("-"), ["-", "NA", "\\N"]), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("£"), ["£"]), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("null"), ["NA"]), Int)
@test r.result === nothing
@test r.code === Parsers.INVALID
@test r.b === UInt8('n')
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("null"), String[]), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer(""), String[]), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer(""), String["NA"]), Int)
@test r.result === nothing
@test r.code === Parsers.EOF
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer(","), String[]), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("1,"), String[]), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing

end # @testset

@testset "Parsers.Quoted" begin

r = Parsers.xparse(Parsers.Quoted(IOBuffer("")), Int)
@test r.result === nothing
@test r.code === Parsers.EOF
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"\"")), Int)
@test r.result === nothing
@test r.code === Parsers.INVALID
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("1")), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1\"")), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1a\"")), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('a')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1abc\"")), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("1a")), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("1")), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1")), Int)
@test r.result == 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1a")), Int)
@test r.result == 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('a')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1abc")), Int)
@test r.result == 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1\\")), Int)
@test r.result == 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('\\')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1\\\"")), Int)
@test r.result == 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1\\\"\"")), Int)
@test r.result == 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1ab\"\"c\""), '"', '"'), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1ab\""), '"', '"'), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('b')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1ab\"\""), '"', '"'), Int)
@test r.result === 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('"')

end # @testset

@testset "Parsers.Quoted + Parsers.Sentinel" begin

r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer(""), ["NA"])), Int)
@test r.result === nothing
@test r.code === Parsers.EOF
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"\""), ["NA"])), Int)
@test r.result === nothing
@test r.code === Parsers.INVALID
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"\""), String[])), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("NA"), ["NA"])), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA\""), ["NA"])), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA"), ["NA"])), Int)
@test r.result === missing
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA2"), ["NA"])), Int)
@test r.result === missing
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('2')
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA2\""), ["NA"])), Int)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('2')
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"+1\""), ["NA"])), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"+1"), ["NA"])), Int)
@test r.result === 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NAabc\""), ["NA"])), Int)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA\\\"abc\""), ["NA"])), Int)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"1ab\"\"c\""), String[]), '"', '"'), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"1ab\""), String[]), '"', '"'), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('b')
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"1ab\"\""), String[]), '"', '"'), Int)
@test r.result === 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('"')

end # @testset

@testset "Parsers.Delimited" begin

r = Parsers.xparse(Parsers.Delimited(IOBuffer("")), Int)
@test r.result === nothing
@test r.code === Parsers.EOF
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(IOBuffer("1")), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(IOBuffer("1,")), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(IOBuffer("1;")), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8(';')
r = Parsers.xparse(Parsers.Delimited(IOBuffer("1\n"), ',', '\n'), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(IOBuffer("1abc\n"), ',', '\n'), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('c')

end # @testset

@testset "Parsers.Delimited + Parsers.Sentinel" begin

r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("NA"), ["NA"])), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("\\N"), ["\\N"])), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("NA2"), ["NA"])), Int)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('2')
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("-"), ["-", "NA", "\\N"])), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("£"), ["£"])), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("null"), ["NA"])), Int)
@test r.result === nothing
@test r.code === Parsers.INVALID
@test r.b === UInt8('l')
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("null"), String[])), Int)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('l')
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer(""), String[])), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer(""), String["NA"])), Int)
@test r.result === nothing
@test r.code === Parsers.EOF
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer(","), String[])), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("1,"), String[])), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("1abc,"), String[])), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('c')

end # @testset

@testset "Parsers.Delimited + Parsers.Quoted" begin

r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer(""))), Int)
@test r.result === nothing
@test r.code === Parsers.EOF
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"\""))), Int)
@test r.result === nothing
@test r.code === Parsers.INVALID
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("1"))), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1\""))), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1a\""))), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('a')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1abc\""))), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("1a"))), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('a')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("1"))), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1"))), Int)
@test r.result == 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1a"))), Int)
@test r.result == 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('a')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1abc"))), Int)
@test r.result == 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1\\"))), Int)
@test r.result == 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('\\')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1\\\""))), Int)
@test r.result == 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1\\\"\""))), Int)
@test r.result == 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1\"abc,"))), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1ab\"\"c\""), '"', '"')), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1ab\""), '"', '"')), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('b')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1ab\"\""), '"', '"')), Int)
@test r.result === 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('"')

end # @testset

@testset "Parsers.Delimited + Parsers.Quoted + Parsers.Sentinel" begin

r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer(""), ["NA"]))), Int)
@test r.result === nothing
@test r.code === Parsers.EOF
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"\""), ["NA"]))), Int)
@test r.result === nothing
@test r.code === Parsers.INVALID
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"\""), String[]))), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("NA"), ["NA"]))), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA\""), ["NA"]))), Int)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA"), ["NA"]))), Int)
@test r.result === missing
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA2"), ["NA"]))), Int)
@test r.result === missing
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('2')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA2\""), ["NA"]))), Int)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('2')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"+1\""), ["NA"]))), Int)
@test r.result === 1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"+1"), ["NA"]))), Int)
@test r.result === 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NAabc\""), ["NA"]))), Int)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA\\\"abc\""), ["NA"]))), Int)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"1ab\"\"c\""), String[]), '"', '"')), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"1ab\""), String[]), '"', '"')), Int)
@test r.result === 1
@test r.code === Parsers.INVALID
@test r.b === UInt8('b')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"1ab\"\""), String[]), '"', '"')), Int)
@test r.result === 1
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('"')

end # @testset

include("strings.jl")
include("floats.jl")
include("dates.jl")
include("bools.jl")

end # @testset
