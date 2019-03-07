using BenchmarkTools, Parsers, Test, Dates

# Int
T = Int
run(@benchmarkable Parsers.defaultparser(io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.defaultparser
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.Sentinel(["NA"])
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.Sentinel(["NA"])
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("NA"); r = Parsers.Result($T)))
l = Parsers.Strip(Parsers.Sentinel(["NA"]))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(["NA"])))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(["NA"]))))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))

# Float64
T = Float64
run(@benchmarkable Parsers.defaultparser(io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.defaultparser
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.Sentinel(["NA"])
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.Sentinel(["NA"])
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("NA"); r = Parsers.Result($T)))
l = Parsers.Strip(Parsers.Sentinel(["NA"]))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(["NA"])))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(["NA"]))))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))

run(@benchmarkable Parsers.defaultparser(io, r) setup=(io = IOBuffer("99999999999999974834176"); r = Parsers.Result($T)))
run(@benchmarkable Parsers.defaultparser(io, r) setup=(io = IOBuffer("1.7976931348623157e308"); r = Parsers.Result($T)))

run(@benchmarkable Parsers.defaultparser(io, r) setup=(io = IOBuffer("2.2250738585072011e-308"); r = Parsers.Result($T)))
run(@benchmarkable Parsers.defaultparser(io, r) setup=(io = IOBuffer("0.0017138347201173243"); r = Parsers.Result($T)))


# Tuple{Ptr{UInt8}, Int}
T = Tuple{Ptr{UInt8}, Int}
run(@benchmarkable Parsers.defaultparser(io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.defaultparser
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.Sentinel(["NA"])
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.Sentinel(["NA"])
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("NA"); r = Parsers.Result($T)))
l = Parsers.Strip(Parsers.Sentinel(["NA"]))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(["NA"])))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(["NA"]))))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))

# String
T = String
run(@benchmarkable Parsers.defaultparser(io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.defaultparser
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
@code_warntype Parsers.parse!(l, IOBuffer("0"), Parsers.Result(T))
l = Parsers.Sentinel(["NA"])
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.Sentinel(["NA"])
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("NA"); r = Parsers.Result($T)))
l = Parsers.Strip(Parsers.Sentinel(["NA"]))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(["NA"])))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))
l = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(["NA"]))))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("0"); r = Parsers.Result($T)))

# Bool
T = Bool
run(@benchmarkable Parsers.defaultparser(io, r) setup=(io = IOBuffer("true"); r = Parsers.Result($T)))
l = Parsers.defaultparser
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("true"); r = Parsers.Result($T)))
l = Parsers.Sentinel(["NA"])
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("true"); r = Parsers.Result($T)))
l = Parsers.Sentinel(["NA"])
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("NA"); r = Parsers.Result($T)))
l = Parsers.Strip(Parsers.Sentinel(["NA"]))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("true"); r = Parsers.Result($T)))
l = Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(["NA"])))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("true"); r = Parsers.Result($T)))
l = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(["NA"]))))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("true"); r = Parsers.Result($T)))

# Date
T = Date
run(@benchmarkable Parsers.defaultparser(io, r) setup=(io = IOBuffer("2018-01-01"); r = Parsers.Result($T)))
l = Parsers.defaultparser
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("2018-01-01"); r = Parsers.Result($T)))
l = Parsers.Sentinel(["NA"])
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("2018-01-01"); r = Parsers.Result($T)))
l = Parsers.Sentinel(["NA"])
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("NA"); r = Parsers.Result($T)))
l = Parsers.Strip(Parsers.Sentinel(["NA"]))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("2018-01-01"); r = Parsers.Result($T)))
l = Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(["NA"])))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("2018-01-01"); r = Parsers.Result($T)))
l = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(["NA"]))))
run(@benchmarkable Parsers.parse!($l, io, r) setup=(io = IOBuffer("2018-01-01"); r = Parsers.Result($T)))


function test(n)
    l = Parsers.defaultparser; io = IOBuffer("0"); r = Parsers.Result(Tuple{Ptr{UInt8}, Int})
    for i = 1:n
        Parsers.fastseek!(io, 1)
        Parsers.parse!(l, io, r)
    end
    return
end


@code_warntype Parsers.parse!(Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(["NA"])))), IOBuffer("0"), Parsers.Result(String))
@code_warntype Parsers.parse!(Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(["NA"])))), IOBuffer("0"), Parsers.Result(Int))


@btime Parsers.parse(Parsers.defaultparser, IOBuffer("0"), Int)
io = IOBuffer("0")
@time Parsers.parse(Parsers.defaultparser, io, Int)

# slow
run(@benchmarkable Parsers.parse(io, Int) setup=(io = Parsers.Sentinel(IOBuffer("0"), ["NA"])))
run(@benchmarkable Main.Parsers.parse(io, Int) setup=(io = Main.Parsers.Sentinel(IOBuffer("NA"), ["NA"])))
@code_warntype Parsers.parse(Parsers.defaultparser, Parsers.Sentinel(IOBuffer("0"), ["NA"]), Int)
@code_llvm Parsers.parse(Parsers.defaultparser, Parsers.Sentinel(IOBuffer("0"), ["NA"]), Int)
@btime Parsers.parse(Parsers.defaultparser, Parsers.Sentinel(IOBuffer("0"), ["NA"]), Int)

io = IOBuffer("0")
@time Parsers.parse(Parsers.defaultparser, io, Int)

io = Parsers.Sentinel(IOBuffer("0"), ["NA"])
@time Parsers.parse(Parsers.defaultparser, io, Int)

io = Parsers.Strip(Parsers.Sentinel(IOBuffer("0"), ["NA"]))
@time Parsers.parse(Parsers.defaultparser, io, Int)

io = Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(IOBuffer("0"), ["NA"])))
@time Parsers.parse(Parsers.defaultparser, io, Int)

io = Parsers.Delimited(Parsers.Sentinel(IOBuffer("0"), ["NA"]))
@time Parsers.parse(Parsers.defaultparser, io, Int)

io = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(IOBuffer("0"), ["NA"]))))
@time Parsers.parse(Parsers.defaultparser, io, Int)

io = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(IOBuffer("0.0"), ["NA"]))))
@time Parsers.parse(Parsers.defaultparser, io, Float64)

io = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(IOBuffer("0.0"), ["NA"]))))
@time Parsers.parse(Parsers.defaultparser, io, String)

io = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(IOBuffer("2018-01-01"), ["NA"]))))
@time Parsers.parse(Parsers.defaultparser, io, Date)


run(@benchmarkable Parsers.parse(io, Int) setup=(io = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(IOBuffer("NA"), ["NA"]))))))
io = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(IOBuffer("NA"), ["NA"]))))
@time Parsers.parse(Parsers.defaultparser, io, Int)

function test(n)
    io = Parsers.Sentinel(IOBuffer("NA"), ["NA"])
    io2 = Parsers.getio(io)
    for i = 1:n
        Parsers.parse(Parsers.defaultparser, io, Int)
        Parsers.fastseek!(io2, 1)
    end
end

function test(n)
    io = Parsers.Delimited(Parsers.Sentinel(IOBuffer("NA"), ["NA"]))
    io2 = Parsers.getio(io)
    for i = 1:n
        Parsers.parse(Parsers.defaultparser, io, Int)
        Parsers.fastseek!(io2, 1)
    end
end