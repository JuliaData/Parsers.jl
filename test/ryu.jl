const maxMantissa = (UInt64(1) << 53) - 1
todouble(sign, exp, mant) = Core.bitcast(Float64, (UInt64(sign) << 63) | (UInt64(exp) << 52) | (UInt64(mant)))

@testset "Parsers.writeshortest" begin

@testset "Float64" begin

@testset "Basic" begin
    @test Parsers.writeshortest(0.0) == "0.0"
    @test Parsers.writeshortest(-0.0) == "-0.0"
    @test Parsers.writeshortest(1.0) == "1.0"
    @test Parsers.writeshortest(-1.0) == "-1.0"
    @test Parsers.writeshortest(NaN) == "NaN"
    @test Parsers.writeshortest(Inf) == "Inf"
    @test Parsers.writeshortest(-Inf) == "-Inf"
end

@testset "SwitchToSubnormal" begin
    @test "2.2250738585072014e-308" == Parsers.writeshortest(2.2250738585072014e-308)
end

@testset "MinAndMax" begin
    @test "1.7976931348623157e308" == Parsers.writeshortest(Core.bitcast(Float64, 0x7fefffffffffffff))
    @test "5.0e-324" == Parsers.writeshortest(Core.bitcast(Float64, Int64(1)))
end

@testset "LotsOfTrailingZeros" begin
    @test "2.9802322387695312e-8" == Parsers.writeshortest(2.98023223876953125e-8)
end

@testset "Regression" begin
    @test "-2.109808898695963e16" == Parsers.writeshortest(-2.109808898695963e16)
    @test "4.940656e-318" == Parsers.writeshortest(4.940656e-318)
    @test "1.18575755e-316" == Parsers.writeshortest(1.18575755e-316)
    @test "2.989102097996e-312" == Parsers.writeshortest(2.989102097996e-312)
    @test "9.0608011534336e15" == Parsers.writeshortest(9.0608011534336e15)
    @test "4.708356024711512e18" == Parsers.writeshortest(4.708356024711512e18)
    @test "9.409340012568248e18" == Parsers.writeshortest(9.409340012568248e18)
    @test "1.2345678" == Parsers.writeshortest(1.2345678)
end

@testset "LooksLikePow5" begin
    # These numbers have a mantissa that is a multiple of the largest power of 5 that fits,
    # and an exponent that causes the computation for q to result in 22, which is a corner
    # case for Ryu.
    @test "5.764607523034235e39" == Parsers.writeshortest(Core.bitcast(Float64, 0x4830F0CF064DD592))
    @test "1.152921504606847e40" == Parsers.writeshortest(Core.bitcast(Float64, 0x4840F0CF064DD592))
    @test "2.305843009213694e40" == Parsers.writeshortest(Core.bitcast(Float64, 0x4850F0CF064DD592))
end

@testset "OutputLength" begin
    @test "1.0" == Parsers.writeshortest(1.0) # already tested in Basic
    @test "1.2" == Parsers.writeshortest(1.2)
    @test "1.23" == Parsers.writeshortest(1.23)
    @test "1.234" == Parsers.writeshortest(1.234)
    @test "1.2345" == Parsers.writeshortest(1.2345)
    @test "1.23456" == Parsers.writeshortest(1.23456)
    @test "1.234567" == Parsers.writeshortest(1.234567)
    @test "1.2345678" == Parsers.writeshortest(1.2345678) # already tested in Regressi
    @test "1.23456789" == Parsers.writeshortest(1.23456789)
    @test "1.234567895" == Parsers.writeshortest(1.234567895) # 1.234567890 would be trimm
    @test "1.2345678901" == Parsers.writeshortest(1.2345678901)
    @test "1.23456789012" == Parsers.writeshortest(1.23456789012)
    @test "1.234567890123" == Parsers.writeshortest(1.234567890123)
    @test "1.2345678901234" == Parsers.writeshortest(1.2345678901234)
    @test "1.23456789012345" == Parsers.writeshortest(1.23456789012345)
    @test "1.234567890123456" == Parsers.writeshortest(1.234567890123456)
    @test "1.2345678901234567" == Parsers.writeshortest(1.2345678901234567)

  # Test 32-bit chunking
    @test "4.294967294" == Parsers.writeshortest(4.294967294) # 2^32 -
    @test "4.294967295" == Parsers.writeshortest(4.294967295) # 2^32 -
    @test "4.294967296" == Parsers.writeshortest(4.294967296) # 2^
    @test "4.294967297" == Parsers.writeshortest(4.294967297) # 2^32 +
    @test "4.294967298" == Parsers.writeshortest(4.294967298) # 2^32 +
