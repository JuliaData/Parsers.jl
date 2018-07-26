using Dates

@testset "Date.TimeTypes" begin

r = Parsers.xparse(IOBuffer(""), Date)
@test r.result === missing
@test r.code == Parsers.INVALID
@test r.b === 0x00
r = Parsers.xparse(IOBuffer("2018-01-01"), Date)
@test r.result === Date(2018, 1, 01)
@test r.code == Parsers.OK
@test r.b === 0x00
r = Parsers.xparse(IOBuffer("2018-01-01"), DateTime)
@test r.result === DateTime(2018, 1, 01)
@test r.code == Parsers.OK
@test r.b === 0x00
r = Parsers.xparse(IOBuffer("01:02:03"), Time)
@test r.result === Time(1, 2, 3)
@test r.code == Parsers.OK
@test r.b === 0x00

r = Parsers.xparse(Parsers.Quoted(IOBuffer("")), Date)
@test r.result === missing
@test r.code == Parsers.INVALID
@test r.b === 0x00
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"\"")), Date)
@test r.result === missing
@test r.code == Parsers.INVALID
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("2018-01-01")), Date)
@test r.result === Date(2018, 1, 01)
@test r.code == Parsers.OK
@test r.b === 0x00
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"2018-01-01\"")), Date)
@test r.result === Date(2018, 1, 01)
@test r.code == Parsers.OK
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"2018-01-01")), DateTime)
@test r.result === missing
@test r.code == Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('1')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"01\"\"02\"\"03\""), '"', '"'), Time; dateformat=dateformat"HH\"\"MM\"\"SS")
@test r.result === Time(1, 2, 3)
@test r.code == Parsers.OK
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"abcd\"")), Date)
@test r.result === missing
@test r.code == Parsers.INVALID
@test r.b === UInt8('"')

r = Parsers.xparse(Parsers.Sentinel(IOBuffer("NA"), ["NA"]), Date)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === UInt8('A')
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("\\N"), ["\\N"]), Date)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === UInt8('N')
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("NA2"), ["NA"]), Date)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === UInt8('A')
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("-"), ["-", "NA", "\\N"]), Date)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === UInt8('-')
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("£"), ["£"]), Date)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === 0xa3
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("null"), ["NA"]), Date)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('l')
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("null"), String[]), Date)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === UInt8('l')
r = Parsers.xparse(Parsers.Sentinel(IOBuffer(""), String[]), Date)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === 0x00
r = Parsers.xparse(Parsers.Sentinel(IOBuffer(""), String["NA"]), Date)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === 0x00
r = Parsers.xparse(Parsers.Sentinel(IOBuffer(","), String[]), Date)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === UInt8(',')
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("1,"), String[]), Date)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === UInt8(',')

r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer(""), ["NA"]))), Date)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === 0x00
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"\""), ["NA"]))), Date)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"\""), String[]))), Date)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("NA"), ["NA"]))), Date)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === UInt8('A')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA\""), ["NA"]))), Date)
@test r.result === missing
@test r.code === Parsers.OK
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA"), ["NA"]))), Date)
@test r.result === missing
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('A')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA2"), ["NA"]))), Date)
@test r.result === missing
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('2')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA2\""), ["NA"]))), Date)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"+1\""), ["NA"]))), Date)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"+1"), ["NA"]))), Date)
@test r.result === missing
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('1')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NAabc\""), ["NA"]))), Date)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"NA\\\"abc\""), ["NA"]))), Date)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"1ab\"\"c\""), String[]), '"', '"')), Date)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"1ab\""), String[]), '"', '"')), Date)
@test r.result === missing
@test r.code === Parsers.INVALID
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"1ab\"\""), String[]), '"', '"')), Date)
@test r.result === missing
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"2018-01-01\""), ["NA"]))), Date)
@test r.result === Date(2018,1,1)
@test r.code === Parsers.OK
@test r.b === UInt8('"')
r = Parsers.xparse(Parsers.Delimited(Parsers.Quoted(Parsers.Sentinel(IOBuffer("\"2018-01-01"), ["NA"]))), Date)
@test r.result === missing
@test r.code === Parsers.INVALID_QUOTED_FIELD
@test r.b === UInt8('1')

end
