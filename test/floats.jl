@testset "Floats" begin

r = Parsers.defaultparser(IOBuffer(""), Parsers.Result(Float64))
@test r.result === missing
@test r.code === INVALID | EOF
r = Parsers.defaultparser(IOBuffer("1"), Parsers.Result(Float64))
@test r.result === 1.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("+1"), Parsers.Result(Float64))
@test r.result === 1.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("1x"), Parsers.Result(Float64))
@test r.result === 1.0
@test r.code === OK
r = Parsers.defaultparser(IOBuffer("1.1."), Parsers.Result(Float64))
@test r.result === 1.1
@test r.code === OK
r = Parsers.defaultparser(IOBuffer("1e23"), Parsers.Result(Float64))
@test r.result === 1e+23
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("1E23"), Parsers.Result(Float64))
@test r.result === 1e+23
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("100000000000000000000000"), Parsers.Result(Float64))
@test r.result === 1e+23
@test r.code === OK | EOF

r = Parsers.defaultparser(IOBuffer("1e-100"), Parsers.Result(Float64))
@test r.result === 1e-100
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("123456700"), Parsers.Result(Float64))
@test r.result === 1.234567e+08
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("99999999999999974834176"), Parsers.Result(Float64))
@test r.result === 9.999999999999997e+22
@test r.code === OK | EOF

r = Parsers.defaultparser(IOBuffer("100000000000000000000001"), Parsers.Result(Float64))
@test r.result === 1.0000000000000001e+23
@test r.code === OK | EOF

r = Parsers.defaultparser(IOBuffer("100000000000000008388608"), Parsers.Result(Float64))
@test r.result === 1.0000000000000001e+23
@test r.code === OK | EOF

r = Parsers.defaultparser(IOBuffer("100000000000000016777215"), Parsers.Result(Float64))
@test r.result === 1.0000000000000001e+23
@test r.code === OK | EOF

r = Parsers.defaultparser(IOBuffer("100000000000000016777216"), Parsers.Result(Float64))
@test r.result === 1.0000000000000003e+23
@test r.code === OK | EOF

r = Parsers.defaultparser(IOBuffer("-1"), Parsers.Result(Float64))
@test r.result === -1.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-0.1"), Parsers.Result(Float64))
@test r.result === -0.1
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-0"), Parsers.Result(Float64))
@test r.result === 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("1e-20"), Parsers.Result(Float64))
@test r.result === 1e-20
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("625e-3"), Parsers.Result(Float64))
@test r.result === 0.625
@test r.code === OK | EOF

# zeros
r = Parsers.defaultparser(IOBuffer("0"), Parsers.Result(Float64))
@test r.result == 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("0e0"), Parsers.Result(Float64))
@test r.result == 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-0e0"), Parsers.Result(Float64))
@test r.result == -0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("+0e0"), Parsers.Result(Float64))
@test r.result == 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("0e-0"), Parsers.Result(Float64))
@test r.result == 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-0e-0"), Parsers.Result(Float64))
@test r.result == -0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("+0e-0"), Parsers.Result(Float64))
@test r.result == 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("0e+0"), Parsers.Result(Float64))
@test r.result == 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-0e+0"), Parsers.Result(Float64))
@test r.result == -0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("+0e+0"), Parsers.Result(Float64))
@test r.result == 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("0e+01234567890123456789"), Parsers.Result(Float64))
@test r.result == 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("0.00e-01234567890123456789"), Parsers.Result(Float64))
@test r.result == 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-0e+01234567890123456789"), Parsers.Result(Float64))
@test r.result == -0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-0.00e-01234567890123456789"), Parsers.Result(Float64))
@test r.result == -0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("0e291"), Parsers.Result(Float64))
@test r.result == 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("0e292"), Parsers.Result(Float64))
@test r.result == 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("0e347"), Parsers.Result(Float64))
@test r.result == 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("0e348"), Parsers.Result(Float64))
@test r.result == 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-0e291"), Parsers.Result(Float64))
@test r.result == -0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-0e292"), Parsers.Result(Float64))
@test r.result == -0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-0e347"), Parsers.Result(Float64))
@test r.result == -0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-0e348"), Parsers.Result(Float64))
@test r.result == -0.0
@test r.code === OK | EOF