end

# Test min, max shift values in shiftright128
@testset "MinMaxShift" begin
    # 32-bit opt-size=0:  49 <= dist <= 50
    # 32-bit opt-size=1:  30 <= dist <= 50
    # 64-bit opt-size=0:  50 <= dist <= 50
    # 64-bit opt-size=1:  30 <= dist <= 50
    @test "1.7800590868057611e-307" == Parsers.writeshortest(todouble(false, 4, 0))
    # 32-bit opt-size=0:  49 <= dist <= 49
    # 32-bit opt-size=1:  28 <= dist <= 49
    # 64-bit opt-size=0:  50 <= dist <= 50
    # 64-bit opt-size=1:  28 <= dist <= 50
    @test "2.8480945388892175e-306" == Parsers.writeshortest(todouble(false, 6, maxMantissa))
    # 32-bit opt-size=0:  52 <= dist <= 53
    # 32-bit opt-size=1:   2 <= dist <= 53
    # 64-bit opt-size=0:  53 <= dist <= 53
    # 64-bit opt-size=1:   2 <= dist <= 53
    @test "2.446494580089078e-296" == Parsers.writeshortest(todouble(false, 41, 0))
    # 32-bit opt-size=0:  52 <= dist <= 52
    # 32-bit opt-size=1:   2 <= dist <= 52
    # 64-bit opt-size=0:  53 <= dist <= 53
    # 64-bit opt-size=1:   2 <= dist <= 53
    @test "4.8929891601781557e-296" == Parsers.writeshortest(todouble(false, 40, maxMantissa))

    # 32-bit opt-size=0:  57 <= dist <= 58
    # 32-bit opt-size=1:  57 <= dist <= 58
    # 64-bit opt-size=0:  58 <= dist <= 58
    # 64-bit opt-size=1:  58 <= dist <= 58
    @test "1.8014398509481984e16" == Parsers.writeshortest(todouble(false, 1077, 0))
    # 32-bit opt-size=0:  57 <= dist <= 57
    # 32-bit opt-size=1:  57 <= dist <= 57
    # 64-bit opt-size=0:  58 <= dist <= 58
    # 64-bit opt-size=1:  58 <= dist <= 58
    @test "3.6028797018963964e16" == Parsers.writeshortest(todouble(false, 1076, maxMantissa))
    # 32-bit opt-size=0:  51 <= dist <= 52
    # 32-bit opt-size=1:  51 <= dist <= 59
    # 64-bit opt-size=0:  52 <= dist <= 52
    # 64-bit opt-size=1:  52 <= dist <= 59
    @test "2.900835519859558e-216" == Parsers.writeshortest(todouble(false, 307, 0))
    # 32-bit opt-size=0:  51 <= dist <= 51
    # 32-bit opt-size=1:  51 <= dist <= 59
    # 64-bit opt-size=0:  52 <= dist <= 52
    # 64-bit opt-size=1:  52 <= dist <= 59
    @test "5.801671039719115e-216" == Parsers.writeshortest(todouble(false, 306, maxMantissa))

    # https:#github.com/ulfjack/ryu/commit/19e44d16d80236f5de25800f56d82606d1be00b9#commitcomment-30146483
    # 32-bit opt-size=0:  49 <= dist <= 49
    # 32-bit opt-size=1:  44 <= dist <= 49
    # 64-bit opt-size=0:  50 <= dist <= 50
    # 64-bit opt-size=1:  44 <= dist <= 50
    @test "3.196104012172126e-27" == Parsers.writeshortest(todouble(false, 934, 0x000FA7161A4D6E0C))
end

