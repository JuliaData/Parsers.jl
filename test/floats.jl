@testset "Floats" begin

r = Parsers.xparse(IOBuffer(""), Float64)
@test r.result === nothing
@test r.code === Parsers.EOF
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1"), Float64)
@test r.result === 1.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("+1"), Float64)
@test r.result === 1.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1x"), Float64)
@test r.result === 1.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1.1."), Float64)
@test r.result === 1.1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1e23"), Float64)
@test r.result === 1e+23
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1E23"), Float64)
@test r.result === 1e+23
@test r.code === Parsers.OK
@test r.b === nothing
# r = Parsers.xparse(IOBuffer("100000000000000000000000"), Float64)
# @test r.result === 1e+23
# @test r.code === Parsers.OK
# @test r.b === nothing
r = Parsers.xparse(IOBuffer("1e-100"), Float64)
@test r.result === 1e-100
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("123456700"), Float64)
@test r.result === 1.234567e+08
@test r.code === Parsers.OK
@test r.b === nothing
# r = Parsers.xparse(IOBuffer("99999999999999974834176"), Float64)
# @test r.result === 9.999999999999997e+22
# @test r.code === Parsers.OK
# @test r.b === nothing
# r = Parsers.xparse(IOBuffer("100000000000000000000001"), Float64)
# @test r.result === 1.0000000000000001e+23
# @test r.code === Parsers.OK
# @test r.b === nothing
# r = Parsers.xparse(IOBuffer("100000000000000008388608"), Float64)
# @test r.result === 1.0000000000000001e+23
# @test r.code === Parsers.OK
# @test r.b === nothing
# r = Parsers.xparse(IOBuffer("100000000000000016777215"), Float64)
# @test r.result === 1.0000000000000001e+23
# @test r.code === Parsers.OK
# @test r.b === nothing
# r = Parsers.xparse(IOBuffer("100000000000000016777216"), Float64)
# @test r.result === 1.0000000000000003e+23
# @test r.code === Parsers.OK
# @test r.b === nothing
r = Parsers.xparse(IOBuffer("-1"), Float64)
@test r.result === -1.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-0.1"), Float64)
@test r.result === -0.1
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-0"), Float64)
@test r.result === 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1e-20"), Float64)
@test r.result === 1e-20
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("625e-3"), Float64)
@test r.result === 0.625
@test r.code === Parsers.OK
@test r.b === nothing

# zeros
r = Parsers.xparse(IOBuffer("0"), Float64)
@test r.result == 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("0e0"), Float64)
@test r.result == 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-0e0"), Float64)
@test r.result == -0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("+0e0"), Float64)
@test r.result == 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("0e-0"), Float64)
@test r.result == 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-0e-0"), Float64)
@test r.result == -0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("+0e-0"), Float64)
@test r.result == 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("0e+0"), Float64)
@test r.result == 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-0e+0"), Float64)
@test r.result == -0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("+0e+0"), Float64)
@test r.result == 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("0e+01234567890123456789"), Float64)
@test r.result == 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("0.00e-01234567890123456789"), Float64)
@test r.result == 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-0e+01234567890123456789"), Float64)
@test r.result == -0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-0.00e-01234567890123456789"), Float64)
@test r.result == -0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("0e291"), Float64)
@test r.result == 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("0e292"), Float64)
@test r.result == 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("0e347"), Float64)
@test r.result == 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("0e348"), Float64)
@test r.result == 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-0e291"), Float64)
@test r.result == -0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-0e292"), Float64)
@test r.result == -0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-0e347"), Float64)
@test r.result == -0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-0e348"), Float64)
@test r.result == -0.0
@test r.code === Parsers.OK
@test r.b === nothing

# NaNs
r = Parsers.xparse(IOBuffer("nan"), Float64)
@test r.result === NaN
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("NaN"), Float64)
@test r.result === NaN
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("NAN"), Float64)
@test r.result === NaN
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("nAN"), Float64)
@test r.result === NaN
@test r.code === Parsers.OK
@test r.b === nothing

# Infs
r = Parsers.xparse(IOBuffer("inf"), Float64)
@test r.result === Inf
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("infinity"), Float64)
@test r.result === Inf
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-inf"), Float64)
@test r.result === -Inf
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-Inf"), Float64)
@test r.result === -Inf
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-infinity"), Float64)
@test r.result === -Inf
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-INFINITY"), Float64)
@test r.result === -Inf
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("+inf"), Float64)
@test r.result === Inf
@test r.code === Parsers.OK
@test r.b === nothing

# largest float64
r = Parsers.xparse(IOBuffer("1.7976931348623157e308"), Float64)
@test r.result === 1.7976931348623157e+308
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-1.7976931348623157e308"), Float64)
@test r.result === -1.7976931348623157e+308
@test r.code === Parsers.OK
@test r.b === nothing
# next float64 - too large
r = Parsers.xparse(IOBuffer("1.7976931348623159e308"), Float64)
@test r.result === +Inf
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-1.7976931348623159e308"), Float64)
@test r.result === -Inf
@test r.code === Parsers.OK
@test r.b === nothing
# the border is ...158079
# borderline - okay
r = Parsers.xparse(IOBuffer("1.7976931348623158e308"), Float64)
@test r.result === 1.7976931348623157e+308
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-1.7976931348623158e308"), Float64)
@test r.result === -1.7976931348623157e+308
@test r.code === Parsers.OK
@test r.b === nothing
# borderline - too large
r = Parsers.xparse(IOBuffer("1.797693134862315808e308"), Float64)
@test r.result === +Inf
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-1.797693134862315808e308"), Float64)
@test r.result === -Inf
@test r.code === Parsers.OK
@test r.b === nothing

