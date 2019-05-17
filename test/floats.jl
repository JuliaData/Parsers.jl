@testset "Floats" begin

x, code, vpos, vlen, vlen = Parsers.xparse(Float64, "1x")

testcases = [
    (str="", x=0.0, code=(INVALID | EOF), len=0, tot=0),
    (str="-", x=0.0, code=(INVALID | EOF), len=1, tot=1),
    (str="1", x=1.0, code=(OK | EOF), len=1, tot=1),
    (str="+1", x=1.0, code=(OK | EOF), len=2, tot=2),
    (str="1.1", x=1.1, code=(OK | EOF), len=3, tot=3),
    (str="1.", x=1.0, code=(OK | EOF), len=2, tot=2),
    (str="1.a", x=1.0, code=(OK | EOF | INVALID_DELIMITER), len=2, tot=2),
    (str="1.1.", x=1.1, code=(OK | EOF | INVALID_DELIMITER), len=4, tot=4),
    (str="1e23", x=1e23, code=(OK | EOF), len=4, tot=4),
    (str="1E23", x=1e23, code=(OK | EOF), len=4, tot=4),
    (str="1f23", x=1e23, code=(OK | EOF), len=4, tot=4),
    (str="1F23", x=1e23, code=(OK | EOF), len=4, tot=4),
    (str="428.E+03", x=428000.0, code=(OK | EOF), len=8, tot=8),
    (str="1.0e", x=0.0, code=(INVALID | EOF), len=4, tot=4),
    (str="1.0ea", x=0.0, code=(INVALID | EOF | INVALID_DELIMITER), len=5, tot=5),
    (str="100000000000000000000000", x=1e23, code=(OK | EOF), len=24, tot=24),
    (str="1e-100", x=1e-100, code=(OK | EOF), len=6, tot=6),
    (str="123456700", x=1.234567e+08, code=(OK | EOF), len=9, tot=9),
    (str="99999999999999974834176", x=9.999999999999997e+22, code=(OK | EOF), len=23, tot=23),
    (str="100000000000000000000001", x=1.0000000000000001e+23, code=(OK | EOF), len=24, tot=24),
    (str="100000000000000008388608", x=1.0000000000000001e+23, code=(OK | EOF), len=24, tot=24),
    (str="100000000000000016777215", x=1.0000000000000001e+23, code=(OK | EOF), len=24, tot=24),
    (str="100000000000000016777216", x=1.0000000000000003e+23, code=(OK | EOF), len=0, tot=0),

    (str="-1", x=-1.0, code=(OK | EOF), len=0, tot=0),
    (str="-0.1", x=-0.1, code=(OK | EOF), len=0, tot=0),
    (str="-0", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="1e-20", x=1e-20, code=(OK | EOF), len=0, tot=0),
    (str="625e-3", x=0.625, code=(OK | EOF), len=0, tot=0),

    # zeros
    (str="0", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="0e0", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="-0e0", x=-0.0, code=(OK | EOF), len=0, tot=0),
    (str="+0e0", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="0e-0", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="-0e-0", x=-0.0, code=(OK | EOF), len=0, tot=0),
    (str="+0e-0", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="0e+0", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="-0e+0", x=-0.0, code=(OK | EOF), len=0, tot=0),
    (str="+0e+0", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="0e+01234567890123456789", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="0.00e-01234567890123456789", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="-0e+01234567890123456789", x=-0.0, code=(OK | EOF), len=0, tot=0),
    (str="-0.00e-01234567890123456789", x=-0.0, code=(OK | EOF), len=0, tot=0),
    (str="0e291", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="0e292", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="0e347", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="0e348", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="-0e291", x=-0.0, code=(OK | EOF), len=0, tot=0),
    (str="-0e292", x=-0.0, code=(OK | EOF), len=0, tot=0),
    (str="-0e347", x=-0.0, code=(OK | EOF), len=0, tot=0),
    (str="-0e348", x=-0.0, code=(OK | EOF), len=0, tot=0),

    # Infs/invalid NaNs
    (str="n", x=0.0, code=(INVALID | EOF), len=1, tot=1),
    (str="na", x=0.0, code=(INVALID | EOF), len=2, tot=2),
    (str="n", x=0.0, code=(INVALID | EOF), len=1, tot=1),
    (str="inf", x=Inf, code=(OK | EOF), len=0, tot=0),
    (str="infinity", x=Inf, code=(OK | EOF), len=0, tot=0),
    (str="-inf", x=-Inf, code=(OK | EOF), len=0, tot=0),
    (str="-Inf", x=-Inf, code=(OK | EOF), len=0, tot=0),
    (str="-infinity", x=-Inf, code=(OK | EOF), len=0, tot=0),
    (str="-INFINITY", x=-Inf, code=(OK | EOF), len=0, tot=0),
    (str="+inf", x=Inf, code=(OK | EOF), len=0, tot=0),
    (str="i", x=0.0, code=(INVALID | EOF), len=1, tot=1),
    (str="in", x=0.0, code=(INVALID | EOF), len=2, tot=2),
    (str="infi", x=Inf, code=(OK | EOF), len=1, tot=1),
    (str="infin", x=Inf, code=(OK | EOF), len=1, tot=1),
    (str="infini", x=Inf, code=(OK | EOF), len=1, tot=1),
    (str="infinit", x=Inf, code=(OK | EOF), len=1, tot=1),
    (str="i,", x=0.0, code=(INVALID | DELIMITED), len=1, tot=1),
    (str="in,", x=0.0, code=(INVALID | DELIMITED), len=2, tot=2),
    (str="infi,", x=Inf, code=(OK | DELIMITED), len=1, tot=1),
    (str="infin,", x=Inf, code=(OK | DELIMITED), len=1, tot=1),
    (str="infini,", x=Inf, code=(OK | DELIMITED), len=1, tot=1),
    (str="infinit,", x=Inf, code=(OK | DELIMITED), len=1, tot=1),

    # largest float64
    (str="1.7976931348623157e308", x=1.7976931348623157e+308, code=(OK | EOF), len=0, tot=0),
    (str="-1.7976931348623157e308", x=-1.7976931348623157e+308, code=(OK | EOF), len=0, tot=0),
    # next float64 - too large
    (str="1.7976931348623159e308", x=+Inf, code=(OK | EOF), len=0, tot=0),
    (str="-1.7976931348623159e308", x=-Inf, code=(OK | EOF), len=0, tot=0),
    # the border is ...158079
    # borderline - okay
    (str="1.7976931348623158e308", x=1.7976931348623157e+308, code=(OK | EOF), len=0, tot=0),
    (str="-1.7976931348623158e308", x=-1.7976931348623157e+308, code=(OK | EOF), len=0, tot=0),
    # borderline - too large
    (str="1.797693134862315808e308", x=+Inf, code=(OK | EOF), len=0, tot=0),
    (str="-1.797693134862315808e308", x=-Inf, code=(OK | EOF), len=0, tot=0),

    # a little too large
    (str="1e308", x=1e+308, code=(OK | EOF), len=0, tot=0),
    (str="2e308", x=+Inf, code=(OK | EOF), len=0, tot=0),
    (str="1e309", x=+Inf, code=(OK | EOF), len=0, tot=0),

    # way too large
    (str="1e310", x=+Inf, code=(OK | EOF), len=0, tot=0),
    (str="-1e310", x=-Inf, code=(OK | EOF), len=0, tot=0),
    (str="1e400", x=+Inf, code=(OK | EOF), len=0, tot=0),
    (str="-1e400", x=-Inf, code=(OK | EOF), len=0, tot=0),
    (str="1e400000", x=+Inf, code=(OK | EOF), len=0, tot=0),
    (str="-1e400000", x=-Inf, code=(OK | EOF), len=0, tot=0),

    # denormalized
    (str="1e-305", x=1e-305, code=(OK | EOF), len=0, tot=0),
    (str="1e-306", x=1e-306, code=(OK | EOF), len=0, tot=0),
    (str="1e-307", x=1e-307, code=(OK | EOF), len=0, tot=0),
    (str="1e-308", x=1e-308, code=(OK | EOF), len=0, tot=0),
    (str="1e-309", x=1e-309, code=(OK | EOF), len=0, tot=0),
    (str="1e-310", x=1e-310, code=(OK | EOF), len=0, tot=0),
    (str="1e-322", x=1e-322, code=(OK | EOF), len=0, tot=0),
    # smallest denormal
    (str="5e-324", x=5e-324, code=(OK | EOF), len=0, tot=0),
    (str="4e-324", x=5e-324, code=(OK | EOF), len=0, tot=0),
    (str="3e-324", x=5e-324, code=(OK | EOF), len=0, tot=0),
    # too small
    (str="2e-324", x=0.0, code=(OK | EOF), len=0, tot=0),
    # way too small
    (str="1e-350", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="1e-400000", x=0.0, code=(OK | EOF), len=0, tot=0),

    # try to overflow exponent
    (str="1e-4294967296", x=0.0, code=(OK | EOF), len=0, tot=0),
    (str="1e+4294967296", x=+Inf, code=(OK | EOF), len=0, tot=0),
    (str="1e-18446744073709551616", x=0.0, code=(OK | EOF), len=0, tot=0),

    (str="1e+18446744073709551616", x=+Inf, code=(OK | EOF), len=0, tot=0),

    # Parse errors
    # (str="1e", x=missing, code=(INVALID | EOF), len=0, tot=0),
    # (str="1e-", x=missing, code=(INVALID | EOF), len=0, tot=0),
    # (str=".e-1", x=missing, code=(INVALID | EOF), len=0, tot=0),
    # (str="1\x00.2", x=1.0, code=(OK), len=0, tot=0),

    # http:#www.exploringbinary.com/java-hangs-when-converting-2-2250738585072012e-308/
    (str="2.2250738585072012e-308", x=2.2250738585072014e-308, code=(OK | EOF), len=0, tot=0),
    # http://www.exploringbinary.com/php-hangs-on-numeric-value-2-2250738585072011e-308/
    (str="2.2250738585072011e-308", x=2.225073858507201e-308, code=(OK | EOF), len=0, tot=0),

    # A very large number (initially wrongly parsed by the fast algorithm).
    (str="4.630813248087435e+307", x=4.630813248087435e+307, code=(OK | EOF), len=0, tot=0),

    # A different kind of very large number.
    (str="22.222222222222222", x=22.22222222222222, code=(OK | EOF), len=0, tot=0),

    # Exactly halfway between 1 and math.Nextafter(1, 2).
    # Round to even (down).
    (str="1.00000000000000011102230246251565404236316680908203125", x=1.0, code=(OK | EOF), len=0, tot=0),
    # # Slightly lower; still round down.
    (str="1.00000000000000011102230246251565404236316680908203124", x=1.0, code=(OK | EOF), len=0, tot=0),
    # # Slightly higher; round up.
    (str="1.00000000000000011102230246251565404236316680908203126", x=1.0000000000000002, code=(OK | EOF), len=0, tot=0),

    (str="-5.871153289887625082e-01", x=-5.871153289887625082e-01, code=(OK | EOF), len=0, tot=0),
    (str="8.095032986136727615e-01", x=8.095032986136727615e-01, code=(OK | EOF), len=0, tot=0),
    (str="9.900000000000006573e-01", x=9.900000000000006573e-01, code=(OK | EOF), len=0, tot=0),
    (str="9.900000000000006573e-01", x=9.900000000000006573e-01, code=(OK | EOF), len=0, tot=0),
    (str="-9.866066418838319585e-01", x=-9.866066418838319585e-01, code=(OK | EOF), len=0, tot=0),
    (str="-3.138907529596844714e+00", x=-3.138907529596844714e+00, code=(OK | EOF), len=0, tot=0),
    (str="-5.129218106887371675e+00", x=-5.129218106887371675e+00, code=(OK | EOF), len=0, tot=0),
    (str="-4.803915800699462224e+00", x=-4.803915800699462224e+00, code=(OK | EOF), len=0, tot=0),

    # issue #18
    (str=".24409E+03", x=244.09, code=(OK | EOF), len=0, tot=0),
    (str=".24409E+03 ", x=244.09, code=(OK | EOF), len=0, tot=0),
    (str="-.2", x=-0.2, code=(OK | EOF), len=0, tot=0),
    (str=".2", x=0.2, code=(OK | EOF), len=0, tot=0),

    # from https://www.icir.org/vern/papers/testbase-report.pdf
    (str=string(5.0 * exp10(+125)), x=(5.0 * exp10(+125)), code=(OK | EOF), len=0, tot=0),
    (str=string(69.0 * exp10(+267)), x=(69.0 * exp10(+267)), code=(OK | EOF), len=0, tot=0),
    (str=string(999.0 * exp10(-26)), x=(999.0 * exp10(-26)), code=(OK | EOF), len=0, tot=0),
    (str=string(7861.0 * exp10(-34)), x=(7861.0 * exp10(-34)), code=(OK | EOF), len=0, tot=0),
    (str=string(75569.0 * exp10(-254)), x=(75569.0 * exp10(-254)), code=(OK | EOF), len=0, tot=0),
    (str=string(928609.0 * exp10(-261)), x=(928609.0 * exp10(-261)), code=(OK | EOF), len=0, tot=0),
    (str=string(9210917.0 * exp10(+80)), x=(9210917.0 * exp10(+80)), code=(OK | EOF), len=0, tot=0),
    (str=string(84863171.0 * exp10(+114)), x=(84863171.0 * exp10(+114)), code=(OK | EOF), len=0, tot=0),
    (str=string(653777767.0 * exp10(+273)), x=(653777767.0 * exp10(+273)), code=(OK | EOF), len=0, tot=0),
    (str=string(5232604057.0 * exp10(-298)), x=(5232604057.0 * exp10(-298)), code=(OK | EOF), len=0, tot=0),
    (str=string(27235667517.0 * exp10(-109)), x=(27235667517.0 * exp10(-109)), code=(OK | EOF), len=0, tot=0),
    (str=string(653532977297.0 * exp10(-123)), x=(653532977297.0 * exp10(-123)), code=(OK | EOF), len=0, tot=0),
    (str=string(3142213164987.0 * exp10(-294)), x=(3142213164987.0 * exp10(-294)), code=(OK | EOF), len=0, tot=0),
    (str=string(46202199371337.0 * exp10(-72)), x=(46202199371337.0 * exp10(-72)), code=(OK | EOF), len=0, tot=0),
    (str=string(231010996856685.0 * exp10(-73)), x=(231010996856685.0 * exp10(-73)), code=(OK | EOF), len=0, tot=0),
    (str=string(9324754620109615.0 * exp10(+212)), x=(9324754620109615.0 * exp10(+212)), code=(OK | EOF), len=0, tot=0),
    (str=string(78459735791271921.0 * exp10(+49)), x=(78459735791271921.0 * exp10(+49)), code=(OK | EOF), len=0, tot=0),
    (str=string(272104041512242479.0 * exp10(+200)), x=(272104041512242479.0 * exp10(+200)), code=(OK | EOF), len=0, tot=0),
    (str=string(6802601037806061975.0 * exp10(+198)), x=(6802601037806061975.0 * exp10(+198)), code=(OK | EOF), len=0, tot=0),
    (str=string(20505426358836677347.0 * exp10(-221)), x=(20505426358836677347.0 * exp10(-221)), code=(OK | EOF), len=0, tot=0),
    (str=string(836168422905420598437.0 * exp10(-234)), x=(836168422905420598437.0 * exp10(-234)), code=(OK | EOF), len=0, tot=0),
    (str=string(4891559871276714924261.0 * exp10(+222)), x=(4891559871276714924261.0 * exp10(+222)), code=(OK | EOF), len=0, tot=0),

    (str=string(9.0 * exp10(-265)), x=(9.0 * exp10(-265)), code=(OK | EOF), len=0, tot=0),
    (str=string(85.0 * exp10(-037)), x=(85.0 * exp10(-037)), code=(OK | EOF), len=0, tot=0),
    (str=string(623.0 * exp10(+100)), x=(623.0 * exp10(+100)), code=(OK | EOF), len=0, tot=0),
    (str=string(3571.0 * exp10(+263)), x=(3571.0 * exp10(+263)), code=(OK | EOF), len=0, tot=0),
    (str=string(81661.0 * exp10(+153)), x=(81661.0 * exp10(+153)), code=(OK | EOF), len=0, tot=0),
    (str=string(920657.0 * exp10(-023)), x=(920657.0 * exp10(-023)), code=(OK | EOF), len=0, tot=0),
    (str=string(4603285.0 * exp10(-024)), x=(4603285.0 * exp10(-024)), code=(OK | EOF), len=0, tot=0),
    (str=string(87575437.0 * exp10(-309)), x=(87575437.0 * exp10(-309)), code=(OK | EOF), len=0, tot=0),
    (str=string(245540327.0 * exp10(+122)), x=(245540327.0 * exp10(+122)), code=(OK | EOF), len=0, tot=0),
    (str=string(6138508175.0 * exp10(+120)), x=(6138508175.0 * exp10(+120)), code=(OK | EOF), len=0, tot=0),
    (str=string(83356057653.0 * exp10(+193)), x=(83356057653.0 * exp10(+193)), code=(OK | EOF), len=0, tot=0),
    (str=string(619534293513.0 * exp10(+124)), x=(619534293513.0 * exp10(+124)), code=(OK | EOF), len=0, tot=0),
    (str=string(2335141086879.0 * exp10(+218)), x=(2335141086879.0 * exp10(+218)), code=(OK | EOF), len=0, tot=0),
    (str=string(36167929443327.0 * exp10(-159)), x=(36167929443327.0 * exp10(-159)), code=(OK | EOF), len=0, tot=0),
    (str=string(609610927149051.0 * exp10(-255)), x=(609610927149051.0 * exp10(-255)), code=(OK | EOF), len=0, tot=0),
    (str=string(3743626360493413.0 * exp10(-165)), x=(3743626360493413.0 * exp10(-165)), code=(OK | EOF), len=0, tot=0),
    (str=string(94080055902682397.0 * exp10(-242)), x=(94080055902682397.0 * exp10(-242)), code=(OK | EOF), len=0, tot=0),
    (str=string(899810892172646163.0 * exp10(+283)), x=(899810892172646163.0 * exp10(+283)), code=(OK | EOF), len=0, tot=0),
    (str=string(7120190517612959703.0 * exp10(+120)), x=(7120190517612959703.0 * exp10(+120)), code=(OK | EOF), len=0, tot=0),
    (str=string(25188282901709339043.0 * exp10(-252)), x=(25188282901709339043.0 * exp10(-252)), code=(OK | EOF), len=0, tot=0),
    (str=string(308984926168550152811.0 * exp10(-052)), x=(308984926168550152811.0 * exp10(-052)), code=(OK | EOF), len=0, tot=0),
    (str=string(6372891218502368041059.0 * exp10(+064)), x=(6372891218502368041059.0 * exp10(+064)), code=(OK | EOF), len=0, tot=0),

    (str=string(8511030020275656.0 * exp2(-0342)), x=(8511030020275656.0 * exp2(-0342)), code=(OK | EOF), len=0, tot=0),
    (str=string(5201988407066741.0 * exp2(-0824)), x=(5201988407066741.0 * exp2(-0824)), code=(OK | EOF), len=0, tot=0),
    (str=string(6406892948269899.0 * exp2(+0237)), x=(6406892948269899.0 * exp2(+0237)), code=(OK | EOF), len=0, tot=0),
    (str=string(8431154198732492.0 * exp2(+0072)), x=(8431154198732492.0 * exp2(+0072)), code=(OK | EOF), len=0, tot=0),
    (str=string(6475049196144587.0 * exp2(+0099)), x=(6475049196144587.0 * exp2(+0099)), code=(OK | EOF), len=0, tot=0),
    (str=string(8274307542972842.0 * exp2(+0726)), x=(8274307542972842.0 * exp2(+0726)), code=(OK | EOF), len=0, tot=0),
    (str=string(5381065484265332.0 * exp2(-0456)), x=(5381065484265332.0 * exp2(-0456)), code=(OK | EOF), len=0, tot=0),
    (str=string(6761728585499734.0 * exp2(-1057)), x=(6761728585499734.0 * exp2(-1057)), code=(OK | EOF), len=0, tot=0),
    (str=string(7976538478610756.0 * exp2(+0376)), x=(7976538478610756.0 * exp2(+0376)), code=(OK | EOF), len=0, tot=0),
    (str=string(5982403858958067.0 * exp2(+0377)), x=(5982403858958067.0 * exp2(+0377)), code=(OK | EOF), len=0, tot=0),
    (str=string(5536995190630837.0 * exp2(+0093)), x=(5536995190630837.0 * exp2(+0093)), code=(OK | EOF), len=0, tot=0),
    (str=string(7225450889282194.0 * exp2(+0710)), x=(7225450889282194.0 * exp2(+0710)), code=(OK | EOF), len=0, tot=0),
    (str=string(7225450889282194.0 * exp2(+0709)), x=(7225450889282194.0 * exp2(+0709)), code=(OK | EOF), len=0, tot=0),
    (str=string(8703372741147379.0 * exp2(+0117)), x=(8703372741147379.0 * exp2(+0117)), code=(OK | EOF), len=0, tot=0),
    (str=string(8944262675275217.0 * exp2(-1001)), x=(8944262675275217.0 * exp2(-1001)), code=(OK | EOF), len=0, tot=0),
    (str=string(7459803696087692.0 * exp2(-0707)), x=(7459803696087692.0 * exp2(-0707)), code=(OK | EOF), len=0, tot=0),
    (str=string(6080469016670379.0 * exp2(-0381)), x=(6080469016670379.0 * exp2(-0381)), code=(OK | EOF), len=0, tot=0),
    (str=string(8385515147034757.0 * exp2(+0721)), x=(8385515147034757.0 * exp2(+0721)), code=(OK | EOF), len=0, tot=0),
    (str=string(7514216811389786.0 * exp2(-0828)), x=(7514216811389786.0 * exp2(-0828)), code=(OK | EOF), len=0, tot=0),
    (str=string(8397297803260511.0 * exp2(-0345)), x=(8397297803260511.0 * exp2(-0345)), code=(OK | EOF), len=0, tot=0),
    (str=string(6733459239310543.0 * exp2(+0202)), x=(6733459239310543.0 * exp2(+0202)), code=(OK | EOF), len=0, tot=0),
    (str=string(8091450587292794.0 * exp2(-0473)), x=(8091450587292794.0 * exp2(-0473)), code=(OK | EOF), len=0, tot=0),

    (str=string(6567258882077402.0 * exp2(+952)), x=(6567258882077402.0 * exp2(+952)), code=(OK | EOF), len=0, tot=0),
    (str=string(6712731423444934.0 * exp2(+535)), x=(6712731423444934.0 * exp2(+535)), code=(OK | EOF), len=0, tot=0),
    (str=string(6712731423444934.0 * exp2(+534)), x=(6712731423444934.0 * exp2(+534)), code=(OK | EOF), len=0, tot=0),
    (str=string(5298405411573037.0 * exp2(-957)), x=(5298405411573037.0 * exp2(-957)), code=(OK | EOF), len=0, tot=0),
    (str=string(5137311167659507.0 * exp2(-144)), x=(5137311167659507.0 * exp2(-144)), code=(OK | EOF), len=0, tot=0),
    (str=string(6722280709661868.0 * exp2(+363)), x=(6722280709661868.0 * exp2(+363)), code=(OK | EOF), len=0, tot=0),
    (str=string(5344436398034927.0 * exp2(-169)), x=(5344436398034927.0 * exp2(-169)), code=(OK | EOF), len=0, tot=0),
    (str=string(8369123604277281.0 * exp2(-853)), x=(8369123604277281.0 * exp2(-853)), code=(OK | EOF), len=0, tot=0),
    (str=string(8995822108487663.0 * exp2(-780)), x=(8995822108487663.0 * exp2(-780)), code=(OK | EOF), len=0, tot=0),
    (str=string(8942832835564782.0 * exp2(-383)), x=(8942832835564782.0 * exp2(-383)), code=(OK | EOF), len=0, tot=0),
    (str=string(8942832835564782.0 * exp2(-384)), x=(8942832835564782.0 * exp2(-384)), code=(OK | EOF), len=0, tot=0),
    (str=string(8942832835564782.0 * exp2(-385)), x=(8942832835564782.0 * exp2(-385)), code=(OK | EOF), len=0, tot=0),
    (str=string(6965949469487146.0 * exp2(-249)), x=(6965949469487146.0 * exp2(-249)), code=(OK | EOF), len=0, tot=0),
    (str=string(6965949469487146.0 * exp2(-250)), x=(6965949469487146.0 * exp2(-250)), code=(OK | EOF), len=0, tot=0),
    (str=string(6965949469487146.0 * exp2(-251)), x=(6965949469487146.0 * exp2(-251)), code=(OK | EOF), len=0, tot=0),
    (str=string(7487252720986826.0 * exp2(+548)), x=(7487252720986826.0 * exp2(+548)), code=(OK | EOF), len=0, tot=0),
    (str=string(5592117679628511.0 * exp2(+164)), x=(5592117679628511.0 * exp2(+164)), code=(OK | EOF), len=0, tot=0),
    (str=string(8887055249355788.0 * exp2(+665)), x=(8887055249355788.0 * exp2(+665)), code=(OK | EOF), len=0, tot=0),
    (str=string(6994187472632449.0 * exp2(+690)), x=(6994187472632449.0 * exp2(+690)), code=(OK | EOF), len=0, tot=0),
    (str=string(8797576579012143.0 * exp2(+588)), x=(8797576579012143.0 * exp2(+588)), code=(OK | EOF), len=0, tot=0),
    (str=string(7363326733505337.0 * exp2(+272)), x=(7363326733505337.0 * exp2(+272)), code=(OK | EOF), len=0, tot=0),
    (str=string(8549497411294502.0 * exp2(-448)), x=(8549497411294502.0 * exp2(-448)), code=(OK | EOF), len=0, tot=0),
];

