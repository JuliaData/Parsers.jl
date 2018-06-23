@testset "Strings" begin

@testset "String Parsers.Sentinel" begin

r = Parsers.xparse(Parsers.Sentinel(IOBuffer("NA"), ["NA"]), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("\\N"), ["\\N"]), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("NA2"), ["NA"]), String)
@test r.result === "NA2"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("-"), ["-", "NA", "\\N"]), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("£"), ["£"]), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("null"), ["NA"]), String)
@test r.result === "null"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("null"), String[]), String)
@test r.result === "null"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer(""), String[]), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer(""), String["NA"]), String)
@test r.result === ""
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer(","), String[]), String)
@test r.result === ","
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("1,"), String[]), String)
@test r.result === "1,"
@test r.code === Parsers.OK
@test r.b === nothing

end # @testset

@testset "String Parsers.Quoted" begin

r = Parsers.xparse(Parsers.Quoted(IOBuffer("")), String)
@test r.result === ""
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"\"")), String)
@test r.result === ""
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("1")), String)
@test r.result === "1"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1\"")), String)
@test r.result === "1"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1a\"")), String)
@test r.result === "1a"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1abc\"")), String)
@test r.result === "1abc"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("1a")), String)
@test r.result === "1a"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1")), String)
@test r.result == "1"
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('1')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1a")), String)
@test r.result == "1a"
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('a')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1abc")), String)
@test r.result == "1abc"
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1\\")), String)
@test r.result == "1"
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('\\')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1\\\"")), String)
@test r.result == "1\\\""
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1\\\"\"")), String)
@test r.result == "1\\\""
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1ab\"\"c\""), '"', '"'), String)
@test r.result === "1ab\"\"c"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1ab\""), '"', '"'), String)
@test r.result === "1ab"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"1ab\"\""), '"', '"'), String)
@test r.result === "1ab\"\""
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('"')

end # @testset

@testset "String Parsers.Quoted + Parsers.Sentinel" begin

r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer(""), ["NA"])), String)
@test r.result === ""
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"\""), ["NA"])), String)
@test r.result === ""
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"\""), String[])), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("NA"), ["NA"])), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA\""), ["NA"])), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA"), ["NA"])), String)
@test r.result === "NA"
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('A')
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA2"), ["NA"])), String)
@test r.result === "NA2"
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('2')
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA2\""), ["NA"])), String)
@test r.result === "NA2"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"+1\""), ["NA"])), String)
@test r.result === "+1"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"+1"), ["NA"])), String)
@test r.result === "+1"
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('1')
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NAabc\""), ["NA"])), String)
@test r.result === "NAabc"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA\\\"abc\""), ["NA"])), String)
@test r.result === "NA\\\"abc"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"1ab\"\"c\""), String[]), '"', '"'), String)
@test r.result === "1ab\"\"c"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"1ab\""), String[]), '"', '"'), String)
@test r.result === "1ab"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"1ab\"\""), String[]), '"', '"'), String)
@test r.result === "1ab\"\""
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('"')

end # @testset

@testset "String Parsers.Delimited" begin

r = Parsers.xparse(Parsers.Delimited(IOBuffer("")), String)
@test r.result === ""
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(IOBuffer("1")), String)
@test r.result === "1"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(IOBuffer("1,")), String)
@test r.result === "1"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(IOBuffer("1;")), String)
@test r.result === "1;"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(IOBuffer("1\n"), UInt8[',', '\n']), String)
@test r.result === "1"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(IOBuffer("1abc\n"), UInt8[',', '\n']), String)
@test r.result === "1abc"
@test r.code === Parsers.OK
@test r.b === nothing

end # @testset

@testset "String Parsers.Delimited + Parsers.Sentinel" begin

r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("NA"), ["NA"])), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("\\N"), ["\\N"])), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("NA2"), ["NA"])), String)
@test r.result === "NA2"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("-"), ["-", "NA", "\\N"])), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("£"), ["£"])), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("null"), ["NA"])), String)
@test r.result === "null"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("null"), String[])), String)
@test r.result === "null"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer(""), String[])), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer(""), String["NA"])), String)
@test r.result === ""
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer(","), String[])), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("1,"), String[])), String)
@test r.result === "1"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Sentinel(IOBuffer("1abc,"), String[])), String)
@test r.result === "1abc"
@test r.code === Parsers.OK
@test r.b === nothing

end # @testset

@testset "String Parsers.Delimited + Parsers.Quoted" begin

r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer(""))), String)
@test r.result === ""
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"\""))), String)
@test r.result === ""
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("1"))), String)
@test r.result === "1"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1\""))), String)
@test r.result === "1"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1a\""))), String)
@test r.result === "1a"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1abc\""))), String)
@test r.result === "1abc"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("1a"))), String)
@test r.result === "1a"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1"))), String)
@test r.result == "1"
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('1')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1a"))), String)
@test r.result == "1a"
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('a')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1abc"))), String)
@test r.result == "1abc"
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1\\"))), String)
@test r.result == "1"
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('\\')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1\\\""))), String)
@test r.result == "1\\\""
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1\\\"\""))), String)
@test r.result == "1\\\""
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1\"abc,"))), String)
@test r.result === "1"
@test r.code === Parsers.INVALID
@test r.b === UInt8('c')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1ab\"\"c\""), '"', '"')), String)
@test r.result === "1ab\"\"c"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1ab\""), '"', '"')), String)
@test r.result === "1ab"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(IOBuffer("\"1ab\"\""), '"', '"')), String)
@test r.result === "1ab\"\""
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('"')

end # @testset

@testset "String Parsers.Delimited + Parsers.Quoted + Parsers.Sentinel" begin

r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer(""), ["NA"]))), String)
@test r.result === ""
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"\""), ["NA"]))), String)
@test r.result === ""
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"\""), String[]))), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("NA"), ["NA"]))), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA\""), ["NA"]))), String)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA"), ["NA"]))), String)
@test r.result === "NA"
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('A')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA2"), ["NA"]))), String)
@test r.result === "NA2"
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('2')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA2\""), ["NA"]))), String)
@test r.result === "NA2"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"+1\""), ["NA"]))), String)
@test r.result === "+1"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"+1"), ["NA"]))), String)
@test r.result === "+1"
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('1')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NAabc\""), ["NA"]))), String)
@test r.result === "NAabc"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA\\\"abc\""), ["NA"]))), String)
@test r.result === "NA\\\"abc"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"1ab\"\"c\""), String[]), '"', '"')), String)
@test r.result === "1ab\"\"c"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"1ab\""), String[]), '"', '"')), String)
@test r.result === "1ab"
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"1ab\"\""), String[]), '"', '"')), String)
@test r.result === "1ab\"\""
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('"')

end # @testset

end # @testset