# NaNs
r = Parsers.defaultparser(IOBuffer("nan"), Parsers.Result(Float64))
@test r.result === NaN
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("NaN"), Parsers.Result(Float64))
@test r.result === NaN
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("NAN"), Parsers.Result(Float64))
@test r.result === NaN
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("nAN"), Parsers.Result(Float64))
@test r.result === NaN
@test r.code === OK | EOF

# Infs
r = Parsers.defaultparser(IOBuffer("inf"), Parsers.Result(Float64))
@test r.result === Inf
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("infinity"), Parsers.Result(Float64))
@test r.result === Inf
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-inf"), Parsers.Result(Float64))
@test r.result === -Inf
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-Inf"), Parsers.Result(Float64))
@test r.result === -Inf
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-infinity"), Parsers.Result(Float64))
@test r.result === -Inf
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-INFINITY"), Parsers.Result(Float64))
@test r.result === -Inf
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("+inf"), Parsers.Result(Float64))
@test r.result === Inf
@test r.code === OK | EOF

# largest float64
r = Parsers.defaultparser(IOBuffer("1.7976931348623157e308"), Parsers.Result(Float64))
@test r.result === 1.7976931348623157e+308
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-1.7976931348623157e308"), Parsers.Result(Float64))
@test r.result === -1.7976931348623157e+308
@test r.code === OK | EOF
# next float64 - too large
r = Parsers.defaultparser(IOBuffer("1.7976931348623159e308"), Parsers.Result(Float64))
@test r.result === +Inf
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-1.7976931348623159e308"), Parsers.Result(Float64))
@test r.result === -Inf
@test r.code === OK | EOF
# the border is ...158079
# borderline - okay
r = Parsers.defaultparser(IOBuffer("1.7976931348623158e308"), Parsers.Result(Float64))
@test r.result === 1.7976931348623157e+308
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-1.7976931348623158e308"), Parsers.Result(Float64))
@test r.result === -1.7976931348623157e+308
@test r.code === OK | EOF
# borderline - too large
r = Parsers.defaultparser(IOBuffer("1.797693134862315808e308"), Parsers.Result(Float64))
@test r.result === +Inf
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-1.797693134862315808e308"), Parsers.Result(Float64))
@test r.result === -Inf
@test r.code === OK | EOF

# a little too large
r = Parsers.defaultparser(IOBuffer("1e308"), Parsers.Result(Float64))
@test r.result === 1e+308
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("2e308"), Parsers.Result(Float64))
@test r.result === +Inf
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("1e309"), Parsers.Result(Float64))
@test r.result === +Inf
@test r.code === OK | EOF

# way too large
r = Parsers.defaultparser(IOBuffer("1e310"), Parsers.Result(Float64))
@test r.result === +Inf
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-1e310"), Parsers.Result(Float64))
@test r.result === -Inf
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("1e400"), Parsers.Result(Float64))
@test r.result === +Inf
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-1e400"), Parsers.Result(Float64))
@test r.result === -Inf
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("1e400000"), Parsers.Result(Float64))
@test r.result === +Inf
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-1e400000"), Parsers.Result(Float64))
@test r.result === -Inf
@test r.code === OK | EOF

# denormalized
r = Parsers.defaultparser(IOBuffer("1e-305"), Parsers.Result(Float64))
@test r.result === 1e-305
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("1e-306"), Parsers.Result(Float64))
@test r.result === 1e-306
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("1e-307"), Parsers.Result(Float64))
@test r.result === 1e-307
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("1e-308"), Parsers.Result(Float64))
@test r.result === 1e-308
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("1e-309"), Parsers.Result(Float64))
@test r.result === 1e-309
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("1e-310"), Parsers.Result(Float64))
@test r.result === 1e-310
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("1e-322"), Parsers.Result(Float64))
@test r.result === 1e-322
@test r.code === OK | EOF
# smallest denormal
r = Parsers.defaultparser(IOBuffer("5e-324"), Parsers.Result(Float64))
@test r.result === 5e-324
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("4e-324"), Parsers.Result(Float64))
@test r.result === 5e-324
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("3e-324"), Parsers.Result(Float64))
@test r.result === 5e-324
@test r.code === OK | EOF
# too small
r = Parsers.defaultparser(IOBuffer("2e-324"), Parsers.Result(Float64))
@test r.result === 0.0
@test r.code === OK | EOF
# way too small
r = Parsers.defaultparser(IOBuffer("1e-350"), Parsers.Result(Float64))
@test r.result === 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("1e-400000"), Parsers.Result(Float64))
@test r.result === 0.0
@test r.code === OK | EOF