# a little too large
r = Parsers.xparse(IOBuffer("1e308"), Float64)
@test r.result === 1e+308
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("2e308"), Float64)
@test r.result === +Inf
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1e309"), Float64)
@test r.result === +Inf
@test r.code === Parsers.OK
@test r.b === nothing

# way too large
r = Parsers.xparse(IOBuffer("1e310"), Float64)
@test r.result === +Inf
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-1e310"), Float64)
@test r.result === -Inf
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1e400"), Float64)
@test r.result === +Inf
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-1e400"), Float64)
@test r.result === -Inf
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1e400000"), Float64)
@test r.result === +Inf
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("-1e400000"), Float64)
@test r.result === -Inf
@test r.code === Parsers.OK
@test r.b === nothing

# denormalized
r = Parsers.xparse(IOBuffer("1e-305"), Float64)
@test r.result === 1e-305
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1e-306"), Float64)
@test r.result === 1e-306
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1e-307"), Float64)
@test r.result === 1e-307
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1e-308"), Float64)
@test r.result === 1e-308
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1e-309"), Float64)
@test r.result === 1e-309
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1e-310"), Float64)
@test r.result === 1e-310
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1e-322"), Float64)
@test r.result === 1e-322
@test r.code === Parsers.OK
@test r.b === nothing
# smallest denormal
r = Parsers.xparse(IOBuffer("5e-324"), Float64)
@test r.result === 5e-324
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("4e-324"), Float64)
@test r.result === 5e-324
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("3e-324"), Float64)
@test r.result === 5e-324
@test r.code === Parsers.OK
@test r.b === nothing
# too small
r = Parsers.xparse(IOBuffer("2e-324"), Float64)
@test r.result === 0.0
@test r.code === Parsers.OK
@test r.b === nothing
# way too small
r = Parsers.xparse(IOBuffer("1e-350"), Float64)
@test r.result === 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1e-400000"), Float64)
@test r.result === 0.0
@test r.code === Parsers.OK
@test r.b === nothing

# try to overflow exponent
r = Parsers.xparse(IOBuffer("1e-4294967296"), Float64)
@test r.result === 0.0
@test r.code === Parsers.OK
@test r.b === nothing
r = Parsers.xparse(IOBuffer("1e+4294967296"), Float64)
@test r.result === +Inf
@test r.code === Parsers.OK
@test r.b === nothing
# r = Parsers.xparse(IOBuffer("1e-18446744073709551616"), Float64)
# @test r.result === 0
# @test r.code === Parsers.OK
# @test r.b === nothing
# r = Parsers.xparse(IOBuffer("1e+18446744073709551616"), Float64)
# @test r.result === +Inf
# @test r.code === Parsers.OK
# @test r.b === nothing

# Parse errors
r = Parsers.xparse(IOBuffer("1e"), Float64)
@test r.result === nothing
@test r.code === Parsers.INVALID
@test r.b === UInt8('e')
r = Parsers.xparse(IOBuffer("1e-"), Float64)
@test r.result === nothing
@test r.code === Parsers.INVALID
@test r.b === 0x00
r = Parsers.xparse(IOBuffer(".e-1"), Float64)
@test r.result === nothing
@test r.code === Parsers.INVALID
@test r.b === UInt8('1')
r = Parsers.xparse(IOBuffer("1\x00.2"), Float64)
@test r.result === 1.0
@test r.code === Parsers.OK
@test r.b === nothing

# http:#www.exploringbinary.com/java-hangs-when-converting-2-2250738585072012e-308/
r = Parsers.xparse(IOBuffer("2.2250738585072012e-308"), Float64)
@test r.result === 2.2250738585072014e-308
@test r.code === Parsers.OK
@test r.b === nothing
# http:#www.exploringbinary.com/php-hangs-on-numeric-value-2-2250738585072011e-308/
r = Parsers.xparse(IOBuffer("2.2250738585072011e-308"), Float64)
@test r.result === 2.225073858507201e-308
@test r.code === Parsers.OK
@test r.b === nothing

# A very large number (initially wrongly parsed by the fast algorithm).
r = Parsers.xparse(IOBuffer("4.630813248087435e+307"), Float64)
@test r.result === 4.630813248087435e+307
@test r.code === Parsers.OK
@test r.b === nothing

# A different kind of very large number.
r = Parsers.xparse(IOBuffer("22.222222222222222"), Float64)
@test r.result === 22.22222222222222
@test r.code === Parsers.OK
@test r.b === nothing

# Exactly halfway between 1 and math.Nextafter(1, 2).
# Round to even (down).
# {"1.00000000000000011102230246251565404236316680908203125", "1", nil},
# # Slightly lower; still round down.
# {"1.00000000000000011102230246251565404236316680908203124", "1", nil},
# # Slightly higher; round up.
# {"1.00000000000000011102230246251565404236316680908203126", "1.0000000000000002", nil},
# # Slightly higher, but you have to read all the way to the end.
# {"1.00000000000000011102230246251565404236316680908203125" + strings.Repeat("0", 10000) + "1", "1.0000000000000002", nil},
    

end # @testset
