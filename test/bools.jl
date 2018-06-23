@testset "Bool" begin

r = Parsers.xparse(IOBuffer(""), Bool)
@test r.result === nothing
@test r.code == Parsers.INVALID
@test r.b === nothing
r = Parsers.xparse(IOBuffer("true"), Bool)
@test r.result === true
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("false"), Bool)
@test r.result === false
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("falsee"), Bool)
@test r.result === false
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("fals"), Bool)
@test r.result === nothing
@test r.code == Parsers.INVALID
@test r.b === nothing

r = Parsers.xparse(Parsers.Quoted(IOBuffer("")), Bool)
@test r.result === nothing
@test r.code == Parsers.INVALID
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("true")), Bool)
@test r.result === true
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("false")), Bool)
@test r.result === false
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("falsee")), Bool)
@test r.result === false
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("fals")), Bool)
@test r.result === nothing
@test r.code == Parsers.INVALID
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"false\"")), Bool)
@test r.result === false
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"falsee\"")), Bool)
@test r.result === false
@test r.code == Parsers.INVALID
@test r.b === UInt8('e')
r = Parsers.xparse(Parsers.Quoted(IOBuffer("\"fals\"")), Bool)
@test r.result === nothing
@test r.code == Parsers.INVALID
@test r.b === UInt8('s')

r = Parsers.xparse(Parsers.Delimited(IOBuffer("false"), ','), Bool)
@test r.result === false
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(IOBuffer("falsee"), ','), Bool)
@test r.result === false
@test r.code == Parsers.INVALID
@test r.b === UInt8('e')
r = Parsers.xparse(Parsers.Delimited(IOBuffer("fals"), ','), Bool)
@test r.result === nothing
@test r.code == Parsers.INVALID
@test r.b === UInt8('s')
r = Parsers.xparse(Parsers.Delimited(IOBuffer("false,"), ','), Bool)
@test r.result === false
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Delimited(IOBuffer("falsee,"), ','), Bool)
@test r.result === false
@test r.code == Parsers.INVALID
@test r.b === UInt8('e')
r = Parsers.xparse(Parsers.Delimited(IOBuffer("fals,"), ','), Bool)
@test r.result === nothing
@test r.code == Parsers.INVALID
@test r.b === UInt8('s')

r = Parsers.xparse(Parsers.Sentinel(IOBuffer(""), String[]), Bool)
@test r.result === missing
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer(""), ["NA"]), Bool)
@test r.result === nothing
@test r.code == Parsers.INVALID
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("true"), String[]), Bool)
@test r.result === true
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("true"), ["NA"]), Bool)
@test r.result === true
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("NA"), ["NA"]), Bool)
@test r.result === missing
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("false"), ["false"]), Bool)
@test r.result === false
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("falsee"), ["fals"]), Bool)
@test r.result === false
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("fals"), ["fals"]), Bool)
@test r.result === missing
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("fals"), String[]), Bool)
@test r.result === missing
@test r.code == Parsers.OK
@test r.b === nothing
r = Parsers.xparse(Parsers.Sentinel(IOBuffer("fals"), ["NA"]), Bool)
@test r.result === nothing
@test r.code == Parsers.INVALID
@test r.b === nothing

end