for (i, case) in enumerate(testcases)
    x, code, vpos, vlen, tlen = Parsers.xparse(Float64, case.str)
    if x != case.x || code != case.code #|| len != case.len || tlen != case.tlen
        println("ERROR on case=$i, $case")
        x, code, vpos, vlen, tlen = Parsers.xparse(Float64, case.str; debug=Val(true))
    end
    @test x == case.x
    @test code == case.code
    # @test len == case.len
    # @test tlen == case.tlen
end

# NaNs
case = (str="nan", x=NaN, code=(OK | EOF), len=3, tot=3)
x, code, vpos, vlen, tlen = Parsers.xparse(Float64, case.str)
@test isnan(x)
@test code == case.code
@test vlen == tlen == 3
case = (str="NaN", x=NaN, code=(OK | EOF), len=3, tot=3)
x, code, vpos, vlen, tlen = Parsers.xparse(Float64, case.str)
@test isnan(x)
@test code == case.code
@test vlen == tlen == 3
case = (str="NAN", x=NaN, code=(OK | EOF), len=3, tot=3)
x, code, vpos, vlen, tlen = Parsers.xparse(Float64, case.str)
@test isnan(x)
@test code == case.code
@test vlen == tlen == 3
case = (str="nAN", x=NaN, code=(OK | EOF), len=3, tot=3)
x, code, vpos, vlen, tlen = Parsers.xparse(Float64, case.str)
@test isnan(x)
@test code == case.code
@test vlen == tlen == 3
case = (str="nAN,", x=NaN, code=(OK | DELIMITED), len=4, tot=4)
x, code, vpos, vlen, tlen = Parsers.xparse(Float64, case.str)
@test isnan(x)
@test code == case.code
@test vlen == 3
@test tlen == 4

# #25
case = (str="74810199.033988851037472901827191090834", x=7.481019903398885e7, code=(OK | EOF))
x, code, vpos, vlen, tlen = Parsers.xparse(Float64, case.str)
@test x == case.x
@test code == case.code
@test vlen == tlen == 39

end # @testset