# try to overflow exponent
r = Parsers.defaultparser(IOBuffer("1e-4294967296"), Parsers.Result(Float64))
@test r.result === 0.0
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("1e+4294967296"), Parsers.Result(Float64))
@test r.result === +Inf
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("1e-18446744073709551616"), Parsers.Result(Float64))
@test r.result === 0.0
@test r.code === OK | EOF

r = Parsers.defaultparser(IOBuffer("1e+18446744073709551616"), Parsers.Result(Float64))
@test r.result === +Inf
@test r.code === OK | EOF

# Parse errors
r = Parsers.defaultparser(IOBuffer("1e"), Parsers.Result(Float64))
@test r.result === missing
@test r.code === INVALID | EOF
r = Parsers.defaultparser(IOBuffer("1e-"), Parsers.Result(Float64))
@test r.result === missing
@test r.code === INVALID | EOF
r = Parsers.defaultparser(IOBuffer(".e-1"), Parsers.Result(Float64))
@test r.result === missing
@test r.code === INVALID | EOF
r = Parsers.defaultparser(IOBuffer("1\x00.2"), Parsers.Result(Float64))
@test r.result === 1.0
@test r.code === OK

# http:#www.exploringbinary.com/java-hangs-when-converting-2-2250738585072012e-308/
r = Parsers.defaultparser(IOBuffer("2.2250738585072012e-308"), Parsers.Result(Float64))
@test r.result === 2.2250738585072014e-308
@test r.code === OK | EOF
# http://www.exploringbinary.com/php-hangs-on-numeric-value-2-2250738585072011e-308/
r = Parsers.defaultparser(IOBuffer("2.2250738585072011e-308"), Parsers.Result(Float64))
@test r.result === 2.225073858507201e-308
@test r.code === OK | EOF

# A very large number (initially wrongly parsed by the fast algorithm).
r = Parsers.defaultparser(IOBuffer("4.630813248087435e+307"), Parsers.Result(Float64))
@test r.result === 4.630813248087435e+307
@test r.code === OK | EOF

# A different kind of very large number.
r = Parsers.defaultparser(IOBuffer("22.222222222222222"), Parsers.Result(Float64))
@test r.result === 22.22222222222222
@test r.code === OK | EOF

# Exactly halfway between 1 and math.Nextafter(1, 2).
# Round to even (down).
r = Parsers.defaultparser(IOBuffer("1.00000000000000011102230246251565404236316680908203125"), Parsers.Result(Float64))
@test r.result === 1.0
@test r.code === OK | EOF
# # Slightly lower; still round down.
r = Parsers.defaultparser(IOBuffer("1.00000000000000011102230246251565404236316680908203124"), Parsers.Result(Float64))
@test r.result === 1.0
@test r.code === OK | EOF
# # Slightly higher; round up.
r = Parsers.defaultparser(IOBuffer("1.00000000000000011102230246251565404236316680908203126"), Parsers.Result(Float64))
@test r.result === 1.0000000000000002
@test r.code === OK | EOF

r = Parsers.defaultparser(IOBuffer("-5.871153289887625082e-01"), Parsers.Result(Float64))
@test r.result === -5.871153289887625082e-01
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("8.095032986136727615e-01"), Parsers.Result(Float64))
@test r.result === 8.095032986136727615e-01
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("9.900000000000006573e-01"), Parsers.Result(Float64))
@test r.result === 9.900000000000006573e-01
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("9.900000000000006573e-01"), Parsers.Result(Float64))
@test r.result === 9.900000000000006573e-01
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-9.866066418838319585e-01"), Parsers.Result(Float64))
@test r.result === -9.866066418838319585e-01
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-3.138907529596844714e+00"), Parsers.Result(Float64))
@test r.result === -3.138907529596844714e+00
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-5.129218106887371675e+00"), Parsers.Result(Float64))
@test r.result === -5.129218106887371675e+00
@test r.code === OK | EOF
r = Parsers.defaultparser(IOBuffer("-4.803915800699462224e+00"), Parsers.Result(Float64))
@test r.result === -4.803915800699462224e+00
@test r.code === OK | EOF

# issue #18
r = Parsers.defaultparser(IOBuffer(".24409E+03"), Parsers.Result(Float64))
@test r.result === 244.09
@test r.code === OK | EOF

r = Parsers.defaultparser(IOBuffer(".24409E+03 "), Parsers.Result(Float64))
@test r.result === 244.09
@test r.code === OK | EOF

