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
# http:#www.exploringbinary.com/php-hangs-on-numeric-value-2-2250738585072011e-308/
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
# # Slightly higher, but you have to read all the way to the end.
# r = Parsers.defaultparser(IOBuffer("1.00000000000000011102230246251565404236316680908203125"), Parsers.Result(Float64))

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

end # @testset
