@testset "Bool" begin

r = Parsers.parse(Parsers.defaultparser, IOBuffer(""), Bool)
@test r.result === missing
@test r.code == INVALID | EOF
@test r.b === 0x00
r = Parsers.parse(Parsers.defaultparser, IOBuffer("true"), Bool)
@test r.result === true
@test r.code == OK | EOF
@test r.b === UInt8('e')
r = Parsers.parse(Parsers.defaultparser, IOBuffer("false"), Bool)
@test r.result === false
@test r.code == OK | EOF
@test r.b === UInt8('e')
r = Parsers.parse(Parsers.defaultparser, IOBuffer("falsee"), Bool)
@test r.result === false
@test r.code == OK
@test r.b === UInt8('e')
r = Parsers.parse(Parsers.defaultparser, IOBuffer("fals"), Bool)
@test r.result === missing
@test r.code == INVALID
@test r.b === 0x00

r = Parsers.parse(Parsers.Quoted(), IOBuffer(""), Bool)
@test r.result === missing
@test r.code == INVALID | EOF
@test r.b === 0x00
r = Parsers.parse(Parsers.Quoted(), IOBuffer("true"), Bool)
@test r.result === true
@test r.code == OK | EOF
@test r.b === UInt8('e')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("false"), Bool)
@test r.result === false
@test r.code == OK | EOF
@test r.b === UInt8('e')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("falsee"), Bool)
@test r.result === false
@test r.code == OK
@test r.b === UInt8('e')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("fals"), Bool)
@test r.result === missing
@test r.code == INVALID
@test r.b === 0x00
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"false\""), Bool)
@test r.result === false
@test r.code == OK | EOF | QUOTED
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"falsee\""), Bool)
@test r.result === false
@test r.code == INVALID | OK | QUOTED | EOF
@test r.b === UInt8('"')
r = Parsers.parse(Parsers.Quoted(), IOBuffer("\"fals\""), Bool)
@test r.result === missing
@test r.code ==  INVALID | QUOTED | EOF
@test r.b === UInt8('"')

r = Parsers.parse(Parsers.Delimited(','), IOBuffer("false"), Bool)
@test r.result === false
@test r.code == OK | EOF | DELIMITED
@test r.b === UInt8('e')
r = Parsers.parse(Parsers.Delimited(','), IOBuffer("falsee"), Bool)
@test r.result === false
@test r.code == INVALID | OK | EOF | INVALID_DELIMITER
@test r.b === UInt8('e')
r = Parsers.parse(Parsers.Delimited(','), IOBuffer("fals"), Bool)
@test r.result === missing
@test r.code == INVALID_DELIMITER | EOF
@test r.b === UInt8('s')
r = Parsers.parse(Parsers.Delimited(','), IOBuffer("false,"), Bool)
@test r.result === false
@test r.code == OK | EOF | DELIMITED
@test r.b === UInt8(',')
r = Parsers.parse(Parsers.Delimited(','), IOBuffer("falsee,"), Bool)
@test r.result === false
@test r.code == OK | INVALID_DELIMITER | EOF | DELIMITED
@test r.b === UInt8(',')
r = Parsers.parse(Parsers.Delimited(','), IOBuffer("fals,"), Bool)
@test r.result === missing
@test r.code == DELIMITED | EOF | INVALID_DELIMITER
@test r.b === UInt8(',')

r = Parsers.parse(Parsers.Sentinel(String[]), IOBuffer(""), Bool)
@test r.result === missing
@test r.code == SENTINEL | EOF
@test r.b === 0x00
r = Parsers.parse(Parsers.Sentinel(["NA"]), IOBuffer(""), Bool)
@test r.result === missing
@test r.code == INVALID | EOF
@test r.b === 0x00
r = Parsers.parse(Parsers.Sentinel(String[]), IOBuffer("true"), Bool)
@test r.result === true
@test r.code == OK | EOF
@test r.b === UInt8('e')
r = Parsers.parse(Parsers.Sentinel(["NA"]), IOBuffer("true"), Bool)
@test r.result === true
@test r.code == OK | EOF
@test r.b === UInt8('e')
r = Parsers.parse(Parsers.Sentinel(["NA"]), IOBuffer("NA"), Bool)
@test r.result === missing
@test r.code == SENTINEL | EOF
@test r.b === UInt8('A')
r = Parsers.parse(Parsers.Sentinel(["false"]), IOBuffer("false"), Bool)
@test r.result === false
@test r.code == OK | EOF
@test r.b === UInt8('e')
r = Parsers.parse(Parsers.Sentinel(["fals"]), IOBuffer("falsee"), Bool)
@test r.result === false
@test r.code == OK
@test r.b === UInt8('e')
r = Parsers.parse(Parsers.Sentinel(["fals"]), IOBuffer("fals"), Bool)
@test r.result === missing
@test r.code == SENTINEL | EOF
@test r.b === UInt8('s')
r = Parsers.parse(Parsers.Sentinel(String[]), IOBuffer("fals"), Bool)
@test r.result === missing
@test r.code == SENTINEL
@test r.b === 0x00
r = Parsers.parse(Parsers.Sentinel(["NA"]), IOBuffer("fals"), Bool)
@test r.result === missing
@test r.code == INVALID
@test r.b === 0x00

end