@testset "SmallIntegers" begin
    @test "9.007199254740991e15" == Parsers.writeshortest(9007199254740991.0)
    @test "9.007199254740992e15" == Parsers.writeshortest(9007199254740992.0)

    @test "1.0" == Parsers.writeshortest(1.0e+0)
    @test "12.0" == Parsers.writeshortest(1.2e+1)
    @test "123.0" == Parsers.writeshortest(1.23e+2)
    @test "1234.0" == Parsers.writeshortest(1.234e+3)
    @test "12345.0" == Parsers.writeshortest(1.2345e+4)
    @test "123456.0" == Parsers.writeshortest(1.23456e+5)
    @test "1.234567e6" == Parsers.writeshortest(1.234567e+6)
    @test "1.2345678e7" == Parsers.writeshortest(1.2345678e+7)
    @test "1.23456789e8" == Parsers.writeshortest(1.23456789e+8)
    @test "1.23456789e9" == Parsers.writeshortest(1.23456789e+9)
    @test "1.234567895e9" == Parsers.writeshortest(1.234567895e+9)
    @test "1.2345678901e10" == Parsers.writeshortest(1.2345678901e+10)
    @test "1.23456789012e11" == Parsers.writeshortest(1.23456789012e+11)
    @test "1.234567890123e12" == Parsers.writeshortest(1.234567890123e+12)
    @test "1.2345678901234e13" == Parsers.writeshortest(1.2345678901234e+13)
    @test "1.23456789012345e14" == Parsers.writeshortest(1.23456789012345e+14)
    @test "1.234567890123456e15" == Parsers.writeshortest(1.234567890123456e+15)

  # 10^i
    @test "1.0" == Parsers.writeshortest(1.0e+0)
    @test "10.0" == Parsers.writeshortest(1.0e+1)
    @test "100.0" == Parsers.writeshortest(1.0e+2)
    @test "1000.0" == Parsers.writeshortest(1.0e+3)
    @test "10000.0" == Parsers.writeshortest(1.0e+4)
    @test "100000.0" == Parsers.writeshortest(1.0e+5)
    @test "1.0e6" == Parsers.writeshortest(1.0e+6)
    @test "1.0e7" == Parsers.writeshortest(1.0e+7)
    @test "1.0e8" == Parsers.writeshortest(1.0e+8)
    @test "1.0e9" == Parsers.writeshortest(1.0e+9)
    @test "1.0e10" == Parsers.writeshortest(1.0e+10)
    @test "1.0e11" == Parsers.writeshortest(1.0e+11)
    @test "1.0e12" == Parsers.writeshortest(1.0e+12)
    @test "1.0e13" == Parsers.writeshortest(1.0e+13)
    @test "1.0e14" == Parsers.writeshortest(1.0e+14)
    @test "1.0e15" == Parsers.writeshortest(1.0e+15)

  # 10^15 + 10^i
    @test "1.000000000000001e15" == Parsers.writeshortest(1.0e+15 + 1.0e+0)
    @test "1.00000000000001e15" == Parsers.writeshortest(1.0e+15 + 1.0e+1)
    @test "1.0000000000001e15" == Parsers.writeshortest(1.0e+15 + 1.0e+2)
    @test "1.000000000001e15" == Parsers.writeshortest(1.0e+15 + 1.0e+3)
    @test "1.00000000001e15" == Parsers.writeshortest(1.0e+15 + 1.0e+4)
    @test "1.0000000001e15" == Parsers.writeshortest(1.0e+15 + 1.0e+5)
    @test "1.000000001e15" == Parsers.writeshortest(1.0e+15 + 1.0e+6)
    @test "1.00000001e15" == Parsers.writeshortest(1.0e+15 + 1.0e+7)
    @test "1.0000001e15" == Parsers.writeshortest(1.0e+15 + 1.0e+8)
    @test "1.000001e15" == Parsers.writeshortest(1.0e+15 + 1.0e+9)
    @test "1.00001e15" == Parsers.writeshortest(1.0e+15 + 1.0e+10)
    @test "1.0001e15" == Parsers.writeshortest(1.0e+15 + 1.0e+11)
    @test "1.001e15" == Parsers.writeshortest(1.0e+15 + 1.0e+12)
    @test "1.01e15" == Parsers.writeshortest(1.0e+15 + 1.0e+13)
    @test "1.1e15" == Parsers.writeshortest(1.0e+15 + 1.0e+14)

  # Largest power of 2 <= 10^(i+1)
    @test "8.0" == Parsers.writeshortest(8.0)
    @test "64.0" == Parsers.writeshortest(64.0)
    @test "512.0" == Parsers.writeshortest(512.0)
    @test "8192.0" == Parsers.writeshortest(8192.0)
    @test "65536.0" == Parsers.writeshortest(65536.0)
    @test "524288.0" == Parsers.writeshortest(524288.0)
    @test "8.388608e6" == Parsers.writeshortest(8388608.0)
    @test "6.7108864e7" == Parsers.writeshortest(67108864.0)
    @test "5.36870912e8" == Parsers.writeshortest(536870912.0)
    @test "8.589934592e9" == Parsers.writeshortest(8589934592.0)
    @test "6.8719476736e10" == Parsers.writeshortest(68719476736.0)
    @test "5.49755813888e11" == Parsers.writeshortest(549755813888.0)
    @test "8.796093022208e12" == Parsers.writeshortest(8796093022208.0)
    @test "7.0368744177664e13" == Parsers.writeshortest(70368744177664.0)
    @test "5.62949953421312e14" == Parsers.writeshortest(562949953421312.0)
    @test "9.007199254740992e15" == Parsers.writeshortest(9007199254740992.0)

  # 1000 * (Largest power of 2 <= 10^(i+1))
    @test "8000.0" == Parsers.writeshortest(8.0e+3)
    @test "64000.0" == Parsers.writeshortest(64.0e+3)
    @test "512000.0" == Parsers.writeshortest(512.0e+3)
    @test "8.192e6" == Parsers.writeshortest(8192.0e+3)
    @test "6.5536e7" == Parsers.writeshortest(65536.0e+3)
    @test "5.24288e8" == Parsers.writeshortest(524288.0e+3)
    @test "8.388608e9" == Parsers.writeshortest(8388608.0e+3)
    @test "6.7108864e10" == Parsers.writeshortest(67108864.0e+3)
    @test "5.36870912e11" == Parsers.writeshortest(536870912.0e+3)
    @test "8.589934592e12" == Parsers.writeshortest(8589934592.0e+3)
    @test "6.8719476736e13" == Parsers.writeshortest(68719476736.0e+3)
    @test "5.49755813888e14" == Parsers.writeshortest(549755813888.0e+3)
    @test "8.796093022208e15" == Parsers.writeshortest(8796093022208.0e+3)