# from https://www.icir.org/vern/papers/testbase-report.pdf
float = 5.0 * exp10(+125)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 69.0 * exp10(+267)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 999.0 * exp10(-26)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 7861.0 * exp10(-34)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 75569.0 * exp10(-254)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 928609.0 * exp10(-261)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 9210917.0 * exp10(+80)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 84863171.0 * exp10(+114)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 653777767.0 * exp10(+273)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 5232604057.0 * exp10(-298)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 27235667517.0 * exp10(-109)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 653532977297.0 * exp10(-123)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 3142213164987.0 * exp10(-294)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 46202199371337.0 * exp10(-72)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 231010996856685.0 * exp10(-73)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 9324754620109615.0 * exp10(+212)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 78459735791271921.0 * exp10(+49)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 272104041512242479.0 * exp10(+200)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 6802601037806061975.0 * exp10(+198)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 20505426358836677347.0 * exp10(-221)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 836168422905420598437.0 * exp10(-234)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 4891559871276714924261.0 * exp10(+222)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF

float = 9.0 * exp10(-265)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 85.0 * exp10(-037)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 623.0 * exp10(+100)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 3571.0 * exp10(+263)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 81661.0 * exp10(+153)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 920657.0 * exp10(-023)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 4603285.0 * exp10(-024)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 87575437.0 * exp10(-309)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 245540327.0 * exp10(+122)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 6138508175.0 * exp10(+120)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 83356057653.0 * exp10(+193)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 619534293513.0 * exp10(+124)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 2335141086879.0 * exp10(+218)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 36167929443327.0 * exp10(-159)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 609610927149051.0 * exp10(-255)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 3743626360493413.0 * exp10(-165)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 94080055902682397.0 * exp10(-242)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 899810892172646163.0 * exp10(+283)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 7120190517612959703.0 * exp10(+120)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 25188282901709339043.0 * exp10(-252)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 308984926168550152811.0 * exp10(-052)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 6372891218502368041059.0 * exp10(+064)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF

float = 8511030020275656.0 * exp2(-0342)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 5201988407066741.0 * exp2(-0824)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 6406892948269899.0 * exp2(+0237)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 8431154198732492.0 * exp2(+0072)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 6475049196144587.0 * exp2(+0099)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 8274307542972842.0 * exp2(+0726)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 5381065484265332.0 * exp2(-0456)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 6761728585499734.0 * exp2(-1057)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 7976538478610756.0 * exp2(+0376)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 5982403858958067.0 * exp2(+0377)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 5536995190630837.0 * exp2(+0093)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 7225450889282194.0 * exp2(+0710)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 7225450889282194.0 * exp2(+0709)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 8703372741147379.0 * exp2(+0117)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 8944262675275217.0 * exp2(-1001)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 7459803696087692.0 * exp2(-0707)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 6080469016670379.0 * exp2(-0381)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 8385515147034757.0 * exp2(+0721)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 7514216811389786.0 * exp2(-0828)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 8397297803260511.0 * exp2(-0345)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 6733459239310543.0 * exp2(+0202)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 8091450587292794.0 * exp2(-0473)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF

float = 6567258882077402.0 * exp2(+952)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 6712731423444934.0 * exp2(+535)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 6712731423444934.0 * exp2(+534)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 5298405411573037.0 * exp2(-957)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 5137311167659507.0 * exp2(-144)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 6722280709661868.0 * exp2(+363)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 5344436398034927.0 * exp2(-169)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 8369123604277281.0 * exp2(-853)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 8995822108487663.0 * exp2(-780)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 8942832835564782.0 * exp2(-383)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 8942832835564782.0 * exp2(-384)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 8942832835564782.0 * exp2(-385)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 6965949469487146.0 * exp2(-249)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 6965949469487146.0 * exp2(-250)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 6965949469487146.0 * exp2(-251)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 7487252720986826.0 * exp2(+548)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 5592117679628511.0 * exp2(+164)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 8887055249355788.0 * exp2(+665)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 6994187472632449.0 * exp2(+690)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 8797576579012143.0 * exp2(+588)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 7363326733505337.0 * exp2(+272)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF
float = 8549497411294502.0 * exp2(-448)
r = Parsers.defaultparser(IOBuffer(string(float)), Parsers.Result(Float64))
@test r.result === float
@test r.code === OK | EOF

end # @testset
