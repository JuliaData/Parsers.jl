using Dates

@testset "Date.TimeTypes" begin

x, code, vpos, vlen, tlen = Parsers.xparse(Date, "")
@test x === Date(0)
@test code == INVALID | EOF
x, code, vpos, vlen, tlen = Parsers.xparse(Date, "2018-01-01")
@test x === Date(2018, 1, 01)
@test code == OK | EOF
x, code, vpos, vlen, tlen = Parsers.xparse(DateTime, "2018-01-01")
@test x === DateTime(2018, 1, 01)
@test code == OK | EOF
x, code, vpos, vlen, tlen = Parsers.xparse(Time, "01:02:03")
@test x === Time(1, 2, 3)
@test code == OK | EOF

x, code, vpos, vlen, tlen = Parsers.xparse(Date, "")
@test x === Date(0)
@test code == INVALID | EOF
x, code, vpos, vlen, tlen = Parsers.xparse(Date, "\"\"")
@test x === Date(0)
@test code == QUOTED | INVALID | EOF
x, code, vpos, vlen, tlen = Parsers.xparse(Date, "2018-01-01")
@test x === Date(2018, 1, 01)
@test code == OK | EOF
x, code, vpos, vlen, tlen = Parsers.xparse(Date, "\"2018-01-01\"")
@test x === Date(2018, 1, 01)
@test code == QUOTED | OK | EOF
x, code, vpos, vlen, tlen = Parsers.xparse(DateTime, "\"2018-01-01")
@test x === DateTime(2018, 1, 1)
@test code == OK | QUOTED | EOF | INVALID_QUOTED_FIELD
x, code, vpos, vlen, tlen = Parsers.xparse(Date, "\"abcd\"")
@test x === Date(0)
@test code == QUOTED | INVALID | EOF

x, code, vpos, vlen, tlen = Parsers.xparse(Date, "NA", sentinel=["NA"])
@test x === Date(0)
@test code === SENTINEL | EOF
x, code, vpos, vlen, tlen = Parsers.xparse(Date, "\\N", sentinel=["\\N"])
@test x === Date(0)
@test code === SENTINEL | EOF
x, code, vpos, vlen, tlen = Parsers.xparse(Date, "NA2", sentinel=["NA"])
@test x === Date(0)
@test code === SENTINEL | INVALID_DELIMITER | EOF
x, code, vpos, vlen, tlen = Parsers.xparse(Date, "-", sentinel=["-"])
@test x === Date(0)
@test code === SENTINEL | EOF
x, code, vpos, vlen, tlen = Parsers.xparse(Date, "£", sentinel=["£"])
@test x === Date(0)
@test code === SENTINEL | EOF
x, code, vpos, vlen, tlen = Parsers.xparse(Date, "null")
@test x === Date(0)
@test code === INVALID_DELIMITER | EOF
x, code, vpos, vlen, tlen = Parsers.xparse(Date, ",")
@test x === Date(0)
@test code === INVALID | DELIMITED
x, code, vpos, vlen, tlen = Parsers.xparse(Date, "1,")
@test x === Date(1)
@test code === OK | DELIMITED

@test Parsers.parse(DateTime, "1996/Feb/15", Parsers.Options(dateformat="yy/uuu/dd")) === DateTime(1996, 2, 15)
@test Parsers.parse(DateTime, "1996, Jan, 15", Parsers.Options(dateformat="yyyy, uuu, dd")) === DateTime(1996, 1, 15)

end