end

end # Float64

@testset "Float32" begin

@testset "Basic" begin
    @test "0.0" == Parsers.writeshortest(Float32(0.0))
    @test "-0.0" == Parsers.writeshortest(Float32(-0.0))
    @test "1.0" == Parsers.writeshortest(Float32(1.0))
    @test "-1.0" == Parsers.writeshortest(Float32(-1.0))
    @test "NaN" == Parsers.writeshortest(Float32(NaN))
    @test "Inf" == Parsers.writeshortest(Float32(Inf))
    @test "-Inf" == Parsers.writeshortest(Float32(-Inf))
end

@testset "SwitchToSubnormal" begin
    @test "1.1754944e-38" == Parsers.writeshortest(1.1754944f-38)
end

@testset "MinAndMax" begin
    @test "3.4028235e38" == Parsers.writeshortest(Core.bitcast(Float32, 0x7f7fffff))
    @test "1.0e-45" == Parsers.writeshortest(Core.bitcast(Float32, Int32(1)))
end

# Check that we return the exact boundary if it is the shortest
# representation, but only if the original floating point number is even.
@testset "BoundaryRoundeven" begin
    @test "3.355445e7" == Parsers.writeshortest(3.355445f7)
    @test "9.0e9" == Parsers.writeshortest(8.999999f9)
    @test "3.436672e10" == Parsers.writeshortest(3.4366717f10)
end

# If the exact value is exactly halfway between two shortest representations,
# then we round to even. It seems like this only makes a difference if the
# last two digits are ...2|5 or ...7|5, and we cut off the 5.
@testset "exactValueRoundeven" begin
    @test "305404.12" == Parsers.writeshortest(3.0540412f5)
    @test "8099.0312" == Parsers.writeshortest(8.0990312f3)
end

@testset "LotsOfTrailingZeros" begin
    # Pattern for the first test: 00111001100000000000000000000000
    @test "0.00024414062" == Parsers.writeshortest(2.4414062f-4)
    @test "0.0024414062" == Parsers.writeshortest(2.4414062f-3)
    @test "0.0043945312" == Parsers.writeshortest(4.3945312f-3)
    @test "0.0063476562" == Parsers.writeshortest(6.3476562f-3)
end

@testset "Regression" begin
    @test "4.7223665e21" == Parsers.writeshortest(4.7223665f21)
    @test "8.388608e6" == Parsers.writeshortest(8388608f0)
    @test "1.6777216e7" == Parsers.writeshortest(1.6777216f7)
    @test "3.3554436e7" == Parsers.writeshortest(3.3554436f7)
    @test "6.7131496e7" == Parsers.writeshortest(6.7131496f7)
    @test "1.9310392e-38" == Parsers.writeshortest(1.9310392f-38)
    @test "-2.47e-43" == Parsers.writeshortest(-2.47f-43)
    @test "1.993244e-38" == Parsers.writeshortest(1.993244f-38)
    @test "4103.9004" == Parsers.writeshortest(4103.9003f0)
    @test "5.3399997e9" == Parsers.writeshortest(5.3399997f9)
    @test "6.0898e-39" == Parsers.writeshortest(6.0898f-39)
    @test "0.0010310042" == Parsers.writeshortest(0.0010310042f0)
    @test "2.882326e17" == Parsers.writeshortest(2.8823261f17)
    @test "7.038531e-26" == Parsers.writeshortest(7.0385309f-26)
    @test "9.223404e17" == Parsers.writeshortest(9.2234038f17)
    @test "6.710887e7" == Parsers.writeshortest(6.7108872f7)
    @test "1.0e-44" == Parsers.writeshortest(1.0f-44)
    @test "2.816025e14" == Parsers.writeshortest(2.816025f14)
    @test "9.223372e18" == Parsers.writeshortest(9.223372f18)
    @test "1.5846086e29" == Parsers.writeshortest(1.5846085f29)
    @test "1.1811161e19" == Parsers.writeshortest(1.1811161f19)
    @test "5.368709e18" == Parsers.writeshortest(5.368709f18)
    @test "4.6143166e18" == Parsers.writeshortest(4.6143165f18)
    @test "0.007812537" == Parsers.writeshortest(0.007812537f0)
    @test "1.0e-45" == Parsers.writeshortest(1.4f-45)
    @test "1.18697725e20" == Parsers.writeshortest(1.18697724f20)
    @test "1.00014165e-36" == Parsers.writeshortest(1.00014165f-36)
    @test "200.0" == Parsers.writeshortest(200f0)
    @test "3.3554432e7" == Parsers.writeshortest(3.3554432f7)
end

@testset "LooksLikePow5" begin
    # These numbers have a mantissa that is the largest power of 5 that fits,
    # and an exponent that causes the computation for q to result in 10, which is a corner
    # case for Ryu.
    @test "6.7108864e17" == Parsers.writeshortest(Core.bitcast(Float32, 0x5D1502F9))
    @test "1.3421773e18" == Parsers.writeshortest(Core.bitcast(Float32, 0x5D9502F9))
    @test "2.6843546e18" == Parsers.writeshortest(Core.bitcast(Float32, 0x5E1502F9))
end

@testset "OutputLength" begin
    @test "1.0" == Parsers.writeshortest(Float32(1.0))
    @test "1.2" == Parsers.writeshortest(Float32(1.2))
    @test "1.23" == Parsers.writeshortest(Float32(1.23))
    @test "1.234" == Parsers.writeshortest(Float32(1.234))
    @test "1.2345" == Parsers.writeshortest(Float32(1.2345))
    @test "1.23456" == Parsers.writeshortest(Float32(1.23456))
    @test "1.234567" == Parsers.writeshortest(Float32(1.234567))
    @test "1.2345678" == Parsers.writeshortest(Float32(1.2345678))
    @test "1.23456735e-36" == Parsers.writeshortest(Float32(1.23456735e-36))
end

end # Float32

@testset "Float16" begin

@testset "Basic" begin
    @test "0.0" == Parsers.writeshortest(Float16(0.0))
    @test "-0.0" == Parsers.writeshortest(Float16(-0.0))
    @test "1.0" == Parsers.writeshortest(Float16(1.0))
    @test "-1.0" == Parsers.writeshortest(Float16(-1.0))
    @test "NaN" == Parsers.writeshortest(Float16(NaN))
    @test "Inf" == Parsers.writeshortest(Float16(Inf))
    @test "-Inf" == Parsers.writeshortest(Float16(-Inf))
end

let x=floatmin(Float16)
    while x <= floatmax(Float16)
        @test parse(Float16, Parsers.writeshortest(x)) == x
        x = nextfloat(x)
    end
end

# function testfloats(T)
#     x = floatmin(T)
#     i = 0
#     fails = 0
#     success = 0
#     while x < floatmax(T)
#         test = parse(T, Parsers.writeshortest(x)) == x
#         if !test

#             fails += 1
#         else
#             success += 1
#         end
#         x = nextfloat(x)
#         i += 1

#     end
#     return fails / (fails + success)
# end

end # Float16

end